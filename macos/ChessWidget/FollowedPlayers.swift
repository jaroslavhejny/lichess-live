import Foundation
import SwiftUI
import UserNotifications

private struct FollowedUser: Decodable, Identifiable {
    let id: String
    let username: String
    let title: String?
}

private struct UserStatus: Decodable {
    let id: String
    let online: Bool?
    let playing: Bool?
    let playingId: String?
}

private struct FollowedPlayer: Identifiable {
    let user: FollowedUser
    let status: UserStatus?
    var id: String { user.id }
    var isOnline: Bool? { status.map { $0.online == true || $0.playing == true || $0.playingId != nil } }
    var isPlaying: Bool { status?.playing == true || status?.playingId != nil }
    var gameURL: URL? {
        guard let id = status?.playingId, id.count == 8,
              id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { return nil }
        return URL(string: "https://lichess.org/\(id)")
    }
    var profileURL: URL { URL(string: "https://lichess.org/@/")!.appendingPathComponent(user.username) }
}

private func followedUsers() async throws -> [FollowedUser] {
    guard try readLichessToken() != nil else { throw FollowedError.tokenMissing }
    let request = try lichessRequest(URL(string: "https://lichess.org/api/rel/following")!)
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
    guard (200..<300).contains(response.statusCode) else { throw LichessHTTPError(status: response.statusCode) }
    guard let text = String(data: data, encoding: .utf8) else { throw URLError(.cannotDecodeContentData) }
    return try text.split(whereSeparator: \.isNewline).map { line in
        try JSONDecoder().decode(FollowedUser.self, from: Data(line.utf8))
    }
}

private func statuses(for users: [FollowedUser]) async throws -> [String: UserStatus] {
    var all: [String: UserStatus] = [:]
    for start in stride(from: 0, to: users.count, by: 100) {
        try Task.checkCancellation()
        let ids = users[start..<min(start + 100, users.count)].map(\.id).joined(separator: ",")
        var url = URLComponents(string: "https://lichess.org/api/users/status")!
        url.queryItems = [URLQueryItem(name: "ids", value: ids), URLQueryItem(name: "withGameIds", value: "true")]
        let batch: [UserStatus] = try await fetchJSON(url.url!)
        for status in batch { all[status.id.lowercased()] = status }
    }
    return all
}

private enum FollowedError: LocalizedError {
    case tokenMissing
    var errorDescription: String? { "Add a Lichess token with follow:read in Settings." }
}

struct FollowedPlayersView: View {
    let tokenRevision: Int
    @State private var players: [FollowedPlayer] = []
    @State private var cachedUsers: [FollowedUser]?
    @State private var loaded = false
    @State private var loading = false
    @State private var errorMessage = ""
    @State private var expanded = true
    @State private var showOffline = false
    @State private var nextRetry = Date.distantPast
    @State private var retryDelay: TimeInterval = 60
    @AppStorage("moveNotificationsEnabled") private var notificationsEnabled = false
    @AppStorage("friendStatusNotificationsEnabled") private var friendNotificationsEnabled = true

    private var online: [FollowedPlayer] { players.filter { $0.isOnline == true } }
    private var offline: [FollowedPlayer] { players.filter { $0.isOnline == false } }
    private var unknown: [FollowedPlayer] { players.filter { $0.isOnline == nil } }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Friend status notifications", isOn: $friendNotificationsEnabled).font(.caption)
                if friendNotificationsEnabled && !notificationsEnabled {
                    Text("Enable Notifications above to receive alerts.").font(.caption2).foregroundStyle(.secondary)
                }
                if loading && !loaded { ProgressView().controlSize(.small) }
                if !errorMessage.isEmpty { Text(errorMessage).font(.caption).foregroundStyle(.secondary) }
                if loaded && players.isEmpty { Text("You are not following any players.").font(.caption).foregroundStyle(.secondary) }
                else if loaded && online.isEmpty { Text("No followed players are online.").font(.caption).foregroundStyle(.secondary) }
                if !online.isEmpty {
                    ScrollView {
                        LazyVStack(spacing: 0) { ForEach(online) { player in playerRow(player) } }
                    }.frame(maxHeight: 150)
                }
                if !offline.isEmpty || !unknown.isEmpty {
                    DisclosureGroup("Offline or unavailable (\(offline.count + unknown.count))", isExpanded: $showOffline) {
                        ScrollView {
                            LazyVStack(spacing: 0) { ForEach(offline + unknown) { player in playerRow(player) } }
                        }.frame(maxHeight: 150)
                    }.font(.caption)
                }
            }.padding(.top, 6)
        } label: {
            HStack {
                Text("Followed players").font(.headline)
                if loaded { Text("\(online.count) online").font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Button { Task { await refresh(reloadFollowing: true) } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless).disabled(loading || Date() < nextRetry)
                    .help("Refresh followed players")
            }
        }
        .padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        .task(id: tokenRevision) {
            while loading && !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
            players = []
            cachedUsers = nil
            loaded = false
            await refresh(reloadFollowing: true)
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(90)) } catch { return }
                await refresh(reloadFollowing: false)
            }
        }
    }

    private func playerRow(_ player: FollowedPlayer) -> some View {
        HStack(spacing: 8) {
            Circle().fill(player.isOnline == true ? Color.green : Color.gray.opacity(0.5)).frame(width: 7, height: 7)
            Link((player.user.title.map { "\($0) " } ?? "") + player.user.username, destination: player.profileURL)
                .font(.callout).lineLimit(1)
            if player.isPlaying { Text("Playing").font(.caption).foregroundStyle(.green) }
            else if player.isOnline == nil { Text("Unknown").font(.caption).foregroundStyle(.secondary) }
            Spacer()
            if let gameURL = player.gameURL { Link("Open game", destination: gameURL).font(.caption) }
        }.padding(.vertical, 4)
    }

    @MainActor private func refresh(reloadFollowing: Bool) async {
        guard !loading, Date() >= nextRetry else { return }
        loading = true
        defer { loading = false }
        do {
            let users: [FollowedUser]
            if reloadFollowing || cachedUsers == nil { users = try await followedUsers() }
            else { users = cachedUsers! }
            let current = try await statuses(for: users)
            guard !Task.isCancelled else { return }
            cachedUsers = users
            let updated = users.map { FollowedPlayer(user: $0, status: current[$0.id.lowercased()]) }.sorted {
                if $0.isPlaying != $1.isPlaying { return $0.isPlaying }
                if ($0.isOnline == true) != ($1.isOnline == true) { return $0.isOnline == true }
                return $0.user.username.localizedCaseInsensitiveCompare($1.user.username) == .orderedAscending
            }
            errorMessage = ""
            if loaded && notificationsEnabled && friendNotificationsEnabled {
                let oldByID = Dictionary(players.map { ($0.id.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
                for player in updated {
                    guard let old = oldByID[player.id.lowercased()], let wasOnline = old.isOnline, let isOnline = player.isOnline else { continue }
                    let message: String?
                    if !wasOnline && isOnline { message = player.isPlaying ? "Came online and started playing." : "Came online." }
                    else if wasOnline && !isOnline { message = "Went offline." }
                    else if !old.isPlaying && player.isPlaying { message = "Started playing." }
                    else if old.isPlaying && !player.isPlaying { message = "Stopped playing." }
                    else if player.isPlaying, let oldID = old.status?.playingId, let newID = player.status?.playingId, oldID != newID { message = "Started a new game." }
                    else { message = nil }
                    if let message { await notifyStatus(player, message: message) }
                }
            }
            players = updated
            loaded = true
            retryDelay = 60
        } catch {
            guard !Task.isCancelled else { return }
            if let error = error as? LichessHTTPError, error.status == 429 {
                nextRetry = Date().addingTimeInterval(retryDelay)
                errorMessage = "Lichess rate limit; the player list will retry later."
                retryDelay = min(retryDelay * 2, 600)
            } else if let error = error as? LichessHTTPError, error.status == 401 || error.status == 403 {
                errorMessage = "Could not load followed players. Check the saved token and its follow:read permission."
            } else { errorMessage = error.localizedDescription }
        }
    }

    @MainActor private func notifyStatus(_ player: FollowedPlayer, message: String) async {
        let content = UNMutableNotificationContent()
        content.title = (player.user.title.map { "\($0) " } ?? "") + player.user.username
        content.body = message
        do { try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) }
        catch { errorMessage = "Could not send friend notification: \(error.localizedDescription)" }
    }
}
