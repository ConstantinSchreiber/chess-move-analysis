import Foundation
import Observation
import ChessCore
import StockfishKit

/// One engine line prepared for display.
struct DisplayLine: Identifiable, Hashable {
    struct Token: Hashable {
        let label: String?   // "12." / "12…" before the move, if any
        let san: String
        let index: Int       // index into `uci`
    }

    let id: Int
    let score: EngineScore
    let depth: Int
    let uci: [String]
    let tokens: [Token]
}

/// Drives one analysis session: the explored move tree, the current node and the engine.
@Observable
@MainActor
final class AnalysisModel: Identifiable, Hashable {
    enum EngineStatus: Equatable {
        case starting
        case running
        case paused
        case finished
        case gameOver(String)
        case unavailable(String)
    }

    let id = UUID()
    private(set) var tree: MoveTree
    private(set) var current: MoveTree.NodeID = MoveTree.root {
        didSet { displayLines = formatLines() }
    }
    var orientation: PieceColor
    private(set) var snapshot: EngineSnapshot? {
        didSet { displayLines = formatLines() }
    }
    /// Engine lines for the position on the board, formatted once per engine update.
    private(set) var displayLines: [DisplayLine] = []
    private(set) var status: EngineStatus = .starting
    /// Extra depth requested via "Go deeper".
    private var depthBonus = 0
    /// Whether Stockfish has finished booting at least once (for status wording).
    private(set) var engineBooted = StockfishEngine.shared.isReady
    private let historyID: UUID?

    @ObservationIgnored private var analysisTask: Task<Void, Never>?
    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let history: HistoryStore?

    init(position: Position, orientation: PieceColor, settings: AppSettings, history: HistoryStore? = nil, historyID: UUID? = nil) {
        tree = MoveTree(root: position)
        self.orientation = orientation
        self.settings = settings
        self.history = history
        self.historyID = historyID
    }

    nonisolated static func == (lhs: AnalysisModel, rhs: AnalysisModel) -> Bool { lhs.id == rhs.id }
    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(id) }

    // MARK: Derived state

    var position: Position { tree[current].position }
    var lastMove: Move? { tree[current].move }
    var line: [MoveTree.NodeID] { tree.line(through: current) }
    var canGoBack: Bool { current != MoveTree.root }
    var canGoForward: Bool { !tree[current].children.isEmpty }

    /// The engine snapshot, only if it belongs to the position on the board.
    var currentSnapshot: EngineSnapshot? {
        guard let snapshot, snapshot.fen == position.fen else { return nil }
        return snapshot
    }

    /// Longest engine line shown (in plies); longer PVs are trimmed.
    static let maxLinePlies = 16

    private func formatLines() -> [DisplayLine] {
        guard let snapshot = currentSnapshot else { return [] }
        let position = self.position
        return snapshot.lines.compactMap { line in
            let uci = Array(line.pv.prefix(Self.maxLinePlies))
            guard !uci.isEmpty else { return nil }
            return DisplayLine(id: line.multipv, score: line.score, depth: line.depth, uci: uci,
                               tokens: Self.tokens(for: uci, from: position))
        }
    }

    var bestMove: Move? {
        guard let first = currentSnapshot?.lines.first?.pv.first else { return nil }
        return Move(uci: first)
    }

    var evaluation: EngineScore? { currentSnapshot?.lines.first?.score }

    /// White's expected score for the eval bar, including finished games.
    var whiteChance: Double? {
        switch position.status {
        case .checkmate(let winner): return winner == .white ? 1 : 0
        case .stalemate: return 0.5
        default: return evaluation?.whiteWinningChance
        }
    }

    var targetDepth: Int { settings.maxDepth + depthBonus }

    var subtitle: String {
        let side = position.sideToMove == .white ? "White to move" : "Black to move"
        return "\(side) · move \(position.fullmoveNumber)"
    }

    // MARK: Engine

    func start() {
        guard analysisTask == nil else { return }
        restartAnalysis()
    }

    func stop() {
        analysisTask?.cancel()
        analysisTask = nil
        StockfishEngine.shared.stop()
    }

    func togglePause() {
        switch status {
        case .running, .starting:
            analysisTask?.cancel()
            analysisTask = nil
            StockfishEngine.shared.stop()
            status = .paused
        case .paused, .finished:
            restartAnalysis()
        default:
            break
        }
    }

    func goDeeper() {
        depthBonus += 10
        restartAnalysis()
    }

    private func restartAnalysis() {
        analysisTask?.cancel()
        let position = self.position
        switch position.status {
        case .checkmate(let winner):
            StockfishEngine.shared.stop()
            status = .gameOver("Checkmate — \(winner.name) wins")
            analysisTask = nil
            return
        case .stalemate:
            StockfishEngine.shared.stop()
            status = .gameOver("Stalemate — it's a draw")
            analysisTask = nil
            return
        default:
            break
        }
        guard position.isValidForAnalysis else {
            StockfishEngine.shared.stop()
            analysisTask = nil
            status = .unavailable("This position isn't legal, so it can't be analysed.")
            return
        }
        if currentSnapshot == nil { status = .starting }
        let fen = position.fen
        let lines = settings.engineLines
        let depth = targetDepth
        let isRoot = current == MoveTree.root
        analysisTask = Task { [weak self] in
            // Coalesce rapid navigation (e.g. holding the forward button).
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled else { return }
            do {
                try await StockfishEngine.shared.prepare(AppModel.engineConfiguration)
            } catch {
                guard !Task.isCancelled else { return }
                self?.status = .unavailable(error.localizedDescription)
                return
            }
            guard !Task.isCancelled else { return }
            self?.engineBooted = true
            self?.status = .running
            for await snapshot in StockfishEngine.shared.analyze(fen: fen, multiPV: lines, limit: .depth(depth)) {
                guard let self, !Task.isCancelled else { break }
                self.snapshot = snapshot
                if snapshot.isFinal { self.status = .finished }
                if isRoot, snapshot.isFinal || snapshot.depth >= 18, let score = snapshot.lines.first?.score, let historyID {
                    history?.updateEvaluation(score.shortText, for: historyID)
                }
            }
        }
    }

    // MARK: Navigation

    func play(_ move: Move) {
        guard let node = tree.add(move, after: current) else { return }
        select(node)
    }

    func select(_ node: MoveTree.NodeID) {
        guard node != current, tree.nodes.indices.contains(node) else { return }
        current = node
        depthBonus = 0
        restartAnalysis()
    }

    func back() { if let parent = tree[current].parent { select(parent) } }
    func forward() { if let child = tree[current].children.first { select(child) } }
    func toStart() { select(MoveTree.root) }
    func toEnd() { if let last = line.last { select(last) } }

    /// Plays an engine line into the tree up to and including move `index`.
    func play(line: DisplayLine, through index: Int) {
        let node = tree.add(uciLine: Array(line.uci.prefix(index + 1)), after: current)
        select(node)
    }

    func flip() { orientation = orientation.opposite }

    func deleteVariation(_ node: MoveTree.NodeID) {
        guard node != MoveTree.root else { return }
        let onPath = tree.path(to: current).contains(node)
        let currentMoves = tree.moves(to: current)
        let parent = tree.delete(node)
        // Ids are compacted by the deletion; find the same position again by its moves.
        let survivor = onPath ? parent : tree.node(following: currentMoves)
        if let survivor, !onPath {
            current = survivor
        } else {
            current = survivor ?? MoveTree.root
            depthBonus = 0
            restartAnalysis()
        }
    }

    // MARK: Helpers

    static func tokens(for uci: [String], from position: Position) -> [DisplayLine.Token] {
        var tokens: [DisplayLine.Token] = []
        var pos = position
        for (i, move) in uci.enumerated() {
            guard let m = Move(uci: move), pos.isLegal(m) else { break }
            let label: String?
            if pos.sideToMove == .white {
                label = "\(pos.fullmoveNumber)."
            } else {
                label = i == 0 ? "\(pos.fullmoveNumber)…" : nil
            }
            tokens.append(.init(label: label, san: pos.san(for: m), index: i))
            pos.play(m)
        }
        return tokens
    }
}
