import SwiftUI
import WidgetKit
import UserNotifications
import AppKit

final class NotificationDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var model: AppModel?
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) { model?.shutdown() }
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner]
    }
}

@main
struct ChessWidgetApp: App {
    @NSApplicationDelegateAdaptor(NotificationDelegate.self) private var notificationDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        Window("Chess Broadcast", id: "main") {
            ContentView(model: model, engine: model.engine)
                .onAppear { notificationDelegate.model = model; model.start() }
        }.windowResizability(.contentMinSize)
        MenuBarExtra {
            MenuBarContent(model: model)
        } label: {
            Image(nsImage: menuBarBishop)
                .accessibilityLabel("Chess Broadcast")
        }
    }
}

private let menuBarBishop: NSImage = {
    let size = NSSize(width: 22, height: 22)
    let image = NSImage(size: size, flipped: false) { rect in
        NSImage(named: "wB")?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 0.85)
        return true
    }
    image.isTemplate = false
    return image
}()

struct MenuBarContent: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @AppStorage("moveNotificationsEnabled") private var notificationsEnabled = false
    var body: some View {
        Text(model.selection?.name ?? "No game selected")
        Text(model.streamStatus.isEmpty ? "Not monitoring" : model.streamStatus)
        Divider()
        Toggle("Notifications", isOn: Binding(
            get: { notificationsEnabled },
            set: { enabled in
                if enabled { Task { await model.enableNotifications() } }
                else { notificationsEnabled = false }
            }
        ))
        Divider()
        if let url = model.selectedGameURL {
            Link("Open Game", destination: url)
        } else {
            Button("Open Game") {}.disabled(true)
        }
        Button("Open Chess Broadcast") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Button("Quit Chess Broadcast") { model.shutdown(); NSApp.terminate(nil) }
    }
}

struct ContentView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var engine: StockfishEngine
    @State private var showSettings = false
    @AppStorage("moveNotificationsEnabled") private var notificationsEnabled = false
    @AppStorage("liveBroadcastsOnly") private var liveBroadcastsOnly = false
    @AppStorage("runningGamesOnly") private var runningGamesOnly = false

    private var broadcasts: [Broadcast] { model.broadcasts }
    private var games: [Game] { model.games }
    private var selection: Selection? { model.selection }
    private var streamStatus: String { model.streamStatus }
    private var broadcastClock: BroadcastClock? { model.broadcastClock }
    private var message: String { model.message }
    private var loading: Bool { model.loading }
    private var roundID: String { model.roundID }
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
                    if enabled { Task { await model.enableNotifications() } }
                    else { notificationsEnabled = false }
                }
            ))
            FollowedPlayersView(model: model.followed)
            HStack {
                Picker("Broadcast", selection: $model.roundID) {
                    Text("Select a broadcast").tag("")
                    ForEach(visibleBroadcasts) { broadcast in
                        Text(broadcast.label).tag(broadcast.id)
                    }
                }
                Button("Refresh") { Task { await model.loadBroadcasts(); await model.loadGames(roundID) } }.disabled(loading)
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
                        Button { model.select(game) } label: {
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
        .onAppear { model.start() }
        .sheet(isPresented: $showSettings) {
            TokenSettings {
                model.tokenChanged()
                WidgetCenter.shared.reloadAllTimelines()
                Task { await model.loadBroadcasts(); await model.loadGames(model.roundID) }
            }
        }
        .onChange(of: model.roundID) { _, id in Task { await model.loadGames(id) } }
        .onChange(of: liveBroadcastsOnly) { _, enabled in
            if enabled, !roundID.isEmpty, !visibleBroadcasts.contains(where: { $0.id == roundID }) { model.roundID = "" }
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    let engine = StockfishEngine()
    let followed = FollowedPlayersModel()
    @Published var broadcasts: [Broadcast] = []
    @Published var games: [Game] = []
    @Published var roundID = ""
    @Published var message = ""
    @Published var selection = loadSelection()
    @Published var loading = false
    @Published var streamStatus = ""
    @Published var broadcastClock: BroadcastClock?
    private var lastEvaluation: (score: Int, ply: Int)?
    private var clockText: String?
    private var currentNotificationTitle = "Chess Broadcast"
    @AppStorage("moveNotificationsEnabled") private var notificationsEnabled = false
    @AppStorage("streamRetryAfter") private var streamRetryAfter = 0.0
    @AppStorage("streamRateLimitDelay") private var streamRateLimitDelay = 0.0
    var selectedGameURL: URL? {
        guard let selection else { return nil }
        if let url = selection.gameURL { return url }
        return broadcasts.first(where: { $0.id == selection.round })?.round.url?.appendingPathComponent(selection.game)
    }
    private var monitoringTask: Task<Void, Never>?
    private var startupTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        engine.onEvaluation = { [weak self] score, ply, _ in
            guard let self else { return }
            if let selection = self.selection, let fen = self.engine.evaluatedFEN, let evaluation = self.engine.evaluation,
               saveEvaluation(evaluation, fen: fen, for: selection) {
                WidgetCenter.shared.reloadTimelines(ofKind: "ChessPositionBoardV3")
            }
            if let previous = self.lastEvaluation, ply == previous.ply + 1 {
                let change = score - previous.score
                let movedWhite = !ply.isMultiple(of: 2)
                let gameTitle = self.currentNotificationTitle
                let clocks = self.clockText
                if (movedWhite ? -change : change) >= 100 {
                    Task { await self.notifyEvaluation(title: "Possible blunder", previous: previous.score, current: score, gameTitle: gameTitle, clocks: clocks) }
                } else if abs(change) >= 50 {
                    Task { await self.notifyEvaluation(title: "Evaluation change", previous: previous.score, current: score, gameTitle: gameTitle, clocks: clocks) }
                }
            }
            self.lastEvaluation = (score, ply)
        }
        followed.start()
        restartMonitoring()
        startupTask = Task {
            await loadBroadcasts()
            if roundID.isEmpty, let selection,
               broadcasts.contains(where: { $0.id == selection.round && $0.round.ongoing == true }) {
                roundID = selection.round
            }
        }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.suspendForSleep() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.wake() }
        })
    }
    private func restartMonitoring() {
        let previousTask = monitoringTask
        previousTask?.cancel()
        monitoringTask = Task {
            await previousTask?.value
            guard !Task.isCancelled else { return }
            await monitorSelection()
        }
    }
    func tokenChanged() { followed.restart(); restartMonitoring() }
    private func suspendForSleep() {
        monitoringTask?.cancel()
        followed.suspend()
        lastEvaluation = nil
        engine.reset()
        streamStatus = "Mac sleeping; reconnecting after wake."
    }
    private func wake() { followed.restart(); restartMonitoring() }
    func shutdown() {
        monitoringTask?.cancel(); monitoringTask = nil
        startupTask?.cancel(); startupTask = nil
        followed.suspend()
        engine.shutdown()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
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
            clockText = nil
            broadcastClock = nil
            currentNotificationTitle = "Chess Broadcast"
        }
        let gameURL = broadcasts.first(where: { $0.id == roundID })?.round.url?.appendingPathComponent(game.id)
        let selected = Selection(round: roundID, game: game.id, name: game.label, gameURL: gameURL)
        guard let groupID, !groupID.isEmpty, let defaults = UserDefaults(suiteName: groupID), let data = try? JSONEncoder().encode(selected) else {
            message = "Could not save the selection for the widget."
            return
        }
        defaults.set(data, forKey: selectionKey)
        if let fen = game.fen {
            savePosition(fen, for: selected, white: game.players?.first?.name, black: game.players?.dropFirst().first?.name)
        }
        selection = selected
        restartMonitoring()
        message = "Game selected. Add or refresh the Chess Position & Game widget."
        WidgetCenter.shared.reloadAllTimelines()
    }

    @MainActor func enableNotifications() async {
        do {
            let allowed = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
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
        content.body = moveText + (visibleClocks(game.clocks).map { "  \($0)" } ?? "") + (evaluation.map { "  \($0)" } ?? "")
        do { try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) }
        catch { await MainActor.run { message = "Could not send notification: \(error.localizedDescription)" } }
    }

    func notifyEvaluation(title: String, previous: Int, current: Int, gameTitle: String, clocks: String?) async {
        guard notificationsEnabled else { return }
        func label(_ score: Int) -> String {
            if abs(score) >= 100_000 { return score > 0 ? "mate for White" : "mate for Black" }
            return String(format: "%+.2f", Double(score) / 100)
        }
        let content = UNMutableNotificationContent()
        content.title = gameTitle
        content.body = "\(title) · \(label(previous)) → \(label(current))" + (clocks.map { " · \($0)" } ?? "")
        do { try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) }
        catch { await MainActor.run { message = "Could not send notification: \(error.localizedDescription)" } }
    }

    func notifyFinished(_ game: StreamGame, name: String) async {
        guard notificationsEnabled, let result = game.result else { return }
        let content = UNMutableNotificationContent()
        content.title = notificationTitle(game, fallback: name)
        content.body = "Game finished · \(result)" + (visibleClocks(game.clocks).map { " · \($0)" } ?? "")
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
                    guard !Task.isCancelled else { return }
                    needsClockSync = true
                    previous = nil
                    lastEvaluation = nil
                    engine.reset()
                    streamRetryAfter = 0
                    streamRateLimitDelay = 0
                    streamStatus = "Connected; waiting for the selected game…"
                }) { [self] pgn in
                    guard !Task.isCancelled, let game = parseStreamGame(pgn, gameID: selected.game) else { return }
                    streamStatus = "Live broadcast connected"
                    if selection?.round == selected.round, selection?.game == selected.game,
                       selection?.gameURL == nil, let gameURL = game.gameURL, var current = selection {
                        current.gameURL = gameURL
                        if let groupID, let defaults = UserDefaults(suiteName: groupID), let data = try? JSONEncoder().encode(current) {
                            defaults.set(data, forKey: selectionKey)
                            selection = current
                        }
                    }
                    currentNotificationTitle = notificationTitle(game, fallback: selected.name)
                    clockText = visibleClocks(game.clocks)
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
                        guard !Task.isCancelled else { return }
                        updateWidgetPosition(game, for: selected)
                    }
                    if let old = previous, game.moves == old.moves, game.clocks != old.clocks, let fen = game.fen {
                        savePosition(fen, for: selected, white: game.white, black: game.black, clocks: game.clocks)
                        WidgetCenter.shared.reloadTimelines(ofKind: "ChessPositionBoardV3")
                    }
                    if let old = previous, old.result == nil, game.result != nil {
                        await notifyFinished(game, name: selected.name)
                    }
                    previous = game
                }
                if Task.isCancelled { return }
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
    @State private var checkMessage = ""
    @State private var checking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Lichess settings").font(.title2.bold())
            Text("An optional personal access token helps with Lichess broadcast limits. Enable the study:read permission. The token is stored in macOS Keychain.")
            Link("Create a Lichess token", destination: URL(string: "https://lichess.org/account/oauth/token")!)
            Text(hasToken ? "A token is saved." : "No token saved.").foregroundStyle(.secondary)
            SecureField(hasToken ? "Enter a replacement token" : "Paste your Lichess token", text: $token)
            if !errorMessage.isEmpty { Text(errorMessage).foregroundStyle(.red) }
            if !checkMessage.isEmpty { Text(checkMessage).font(.callout).textSelection(.enabled) }
            HStack {
                Button("Remove token") { removeToken() }.disabled(!hasToken)
                Button(checking ? "Checking…" : "Check token") { Task { await checkToken() } }.disabled(!hasToken || checking)
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
            checkMessage = ""
            onChange()
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
    func removeToken() {
        do { try deleteLichessToken(); token = ""; hasToken = false; errorMessage = ""; checkMessage = ""; onChange() }
        catch { errorMessage = error.localizedDescription }
    }
    @MainActor func checkToken() async {
        checking = true
        defer { checking = false }
        do {
            guard let details = try await checkLichessToken() else {
                checkMessage = "The saved token is invalid, expired, or missing."
                return
            }
            let scopes = Set(details.scopes.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            let missing = ["study:read", "follow:read"].filter { !scopes.contains($0) }
            checkMessage = "Token belongs to \(details.userId). " + (missing.isEmpty ? "Permissions study:read and follow:read are present." : "Missing permissions: \(missing.joined(separator: ", ")).")
        } catch { checkMessage = "Token check failed: \(error.localizedDescription)" }
    }
}
