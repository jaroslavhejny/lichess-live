import Foundation
import Combine

@MainActor
final class StockfishEngine: ObservableObject {
    @Published private(set) var status = "Waiting for a position"
    @Published private(set) var evaluation: String?
    private(set) var evaluatedFEN: String?
    var onEvaluation: ((Int, Int, Int?) -> Void)?
    private var process: Process?
    private var input: Pipe?
    private var output: Pipe?
    private var buffer = ""
    private var current: Position?
    private var pending: Position?
    private var ready = false
    private var analyzing = false
    private var generation = 0
    private var engineName = "Stockfish"

    private struct Position {
        let fen: String
        let ply: Int
        let generation: Int
        var score: Int?
        var display: String?
        var mate: Int?
        var depth: Int?
    }

    func reset() {
        generation += 1
        pending = nil
        evaluation = nil
        evaluatedFEN = nil
        status = "Waiting for a position"
        if analyzing { send("stop") }
    }

    func shutdown() {
        onEvaluation = nil
        pending = nil
        output?.fileHandleForReading.readabilityHandler = nil
        if process?.isRunning == true { process?.terminate() }
    }

    func analyze(fen: String, ply: Int) {
        guard !fen.contains("\n"), !fen.contains("\r") else { return }
        pending = Position(fen: fen, ply: ply, generation: generation)
        if process == nil { start() }
        else if analyzing { send("stop") }
        else if ready { startPending() }
    }

    private func start() {
        guard let path = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("stockfish"),
              FileManager.default.isExecutableFile(atPath: path.path) else {
            status = "Stockfish is unavailable in this build"
            return
        }
        let child = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        child.executableURL = path
        child.standardInput = stdin
        child.standardOutput = stdout
        child.standardError = FileHandle.nullDevice
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor [weak self] in self?.receive(data) }
        }
        child.terminationHandler = { [weak self] process in
            let code = process.terminationStatus
            Task { @MainActor [weak self] in self?.terminated(code: code) }
        }
        do {
            try child.run()
            process = child; input = stdin; output = stdout
            status = "Starting Stockfish…"
            send("uci")
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            status = "Could not start Stockfish: \(error.localizedDescription)"
        }
    }

    private func send(_ command: String) {
        guard let data = (command + "\n").data(using: .utf8) else { return }
        do { try input?.fileHandleForWriting.write(contentsOf: data) }
        catch { status = "Stockfish communication failed" }
    }

    private func startPending() {
        guard let position = pending else { return }
        pending = nil
        current = position
        analyzing = true
        status = "Analyzing…"
        send("position fen \(position.fen)")
        send("go movetime 3000")
    }

    private func receive(_ data: Data) {
        buffer += String(decoding: data, as: UTF8.self)
        while let newline = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<newline]).trimmingCharacters(in: .whitespacesAndNewlines)
            buffer.removeSubrange(...newline)
            if line.hasPrefix("id name ") { engineName = String(line.dropFirst("id name ".count)) }
            else if line == "uciok" { send("setoption name Threads value 1"); send("isready") }
            else if line == "readyok" { ready = true; if !analyzing { startPending() } }
            else if line.hasPrefix("info "), !line.contains(" lowerbound"), !line.contains(" upperbound"), var position = current {
                let parts = line.split(separator: " ")
                if let i = parts.firstIndex(of: "score"), i + 2 < parts.count, let raw = Int(parts[i + 2]), ["cp", "mate"].contains(parts[i + 1]) {
                    if let depthIndex = parts.firstIndex(of: "depth"), depthIndex + 1 < parts.count, let depth = Int(parts[depthIndex + 1]) {
                        position.depth = depth
                    }
                    let side = position.fen.split(separator: " ").dropFirst().first == "b" ? -1 : 1
                    let score = raw * side
                    if parts[i + 1] == "cp" {
                        position.score = score
                        position.mate = nil
                        position.display = String(format: "%+.2f", locale: Locale.current, Double(score) / 100)
                    } else {
                        position.mate = score
                        position.score = score > 0 ? 100_000 : (score < 0 ? -100_000 : 0)
                        position.display = "M\(score > 0 ? "+" : "")\(score)"
                    }
                    current = position
                }
            } else if line.hasPrefix("bestmove ") {
                let finished = current
                current = nil; analyzing = false
                if let finished, finished.generation == generation, pending == nil, let score = finished.score, let display = finished.display {
                    evaluation = display
                    evaluatedFEN = finished.fen
                    status = engineName + (finished.depth.map { " · depth \($0)" } ?? "")
                    onEvaluation?(score, finished.ply, finished.mate)
                }
                if pending != nil { startPending() }
            }
        }
    }

    private func terminated(code: Int32) {
        output?.fileHandleForReading.readabilityHandler = nil
        process = nil; input = nil; output = nil
        current = nil; pending = nil; ready = false; analyzing = false
        status = "Stockfish stopped (\(code))"
    }

    deinit {
        output?.fileHandleForReading.readabilityHandler = nil
        if process?.isRunning == true { process?.terminate() }
    }
}
