public enum PieceColor: UInt8, Sendable, Hashable, CaseIterable {
    case white, black

    public var opposite: PieceColor { self == .white ? .black : .white }
    public var name: String { self == .white ? "White" : "Black" }
    /// Pawn push direction in ranks.
    var forward: Int { self == .white ? 1 : -1 }
    var homeRank: Int { self == .white ? 0 : 7 }
}

public enum PieceKind: UInt8, Sendable, Hashable, CaseIterable {
    case pawn, knight, bishop, rook, queen, king

    public var name: String {
        switch self {
        case .pawn: "pawn"
        case .knight: "knight"
        case .bishop: "bishop"
        case .rook: "rook"
        case .queen: "queen"
        case .king: "king"
        }
    }

    /// Uppercase SAN letter; empty for pawns.
    public var sanLetter: String {
        switch self {
        case .pawn: ""
        case .knight: "N"
        case .bishop: "B"
        case .rook: "R"
        case .queen: "Q"
        case .king: "K"
        }
    }

    /// Standard material value in pawns.
    public var value: Int {
        switch self {
        case .pawn: 1
        case .knight, .bishop: 3
        case .rook: 5
        case .queen: 9
        case .king: 0
        }
    }

    public static let promotionChoices: [PieceKind] = [.queen, .rook, .bishop, .knight]

    init?(letter: Character) {
        switch letter.lowercased() {
        case "p": self = .pawn
        case "n": self = .knight
        case "b": self = .bishop
        case "r": self = .rook
        case "q": self = .queen
        case "k": self = .king
        default: return nil
        }
    }

    var lowercaseLetter: Character {
        switch self {
        case .pawn: "p"
        case .knight: "n"
        case .bishop: "b"
        case .rook: "r"
        case .queen: "q"
        case .king: "k"
        }
    }
}

public struct Piece: Hashable, Sendable, CustomStringConvertible {
    public let color: PieceColor
    public let kind: PieceKind

    public init(_ color: PieceColor, _ kind: PieceKind) {
        self.color = color
        self.kind = kind
    }

    /// FEN letter: uppercase for White, lowercase for Black.
    public init?(fen: Character) {
        guard let kind = PieceKind(letter: fen) else { return nil }
        self.init(fen.isUppercase ? .white : .black, kind)
    }

    public var fen: Character {
        let letter = kind.lowercaseLetter
        return color == .white ? Character(letter.uppercased()) : letter
    }

    /// Asset-style identifier, e.g. "wN", "bP".
    public var code: String { (color == .white ? "w" : "b") + String(kind.lowercaseLetter).uppercased() }

    public var description: String { "\(color.name) \(kind.name)" }

    public static let all: [Piece] = PieceColor.allCases.flatMap { c in PieceKind.allCases.map { Piece(c, $0) } }
}
