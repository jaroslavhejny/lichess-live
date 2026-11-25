import SwiftUI
import WidgetKit

struct PositionEntry: TimelineEntry {
    let date: Date
    let name: String
    let fen: String?
    let status: String
}
struct PositionProvider: TimelineProvider {
    func placeholder(in context: Context) -> PositionEntry {
        PositionEntry(date: .now, name: "Chess Position", fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR", status: "")
    }
    func getSnapshot(in context: Context, completion: @escaping (PositionEntry) -> Void) { completion(placeholder(in: context)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<PositionEntry>) -> Void) {
        Task {
            let entry: PositionEntry
            if let selection = loadSelection() {
                do {
                    let games = try await fetchGames(round: selection.round)
                    if let game = games.first(where: { $0.id == selection.game }), let fen = game.fen {
                        entry = PositionEntry(date: .now, name: game.label, fen: fen, status: "Updated now")
                    } else {
                        entry = PositionEntry(date: .now, name: selection.name, fen: nil, status: "Position unavailable")
                    }
                } catch { entry = PositionEntry(date: .now, name: selection.name, fen: nil, status: "Could not load position") }
            } else { entry = PositionEntry(date: .now, name: "Chess Position", fen: nil, status: "Choose a game in the app") }
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60))))
        }
    }
}
@main
struct ChessPositionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ChessPositionBoardV2", provider: PositionProvider()) { entry in
            Group {
                if let fen = entry.fen {
                    BoardView(fen: fen)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "square.grid.3x3").font(.largeTitle)
                        Text(entry.name).font(.caption.bold()).lineLimit(1)
                        Text(entry.status).font(.caption2).multilineTextAlignment(.center)
                    }.padding()
                }
            }.containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Chess Position Board")
        .description("Shows the latest position of your selected broadcast game.")
        .supportedFamilies([.systemSmall, .systemMedium])
        .contentMarginsDisabled()
    }
}
