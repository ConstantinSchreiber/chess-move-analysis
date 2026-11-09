import Foundation

/// Win/draw/loss expectation in per-mille, from White's point of view.
public struct WDL: Sendable, Hashable {
    public let win, draw, loss: Int

    public init(win: Int, draw: Int, loss: Int) {
        self.win = win
        self.draw = draw
        self.loss = loss
    }
}

/// An engine score from White's point of view (UCI reports the side to move's; it is normalized).
public struct EngineScore: Sendable, Hashable {
    public enum Value: Sendable, Hashable {
        case centipawns(Int)
        /// Moves to mate: > 0 White mates, < 0 Black mates. `mate(0)` means the side to move is
        /// already checkmated (the sign can't carry who; check the position's side to move).
        case mate(Int)
    }

    public enum Bound: Sendable, Hashable { case exact, lower, upper }

    public let value: Value
    public let bound: Bound

    public init(value: Value, bound: Bound = .exact) {
        self.value = value
        self.bound = bound
    }
}

public struct EngineLine: Sendable, Hashable, Identifiable {
    public var id: Int { multipv }
    public let multipv: Int
    public let depth: Int
    public let selDepth: Int
    public let score: EngineScore
    public let wdl: WDL?
    /// Principal variation in UCI notation (e.g. "e2e4", "e7e8q"). Empty when the side to move has no legal moves.
    public let pv: [String]

    public init(multipv: Int, depth: Int, selDepth: Int, score: EngineScore, wdl: WDL?, pv: [String]) {
        self.multipv = multipv
        self.depth = depth
        self.selDepth = selDepth
        self.score = score
        self.wdl = wdl
        self.pv = pv
    }
}

public struct EngineSnapshot: Sendable {
    /// The FEN passed to `analyze`, unchanged.
    public let fen: String
    /// Depth of the principal line (multipv 1).
    public let depth: Int
    /// Sorted by `multipv`.
    public let lines: [EngineLine]
    public let nodes: Int
    public let nps: Int
    public let timeMs: Int
    /// Only set on the final snapshot; nil if there is no legal move.
    public let bestMove: String?
    /// True for the last snapshot of a search (`bestmove` received).
    public let isFinal: Bool

    public init(fen: String, depth: Int, lines: [EngineLine], nodes: Int, nps: Int, timeMs: Int,
                bestMove: String?, isFinal: Bool) {
        self.fen = fen
        self.depth = depth
        self.lines = lines
        self.nodes = nodes
        self.nps = nps
        self.timeMs = timeMs
        self.bestMove = bestMove
        self.isFinal = isFinal
    }
}

public enum SearchLimit: Sendable, Hashable {
    case infinite
    case depth(Int)
    /// Milliseconds.
    case movetime(Int)
    case nodes(Int)

    var uciArguments: String {
        switch self {
        case .infinite: return "infinite"
        case .depth(let depth): return "depth \(max(1, depth))"
        case .movetime(let ms): return "movetime \(max(1, ms))"
        case .nodes(let nodes): return "nodes \(max(1, nodes))"
        }
    }
}

public enum StockfishError: Error, LocalizedError, Equatable {
    /// The NNUE file isn't where it was expected. Run `ios/scripts/fetch-nnue.sh` and make sure the
    /// app bundles it (or pass `Configuration.netDirectory`).
    case networkNotFound(name: String, searched: [String])
    /// The file exists but Stockfish could not load it (truncated or incompatible).
    case networkLoadFailed(path: String, reason: String?)
    case engineThreadFailed

    public var errorDescription: String? {
        switch self {
        case let .networkNotFound(name, searched):
            return "Stockfish network \(name) not found (looked in: \(searched.joined(separator: ", ")))."
        case let .networkLoadFailed(path, reason):
            return "Stockfish could not load the network at \(path)" + (reason.map { ": \($0)" } ?? ".")
        case .engineThreadFailed:
            return "Could not start the Stockfish thread."
        }
    }
}
