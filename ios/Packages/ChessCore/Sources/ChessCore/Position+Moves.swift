private let knightOffsets = [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)]
private let kingOffsets = [(1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1), (0, -1), (1, -1)]
private let rookDirections = [(1, 0), (-1, 0), (0, 1), (0, -1)]
private let bishopDirections = [(1, 1), (1, -1), (-1, 1), (-1, -1)]

public enum GameStatus: Equatable, Sendable {
    case ongoing
    case checkmate(winner: PieceColor)
    case stalemate
    case insufficientMaterial
    case fiftyMoveRule
}

extension Position {
    // MARK: Attacks

    /// Whether `square` is attacked by any piece of `color` (pins are ignored, as in chess rules for check).
    public func isAttacked(_ square: Square, by color: PieceColor) -> Bool {
        // Pawns attack diagonally forward, so look one rank "behind" the target from the attacker's view.
        for df in [-1, 1] {
            if let s = square.offset(df, -color.forward), self[s] == Piece(color, .pawn) { return true }
        }
        for (df, dr) in knightOffsets {
            if let s = square.offset(df, dr), self[s] == Piece(color, .knight) { return true }
        }
        for (df, dr) in kingOffsets {
            if let s = square.offset(df, dr), self[s] == Piece(color, .king) { return true }
        }
        if rayHits(from: square, directions: rookDirections, color: color, kinds: [.rook, .queen]) { return true }
        if rayHits(from: square, directions: bishopDirections, color: color, kinds: [.bishop, .queen]) { return true }
        return false
    }

    private func rayHits(from square: Square, directions: [(Int, Int)], color: PieceColor, kinds: [PieceKind]) -> Bool {
        for (df, dr) in directions {
            var current = square.offset(df, dr)
            while let s = current {
                if let piece = self[s] {
                    if piece.color == color && kinds.contains(piece.kind) { return true }
                    break
                }
                current = s.offset(df, dr)
            }
        }
        return false
    }

    public func isInCheck(_ color: PieceColor) -> Bool {
        guard let king = kingSquare(of: color) else { return false }
        return isAttacked(king, by: color.opposite)
    }

    public var isCheck: Bool { isInCheck(sideToMove) }

    /// Squares of pieces of `color.opposite` currently giving check to `color`'s king.
    public func checkers(of color: PieceColor) -> [Square] {
        guard let king = kingSquare(of: color) else { return [] }
        let attacker = color.opposite
        return pieces.compactMap { entry in
            guard entry.piece.color == attacker else { return nil }
            return pseudoTargets(from: entry.square, piece: entry.piece, capturesOnly: true).contains(king) ? entry.square : nil
        }
    }

    // MARK: Move generation

    public func legalMoves() -> [Move] {
        var moves: [Move] = []
        moves.reserveCapacity(48)
        for (square, piece) in pieces where piece.color == sideToMove {
            appendLegalMoves(from: square, piece: piece, into: &moves)
        }
        return moves
    }

    public func legalMoves(from square: Square) -> [Move] {
        guard let piece = self[square], piece.color == sideToMove else { return [] }
        var moves: [Move] = []
        appendLegalMoves(from: square, piece: piece, into: &moves)
        return moves
    }

    public func isLegal(_ move: Move) -> Bool {
        legalMoves(from: move.from).contains(move)
    }

    /// Finds the legal move between two squares; promotions default to `promotion` (queen if nil).
    public func legalMove(from: Square, to: Square, promotion: PieceKind? = nil) -> Move? {
        let candidates = legalMoves(from: from).filter { $0.to == to }
        if candidates.count <= 1 { return candidates.first }
        return candidates.first { $0.promotion == (promotion ?? .queen) }
    }

    public func isPromotion(from: Square, to: Square) -> Bool {
        legalMoves(from: from).contains { $0.to == to && $0.promotion != nil }
    }

    private func appendLegalMoves(from square: Square, piece: Piece, into moves: inout [Move]) {
        var candidates: [Move] = []
        appendPseudoLegalMoves(from: square, piece: piece, into: &candidates)
        for move in candidates {
            var next = self
            next.applyUnchecked(move)
            if !next.isInCheck(piece.color) { moves.append(move) }
        }
    }

    private func pseudoTargets(from square: Square, piece: Piece, capturesOnly: Bool) -> [Square] {
        var targets: [Square] = []
        switch piece.kind {
        case .pawn:
            for df in [-1, 1] {
                if let s = square.offset(df, piece.color.forward) { targets.append(s) }
            }
        case .knight:
            targets = knightOffsets.compactMap { square.offset($0.0, $0.1) }
        case .king:
            targets = kingOffsets.compactMap { square.offset($0.0, $0.1) }
        case .bishop, .rook, .queen:
            let dirs: [(Int, Int)] = piece.kind == .bishop ? bishopDirections
                : piece.kind == .rook ? rookDirections : rookDirections + bishopDirections
            for (df, dr) in dirs {
                var current = square.offset(df, dr)
                while let s = current {
                    targets.append(s)
                    if self[s] != nil { break }
                    current = s.offset(df, dr)
                }
            }
        }
        return targets
    }

    private func appendPseudoLegalMoves(from square: Square, piece: Piece, into moves: inout [Move]) {
        let color = piece.color
        switch piece.kind {
        case .pawn:
            let promotionRank = color == .white ? 7 : 0
            func add(_ to: Square) {
                if to.rank == promotionRank {
                    for kind in PieceKind.promotionChoices { moves.append(Move(from: square, to: to, promotion: kind)) }
                } else {
                    moves.append(Move(from: square, to: to))
                }
            }
            if let one = square.offset(0, color.forward), self[one] == nil {
                add(one)
                let startRank = color == .white ? 1 : 6
                if square.rank == startRank, let two = one.offset(0, color.forward), self[two] == nil {
                    moves.append(Move(from: square, to: two))
                }
            }
            for df in [-1, 1] {
                guard let target = square.offset(df, color.forward) else { continue }
                if let victim = self[target], victim.color != color {
                    add(target)
                } else if target == enPassant, self[target] == nil {
                    moves.append(Move(from: square, to: target))
                }
            }

        case .king:
            for target in pseudoTargets(from: square, piece: piece, capturesOnly: false) where self[target]?.color != color {
                moves.append(Move(from: square, to: target))
            }
            appendCastlingMoves(for: color, kingSquare: square, into: &moves)

        default:
            for target in pseudoTargets(from: square, piece: piece, capturesOnly: false) where self[target]?.color != color {
                moves.append(Move(from: square, to: target))
            }
        }
    }

    private func appendCastlingMoves(for color: PieceColor, kingSquare: Square, into moves: inout [Move]) {
        let rank = color.homeRank
        guard kingSquare == Square(file: 4, rank: rank) else { return }
        let enemy = color.opposite
        if castling.contains(.kingside(color)),
           self[Square(file: 7, rank: rank)] == Piece(color, .rook),
           self[Square(file: 5, rank: rank)] == nil, self[Square(file: 6, rank: rank)] == nil,
           !isAttacked(kingSquare, by: enemy),
           !isAttacked(Square(file: 5, rank: rank), by: enemy),
           !isAttacked(Square(file: 6, rank: rank), by: enemy) {
            moves.append(Move(from: kingSquare, to: Square(file: 6, rank: rank)))
        }
        if castling.contains(.queenside(color)),
           self[Square(file: 0, rank: rank)] == Piece(color, .rook),
           self[Square(file: 1, rank: rank)] == nil, self[Square(file: 2, rank: rank)] == nil,
           self[Square(file: 3, rank: rank)] == nil,
           !isAttacked(kingSquare, by: enemy),
           !isAttacked(Square(file: 3, rank: rank), by: enemy),
           !isAttacked(Square(file: 2, rank: rank), by: enemy) {
            moves.append(Move(from: kingSquare, to: Square(file: 2, rank: rank)))
        }
    }

    // MARK: Making moves

    public func isCastling(_ move: Move) -> Bool {
        self[move.from]?.kind == .king && abs(move.to.file - move.from.file) == 2
    }

    public func isEnPassant(_ move: Move) -> Bool {
        self[move.from]?.kind == .pawn && move.to == enPassant && move.from.file != move.to.file && self[move.to] == nil
    }

    public func isCapture(_ move: Move) -> Bool {
        (self[move.to].map { $0.color != self[move.from]?.color } ?? false) || isEnPassant(move)
    }

    /// The piece captured by `move`, if any (including en passant).
    public func capturedPiece(by move: Move) -> Piece? {
        if isEnPassant(move), let mover = self[move.from] { return Piece(mover.color.opposite, .pawn) }
        guard let victim = self[move.to], victim.color != self[move.from]?.color else { return nil }
        return victim
    }

    /// Plays a legal move. Returns false (leaving the position unchanged) if the move is illegal.
    @discardableResult
    public mutating func play(_ move: Move) -> Bool {
        guard isLegal(move) else { return false }
        applyUnchecked(move)
        return true
    }

    /// The position after a legal move, or nil if it is illegal.
    public func playing(_ move: Move) -> Position? {
        var next = self
        return next.play(move) ? next : nil
    }

    /// Applies a pseudo-legal move without checking legality.
    mutating func applyUnchecked(_ move: Move) {
        guard let piece = self[move.from] else { return }
        let color = piece.color
        let isCapture = self[move.to] != nil
        var newEnPassant: Square?

        if piece.kind == .pawn {
            if move.to == enPassant, move.from.file != move.to.file, self[move.to] == nil {
                self[Square(file: move.to.file, rank: move.from.rank)] = nil
            }
            if abs(move.to.rank - move.from.rank) == 2 {
                newEnPassant = Square(file: move.from.file, rank: (move.from.rank + move.to.rank) / 2)
            }
        }
        if piece.kind == .king, abs(move.to.file - move.from.file) == 2 {
            let rank = move.from.rank
            if move.to.file == 6 {
                self[Square(file: 5, rank: rank)] = self[Square(file: 7, rank: rank)]
                self[Square(file: 7, rank: rank)] = nil
            } else {
                self[Square(file: 3, rank: rank)] = self[Square(file: 0, rank: rank)]
                self[Square(file: 0, rank: rank)] = nil
            }
        }

        self[move.to] = move.promotion.map { Piece(color, $0) } ?? piece
        self[move.from] = nil

        if piece.kind == .king {
            castling.remove(.kingside(color))
            castling.remove(.queenside(color))
        }
        for sq in [move.from, move.to] {
            switch sq {
            case .h1: castling.remove(.whiteKingside)
            case .a1: castling.remove(.whiteQueenside)
            case .h8: castling.remove(.blackKingside)
            case .a8: castling.remove(.blackQueenside)
            default: break
            }
        }

        enPassant = newEnPassant
        halfmoveClock = (piece.kind == .pawn || isCapture) ? 0 : halfmoveClock + 1
        if color == .black { fullmoveNumber += 1 }
        sideToMove = color.opposite
    }

    // MARK: Game status

    public var hasInsufficientMaterial: Bool {
        var minors: [(Piece, Square)] = []
        for (square, piece) in pieces where piece.kind != .king {
            switch piece.kind {
            case .knight, .bishop: minors.append((piece, square))
            default: return false
            }
        }
        if minors.count <= 1 { return true }
        // Only bishops, all on the same square colour.
        if minors.allSatisfy({ $0.0.kind == .bishop }) {
            let shade = minors[0].1.isLight
            return minors.allSatisfy { $0.1.isLight == shade }
        }
        return false
    }

    public var status: GameStatus {
        if legalMoves().isEmpty {
            return isCheck ? .checkmate(winner: sideToMove.opposite) : .stalemate
        }
        if hasInsufficientMaterial { return .insufficientMaterial }
        if halfmoveClock >= 100 { return .fiftyMoveRule }
        return .ongoing
    }

    public var isCheckmate: Bool { isCheck && legalMoves().isEmpty }
    public var isStalemate: Bool { !isCheck && legalMoves().isEmpty }
}
