import Foundation

let groupID = Bundle.main.object(forInfoDictionaryKey: "ChessAppGroup") as? String
let selectionKey = "selectedGame"
let positionKey = "latestPosition"

func visibleClocks(_ clocks: String?) -> String? {
    guard let clocks else { return nil }
    let parts = clocks.components(separatedBy: " – ")
    guard parts.count == 2 else { return nil }
    let white = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
    let black = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
    let hasWhite = !white.isEmpty && white != "?"
    let hasBlack = !black.isEmpty && black != "?"
    if hasWhite && hasBlack { return "\(white) – \(black)" }
    if hasWhite { return "White \(white)" }
    if hasBlack { return "Black \(black)" }
    return nil
}

struct Selection: Codable {
    let round: String
    let game: String
    let name: String
    var gameURL: URL? = nil
}
struct SavedPosition: Codable {
    let round: String
    let game: String
    let fen: String
    let updatedAt: Date
    let evaluation: String?
    let white: String?
    let black: String?
    let lastMove: String?
    let clocks: String?
}

func loadPosition(for selection: Selection) -> SavedPosition? {
    guard let groupID, let data = UserDefaults(suiteName: groupID)?.data(forKey: positionKey),
          let position = try? JSONDecoder().decode(SavedPosition.self, from: data),
          position.round == selection.round, position.game == selection.game else { return nil }
    return position
}

func savePosition(_ fen: String, for selection: Selection, white: String? = nil, black: String? = nil, lastMove: String? = nil, clocks: String? = nil) {
    guard let current = loadSelection(), current.round == selection.round, current.game == selection.game,
          let groupID, let defaults = UserDefaults(suiteName: groupID) else { return }
    let old = loadPosition(for: selection)
    let samePosition = old?.fen == fen
    let position = SavedPosition(round: selection.round, game: selection.game, fen: fen, updatedAt: Date(),
        evaluation: samePosition ? old?.evaluation : nil, white: white ?? old?.white, black: black ?? old?.black,
        lastMove: lastMove ?? (samePosition ? old?.lastMove : nil), clocks: clocks ?? (samePosition ? old?.clocks : nil))
    guard let data = try? JSONEncoder().encode(position) else { return }
    defaults.set(data, forKey: positionKey)
}

func saveEvaluation(_ evaluation: String, fen: String, for selection: Selection) -> Bool {
    guard let current = loadSelection(), current.round == selection.round, current.game == selection.game,
          let position = loadPosition(for: selection), position.fen == fen,
          let groupID, let defaults = UserDefaults(suiteName: groupID),
          let data = try? JSONEncoder().encode(SavedPosition(round: position.round, game: position.game, fen: position.fen, updatedAt: position.updatedAt, evaluation: evaluation, white: position.white, black: position.black, lastMove: position.lastMove, clocks: position.clocks)) else { return false }
    defaults.set(data, forKey: positionKey)
    return true
}

struct BroadcastList: Decodable { let active: [Broadcast]; let upcoming: [Broadcast]? }
struct Broadcast: Decodable, Identifiable {
    struct Tour: Decodable { let name: String; let info: Info? }
    struct Info: Decodable { let tc: String? }
    struct Round: Decodable { let id: String; let name: String; let ongoing: Bool?; let startsAt: Double?; let url: URL? }
    let tour: Tour
    let round: Round
    var id: String { round.id }
    var label: String {
        let tempo = tour.info?.tc.map { " (\($0))" } ?? ""
        let start: String
        if round.ongoing == true { start = " · Live" }
        else if let timestamp = round.startsAt, timestamp / 1000 > Date().timeIntervalSince1970 {
            let date = Date(timeIntervalSince1970: timestamp / 1000)
            start = " · Starts \(date.formatted(date: .abbreviated, time: .shortened))"
        } else { start = "" }
        return "\(tour.name) – \(round.name)\(tempo)\(start)"
    }
}
struct RoundDetail: Decodable { let games: [Game] }
struct Game: Decodable, Identifiable {
    struct Player: Decodable { let name: String?; let rating: Int? }
    let id: String
    let name: String?
    let fen: String?
    let players: [Player]?
    let status: String?
    let lastMove: String?
    var label: String {
        guard let players, players.count == 2, players.allSatisfy({ $0.name != nil }) else { return name ?? id }
        return players.map { ($0.name ?? "") + ($0.rating.map { " (\($0))" } ?? "") }.joined(separator: " – ")
    }
    var listLabel: String {
        guard let status, ["1-0", "0-1", "1/2-1/2", "½-½"].contains(status) else { return label }
        return "\(label)  ·  \(status)"
    }
}

func fetchJSON<T: Decodable>(_ url: URL, useToken: Bool = true) async throws -> T {
    let (data, response) = try await URLSession.shared.data(for: lichessRequest(url, useToken: useToken))
    guard let response = response as? HTTPURLResponse else {
        throw URLError(.badServerResponse)
    }
    guard (200..<300).contains(response.statusCode) else { throw LichessHTTPError(status: response.statusCode) }
    return try JSONDecoder().decode(T.self, from: data)
}
struct LichessHTTPError: LocalizedError {
    let status: Int
    var errorDescription: String? { "Lichess returned HTTP \(status)\(status == 401 || status == 403 ? "; check your token and its permissions" : "")." }
}
func fetchBroadcasts() async throws -> [Broadcast] {
    let list: BroadcastList = try await fetchJSON(URL(string: "https://lichess.org/api/broadcast/top")!)
    var seen = Set<String>()
    return (list.active + (list.upcoming ?? []))
        .filter { seen.insert($0.id).inserted }
        .sorted {
            if ($0.round.ongoing == true) != ($1.round.ongoing == true) { return $0.round.ongoing == true }
            return ($0.round.startsAt ?? .greatestFiniteMagnitude) < ($1.round.startsAt ?? .greatestFiniteMagnitude)
        }
}
func fetchGames(round: String, useToken: Bool = true) async throws -> [Game] {
    guard round.count == 8, round.allSatisfy({ $0.isASCII && $0.isLetter || $0.isNumber && $0.isASCII }) else { throw URLError(.badURL) }
    let detail: RoundDetail = try await fetchJSON(URL(string: "https://lichess.org/api/broadcast/-/-/\(round)")!, useToken: useToken)
    return detail.games
}
func loadSelection() -> Selection? {
    guard let groupID, !groupID.isEmpty, let data = UserDefaults(suiteName: groupID)?.data(forKey: selectionKey) else { return nil }
    return try? JSONDecoder().decode(Selection.self, from: data)
}
