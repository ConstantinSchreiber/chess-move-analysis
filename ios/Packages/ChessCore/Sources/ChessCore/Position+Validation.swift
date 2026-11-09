/// Problems that make a set-up position unplayable or unanalysable.
public enum SetupIssue: Hashable, Sendable, CustomStringConvertible {
    case missingKing(PieceColor)
    case extraKings(PieceColor)
    case pawnsOnBackRank
    case tooManyPawns(PieceColor)
    case tooManyPieces(PieceColor)
    case kingsAdjacent
    /// The side that is *not* to move is in check — impossible in a real game.
    case opponentInCheck(PieceColor)
    case tooManyCheckers

    public var description: String {
        switch self {
        case .missingKing(let c): "\(c.name) has no king."
        case .extraKings(let c): "\(c.name) has more than one king."
        case .pawnsOnBackRank: "Pawns can't stand on the first or last rank."
        case .tooManyPawns(let c): "\(c.name) has more than 8 pawns."
        case .tooManyPieces(let c): "\(c.name) has more than 16 pieces."
        case .kingsAdjacent: "The kings can't stand next to each other."
        case .opponentInCheck(let c): "\(c.name) is in check but it's not their move."
        case .tooManyCheckers: "The king is attacked by more than two pieces."
        }
    }
}

extension Position {
    public func setupIssues() -> [SetupIssue] {
        var issues: [SetupIssue] = []
        for color in PieceColor.allCases {
            let mine = pieces.filter { $0.piece.color == color }
            let kings = mine.filter { $0.piece.kind == .king }.count
            if kings == 0 { issues.append(.missingKing(color)) }
            if kings > 1 { issues.append(.extraKings(color)) }
            if mine.filter({ $0.piece.kind == .pawn }).count > 8 { issues.append(.tooManyPawns(color)) }
            if mine.count > 16 { issues.append(.tooManyPieces(color)) }
        }
        if pieces.contains(where: { $0.piece.kind == .pawn && ($0.square.rank == 0 || $0.square.rank == 7) }) {
            issues.append(.pawnsOnBackRank)
        }
        guard !issues.contains(where: { if case .missingKing = $0 { true } else if case .extraKings = $0 { true } else { false } })
        else { return issues }

        if let wk = kingSquare(of: .white), let bk = kingSquare(of: .black),
           abs(wk.file - bk.file) <= 1, abs(wk.rank - bk.rank) <= 1 {
            issues.append(.kingsAdjacent)
        }
        if isInCheck(sideToMove.opposite) { issues.append(.opponentInCheck(sideToMove.opposite)) }
        if checkers(of: sideToMove).count > 2 { issues.append(.tooManyCheckers) }
        return issues
    }

    public var isValidForAnalysis: Bool { setupIssues().isEmpty }

    /// Castling rights that are actually possible given where kings and rooks stand.
    public var possibleCastling: CastlingRights {
        var rights: CastlingRights = []
        for color in PieceColor.allCases {
            let rank = color.homeRank
            guard self[Square(file: 4, rank: rank)] == Piece(color, .king) else { continue }
            if self[Square(file: 7, rank: rank)] == Piece(color, .rook) { rights.insert(.kingside(color)) }
            if self[Square(file: 0, rank: rank)] == Piece(color, .rook) { rights.insert(.queenside(color)) }
        }
        return rights
    }

    /// Drops castling rights and en-passant targets that are inconsistent with the board.
    public mutating func sanitize() {
        castling.formIntersection(possibleCastling)
        if let ep = enPassant {
            let mover = sideToMove.opposite
            let pawnSquare = Square(file: ep.file, rank: ep.rank - mover.forward)
            let origin = Square(file: ep.file, rank: ep.rank + mover.forward)
            let expectedRank = sideToMove == .white ? 5 : 2
            if ep.rank != expectedRank || self[ep] != nil || self[origin] != nil || self[pawnSquare] != Piece(mover, .pawn) {
                enPassant = nil
            }
        }
        if fullmoveNumber < 1 { fullmoveNumber = 1 }
    }

    public func sanitized() -> Position {
        var copy = self
        copy.sanitize()
        return copy
    }
}
