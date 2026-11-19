import SwiftUI
import CoreTransferable
import UniformTypeIdentifiers
import ChessCore
import StockfishKit

/// The picture shared from the analysis: the position with the best move, sized for chats and posts
/// (1200 px wide), with the app's name as a quiet signature.
struct ShareCard: View {
    let position: Position
    let orientation: PieceColor
    let lastMove: Move?
    let best: Move?
    let san: String?
    let score: EngineScore?
    let theme: BoardTheme
    let pieceSet: PieceSet

    static let width: CGFloat = 400

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(san == nil ? "Position" : "Best move").eyebrowStyle(Palette.gold)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(san ?? position.sideToMove.toMoveText)
                        .font(.display(san == nil ? 32 : 46, weight: .bold))
                        .foregroundStyle(Palette.textPrimary)
                    if let score { ScoreChip(score: score, large: true) }
                    Spacer(minLength: 0)
                }
                if let best {
                    let description = MoveDescriber.describe(best, in: position)
                    Text(score.map { String(localized: "\(description.detail) \($0.verdict).") } ?? description.detail)
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            MiniBoardView(position: position, orientation: orientation, lastMove: lastMove,
                          arrows: best.map { [BoardArrow(from: $0.from, to: $0.to)] } ?? [], cornerRadius: 14)
                .environment(\.boardTheme, theme)
                .environment(\.pieceSet, pieceSet)
                .environment(\.layoutDirection, .leftToRight)
                .shadow(color: .black.opacity(0.5), radius: 18, y: 10)

            HStack(spacing: 12) {
                Image("Logo")
                    .resizable()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Best Move").font(.display(19)).foregroundStyle(Palette.textPrimary)
                    Text("Scan any chess board, get the best move. Free on the App Store.")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textSecondary)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(28)
        .frame(width: Self.width)
        .background {
            ZStack {
                Palette.background
                RadialGradient(colors: [Palette.gold.opacity(0.28), .clear], center: .top, startRadius: 0, endRadius: 360)
            }
        }
        .environment(\.colorScheme, .dark)
    }

    /// PNG of the card at 3x (1200 px wide).
    @MainActor
    func pngData() -> Data? {
        let renderer = ImageRenderer(content: self)
        renderer.scale = 3
        return renderer.uiImage?.pngData()
    }
}

/// Renders the card only when the share sheet actually asks for it.
struct ShareCardImage: Transferable {
    let card: ShareCard

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            guard let data = await item.card.pngData() else { throw CocoaError(.fileWriteUnknown) }
            return data
        }
        .suggestedFileName("Best Move.png")
    }
}
