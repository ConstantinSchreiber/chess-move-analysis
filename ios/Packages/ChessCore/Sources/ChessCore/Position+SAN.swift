import Foundation

extension Position {
    /// Standard Algebraic Notation for a legal move in this position, e.g. "Nbd7", "exd6", "O-O", "e8=Q+".
    public func san(for move: Move) -> String {
        guard let piece = self[move.from] else { return move.uci }
        var san: String

        if isCastling(move) {
            san = move.to.file == 6 ? "O-O" : "O-O-O"
        } else {
            san = piece.kind.sanLetter
            if piece.kind == .pawn {
                if isCapture(move) { san.append(move.from.fileLetter) }
            } else {
                let rivals = legalMoves().filter {
                    $0.to == move.to && $0.from != move.from && self[$0.from] == piece
                }
                if !rivals.isEmpty {
                    let sameFile = rivals.contains { $0.from.file == move.from.file }
                    let sameRank = rivals.contains { $0.from.rank == move.from.rank }
                    if !sameFile {
                        san.append(move.from.fileLetter)
                    } else if !sameRank {
                        san.append(move.from.rankDigit)
                    } else {
                        san += move.from.name
                    }
                }
            }
            if isCapture(move) { san += "x" }
            san += move.to.name
            if let promotion = move.promotion { san += "=" + promotion.sanLetter }
        }

        if let next = playing(move), next.isCheck {
            san += next.legalMoves().isEmpty ? "#" : "+"
        }
        return san
    }

    /// Parses a SAN move (annotations like +, #, !, ? are ignored). Also accepts UCI.
    public func move(san input: String) -> Move? {
        let cleaned = input.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "0-0-0", with: "O-O-O")
            .replacingOccurrences(of: "0-0", with: "O-O")
            .filter { !"+#!?".contains($0) }
        if let uci = Move(uci: cleaned), isLegal(uci) { return uci }
        let strip: (String) -> String = { $0.filter { !"+#".contains($0) } }
        return legalMoves().first { strip(san(for: $0)) == cleaned }
    }

    /// Converts a sequence of UCI moves into SAN, stopping at the first illegal move.
    public func sanLine(_ uciMoves: [String]) -> [String] {
        var position = self
        var result: [String] = []
        for uci in uciMoves {
            guard let move = Move(uci: uci), position.isLegal(move) else { break }
            result.append(position.san(for: move))
            position.applyUnchecked(move)
        }
        return result
    }
}
