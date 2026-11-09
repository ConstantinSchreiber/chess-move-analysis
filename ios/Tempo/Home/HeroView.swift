import SwiftUI
import ChessCore

/// Atmospheric header: a board receding into darkness under a warm key light.
struct HeroView: View {
    @Environment(\.boardTheme) private var theme
    @State private var drift = false

    private static let position = (try? Position(fen: "r1bq1rk1/pp2bppp/2n1pn2/3p4/2PP4/2N1PN2/PP3PPP/R2QKB1R w KQ - 0 8")) ?? .start

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack {
                Palette.background

                MiniBoardView(position: Self.position)
                    .frame(width: width * 1.5, height: width * 1.5)
                    .rotation3DEffect(.degrees(62), axis: (x: 1, y: 0, z: 0), anchor: .center, perspective: 0.55)
                    .rotationEffect(.degrees(drift ? -4 : -8))
                    .offset(x: drift ? -10 : 10, y: proxy.size.height * 0.05)
                    .saturation(0.75)
                    .brightness(-0.05)

                // Warm key light from above.
                RadialGradient(colors: [Palette.gold.opacity(0.32), .clear], center: .init(x: 0.62, y: 0.18),
                               startRadius: 10, endRadius: width * 0.85)
                    .blendMode(.plusLighter)

                // Vignette into the page background.
                LinearGradient(stops: [
                    .init(color: Palette.background.opacity(0.95), location: 0),
                    .init(color: Palette.background.opacity(0.15), location: 0.32),
                    .init(color: Palette.background.opacity(0.35), location: 0.6),
                    .init(color: Palette.background, location: 1),
                ], startPoint: .top, endPoint: .bottom)
                RadialGradient(colors: [.clear, Palette.background.opacity(0.85)], center: .center,
                               startRadius: width * 0.3, endRadius: width * 0.95)
            }
            .clipped()
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) { drift = true }
        }
        .accessibilityHidden(true)
    }
}
