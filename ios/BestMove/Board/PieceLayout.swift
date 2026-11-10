import ChessCore

/// A piece with a stable identity, so SwiftUI can animate it sliding between squares.
struct PlacedPiece: Identifiable, Hashable {
    let id: Int
    let piece: Piece
    let square: Square
}

/// Assigns stable identities to pieces across position changes (moves, take-backs, edits).
struct PieceLayout {
    private(set) var pieces: [PlacedPiece] = []
    private var nextID = 0

    mutating func update(to position: Position, move: Move? = nil) {
        let old = pieces
        var unmatchedOld = old
        var result: [PlacedPiece] = []
        var unmatchedNew: [(Square, Piece)] = []

        // 1. Pieces that stayed put keep their identity.
        for (square, piece) in position.pieces {
            if let i = unmatchedOld.firstIndex(where: { $0.square == square && $0.piece == piece }) {
                result.append(unmatchedOld.remove(at: i))
            } else {
                unmatchedNew.append((square, piece))
            }
        }

        // 2. The moved piece (including promotions, where the piece type changes).
        if let move, let i = unmatchedNew.firstIndex(where: { $0.0 == move.to }),
           let j = unmatchedOld.firstIndex(where: { $0.square == move.from }) {
            let (square, piece) = unmatchedNew.remove(at: i)
            result.append(PlacedPiece(id: unmatchedOld.remove(at: j).id, piece: piece, square: square))
        }

        // 3. Anything else slides from the nearest vacated square holding the same piece (castling rook, take-backs).
        for (square, piece) in unmatchedNew {
            let candidates = unmatchedOld.enumerated().filter { $0.element.piece == piece }
            if let best = candidates.min(by: { distance($0.element.square, square) < distance($1.element.square, square) }) {
                unmatchedOld.remove(at: best.offset)
                result.append(PlacedPiece(id: best.element.id, piece: piece, square: square))
            } else {
                result.append(PlacedPiece(id: nextID, piece: piece, square: square))
                nextID += 1
            }
        }
        pieces = result.sorted { $0.id < $1.id }
    }

    private func distance(_ a: Square, _ b: Square) -> Int {
        max(abs(a.file - b.file), abs(a.rank - b.rank))
    }
}
