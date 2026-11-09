public enum FENError: Error, Equatable, Sendable {
    case wrongFieldCount
    case badBoard
    case badSideToMove
    case badCastling
    case badEnPassant
    case badCounter
}

/// A complete chess position (piece placement plus game state), as described by a FEN string.
public struct Position: Hashable, Sendable {
    private var squares: [Piece?]
    public var sideToMove: PieceColor
    public var castling: CastlingRights
    /// Target square of a possible en-passant capture.
    public var enPassant: Square?
    public var halfmoveClock: Int
    public var fullmoveNumber: Int

    public init() {
        squares = Array(repeating: nil, count: 64)
        sideToMove = .white
        castling = []
        enPassant = nil
        halfmoveClock = 0
        fullmoveNumber = 1
    }

    public static let empty = Position()
    public static let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    // swiftlint:disable:next force_try
    public static let start = try! Position(fen: startFEN)

    public subscript(square: Square) -> Piece? {
        get { squares[square.index] }
        set { squares[square.index] = newValue }
    }

    /// All occupied squares with their pieces, a1→h8.
    public var pieces: [(square: Square, piece: Piece)] {
        Square.all.compactMap { sq in squares[sq.index].map { (sq, $0) } }
    }

    public func kingSquare(of color: PieceColor) -> Square? {
        let king = Piece(color, .king)
        return squares.firstIndex(of: king).map(Square.init)
    }

    // MARK: FEN

    /// Parses a FEN. Missing trailing fields (castling, en passant, clocks) are tolerated.
    public init(fen: String) throws {
        self.init()
        let fields = fen.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard (1...6).contains(fields.count) else { throw FENError.wrongFieldCount }

        let ranks = fields[0].split(separator: "/", omittingEmptySubsequences: false)
        guard ranks.count == 8 else { throw FENError.badBoard }
        for (i, rankString) in ranks.enumerated() {
            let rank = 7 - i
            var file = 0
            for ch in rankString {
                if let n = ch.wholeNumberValue, (1...8).contains(n) {
                    file += n
                } else if let piece = Piece(fen: ch) {
                    guard file < 8 else { throw FENError.badBoard }
                    squares[rank * 8 + file] = piece
                    file += 1
                } else {
                    throw FENError.badBoard
                }
                guard file <= 8 else { throw FENError.badBoard }
            }
            guard file == 8 else { throw FENError.badBoard }
        }

        if fields.count > 1 {
            switch fields[1] {
            case "w": sideToMove = .white
            case "b": sideToMove = .black
            default: throw FENError.badSideToMove
            }
        }

        if fields.count > 2, fields[2] != "-" {
            for ch in fields[2] {
                switch ch {
                case "K": castling.insert(.whiteKingside)
                case "Q": castling.insert(.whiteQueenside)
                case "k": castling.insert(.blackKingside)
                case "q": castling.insert(.blackQueenside)
                default: throw FENError.badCastling
                }
            }
        }

        if fields.count > 3, fields[3] != "-" {
            guard let sq = Square(fields[3]), sq.rank == 2 || sq.rank == 5 else { throw FENError.badEnPassant }
            enPassant = sq
        }

        if fields.count > 4 {
            guard let n = Int(fields[4]), n >= 0 else { throw FENError.badCounter }
            halfmoveClock = n
        }
        if fields.count > 5 {
            guard let n = Int(fields[5]), n >= 1 else { throw FENError.badCounter }
            fullmoveNumber = n
        }
    }

    public var boardFEN: String {
        var out = ""
        for rank in stride(from: 7, through: 0, by: -1) {
            var empty = 0
            for file in 0..<8 {
                if let piece = squares[rank * 8 + file] {
                    if empty > 0 { out += String(empty); empty = 0 }
                    out.append(piece.fen)
                } else {
                    empty += 1
                }
            }
            if empty > 0 { out += String(empty) }
            if rank > 0 { out += "/" }
        }
        return out
    }

    public var fen: String {
        [
            boardFEN,
            sideToMove == .white ? "w" : "b",
            castling.fen,
            enPassant?.name ?? "-",
            String(halfmoveClock),
            String(fullmoveNumber),
        ].joined(separator: " ")
    }
}

extension Position: CustomStringConvertible {
    public var description: String { fen }
}
