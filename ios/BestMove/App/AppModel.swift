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
    #if DEBUG
    /// A ready-made recognition result to show in the review screen (UI development without models).
    var pendingDemoReview: RecognitionResult?
    /// Open the camera straight away (with `CameraScannerView.demoImage` as the feed).
    var pendingDemoCamera = false
    #endif

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
    /// `-demoScan sample-photo`, `-demoCamera sample-photo [-demoCameraCenterX 0.33]`, `-demoScanSheet`, `-demoReview`, `-demoAnalysis <FEN>`, `-demoSetup`, `-demoSettings`.
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
        } else if args.contains("-demoReview"), let review = Self.demoReview() {
            pendingDemoReview = review
            startScan()
        } else if let sample = value(after: "-demoCamera"),
                  let image = SampleImages.all.first(where: { $0.id == sample })?.image {
            CameraScannerView.demoImage = Self.cameraFrame(image, centerX: Double(value(after: "-demoCameraCenterX") ?? "") ?? 0.5)
            pendingDemoCamera = true
            startScan()
        } else if args.contains("-demoScanSheet") {
            startScan()
        } else if args.contains("-demoSetup") {
            openSetup()
        } else if args.contains("-demoSettings") {
            isSettingsPresented = true
        }
    }

    /// Crops a photo to the screen's aspect ratio around `centerX` (0…1), the way a camera held over
    /// the board would frame it.
    private static func cameraFrame(_ image: UIImage, centerX: Double) -> UIImage {
        guard let cg = image.cgImage else { return image }
        let screen = UIScreen.main.bounds.size
        let height = CGFloat(cg.height)
        let width = min(CGFloat(cg.width), (height * screen.width / screen.height).rounded())
        let x = min(max(CGFloat(centerX) * CGFloat(cg.width) - width / 2, 0), CGFloat(cg.width) - width)
        guard let cropped = cg.cropping(to: CGRect(x: x, y: 0, width: width, height: height)) else { return image }
        return UIImage(cgImage: cropped)
    }

    /// The bundled photo sample with its known answer, as if the recogniser had read it.
    private static func demoReview() -> RecognitionResult? {
        guard let image = SampleImages.all.first(where: { $0.id == "sample-photo" })?.image,
              let source = RGBAImage(image: image, maxSide: 2048),
              let position = try? Position(fen: "r1bq1rk1/pp1nbppp/2p1p3/3n2B1/2BP4/2N1PN2/PP3PPP/2RQK2R w K - 1 10") else { return nil }
        let corners = [CGPoint(x: 120.1, y: 693.5), CGPoint(x: 904.9, y: 671.4), CGPoint(x: 896.1, y: 1484.8), CGPoint(x: 139, y: 1468.8)]
        return RecognitionResult(image: source.uiImage(), boardImage: source.warped(quad: corners, size: 384).uiImage(),
                                 corners: corners, position: position, orientation: .white,
                                 uncertainSquares: [Square("d5")!, Square("g5")!],
                                 evidence: .highlight(mover: .black, move: Move(uci: "f6d5")), duration: 0.08)
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
