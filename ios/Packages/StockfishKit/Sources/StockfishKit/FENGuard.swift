import Foundation

/// Cheap validation in front of the engine. Stockfish's own checks are also defused (see
/// CStockfish/PATCHES.md), but rejecting here gives callers an immediately finished stream.
///
/// Rejects what Stockfish would refuse or mis-search: malformed boards, not exactly one king per
/// side, pawns on the first/eighth rank, impossible material, and the side *not* to move being in
/// check. Repairs what is merely sloppy: castling rights without king/rook on their home squares,
/// a malformed en-passant field, missing or out-of-range move counters.
enum FENGuard {
    struct Result: Equatable {
        let fen: String
        let whiteToMove: Bool
    }

    static func sanitize(_ fen: String) -> Result? {
        let fields = fen.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let placement = fields.first else { return nil }

        // board[rank][file], rank 0 = first rank.
        var board = [[Character?]](repeating: [Character?](repeating: nil, count: 8), count: 8)
        let ranks = placement.split(separator: "/", omittingEmptySubsequences: false)
        guard ranks.count == 8 else { return nil }
        for (row, text) in ranks.enumerated() {
            let rank = 7 - row
            var file = 0
            for char in text {
                if let skip = char.wholeNumberValue {
                    guard (1...8).contains(skip) else { return nil }
                    file += skip
                } else {
                    guard "pnbrqkPNBRQK".contains(char), file < 8 else { return nil }
                    board[rank][file] = char
                    file += 1
                }
                guard file <= 8 else { return nil }
            }
            guard file == 8 else { return nil }
        }

        var counts: [Character: Int] = [:]
        for rank in 0..<8 {
            for file in 0..<8 {
                guard let piece = board[rank][file] else { continue }
                counts[piece, default: 0] += 1
                if (piece == "P" || piece == "p") && (rank == 0 || rank == 7) { return nil }
            }
        }
        guard counts["K"] == 1, counts["k"] == 1 else { return nil }
        guard counts.values.reduce(0, +) <= 32 else { return nil }
        for side in ["PNBRQ", "pnbrq"] {
            let letters = Array(side)
            let pawns = counts[letters[0]] ?? 0
            let promoted = max((counts[letters[1]] ?? 0) - 2, 0) + max((counts[letters[2]] ?? 0) - 2, 0)
                + max((counts[letters[3]] ?? 0) - 2, 0) + max((counts[letters[4]] ?? 0) - 1, 0)
            guard pawns <= 8, promoted <= 8 - pawns else { return nil }
        }

        let sideField = fields.count > 1 ? fields[1] : "w"
        guard sideField == "w" || sideField == "b" else { return nil }
        let whiteToMove = sideField == "w"

        // The side that just moved must not have left its king attacked.
        let waitingKing: Character = whiteToMove ? "k" : "K"
        guard let king = square(of: waitingKing, on: board),
              !isAttacked(king, byWhite: whiteToMove, on: board) else { return nil }

        var castling = ""
        let requested = fields.count > 2 ? fields[2] : "-"
        if requested.contains("K"), board[0][4] == "K", board[0][7] == "R" { castling += "K" }
        if requested.contains("Q"), board[0][4] == "K", board[0][0] == "R" { castling += "Q" }
        if requested.contains("k"), board[7][4] == "k", board[7][7] == "r" { castling += "k" }
        if requested.contains("q"), board[7][4] == "k", board[7][0] == "r" { castling += "q" }
        if castling.isEmpty { castling = "-" }

        var enPassant = fields.count > 3 ? fields[3] : "-"
        let epChars = Array(enPassant)
        if !(epChars.count == 2 && ("a"..."h").contains(epChars[0])
             && epChars[1] == (whiteToMove ? "6" : "3")) {
            enPassant = "-"
        }

        var halfmove = fields.count > 4 ? Int(fields[4]) ?? 0 : 0
        if !(0...32767).contains(halfmove) { halfmove = 0 }
        var fullmove = fields.count > 5 ? Int(fields[5]) ?? 1 : 1
        if !(1...100_000).contains(fullmove) { fullmove = 1 }

        return Result(fen: "\(placement) \(sideField) \(castling) \(enPassant) \(halfmove) \(fullmove)",
                      whiteToMove: whiteToMove)
    }

    private static func square(of piece: Character, on board: [[Character?]]) -> (rank: Int, file: Int)? {
        for rank in 0..<8 {
            for file in 0..<8 where board[rank][file] == piece {
                return (rank, file)
            }
        }
        return nil
    }

    /// Whether `target` is attacked by White (`byWhite`) or Black pieces.
    private static func isAttacked(_ target: (rank: Int, file: Int), byWhite: Bool, on board: [[Character?]]) -> Bool {
        func piece(_ rank: Int, _ file: Int) -> Character? {
            guard (0..<8).contains(rank), (0..<8).contains(file) else { return nil }
            return board[rank][file]
        }
        func own(_ letter: Character) -> Character {
            byWhite ? Character(letter.uppercased()) : letter
        }
        let (r, f) = target

        // Pawns attack diagonally forward, so look one rank "behind" the target from their side.
        let pawnRank = byWhite ? r - 1 : r + 1
        if piece(pawnRank, f - 1) == own("p") || piece(pawnRank, f + 1) == own("p") { return true }

        for (dr, df) in [(1, 2), (2, 1), (2, -1), (1, -2), (-1, -2), (-2, -1), (-2, 1), (-1, 2)]
            where piece(r + dr, f + df) == own("n") { return true }

        for dr in -1...1 {
            for df in -1...1 where (dr, df) != (0, 0) && piece(r + dr, f + df) == own("k") {
                return true
            }
        }

        let straight = [(1, 0), (-1, 0), (0, 1), (0, -1)]
        let diagonal = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
        for (directions, slider) in [(straight, own("r")), (diagonal, own("b"))] {
            for (dr, df) in directions {
                var rank = r + dr, file = f + df
                while (0..<8).contains(rank), (0..<8).contains(file) {
                    if let occupant = board[rank][file] {
                        if occupant == slider || occupant == own("q") { return true }
                        break
                    }
                    rank += dr
                    file += df
                }
            }
        }
        return false
    }
}
