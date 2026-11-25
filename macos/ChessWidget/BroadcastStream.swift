import Foundation
import ChessKit

struct StreamGame {
    let gameURL: URL?
    let moves: [String]
    let result: String?
    let fen: String?
    let clocks: String
    let white: String?
    let black: String?
}

func parseStreamGame(_ pgn: String, gameID: String) -> StreamGame? {
    let lines = pgn.components(separatedBy: .newlines)
    let headers = lines.filter { $0.hasPrefix("[") }
    func tag(_ name: String) -> String? {
        let prefix = "[\(name) \""
        guard let line = headers.first(where: { $0.hasPrefix(prefix) && $0.hasSuffix("\"]") }) else { return nil }
        return String(line.dropFirst(prefix.count).dropLast(2))
    }
    guard headers.contains(where: { line in
        (line.hasPrefix("[GameURL ") || line.hasPrefix("[Site ")) && line.contains("/\(gameID)\"")
    }) else { return nil }
    let resultLine = headers.first { $0.hasPrefix("[Result ") }
    let result = ["1-0", "0-1", "1/2-1/2"].first { resultLine?.contains("\"\($0)\"") == true }
    let text = lines.filter { !$0.hasPrefix("[") }.joined(separator: "\n")
    var clean = ""
    var clockScan = ""
    var comment = false
    var variation = 0
    var lineComment = false
    for char in text {
        if lineComment { if char == "\n" { lineComment = false }; continue }
        if comment {
            if variation == 0 { clockScan.append(char) }
            if char == "}" { comment = false }
            continue
        }
        if char == "{" { if variation == 0 { clockScan.append(char) }; comment = true; continue }
        if char == ";" { lineComment = true; continue }
        if char == "(" { variation += 1; continue }
        if char == ")" { variation = max(0, variation - 1); continue }
        if variation == 0 { clean.append(char); clockScan.append(char) }
    }
    let pattern = #"(?<![A-Za-z0-9])(?:O-O-O|O-O|[KQRBN]?[a-h]?[1-8]?x?[a-h][1-8](?:=[QRBN])?)[+#]?(?![A-Za-z0-9])"#
    let expression = try! NSRegularExpression(pattern: pattern)
    let range = NSRange(clean.startIndex..., in: clean)
    let moves = expression.matches(in: clean, range: range).compactMap { match in Range(match.range, in: clean).map { String(clean[$0]) } }
    let fenHeader = headers.first { $0.hasPrefix("[FEN \"") }
    let fenValue = fenHeader.map { String($0.dropFirst(6).dropLast(2)) }
    let initial = fenValue.flatMap { Position(fen: $0) } ?? (fenValue == nil ? .standard : nil)
    var fen: String?
    if let initial, !headers.contains(where: { $0.hasPrefix("[Variant ") && $0 != "[Variant \"Standard\"]" }) {
        var replay = ChessKit.Game(startingWith: initial)
        var index = replay.startingIndex
        var valid = true
        for move in moves {
            let next = replay.make(move: move, from: index)
            if next == index { valid = false; break }
            index = next
        }
        if valid { fen = replay.positions[index]?.fen }
    }
    let clockPattern = #"(?<![A-Za-z0-9])(O-O-O|O-O|[KQRBN]?[a-h]?[1-8]?x?[a-h][1-8](?:=[QRBN])?)[+#]?[!?]*\s*((?:\{[^}]*\}\s*)*)"#
    let clockExpression = try! NSRegularExpression(pattern: clockPattern)
    let clockTag = try! NSRegularExpression(pattern: #"\[%clk\s+([^\]]+)\]"#)
    let candidates = clockExpression.matches(in: clockScan, range: NSRange(clockScan.startIndex..., in: clockScan))
    var values: [String?] = [nil, nil]
    if candidates.count == moves.count {
        let startsWithBlack = initial?.sideToMove == .black
        for (index, match) in candidates.enumerated() {
            guard let commentsRange = Range(match.range(at: 2), in: clockScan) else { continue }
            let comments = String(clockScan[commentsRange])
            guard let tag = clockTag.firstMatch(in: comments, range: NSRange(comments.startIndex..., in: comments)),
                  let valueRange = Range(tag.range(at: 1), in: comments) else { continue }
            values[(index + (startsWithBlack ? 1 : 0)) % 2] = String(comments[valueRange]).trimmingCharacters(in: .whitespaces)
        }
    }
    let candidate = tag("GameURL").flatMap(URL.init(string:))
    let gameURL = candidate.flatMap { url in
        url.scheme == "https" && url.host?.lowercased() == "lichess.org" && url.lastPathComponent == gameID ? url : nil
    }
    return StreamGame(gameURL: gameURL, moves: moves, result: result, fen: fen, clocks: "\(values[0] ?? "?") – \(values[1] ?? "?")", white: tag("White"), black: tag("Black"))
}

enum StreamError: Error { case rateLimited, invalidResponse, tooLarge }

enum StreamEvent {
    case connected
    case game(String)
}

private final class StreamReader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    let continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    private var buffer = Data()

    init(_ continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation) {
        self.continuation = continuation
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let response = response as? HTTPURLResponse else {
            continuation.finish(throwing: StreamError.invalidResponse)
            completionHandler(.cancel)
            return
        }
        if response.statusCode == 429 {
            continuation.finish(throwing: StreamError.rateLimited)
            completionHandler(.cancel)
            return
        }
        guard (200..<300).contains(response.statusCode) else {
            continuation.finish(throwing: LichessHTTPError(status: response.statusCode))
            completionHandler(.cancel)
            return
        }
        continuation.yield(.connected)
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // PGN records end with three newlines; CRLF is normalized across chunks.
        for byte in data where byte != 13 {
            buffer.append(byte)
            if buffer.count > 1_000_000 {
                continuation.finish(throwing: StreamError.tooLarge)
                dataTask.cancel()
                return
            }
            if buffer.suffix(3).elementsEqual([10, 10, 10]) {
                let pgn = String(decoding: buffer.dropLast(3), as: UTF8.self)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                buffer.removeAll(keepingCapacity: true)
                if !pgn.isEmpty { continuation.yield(.game(pgn)) }
            }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { continuation.finish(throwing: error) }
        else { continuation.finish() }
    }
}

func streamPGN(url: URL, onConnected: () async -> Void, onPGN: @escaping (String) async -> Void) async throws {
    var request = try lichessRequest(url)
    request.timeoutInterval = 120
    var continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation!
    let events = AsyncThrowingStream<StreamEvent, Error> { continuation = $0 }
    let reader = StreamReader(continuation)
    let session = URLSession(configuration: .ephemeral, delegate: reader, delegateQueue: nil)
    defer { session.invalidateAndCancel() }
    try await withTaskCancellationHandler {
        session.dataTask(with: request).resume()
        for try await event in events {
            try Task.checkCancellation()
            switch event {
            case .connected: await onConnected()
            case .game(let pgn): await onPGN(pgn)
            }
        }
    } onCancel: {
        session.invalidateAndCancel()
        continuation.finish()
    }
}

func streamRound(_ round: String, onConnected: () async -> Void, onPGN: @escaping (String) async -> Void) async throws {
    guard round.count == 8, round.allSatisfy({ $0.isASCII && $0.isLetter || $0.isASCII && $0.isNumber }),
          let url = URL(string: "https://lichess.org/api/stream/broadcast/round/\(round).pgn?clocks=true") else { throw URLError(.badURL) }
    try await streamPGN(url: url, onConnected: onConnected, onPGN: onPGN)
}
