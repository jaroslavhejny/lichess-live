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
    @StateObject private var engine = StockfishEngine()
    @State private var broadcasts: [Broadcast] = []
    @State private var games: [Game] = []
    @State private var roundID = ""
    @State private var message = ""
    @State private var selection = loadSelection()
    @State private var loading = false
    @State private var streamStatus = ""
    @State private var showSettings = false
    @State private var tokenRevision = 0
    @State private var lastEvaluation: (score: Int, ply: Int)?
    @State private var clockText = "? – ?"
    @State private var broadcastClock: BroadcastClock?
    @State private var currentNotificationTitle = "Chess Broadcast"
    @AppStorage("moveNotificationsEnabled") private var notificationsEnabled = false
    @AppStorage("liveBroadcastsOnly") private var liveBroadcastsOnly = false
    @AppStorage("runningGamesOnly") private var runningGamesOnly = false
    @AppStorage("streamRetryAfter") private var streamRetryAfter = 0.0
    @AppStorage("streamRateLimitDelay") private var streamRateLimitDelay = 0.0

    private var visibleBroadcasts: [Broadcast] {
        liveBroadcastsOnly ? broadcasts.filter { $0.round.ongoing == true } : broadcasts
    }
    private var visibleGames: [Game] {
        guard runningGamesOnly else { return games }
        guard broadcasts.first(where: { $0.id == roundID })?.round.ongoing == true else { return [] }
        return games.filter { $0.status == "*" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Chess Broadcast").font(.title2.bold())
                    Text("Follow a game live").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Button { showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
            }
            if let selection {
                HStack(spacing: 12) {
                    Image(systemName: "dot.radiowaves.left.and.right").font(.title3).foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selection.name).font(.headline).lineLimit(1)
                        Text(streamStatus.isEmpty ? "Connecting…" : streamStatus).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer()
                    if let broadcastClock { ClockPanel(clock: broadcastClock) }
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(engine.evaluation ?? "—").font(.title3.monospacedDigit().weight(.semibold))
                        Text(engine.status).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
            }
            Toggle("Notifications", isOn: Binding(
                get: { notificationsEnabled },
                set: { enabled in
                    if enabled { Task { await enableNotifications() } }
                    else { notificationsEnabled = false }
                }
            ))
            HStack {
                Picker("Broadcast", selection: $roundID) {
                    Text("Select a broadcast").tag("")
                    ForEach(visibleBroadcasts) { broadcast in
                        Text(broadcast.label).tag(broadcast.id)
                    }
                }
                Button("Refresh") { Task { await loadBroadcasts(); await loadGames(roundID) } }.disabled(loading)
            }
            Toggle("Live broadcasts only", isOn: $liveBroadcastsOnly)
            if !roundID.isEmpty { Toggle("Running games only", isOn: $runningGamesOnly) }
            if !games.isEmpty {
                if visibleGames.isEmpty {
                    Text("No running games in this round.").foregroundStyle(.secondary)
                }
                List(visibleGames) { game in
                    let selected = selection?.round == roundID && selection?.game == game.id
                    HStack {
                        Button { select(game) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(game.listLabel).fontWeight(selected ? .semibold : .regular)
                                    Text(game.status == "*" ? (broadcasts.first(where: { $0.id == roundID })?.round.ongoing == true ? "In progress" : "Upcoming") : (game.status == nil ? "Status unknown" : "Finished"))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }.padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if let roundURL = broadcasts.first(where: { $0.id == roundID })?.round.url {
                            Link("Open", destination: roundURL.appendingPathComponent(game.id))
                        }
                    }
                    .listRowBackground(selected ? Color.accentColor.opacity(0.22) : Color.clear)
                }.frame(minHeight: 180)
            }
            if loading { ProgressView() }
            if !message.isEmpty { Text(message).foregroundStyle(.secondary) }
            Text("The widget updates periodically; macOS controls the refresh schedule.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(20).frame(minWidth: 680, minHeight: 440)
        .onAppear {
            engine.onEvaluation = { score, ply, _ in
                if let selection, let fen = engine.evaluatedFEN, let evaluation = engine.evaluation,
                   saveEvaluation(evaluation, fen: fen, for: selection) {
                    WidgetCenter.shared.reloadTimelines(ofKind: "ChessPositionBoardV3")
                }
                if let previous = lastEvaluation, ply == previous.ply + 1 {
                    let change = score - previous.score
                    let movedWhite = !ply.isMultiple(of: 2)
                    let gameTitle = currentNotificationTitle
                    let clocks = clockText
                    if (movedWhite ? -change : change) >= 100 {
                        Task { await notifyEvaluation(title: "Possible blunder", previous: previous.score, current: score, gameTitle: gameTitle, clocks: clocks) }
                    } else if abs(change) >= 50 {
                        Task { await notifyEvaluation(title: "Evaluation change", previous: previous.score, current: score, gameTitle: gameTitle, clocks: clocks) }
                    }
                }
                lastEvaluation = (score, ply)
            }
        }
        .onDisappear { engine.shutdown() }
        .task { await loadBroadcasts() }
        .task(id: "\(selection?.round ?? "")/\(selection?.game ?? "")/\(tokenRevision)") { await monitorSelection() }
        .sheet(isPresented: $showSettings) {
            TokenSettings {
                tokenRevision += 1
                WidgetCenter.shared.reloadAllTimelines()
                Task { await loadBroadcasts(); await loadGames(roundID) }
            }
        }
        .onChange(of: roundID) { _, id in Task { await loadGames(id) } }
        .onChange(of: liveBroadcastsOnly) { _, enabled in
            if enabled, !roundID.isEmpty, !visibleBroadcasts.contains(where: { $0.id == roundID }) { roundID = "" }
        }
    }
    @MainActor func loadBroadcasts() async {
        loading = true
        defer { loading = false }
        do { broadcasts = try await fetchBroadcasts(); message = broadcasts.isEmpty ? "No broadcasts are available." : "" }
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
        if selection?.round != roundID || selection?.game != game.id {
            engine.reset()
            lastEvaluation = nil
            clockText = "? – ?"
            broadcastClock = nil
            currentNotificationTitle = "Chess Broadcast"
        }
        let selected = Selection(round: roundID, game: game.id, name: game.label)
        guard let groupID, !groupID.isEmpty, let defaults = UserDefaults(suiteName: groupID), let data = try? JSONEncoder().encode(selected) else {
            message = "Could not save the selection for the widget."
            return
        }
        defaults.set(data, forKey: selectionKey)
        if let fen = game.fen {
            savePosition(fen, for: selected, white: game.players?.first?.name, black: game.players?.dropFirst().first?.name)
        }
        selection = selected
        message = "Game selected. Add or refresh the Chess Position & Game widget."
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

    func notificationTitle(_ game: StreamGame, fallback: String) -> String {
        func shortName(_ name: String) -> String {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if let comma = trimmed.firstIndex(of: ",") { return String(trimmed[..<comma]) }
            return trimmed.split(separator: " ").last.map(String.init) ?? trimmed
        }
        if let white = game.white, let black = game.black { return "\(shortName(white)) – \(shortName(black))" }
        return fallback.replacingOccurrences(of: #"\s*\(\d+\)"#, with: "", options: .regularExpression)
    }

    func notifyMove(_ game: StreamGame, previous: StreamGame, fallbackName: String, evaluation: String?) async {
        guard notificationsEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = notificationTitle(game, fallback: fallbackName)
        let moveText: String
        if game.moves.count == previous.moves.count + 1, let move = game.moves.last {
            let ply = game.moves.count
            moveText = "\((ply + 1) / 2)\(ply.isMultiple(of: 2) ? "..." : ".") \(move)"
        } else {
            moveText = "\(game.moves.count - previous.moves.count) new moves"
        }
        content.body = "\(moveText)  \(game.clocks)" + (evaluation.map { "  \($0)" } ?? "")
        content.sound = .default
        do { try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) }
        catch { await MainActor.run { message = "Could not send notification: \(error.localizedDescription)" } }
    }

    func notifyEvaluation(title: String, previous: Int, current: Int, gameTitle: String, clocks: String) async {
        guard notificationsEnabled else { return }
        func label(_ score: Int) -> String {
            if abs(score) >= 100_000 { return score > 0 ? "mate for White" : "mate for Black" }
            return String(format: "%+.2f", Double(score) / 100)
        }
        let content = UNMutableNotificationContent()
        content.title = gameTitle
        content.body = "\(title) · \(label(previous)) → \(label(current)) · \(clocks)"
        content.sound = .default
        do { try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) }
        catch { await MainActor.run { message = "Could not send notification: \(error.localizedDescription)" } }
    }

    func notifyFinished(_ game: StreamGame, name: String) async {
        guard notificationsEnabled, let result = game.result else { return }
        let content = UNMutableNotificationContent()
        content.title = notificationTitle(game, fallback: name)
        content.body = "Game finished · \(result) · \(game.clocks)"
        content.sound = .default
        do { try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) }
        catch { await MainActor.run { message = "Could not send notification: \(error.localizedDescription)" } }
    }

    func updateWidgetPosition(_ game: StreamGame, for selected: Selection) {
        guard let fen = game.fen else {
            streamStatus = "Connected; could not calculate the board position."
            return
        }
        let lastMove: String? = game.moves.last.map { move in
            let ply = game.moves.count
            return "\((ply + 1) / 2)\(ply.isMultiple(of: 2) ? "..." : ".") \(move)"
        }
        savePosition(fen, for: selected, white: game.white, black: game.black, lastMove: lastMove, clocks: game.clocks)
        engine.analyze(fen: fen, ply: game.moves.count)
        WidgetCenter.shared.reloadTimelines(ofKind: "ChessPositionBoardV3")
    }

    func monitorSelection() async {
        guard let selected = selection else { return }
        var previous: StreamGame?
        var needsClockSync = true
        while !Task.isCancelled {
            let wait = streamRetryAfter - Date().timeIntervalSince1970
            if wait > 0 {
                streamStatus = "Lichess rate limit; retrying in \(Int(ceil(wait))) seconds."
                do { try await Task.sleep(for: .seconds(wait)) } catch { return }
            }
            do {
                streamStatus = "Connecting to the broadcast…"
                try await streamRound(selected.round, onConnected: {
                    needsClockSync = true
                    streamRetryAfter = 0
                    streamRateLimitDelay = 0
                    streamStatus = "Connected; waiting for the selected game…"
                }) { pgn in
                    guard !Task.isCancelled, let game = parseStreamGame(pgn, gameID: selected.game) else { return }
                    streamStatus = "Live broadcast connected"
                    currentNotificationTitle = notificationTitle(game, fallback: selected.name)
                    clockText = game.clocks
                    if needsClockSync || previous?.moves != game.moves || previous?.clocks != game.clocks || previous?.result != game.result {
                        broadcastClock = BroadcastClock(game: game)
                        needsClockSync = false
                    }
                    if previous == nil { updateWidgetPosition(game, for: selected) }
                    if let old = previous, game.moves != old.moves {
                        if game.moves.count > old.moves.count, Array(game.moves.prefix(old.moves.count)) == old.moves {
                            let evaluation = game.fen != nil && game.fen == engine.evaluatedFEN ? engine.evaluation : nil
                            await notifyMove(game, previous: old, fallbackName: selected.name, evaluation: evaluation)
                        }
                        updateWidgetPosition(game, for: selected)
                    }
                    if let old = previous, old.result == nil, game.result != nil {
                        await notifyFinished(game, name: selected.name)
                    }
                    previous = game
                }
                streamStatus = "Broadcast disconnected; reconnecting…"
            } catch StreamError.rateLimited {
                if Task.isCancelled { return }
                streamRateLimitDelay = min(max(60, streamRateLimitDelay * 2), 600)
                streamRetryAfter = Date().timeIntervalSince1970 + streamRateLimitDelay
                continue
            } catch let error as LichessHTTPError where error.status == 401 || error.status == 403 {
                streamStatus = error.localizedDescription + " Open Settings to update the token."
                return
            } catch let error as TokenError {
                streamStatus = error.localizedDescription
                return
            } catch {
                if Task.isCancelled { return }
                streamStatus = "Broadcast error: \(error.localizedDescription). Reconnecting…"
            }
            do { try await Task.sleep(for: .seconds(5)) }
            catch { return }
        }
    }
}

struct TokenSettings: View {
    let onChange: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var hasToken = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Lichess settings").font(.title2.bold())
            Text("An optional personal access token helps with Lichess broadcast limits. Enable the study:read permission. The token is stored in macOS Keychain.")
            Link("Create a Lichess token", destination: URL(string: "https://lichess.org/account/oauth/token")!)
            Text(hasToken ? "A token is saved." : "No token saved.").foregroundStyle(.secondary)
            SecureField(hasToken ? "Enter a replacement token" : "Paste your Lichess token", text: $token)
            if !errorMessage.isEmpty { Text(errorMessage).foregroundStyle(.red) }
            HStack {
                Button("Remove token") { removeToken() }.disabled(!hasToken)
                Spacer()
                Button("Close") { dismiss() }
                Button("Save") { saveToken() }.disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding().frame(width: 500)
        .onAppear { refreshTokenState() }
    }
    func refreshTokenState() {
        do { hasToken = try readLichessToken() != nil; errorMessage = "" }
        catch { errorMessage = error.localizedDescription }
    }
    func saveToken() {
        do {
            try saveLichessToken(token.trimmingCharacters(in: .whitespacesAndNewlines))
            token = ""
            hasToken = true
            errorMessage = ""
            onChange()
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
    func removeToken() {
        do { try deleteLichessToken(); token = ""; hasToken = false; errorMessage = ""; onChange() }
        catch { errorMessage = error.localizedDescription }
    }
}
