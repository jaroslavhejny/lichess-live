import SwiftUI

struct BroadcastClock {
    let white: Int?
    let black: Int?
    let whiteToMove: Bool
    let receivedAt: Date
    let running: Bool

    init?(game: StreamGame, receivedAt: Date = .now) {
        let values = game.clocks.components(separatedBy: " – ")
        guard values.count == 2, let fen = game.fen else { return nil }
        let fields = fen.split(separator: " ")
        guard fields.count > 1, fields[1] == "w" || fields[1] == "b" else { return nil }
        white = Self.seconds(values[0])
        black = Self.seconds(values[1])
        whiteToMove = fields[1] == "w"
        self.receivedAt = receivedAt
        running = game.result == nil
    }

    private static func seconds(_ clock: String) -> Int? {
        let parts = clock.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, let hours = Int(parts[0]), let minutes = Int(parts[1]),
              let seconds = Double(parts[2]), hours >= 0, (0..<60).contains(minutes),
              seconds >= 0, seconds < 60, hours < 1000 else { return nil }
        return hours * 3600 + minutes * 60 + Int(seconds.rounded(.down))
    }

    static func format(_ seconds: Int?) -> String {
        guard let seconds else { return "?" }
        let remaining = max(0, seconds)
        return String(format: "%d:%02d:%02d", remaining / 3600, (remaining / 60) % 60, remaining % 60)
    }

    func elapsed(at now: Date) -> Int {
        guard running else { return 0 }
        return max(0, Int(now.timeIntervalSince(receivedAt)))
    }

    func display(whiteSide: Bool, at now: Date) -> String {
        let value = whiteSide ? white : black
        let active = running && whiteToMove == whiteSide
        return Self.format(value.map { $0 - (active ? elapsed(at: now) : 0) })
    }
}

struct ClockPanel: View {
    let clock: BroadcastClock

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            HStack(spacing: 14) {
                clockLabel("White", whiteSide: true, now: timeline.date)
                clockLabel("Black", whiteSide: false, now: timeline.date)
                if clock.running {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("≈ \(BroadcastClock.format(clock.elapsed(at: timeline.date)))")
                            .font(.callout.monospacedDigit().weight(.medium))
                        Text("Move time · since update").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .help("Times are estimated from the latest broadcast update. They can differ from the official clocks.")
        }
    }

    private func clockLabel(_ label: String, whiteSide: Bool, now: Date) -> some View {
        let active = clock.running && clock.whiteToMove == whiteSide
        return VStack(alignment: .trailing, spacing: 2) {
            Text("\(active ? "≈ " : "")\(clock.display(whiteSide: whiteSide, at: now))")
                .font(.callout.monospacedDigit().weight(active ? .bold : .regular))
                .foregroundStyle(active ? Color.accentColor : Color.primary)
            Text(label + (active ? " · to move" : ""))
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}
