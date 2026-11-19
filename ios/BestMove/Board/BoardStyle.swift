import SwiftUI
import ChessCore

struct BoardTheme: Identifiable, Hashable {
    let id: String
    let name: String
    let light: Color
    let dark: Color
    /// Tint laid over the from/to squares of the last move.
    let highlight: Color

    static let walnut = BoardTheme(id: "walnut", name: String(localized: "Walnut", comment: "Board colour theme"),
                                   light: Color(hex: 0xEEDCBC), dark: Color(hex: 0xB0855F),
                                   highlight: Color(hex: 0xF2C14E, opacity: 0.42))
    static let slate = BoardTheme(id: "slate", name: String(localized: "Slate", comment: "Board colour theme"),
                                  light: Color(hex: 0xDCE1E6), dark: Color(hex: 0x7C8C9E),
                                  highlight: Color(hex: 0x9FD2FF, opacity: 0.45))
    static let emerald = BoardTheme(id: "emerald", name: String(localized: "Tournament", comment: "Board colour theme"),
                                    light: Color(hex: 0xEDEDD3), dark: Color(hex: 0x76975A),
                                    highlight: Color(hex: 0xF5F06A, opacity: 0.45))
    static let obsidian = BoardTheme(id: "obsidian", name: String(localized: "Obsidian", comment: "Board colour theme"),
                                     light: Color(hex: 0xC7C0B3), dark: Color(hex: 0x5D5850),
                                     highlight: Color(hex: 0xE6B85C, opacity: 0.45))
    static let rosewood = BoardTheme(id: "rosewood", name: String(localized: "Rosewood", comment: "Board colour theme"),
                                     light: Color(hex: 0xF0D9C8), dark: Color(hex: 0xA2665A),
                                     highlight: Color(hex: 0xFFC46B, opacity: 0.42))

    static let all: [BoardTheme] = [.walnut, .emerald, .slate, .obsidian, .rosewood]
    static func named(_ id: String) -> BoardTheme { all.first { $0.id == id } ?? .walnut }
}

enum PieceSet: String, CaseIterable, Identifiable {
    case cburnett, merida, chessnut

    var id: String { rawValue }

    var name: String {
        switch self {
        case .cburnett: String(localized: "Classic", comment: "Piece set name")
        case .merida: "Merida"
        case .chessnut: "Chessnut"
        }
    }

    var credit: String {
        switch self {
        case .cburnett: "Colin M.L. Burnett — GPLv2+"
        case .merida: "Armando Hernandez Marroquin — GPLv2+"
        case .chessnut: "Alexis Luengas — Apache 2.0"
        }
    }

    func imageName(_ piece: Piece) -> String { "Pieces-\(rawValue)/\(piece.code)" }
}

private struct BoardThemeKey: EnvironmentKey { static let defaultValue = BoardTheme.walnut }
private struct PieceSetKey: EnvironmentKey { static let defaultValue = PieceSet.cburnett }

extension EnvironmentValues {
    var boardTheme: BoardTheme {
        get { self[BoardThemeKey.self] }
        set { self[BoardThemeKey.self] = newValue }
    }

    var pieceSet: PieceSet {
        get { self[PieceSetKey.self] }
        set { self[PieceSetKey.self] = newValue }
    }
}

/// Maps squares to points for a board drawn with the given side at the bottom.
struct BoardGeometry {
    let size: CGFloat
    let orientation: PieceColor

    var squareSize: CGFloat { size / 8 }

    func column(of square: Square) -> Int { orientation == .white ? square.file : 7 - square.file }
    func row(of square: Square) -> Int { orientation == .white ? 7 - square.rank : square.rank }

    func rect(of square: Square) -> CGRect {
        CGRect(x: CGFloat(column(of: square)) * squareSize, y: CGFloat(row(of: square)) * squareSize,
               width: squareSize, height: squareSize)
    }

    func center(of square: Square) -> CGPoint {
        CGPoint(x: (CGFloat(column(of: square)) + 0.5) * squareSize, y: (CGFloat(row(of: square)) + 0.5) * squareSize)
    }

    func square(at point: CGPoint) -> Square? {
        guard point.x >= 0, point.y >= 0, point.x < size, point.y < size else { return nil }
        let col = min(7, Int(point.x / squareSize)), row = min(7, Int(point.y / squareSize))
        return orientation == .white ? Square(file: col, rank: 7 - row) : Square(file: 7 - col, rank: row)
    }
}
