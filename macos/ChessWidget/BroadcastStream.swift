import Foundation

struct StreamGame {
    let moves: [String]
    let result: String?
}

func parseStreamGame(_ pgn: String, gameID: String) -> StreamGame? {
    let lines = pgn.components(separatedBy: .newlines)
    let headers = lines.filter { $0.hasPrefix("[") }
    guard headers.contains(where: { line in
        (line.hasPrefix("[GameURL ") || line.hasPrefix("[Site ")) && line.contains("/\(gameID)\"")
    }) else { return nil }
    let resultLine = headers.first { $0.hasPrefix("[Result ") }
    let result = ["1-0", "0-1", "1/2-1/2"].first { resultLine?.contains("\"\($0)\"") == true }
    let text = lines.filter { !$0.hasPrefix("[") }.joined(separator: "\n")
    var clean = ""
    var comment = false
    var variation = 0
    var lineComment = false
    for char in text {
        if lineComment { if char == "\n" { lineComment = false }; continue }
        if comment { if char == "}" { comment = false }; continue }
        if char == "{" { comment = true; continue }
        if char == ";" { lineComment = true; continue }
        if char == "(" { variation += 1; continue }
        if char == ")" { variation = max(0, variation - 1); continue }
        if variation == 0 { clean.append(char) }
    }
    let pattern = #"(?<![A-Za-z0-9])(?:O-O-O|O-O|[KQRBN]?[a-h]?[1-8]?x?[a-h][1-8](?:=[QRBN])?)[+#]?(?![A-Za-z0-9])"#
    let expression = try! NSRegularExpression(pattern: pattern)
    let range = NSRange(clean.startIndex..., in: clean)
    let moves = expression.matches(in: clean, range: range).compactMap { match in Range(match.range, in: clean).map { String(clean[$0]) } }
    return StreamGame(moves: moves, result: result)
}

func streamRound(_ round: String, onConnected: () async -> Void, onPGN: @escaping (String) async -> Void) async throws {
    guard round.count == 8, round.allSatisfy({ $0.isASCII && $0.isLetter || $0.isASCII && $0.isNumber }),
          let url = URL(string: "https://lichess.org/api/stream/broadcast/round/\(round).pgn?clocks=true") else { throw URLError(.badURL) }
    var request = URLRequest(url: url)
    request.timeoutInterval = 120
    let session = URLSession(configuration: .ephemeral)
    defer { session.invalidateAndCancel() }
    try await withTaskCancellationHandler {
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        if response.statusCode == 429 { throw StreamError.rateLimited }
        guard (200..<300).contains(response.statusCode) else { throw URLError(.badServerResponse) }
        await onConnected()
        var lines: [String] = []
        var blankCount = 0
        var length = 0
        for try await line in bytes.lines {
            try Task.checkCancellation()
            if line.isEmpty { blankCount += 1 } else { blankCount = 0 }
            lines.append(line)
            length += line.utf8.count + 1
            if length > 1_000_000 { throw URLError(.dataLengthExceedsMaximum) }
            if blankCount >= 2 {
                let pgn = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                lines.removeAll(keepingCapacity: true); length = 0; blankCount = 0
                if !pgn.isEmpty { await onPGN(pgn) }
            }
        }
    } onCancel: {
        session.invalidateAndCancel()
    }
}
enum StreamError: Error { case rateLimited }
