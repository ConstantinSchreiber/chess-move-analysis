public struct Move: Hashable, Sendable, CustomStringConvertible {
    public let from: Square
    public let to: Square
    public let promotion: PieceKind?

    public init(from: Square, to: Square, promotion: PieceKind? = nil) {
        self.from = from
        self.to = to
        self.promotion = promotion
    }

    /// Parses long algebraic UCI notation, e.g. "e2e4", "e7e8q".
    public init?(uci: String) {
        guard uci.count == 4 || uci.count == 5 else { return nil }
        let s = Array(uci)
        guard let from = Square(String(s[0...1])), let to = Square(String(s[2...3])) else { return nil }
        var promotion: PieceKind?
        if s.count == 5 {
            guard let kind = PieceKind(letter: s[4]), kind != .pawn, kind != .king else { return nil }
            promotion = kind
        }
        self.init(from: from, to: to, promotion: promotion)
    }

    public var uci: String {
        from.name + to.name + (promotion.map { String($0.lowercaseLetter) } ?? "")
    }

    public var description: String { uci }
}

public struct CastlingRights: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let whiteKingside = CastlingRights(rawValue: 1)
    public static let whiteQueenside = CastlingRights(rawValue: 2)
    public static let blackKingside = CastlingRights(rawValue: 4)
    public static let blackQueenside = CastlingRights(rawValue: 8)
    public static let all: CastlingRights = [.whiteKingside, .whiteQueenside, .blackKingside, .blackQueenside]

    public static func kingside(_ color: PieceColor) -> CastlingRights {
        color == .white ? .whiteKingside : .blackKingside
    }

    public static func queenside(_ color: PieceColor) -> CastlingRights {
        color == .white ? .whiteQueenside : .blackQueenside
    }

    public var fen: String {
        var s = ""
        if contains(.whiteKingside) { s += "K" }
        if contains(.whiteQueenside) { s += "Q" }
        if contains(.blackKingside) { s += "k" }
        if contains(.blackQueenside) { s += "q" }
        return s.isEmpty ? "-" : s
    }
}
