import SwiftUI
import ChessCore

@main
struct BestMoveApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            DebugLandscapeFrame { RootView() }
                .environment(app)
                .environment(\.boardTheme, app.settings.boardTheme)
                .environment(\.pieceSet, app.settings.pieceSet)
                .preferredColorScheme(.dark)
                .tint(Palette.gold)
                .task {
                    #if DEBUG
                    app.applyDebugLaunchArguments()
                    #endif
                    BoardRecognizer.shared.preload()
                    await app.warmUpEngine()
                }
                .onChange(of: app.settings.haptics, initial: true) { _, enabled in Haptics.isEnabled = enabled }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        NavigationStack(path: $app.path) {
            HomeView()
                .navigationDestination(for: AppRoute.self) { route in
                    switch route {
                    case .analysis(let model):
                        AnalysisView(model: model)
                    }
                }
        }
        .sheet(isPresented: $app.isScanPresented) {
            ScanFlowView()
        }
        .sheet(item: $app.setupRequest) { request in
            PositionEditorSheet(initial: request.position, orientation: request.orientation, title: "Set up position") { position, orientation in
                app.analyze(position: position, orientation: orientation, source: .setup)
            }
        }
        .sheet(isPresented: $app.isSettingsPresented) {
            SettingsView()
        }
        .onOpenURL { url in
            // bestmove://analyze?fen=…  — handy for testing and sharing.
            guard let fen = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "fen" })?.value,
                  let position = try? Position(fen: fen) else { return }
            app.analyze(position: position, orientation: position.sideToMove, source: .board)
        }
    }
}

/// `-demoLandscapeFrame` (DEBUG): lays the UI out in a landscape-shaped frame turned on its side, to
/// check iPad landscape layouts in a simulator that can't rotate. Release builds pass content through.
struct DebugLandscapeFrame<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-demoLandscapeFrame") {
            GeometryReader { proxy in
                content
                    .frame(width: proxy.size.height, height: proxy.size.width)
                    .rotationEffect(.degrees(90))
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
            .ignoresSafeArea()
        } else {
            content
        }
        #else
        content
        #endif
    }
}
