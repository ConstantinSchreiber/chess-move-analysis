import SwiftUI
import Observation
import ChessCore
import StockfishKit

enum AppRoute: Hashable {
    case analysis(AnalysisModel)
}

/// App-wide state: navigation, settings, history and engine warm-up.
@Observable
@MainActor
final class AppModel {
    let settings = AppSettings()
    let history = HistoryStore()
    var path: [AppRoute] = []
    var isScanPresented = false
    var isSettingsPresented = false
    var setupRequest: SetupRequest?
    /// An image the scan sheet should recognise as soon as it opens (samples, shortcuts, debug).
    var pendingScanImage: UIImage?

    struct SetupRequest: Identifiable {
        let id = UUID()
        let position: Position
        let orientation: PieceColor
    }

    static var engineConfiguration: StockfishEngine.Configuration {
        StockfishEngine.Configuration(netDirectory: Bundle.main.resourceURL?.appendingPathComponent("NNUE"))
    }

    /// Boots Stockfish in the background so the first analysis starts instantly.
    func warmUpEngine() async {
        try? await StockfishEngine.shared.prepare(Self.engineConfiguration)
    }

    func startScan() {
        path.removeAll()
        isScanPresented = true
    }

    func scan(_ image: UIImage) {
        pendingScanImage = image
        startScan()
    }

    #if DEBUG
    /// Launch arguments for screenshots and manual testing:
    /// `-demoScan sample-photo`, `-demoAnalysis <FEN>`, `-demoSetup`, `-demoSettings`.
    func applyDebugLaunchArguments() {
        let args = ProcessInfo.processInfo.arguments
        func value(after flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }
        if let sample = value(after: "-demoScan"), let image = SampleImages.all.first(where: { $0.id == sample })?.image {
            scan(image)
        } else if let fen = value(after: "-demoAnalysis"), let position = try? Position(fen: fen) {
            analyze(position: position, orientation: position.sideToMove, source: .board)
        } else if args.contains("-demoSetup") {
            openSetup()
        } else if args.contains("-demoSettings") {
            isSettingsPresented = true
        }
    }
    #endif

    func openBoard() {
        analyze(position: .start, orientation: .white, source: .board)
    }

    func openSetup(position: Position = .start, orientation: PieceColor = .white) {
        setupRequest = SetupRequest(position: position, orientation: orientation)
    }

    func analyze(position: Position, orientation: PieceColor, source: HistoryEntry.Source) {
        let historyID = history.record(position: position, orientation: orientation, source: source)
        let model = AnalysisModel(position: position, orientation: orientation, settings: settings,
                                  history: history, historyID: historyID)
        isScanPresented = false
        setupRequest = nil
        path.append(.analysis(model))
    }

    func open(_ entry: HistoryEntry) {
        analyze(position: entry.position, orientation: entry.orientation, source: entry.source)
    }

    func replaceAnalysis(_ model: AnalysisModel, with position: Position, orientation: PieceColor) {
        model.stop()
        if let index = path.lastIndex(of: .analysis(model)) { path.removeSubrange(index...) }
        analyze(position: position, orientation: orientation, source: .setup)
    }
}
