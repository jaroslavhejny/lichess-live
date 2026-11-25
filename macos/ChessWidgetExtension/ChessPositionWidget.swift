import SwiftUI
import WidgetKit

struct PositionEntry: TimelineEntry {
    let date: Date
    let name: String
    let fen: String?
    let status: String
    let evaluation: String?
    let details: SavedPosition?
}
struct PositionProvider: TimelineProvider {
    func placeholder(in context: Context) -> PositionEntry {
        PositionEntry(date: .now, name: "Chess Position", fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR", status: "", evaluation: nil, details: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (PositionEntry) -> Void) { completion(placeholder(in: context)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PositionEntry>) -> Void) {
        Task {
            let entry: PositionEntry
            if let selection = loadSelection() {
                let saved = loadPosition(for: selection)
                if let saved, Date().timeIntervalSince(saved.updatedAt) < 90 {
                    entry = PositionEntry(date: saved.updatedAt, name: selection.name, fen: saved.fen, status: "", evaluation: saved.evaluation, details: saved)
                } else {
                    do {
                        let games = try await fetchGames(round: selection.round, useToken: false)
                        if let latest = loadPosition(for: selection), latest.updatedAt > (saved?.updatedAt ?? .distantPast) {
                            entry = PositionEntry(date: latest.updatedAt, name: selection.name, fen: latest.fen, status: "", evaluation: latest.evaluation, details: latest)
                        } else if let game = games.first(where: { $0.id == selection.game }), let fen = game.fen {
                            savePosition(fen, for: selection, white: game.players?.first?.name, black: game.players?.dropFirst().first?.name)
                            let latest = loadPosition(for: selection)
                            entry = PositionEntry(date: .now, name: game.label, fen: fen, status: "Updated now", evaluation: latest?.fen == fen ? latest?.evaluation : nil, details: latest?.fen == fen ? latest : nil)
                        } else {
                            entry = PositionEntry(date: saved?.updatedAt ?? .now, name: selection.name, fen: saved?.fen, status: "Position unavailable", evaluation: saved?.evaluation, details: saved)
                        }
                    } catch {
                        let latest = loadPosition(for: selection) ?? saved
                        entry = PositionEntry(date: latest?.updatedAt ?? .now, name: selection.name, fen: latest?.fen, status: "Could not load position", evaluation: latest?.evaluation, details: latest)
                    }
                }
            } else {
                entry = PositionEntry(date: .now, name: "Chess Position", fen: nil, status: "Choose a game in the app", evaluation: nil, details: nil)
            }
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
        }
    }
}

struct PositionWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PositionEntry

    var body: some View {
        Group {
            if let fen = entry.fen {
                if family == .systemMedium {
                    GeometryReader { geometry in
                        HStack(spacing: 0) {
                            BoardView(fen: fen)
                                .frame(width: geometry.size.height, height: geometry.size.height)
                            information
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                        }
                    }
                } else {
                    BoardView(fen: fen)
                        .overlay(alignment: .bottomTrailing) {
                            if let evaluation = entry.evaluation {
                                Text(evaluation)
                                    .font(.system(size: 11, weight: .bold, design: .rounded).monospacedDigit())
                                    .foregroundStyle(.white)
                                    .shadow(color: .black.opacity(0.8), radius: 1)
                                    .padding(.horizontal, 5).padding(.vertical, 3)
                                    .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 5))
                                    .padding(3)
                            }
                        }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "square.grid.3x3").font(.largeTitle)
                    Text(entry.name).font(.caption.bold()).lineLimit(1)
                    Text(entry.status).font(.caption2).multilineTextAlignment(.center)
                }.padding()
            }
        }.containerBackground(.background, for: .widget)
    }

    private var information: some View {
        let names = entry.name.components(separatedBy: " – ")
        let white = entry.details?.white ?? names.first ?? "White"
        let black = entry.details?.black ?? (names.count > 1 ? names[1] : "Black")
        return VStack(alignment: .leading, spacing: 7) {
            player("WHITE", name: white)
            player("BLACK", name: black)
            Divider()
            HStack(alignment: .top, spacing: 8) {
                metric("LAST MOVE", value: entry.details?.lastMove ?? "—")
                Spacer(minLength: 2)
                metric("EVALUATION", value: entry.evaluation ?? "—")
            }
            if let clocks = visibleClocks(entry.details?.clocks) {
                metric("CLOCKS · LAST REPORTED", value: clocks)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
    }

    private func player(_ label: String, name: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary)
            Text(name).font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.75)
        }
    }

    private func metric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            Text(value).font(.system(size: 11, weight: .medium, design: .rounded).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.8)
        }
    }
}

@main
struct ChessPositionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ChessPositionBoardV3", provider: PositionProvider()) { entry in
            PositionWidgetView(entry: entry)
        }
        .configurationDisplayName("Chess Position & Game")
        .description("Shows the latest position of your selected broadcast game.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}
