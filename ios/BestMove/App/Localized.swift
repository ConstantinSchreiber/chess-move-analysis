import Foundation
import ChessCore
import StockfishKit

// Localised wording for chess concepts. Phrases are whole units (not "White" + "queen") so that
// languages with grammatical gender and case can translate them properly. ChessCore stays
// language-neutral; SAN, FEN and square names are universal and never translated.

extension PieceColor {
    var localizedName: String {
        self == .white ? String(localized: "White", comment: "Chess side") : String(localized: "Black", comment: "Chess side")
    }

    var toMoveText: String {
        self == .white ? String(localized: "White to move") : String(localized: "Black to move")
    }
}

extension Piece {
    /// "White queen" — sentence-initial form, as used in "White queen b3 → b8".
    var localizedName: String {
        switch (color, kind) {
        case (.white, .king): String(localized: "White king")
        case (.white, .queen): String(localized: "White queen")
        case (.white, .rook): String(localized: "White rook")
        case (.white, .bishop): String(localized: "White bishop")
        case (.white, .knight): String(localized: "White knight")
        case (.white, .pawn): String(localized: "White pawn")
        case (.black, .king): String(localized: "Black king")
        case (.black, .queen): String(localized: "Black queen")
        case (.black, .rook): String(localized: "Black rook")
        case (.black, .bishop): String(localized: "Black bishop")
        case (.black, .knight): String(localized: "Black knight")
        case (.black, .pawn): String(localized: "Black pawn")
        }
    }
}

extension SetupIssue {
    var localizedDescription: String {
        switch self {
        case .missingKing(let c):
            c == .white ? String(localized: "White has no king.") : String(localized: "Black has no king.")
        case .extraKings(let c):
            c == .white ? String(localized: "White has more than one king.") : String(localized: "Black has more than one king.")
        case .pawnsOnBackRank:
            String(localized: "Pawns can't stand on the first or last rank.")
        case .tooManyPawns(let c):
            c == .white ? String(localized: "White has more than 8 pawns.") : String(localized: "Black has more than 8 pawns.")
        case .tooManyPieces(let c):
            c == .white ? String(localized: "White has more than 16 pieces.") : String(localized: "Black has more than 16 pieces.")
        case .kingsAdjacent:
            String(localized: "The kings can't stand next to each other.")
        case .opponentInCheck(let c):
            c == .white ? String(localized: "White is in check but it's not their move.")
                : String(localized: "Black is in check but it's not their move.")
        case .tooManyCheckers:
            String(localized: "The king is attacked by more than two pieces.")
        }
    }
}

extension EngineScore {
    /// Plain-language verdict, e.g. "White is clearly better".
    var verdict: String {
        switch value {
        case .mate(let n):
            if n == 0 { return String(localized: "Checkmate") }
            let moves = abs(n)
            return n > 0 ? String(localized: "White mates in \(moves)") : String(localized: "Black mates in \(moves)")
        case .centipawns(let cp):
            let white = cp > 0
            switch abs(cp) {
            case ..<35: return String(localized: "The position is equal")
            case ..<90: return white ? String(localized: "White is slightly better") : String(localized: "Black is slightly better")
            case ..<200: return white ? String(localized: "White is clearly better") : String(localized: "Black is clearly better")
            case ..<500: return white ? String(localized: "White is winning") : String(localized: "Black is winning")
            default: return white ? String(localized: "White is completely winning") : String(localized: "Black is completely winning")
            }
        }
    }
}

enum MoveDescriber {
    static func describe(_ move: Move, in position: Position) -> (title: String, detail: String) {
        guard let piece = position[move.from] else { return (move.uci, "") }
        if position.isCastling(move) {
            let kingside = move.to.file == 6
            let to = move.to.name
            let detail = piece.color == .white
                ? String(localized: "White king to \(to), rook tucks in beside it.")
                : String(localized: "Black king to \(to), rook tucks in beside it.")
            return (kingside ? String(localized: "Castle kingside") : String(localized: "Castle queenside"), detail)
        }
        var title = "\(piece.localizedName) \(move.from.name) → \(move.to.name)"
        var parts: [String] = []
        if let captured = position.capturedPiece(by: move) {
            parts.append(position.isEnPassant(move) ? String(localized: "Captures the pawn en passant")
                                                    : captures(captured.kind, on: move.to.name))
        }
        if let promotion = move.promotion {
            parts.append(promotes(to: promotion))
            title += " = \(promotion.sanLetter)"
        }
        if let next = position.playing(move) {
            if next.isCheckmate {
                parts.append(String(localized: "checkmate", comment: "Part of a move description, e.g. 'Captures the queen on d8, checkmate.'"))
            } else if next.isCheck {
                parts.append(String(localized: "gives check", comment: "Part of a move description, e.g. 'Captures the knight on f7, gives check.'"))
            }
        }
        if parts.isEmpty { parts.append(String(localized: "Quiet move")) }
        let detail = parts.joined(separator: String(localized: ", ", comment: "Separator between parts of a move description"))
        return (title, detail.capitalizedFirst + String(localized: ".", comment: "End of a move description sentence"))
    }

    private static func captures(_ kind: PieceKind, on square: String) -> String {
        switch kind {
        case .pawn: String(localized: "Captures the pawn on \(square)")
        case .knight: String(localized: "Captures the knight on \(square)")
        case .bishop: String(localized: "Captures the bishop on \(square)")
        case .rook: String(localized: "Captures the rook on \(square)")
        case .queen: String(localized: "Captures the queen on \(square)")
        case .king: String(localized: "Captures the king on \(square)")
        }
    }

    private static func promotes(to kind: PieceKind) -> String {
        switch kind {
        case .queen: String(localized: "promotes to a queen", comment: "Part of a move description")
        case .rook: String(localized: "promotes to a rook", comment: "Part of a move description")
        case .bishop: String(localized: "promotes to a bishop", comment: "Part of a move description")
        default: String(localized: "promotes to a knight", comment: "Part of a move description")
        }
    }
}

extension String {
    /// Capitalizes the first letter, unless the sentence starts with a square ("e7のビショップを取る").
    /// Skips leading bidi isolates and other invisible format characters.
    var capitalizedFirst: String {
        guard let start = firstIndex(where: { !$0.unicodeScalars.allSatisfy { $0.properties.generalCategory == .format } })
        else { return self }
        let text = self[start...]
        if let file = text.first, ("a"..."h").contains(file),
           let rank = text.dropFirst().first, ("1"..."8").contains(rank) { return self }
        return self[..<start] + text.prefix(1).uppercased() + text.dropFirst()
    }
}
