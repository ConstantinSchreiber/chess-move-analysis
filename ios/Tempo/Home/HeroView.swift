import SwiftUI

/// Atmospheric header: the pre-rendered 3D scene with a slow drift, faded into the page.
struct HeroView: View {
    private let renderer = HeroRenderer.shared
    @State private var drift = false

    var body: some View {
        ZStack {
            Palette.background
            GeometryReader { proxy in
                if let image = renderer.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .scaleEffect(drift ? 1.06 : 1.0, anchor: .init(x: 0.6, y: 0.55))
                        .transition(.opacity)
                }
                Color.clear.onAppear { renderer.load(size: proxy.size) }
            }
            LinearGradient(stops: [
                .init(color: Palette.background.opacity(0.85), location: 0),
                .init(color: Palette.background.opacity(0), location: 0.22),
                .init(color: Palette.background.opacity(0), location: 0.55),
                .init(color: Palette.background.opacity(0.75), location: 0.8),
                .init(color: Palette.background, location: 1),
            ], startPoint: .top, endPoint: .bottom)
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.easeInOut(duration: 18).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}
