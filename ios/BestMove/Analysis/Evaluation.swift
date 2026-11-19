import SwiftUI
import ChessCore
import StockfishKit

/// Display helpers for engine scores (all scores are from White's point of view).
extension EngineScore {
    /// Expected score for White in 0…1 (lichess' logistic model for centipawns).
    var whiteWinningChance: Double {
        switch value {
        case .centipawns(let cp):
            return 1 / (1 + exp(-0.00368208 * Double(cp)))
        case .mate(let n):
            return n > 0 ? 1 : 0
        }
    }

    var isMate: Bool {
        if case .mate = value { return true }
        return false
    }

    /// "+1.24", "−0.30", "M3", "−M5".
    var shortText: String {
        switch value {
        case .centipawns(let cp):
            let pawns = Double(cp) / 100
            if abs(pawns) < 0.005 { return "0.00" }
            return (pawns > 0 ? "+" : "−") + String(format: "%.2f", abs(pawns))
        case .mate(let n):
            if n == 0 { return "#" }
            return (n > 0 ? "M" : "−M") + String(abs(n))
        }
    }

    var favoursWhite: Bool {
        switch value {
        case .centipawns(let cp): cp >= 0
        case .mate(let n): n > 0
        }
    }
}

/// Vertical evaluation bar: White's share grows from the bottom (or top when the board is flipped).
struct EvalBar: View {
    /// White's expected score 0…1, nil while unknown.
    let whiteChance: Double?
    var orientation: PieceColor = .white

    var body: some View {
        GeometryReader { proxy in
            let chance = whiteChance ?? 0.5
            let whiteHeight = proxy.size.height * chance
            ZStack(alignment: orientation == .white ? .bottom : .top) {
                Color(hex: 0x2A2B30)
                Color(hex: 0xF1ECE2)
                    .frame(height: whiteHeight)
                Rectangle()
                    .fill(Palette.gold)
                    .frame(height: 1.5)
                    .offset(y: orientation == .white ? -whiteHeight : whiteHeight)
                    .opacity(whiteChance == nil ? 0 : 1)
                // Centre line
                Rectangle().fill(Color.gray.opacity(0.5)).frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            .animation(.spring(response: 0.55, dampingFraction: 0.9), value: chance)
        }
        .frame(width: 10)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(Palette.stroke))
        .accessibilityLabel("Evaluation")
        .accessibilityValue(whiteChance.map { "White \(Int(($0 * 100).rounded())) percent" } ?? "Calculating")
    }
}

/// Pill showing a score, styled light when White is better and dark when Black is better.
struct ScoreChip: View {
    let score: EngineScore
    var large = false

    var body: some View {
        Text(score.shortText)
            .font(.system(size: large ? 15 : 12.5, weight: .bold, design: .rounded).monospacedDigit())
            .foregroundStyle(score.favoursWhite ? Color(hex: 0x15161A) : Color(hex: 0xF1ECE2))
            .padding(.horizontal, large ? 10 : 7)
            .frame(minWidth: large ? 64 : 52, minHeight: large ? 30 : 24)
            .background(score.favoursWhite ? Color(hex: 0xF1ECE2) : Color(hex: 0x2E3036),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.stroke))
    }
}

/// Natural-language description of a move, e.g. "Knight from g1 to f3, capturing the bishop".
