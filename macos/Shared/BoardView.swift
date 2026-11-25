import SwiftUI

struct BoardView: View {
    let fen: String
    private let pieces = Set("KQRBNPkqrbnp")
    private var squares: [Character?] {
        let board = fen.split(separator: " ").first ?? ""
        let ranks = board.split(separator: "/")
        guard ranks.count == 8 else { return Array(repeating: nil, count: 64) }
        var result: [Character?] = []
        for rank in ranks {
            var row: [Character?] = []
            for character in rank {
                if let count = character.wholeNumberValue, (1...8).contains(count) { row += Array(repeating: nil, count: count) }
                else if pieces.contains(character) { row.append(character) }
                else { return Array(repeating: nil, count: 64) }
            }
            guard row.count == 8 else { return Array(repeating: nil, count: 64) }
            result += row
        }
        return result
    }
    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height) / 8
            let positions = squares
            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<8, id: \.self) { column in
                            let piece = positions[row * 8 + column]
                            ZStack {
                                Rectangle().fill((row + column).isMultiple(of: 2) ? Color(red: 0.93, green: 0.89, blue: 0.80) : Color(red: 0.48, green: 0.59, blue: 0.42))
                                if let piece {
                                    Image("\(piece.isUppercase ? "w" : "b")\(piece.uppercased())")
                                        .resizable().aspectRatio(contentMode: .fit)
                                        .frame(width: size, height: size)
                                }
                            }.frame(width: size, height: size)
                        }
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.aspectRatio(1, contentMode: .fit)
    }
}
