import Foundation

let groupID = Bundle.main.object(forInfoDictionaryKey: "ChessAppGroup") as? String
let selectionKey = "selectedGame"

struct Selection: Codable {
    let round: String
    let game: String
    let name: String
}

struct BroadcastList: Decodable { let active: [Broadcast] }
struct Broadcast: Decodable, Identifiable {
    struct Tour: Decodable { let name: String; let info: Info? }
    struct Info: Decodable { let tc: String? }
    struct Round: Decodable { let id: String; let name: String; let ongoing: Bool? }
    let tour: Tour
    let round: Round
    var id: String { round.id }
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

func fetchJSON<T: Decodable>(_ url: URL) async throws -> T {
    let (data, response) = try await URLSession.shared.data(from: url)
    guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else {
        throw URLError(.badServerResponse)
    }
    return try JSONDecoder().decode(T.self, from: data)
}
func fetchBroadcasts() async throws -> [Broadcast] {
    let list: BroadcastList = try await fetchJSON(URL(string: "https://lichess.org/api/broadcast/top")!)
    return list.active.filter { $0.round.ongoing == true }
}
func fetchGames(round: String) async throws -> [Game] {
    guard round.count == 8, round.allSatisfy({ $0.isASCII && $0.isLetter || $0.isNumber && $0.isASCII }) else { throw URLError(.badURL) }
    let detail: RoundDetail = try await fetchJSON(URL(string: "https://lichess.org/api/broadcast/-/-/\(round)")!)
    return detail.games
}
func loadSelection() -> Selection? {
    guard let groupID, !groupID.isEmpty, let data = UserDefaults(suiteName: groupID)?.data(forKey: selectionKey) else { return nil }
    return try? JSONDecoder().decode(Selection.self, from: data)
}
