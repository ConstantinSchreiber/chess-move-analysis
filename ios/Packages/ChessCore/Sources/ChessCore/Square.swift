/// A board square. Index 0 = a1, 7 = h1, 56 = a8, 63 = h8.
public struct Square: Hashable, Sendable, Comparable, CustomStringConvertible {
    public let index: Int

    public init(_ index: Int) {
        precondition((0..<64).contains(index), "square index out of range")
        self.index = index
    }

    public init(file: Int, rank: Int) {
        self.init(rank * 8 + file)
    }

    /// Algebraic name like "e4".
    public init?(_ name: String) {
        let chars = Array(name.lowercased())
        guard chars.count == 2,
              let f = chars[0].asciiValue, let r = chars[1].asciiValue,
              (97...104).contains(f), (49...56).contains(r) else { return nil }
        self.init(file: Int(f) - 97, rank: Int(r) - 49)
    }

    /// 0 = a-file … 7 = h-file.
    public var file: Int { index & 7 }
    /// 0 = first rank … 7 = eighth rank.
    public var rank: Int { index >> 3 }

    public var fileLetter: Character { Character(UnicodeScalar(UInt8(97 + file))) }
    public var rankDigit: Character { Character(UnicodeScalar(UInt8(49 + rank))) }
    public var name: String { String(fileLetter) + String(rankDigit) }
    public var description: String { name }

    public var isLight: Bool { (file + rank) % 2 == 1 }

    /// The square shifted by (df, dr), or nil when that leaves the board.
    public func offset(_ df: Int, _ dr: Int) -> Square? {
        let f = file + df, r = rank + dr
        guard (0..<8).contains(f), (0..<8).contains(r) else { return nil }
        return Square(file: f, rank: r)
    }

    public static func < (lhs: Square, rhs: Square) -> Bool { lhs.index < rhs.index }

    public static let all: [Square] = (0..<64).map(Square.init)
}

public extension Square {
    static let a1 = Square(0), b1 = Square(1), c1 = Square(2), d1 = Square(3)
    static let e1 = Square(4), f1 = Square(5), g1 = Square(6), h1 = Square(7)
    static let a8 = Square(56), b8 = Square(57), c8 = Square(58), d8 = Square(59)
    static let e8 = Square(60), f8 = Square(61), g8 = Square(62), h8 = Square(63)
}
