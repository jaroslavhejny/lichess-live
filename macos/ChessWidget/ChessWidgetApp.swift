import SwiftUI
import WidgetKit
import UserNotifications

final class NotificationDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

@main
struct ChessWidgetApp: App {
    @NSApplicationDelegateAdaptor(NotificationDelegate.self) private var notificationDelegate
    var body: some Scene { WindowGroup { ContentView() }.windowResizability(.contentMinSize) }
}

struct ContentView: View {
    @State private var broadcasts: [Broadcast] = []
    @State private var games: [Game] = []
    @State private var roundID = ""
    @State private var message = ""
    @State private var selection = loadSelection()
    @State private var loading = false
    @State private var streamStatus = ""
    @AppStorage("moveNotificationsEnabled") private var notificationsEnabled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Chess Broadcast Widget").font(.title2.bold())
            Text("Choose a live broadcast and game, then add Chess Position Board in Notification Center.")
            if let selection { Text("Selected: \(selection.name)").font(.callout) }
            if !streamStatus.isEmpty { Text(streamStatus).font(.caption).foregroundStyle(.secondary) }
            Toggle("Move notifications", isOn: Binding(
                get: { notificationsEnabled },
                set: { enabled in
                    if enabled { Task { await enableNotifications() } }
                    else { notificationsEnabled = false }
                }
            ))
            HStack {
                Picker("Broadcast", selection: $roundID) {
                    Text("Select a broadcast").tag("")
                    ForEach(broadcasts) { broadcast in
                        Text("\(broadcast.tour.name) – \(broadcast.round.name)\(broadcast.tour.info?.tc.map { " (\($0))" } ?? "")").tag(broadcast.id)
                    }
                }
                Button("Refresh") { Task { await loadBroadcasts(); await loadGames(roundID) } }.disabled(loading)
            }
            if !games.isEmpty {
                List(games) { game in
                    HStack {
                        Text(game.listLabel)
                        Spacer()
                        Button("Select") { select(game) }
                    }
                }.frame(minHeight: 180)
            }
            if loading { ProgressView() }
            if !message.isEmpty { Text(message).foregroundStyle(.secondary) }
            Text("The widget updates periodically; macOS controls the refresh schedule.").font(.caption).foregroundStyle(.secondary)
        }
        .padding().frame(minWidth: 580, minHeight: 300)
        .task { await loadBroadcasts() }
        .task(id: selection?.game) { await monitorSelection() }
        .onChange(of: roundID) { _, id in Task { await loadGames(id) } }
    }
    @MainActor func loadBroadcasts() async {
        loading = true
        defer { loading = false }
        do { broadcasts = try await fetchBroadcasts(); message = broadcasts.isEmpty ? "No live broadcasts are available." : "" }
        catch { message = "Could not load broadcasts: \(error.localizedDescription)" }
    }
    @MainActor func loadGames(_ id: String) async {
        games = []
        guard !id.isEmpty else { return }
        do {
            let loaded = try await fetchGames(round: id)
            guard roundID == id else { return }
            games = loaded
            message = loaded.isEmpty ? "No games are available in this round." : ""
        } catch { if roundID == id { message = "Could not load games: \(error.localizedDescription)" } }
    }
    func select(_ game: Game) {
        let selected = Selection(round: roundID, game: game.id, name: game.label)
        guard let groupID, !groupID.isEmpty, let defaults = UserDefaults(suiteName: groupID), let data = try? JSONEncoder().encode(selected) else {
            message = "Could not save the selection for the widget."
            return
        }
        defaults.set(data, forKey: selectionKey)
        selection = selected
        message = "Game selected. Add or refresh the Chess Position Board widget."
        WidgetCenter.shared.reloadAllTimelines()
    }

    @MainActor func enableNotifications() async {
        do {
            let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            notificationsEnabled = allowed
            if !allowed { message = "Notifications are disabled in System Settings. Allow them there to enable move notifications." }
        } catch {
            notificationsEnabled = false
            message = "Could not enable notifications: \(error.localizedDescription)"
        }
    }

    func notifyMove(_ game: StreamGame, previous: StreamGame, name: String) async {
        guard notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "New move"
        if game.moves.count == previous.moves.count + 1, let move = game.moves.last {
            let ply = game.moves.count
            content.body = "\(name): \((ply + 1) / 2)\(ply.isMultiple(of: 2) ? "..." : ".")\(move)"
        } else {
            content.body = "\(name): \(game.moves.count - previous.moves.count) new moves"
        }
        content.sound = .default
        do { try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) }
        catch { await MainActor.run { message = "Could not send notification: \(error.localizedDescription)" } }
    }

    func monitorSelection() async {
        guard let selected = selection else { return }
        var previous: StreamGame?
        while !Task.isCancelled {
            do {
                streamStatus = "Connecting to the broadcast…"
                try await streamRound(selected.round, onConnected: {
                    streamStatus = "Connected; waiting for the selected game…"
                }) { pgn in
                    guard !Task.isCancelled, let game = parseStreamGame(pgn, gameID: selected.game) else { return }
                    streamStatus = "Live broadcast connected"
                    if let old = previous, game.moves != old.moves {
                        WidgetCenter.shared.reloadTimelines(ofKind: "ChessPositionBoardV2")
                        if game.moves.count > old.moves.count, Array(game.moves.prefix(old.moves.count)) == old.moves {
                            await notifyMove(game, previous: old, name: selected.name)
                        }
                    }
                    previous = game
                }
                streamStatus = "Broadcast disconnected; reconnecting…"
            } catch StreamError.rateLimited {
                streamStatus = "Lichess rate limit; retrying in 60 seconds."
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                continue
            } catch {
                if Task.isCancelled { return }
                streamStatus = "Broadcast error: \(error.localizedDescription). Reconnecting…"
            }
            do { try await Task.sleep(for: .seconds(5)) }
            catch { return }
        }
    }
}
