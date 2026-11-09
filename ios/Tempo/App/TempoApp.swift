import SwiftUI
import ChessCore

@main
struct TempoApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
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
            // tempo://analyze?fen=…  — handy for testing and sharing.
            guard let fen = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "fen" })?.value,
                  let position = try? Position(fen: fen) else { return }
            app.analyze(position: position, orientation: position.sideToMove, source: .board)
        }
    }
}
