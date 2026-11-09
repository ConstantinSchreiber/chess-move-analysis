import CStockfish
import Foundation

/// Stockfish running in-process. One engine per process; use `shared`.
///
/// All engine state lives on a private serial queue. Every `go` sent to Stockfish produces exactly
/// one `bestmove`, and Stockfish prints a search's output strictly before the next search's, so
/// output is attributed to the oldest search in a FIFO of in-flight searches. That keeps a stopped
/// search's late `info`/`bestmove` lines from ever reaching a newer analysis.
public final class StockfishEngine: @unchecked Sendable {
    public static let shared = StockfishEngine()

    /// NNUE file name this build expects (bundle it, e.g. under `NNUE/`).
    public static let networkFileName = String(cString: sfkit_default_net_name())

    public static var defaultThreads: Int { max(1, ProcessInfo.processInfo.activeProcessorCount - 1) }

    public struct Configuration: Sendable, Equatable {
        public var threads: Int
        public var hashMB: Int
        /// Directory containing `networkFileName`. nil → the main bundle (`NNUE/` or resource root).
        public var netDirectory: URL?

        public init(threads: Int = StockfishEngine.defaultThreads, hashMB: Int = 128, netDirectory: URL? = nil) {
            self.threads = threads
            self.hashMB = hashMB
            self.netDirectory = netDirectory
        }
    }

    public var isReady: Bool {
        readyLock.lock()
        defer { readyLock.unlock() }
        return ready
    }

    // MARK: State (only touched on `queue`, except `ready`)

    private let queue = DispatchQueue(label: "StockfishKit.engine", qos: .userInitiated)
    private let readyLock = NSLock()
    private var ready = false

    private var booted = false
    private var lastConfiguration = Configuration()
    private var loadedNetPath: String?
    private var verifiedNetPath: String?
    private var appliedThreads: Int?
    private var appliedHashMB: Int?
    private var appliedMultiPV: Int?
    private var inFlight: [Search] = []
    private var active: Search?
    private var readyWaiters: [() -> Void] = []
    private var pendingPrepares: [(Result<Void, Error>) -> Void] = []

    /// At most ~12 snapshots per second; a short debounce lets a MultiPV batch land together.
    private static let minimumEmitInterval: UInt64 = 1_000_000_000 / 12
    private static let batchDebounce: UInt64 = 12_000_000

    private init() {}

    // MARK: Public API

    /// Boots the engine (once), applies options and verifies the network loads. Cheap to call again;
    /// changed options are re-applied (Threads/Hash/network changes stop a running search first).
    public func prepare(_ config: Configuration = .init()) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                self.prepareOnQueue(config) { continuation.resume(with: $0) }
            }
        }
    }

    /// Analyses `fen` until `limit` is reached, `stop()` is called, another analysis starts, or the
    /// consuming task is cancelled. The stream ends after the final snapshot (`isFinal`), or right
    /// away without snapshots for an invalid FEN / unusable engine. Calls `prepare` implicitly with
    /// the last configuration if needed.
    public func analyze(fen: String, multiPV: Int = 3, limit: SearchLimit = .infinite) -> AsyncStream<EngineSnapshot> {
        let (stream, continuation) = AsyncStream.makeStream(of: EngineSnapshot.self,
                                                            bufferingPolicy: .bufferingNewest(1))
        guard let sanitized = FENGuard.sanitize(fen) else {
            continuation.finish()
            return stream
        }
        let search = Search(fen: fen, whiteToMove: sanitized.whiteToMove,
                            multiPV: min(max(multiPV, 1), 256), continuation: continuation)
        continuation.onTermination = { [weak self] termination in
            guard case .cancelled = termination else { return }
            self?.queue.async { self?.cancel(search) }
        }
        queue.async {
            self.start(search, sanitizedFEN: sanitized.fen, limit: limit)
        }
        return stream
    }

    /// Test hook: sends `fen` to Stockfish without `FENGuard`, to exercise the engine-side guards.
    func analyzeUnchecked(fen: String, limit: SearchLimit) -> AsyncStream<EngineSnapshot> {
        let (stream, continuation) = AsyncStream.makeStream(of: EngineSnapshot.self,
                                                            bufferingPolicy: .bufferingNewest(1))
        let search = Search(fen: fen, whiteToMove: !fen.contains(" b "), multiPV: 1, continuation: continuation)
        queue.async { self.start(search, sanitizedFEN: fen, limit: limit) }
        return stream
    }

    /// Stops the current analysis; its stream still receives a final snapshot with the best move.
    public func stop() {
        queue.async {
            guard let search = self.active, !search.done else { return }
            self.sendStop(for: search)
        }
    }

    /// Clears the hash and search history (`ucinewgame`). Stops a running analysis first.
    public func newGame() {
        queue.async {
            guard self.booted else { return }
            if let search = self.active, !search.done { self.sendStop(for: search) }
            self.send("ucinewgame")
        }
    }

    // MARK: Preparation

    private func prepareOnQueue(_ config: Configuration, completion: @escaping (Result<Void, Error>) -> Void) {
        let netURL: URL
        do {
            netURL = try resolveNetwork(in: config.netDirectory)
        } catch {
            completion(.failure(error))
            return
        }
        lastConfiguration = config

        let netPath = netURL.path
        let threads = min(max(config.threads, 1), 1024)
        let maxHash = max(16, Int(ProcessInfo.processInfo.physicalMemory / 4 / 1_048_576))
        let hashMB = min(max(config.hashMB, 1), maxHash)

        // These options make Stockfish wait for the current search; an infinite one would never end.
        let blocking = (booted && netPath != loadedNetPath) || threads != appliedThreads || hashMB != appliedHashMB
        if blocking, let search = active, !search.done { sendStop(for: search) }

        if !booted {
            // Stockfish looks for the default net next to argv[0], so this loads it during boot.
            let argv0 = netURL.deletingLastPathComponent().appendingPathComponent("stockfish").path
            let context = Unmanaged.passUnretained(self).toOpaque()
            let started = sfkit_start(argv0, { line, context in
                guard let line, let context else { return }
                let engine = Unmanaged<StockfishEngine>.fromOpaque(context).takeUnretainedValue()
                let text = String(cString: line)
                engine.queue.async { engine.receive(text) }
            }, context)
            guard started >= 0 else {
                completion(.failure(StockfishError.engineThreadFailed))
                return
            }
            booted = true
            loadedNetPath = netPath
            send("uci")
            send("setoption name UCI_ShowWDL value true")
        } else if netPath != loadedNetPath {
            send("setoption name EvalFile value \(netPath)")
            loadedNetPath = netPath
            verifiedNetPath = nil
        }
        if threads != appliedThreads {
            send("setoption name Threads value \(threads)")
            appliedThreads = threads
        }
        if hashMB != appliedHashMB {
            send("setoption name Hash value \(hashMB)")
            appliedHashMB = hashMB
        }

        if verifiedNetPath == netPath {
            send("isready")
            readyWaiters.append { [weak self] in
                self?.setReady(true)
                completion(.success(()))
            }
            return
        }

        pendingPrepares.append(completion)
        guard pendingPrepares.count == 1 else { return }  // a probe is already on its way

        // A depth-1 search proves the network is usable (the patched engine answers
        // `bestmove (none)` instead of exiting when it isn't).
        let probe = Search(fen: "startpos", whiteToMove: true, multiPV: 1, continuation: nil)
        probe.onFinish = { [weak self, weak probe] bestMove in
            guard let self else { return }
            if self.loadedNetPath != netPath, self.loadedNetPath != nil {
                // Another prepare switched networks meanwhile; verify that one instead.
                let waiting = self.pendingPrepares
                self.pendingPrepares.removeAll()
                waiting.forEach { self.prepareOnQueue(self.lastConfiguration, completion: $0) }
                return
            }
            let result: Result<Void, Error>
            if bestMove != nil {
                self.verifiedNetPath = netPath
                result = .success(())
            } else {
                self.loadedNetPath = nil  // retry the load on the next prepare
                result = .failure(StockfishError.networkLoadFailed(path: netPath, reason: probe?.errorMessage))
            }
            self.setReady(bestMove != nil)
            let waiting = self.pendingPrepares
            self.pendingPrepares.removeAll()
            waiting.forEach { $0(result) }
        }
        send("position startpos")
        send("go depth 1")
        inFlight.append(probe)
    }

    private func resolveNetwork(in directory: URL?) throws -> URL {
        let name = Self.networkFileName
        var candidates: [URL] = []
        if let directory {
            candidates.append(directory.appendingPathComponent(name))
        } else {
            if let resources = Bundle.main.resourceURL {
                candidates.append(resources.appendingPathComponent("NNUE").appendingPathComponent(name))
                candidates.append(resources.appendingPathComponent(name))
            }
            if let url = Bundle.main.url(forResource: name, withExtension: nil) {
                candidates.append(url)
            }
        }
        let manager = FileManager.default
        for url in candidates {
            let size = (try? manager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
            if size > 1_000_000 { return url }
        }
        throw StockfishError.networkNotFound(name: name, searched: candidates.map(\.path))
    }

    private func setReady(_ value: Bool) {
        readyLock.lock()
        ready = value
        readyLock.unlock()
    }

    // MARK: Searches

    private func start(_ search: Search, sanitizedFEN: String, limit: SearchLimit) {
        guard !search.cancelled else { return }

        if let current = active, !current.done {
            sendStop(for: current)
            current.finishStream()  // superseded: its consumer gets no more snapshots
        }
        active = nil

        if !booted || loadedNetPath == nil {
            var failure: Error?
            prepareOnQueue(lastConfiguration) { result in
                if case .failure(let error) = result { failure = error }
            }
            // Only a synchronous failure (missing file) matters here; a failed load surfaces as
            // `bestmove (none)` for this search too.
            if failure != nil || !booted {
                search.finishStream()
                return
            }
        }

        if appliedMultiPV != search.multiPV {
            send("setoption name MultiPV value \(search.multiPV)")
            appliedMultiPV = search.multiPV
        }
        send("position fen \(sanitizedFEN)")
        send("go \(limit.uciArguments)")
        inFlight.append(search)
        active = search
    }

    private func cancel(_ search: Search) {
        search.cancelled = true
        search.continuation = nil
        if !search.done, inFlight.contains(where: { $0 === search }) {
            sendStop(for: search)
        }
        if active === search { active = nil }
    }

    private func sendStop(for search: Search) {
        guard !search.stopSent else { return }
        search.stopSent = true
        send("stop")
    }

    private func send(_ command: String) {
        sfkit_send(command)
    }

    // MARK: Output

    private func receive(_ line: String) {
        if line.hasPrefix("info ") {
            handleInfo(line)
        } else if line.hasPrefix("bestmove") {
            handleBestMove(line)
        } else if line == "readyok" {
            if !readyWaiters.isEmpty { readyWaiters.removeFirst()() }
        }
        // `id …`, `option …`, `uciok`: nothing to do.
    }

    private func handleInfo(_ text: String) {
        guard let search = inFlight.first, let info = UCIInfo(line: text) else { return }

        if let message = info.string {
            if message.hasPrefix("ERROR") { search.errorMessage = message }
            return
        }
        if let nodes = info.nodes { search.nodes = nodes }
        if let nps = info.nps { search.nps = nps }
        if let time = info.timeMs { search.timeMs = time }

        guard let line = info.line(whiteToMove: search.whiteToMove), line.multipv <= search.multiPV else { return }
        // Aspiration fail-high/low lines only replace nothing: an exact line, even one ply older,
        // is more useful than a bound.
        if line.score.bound != .exact, search.lines[line.multipv] != nil { return }
        search.lines[line.multipv] = line
        scheduleEmit(search, batchComplete: line.multipv == search.multiPV)
    }

    private func handleBestMove(_ text: String) {
        guard !inFlight.isEmpty else { return }
        let search = inFlight.removeFirst()
        search.done = true

        let tokens = text.split(separator: " ")
        let move = tokens.count > 1 ? String(tokens[1]) : nil
        let bestMove = (move == nil || move == "(none)") ? nil : move

        search.onFinish?(bestMove)
        search.onFinish = nil

        if search.errorMessage == nil || !search.lines.isEmpty {
            emit(search, bestMove: bestMove, isFinal: true)
        }
        search.finishStream()
        if active === search { active = nil }
    }

    private func scheduleEmit(_ search: Search, batchComplete: Bool) {
        guard search.continuation != nil else { return }
        search.dirty = true
        guard !search.emitScheduled else { return }

        let now = DispatchTime.now().uptimeNanoseconds
        let earliest = search.lastEmit + Self.minimumEmitInterval
        let fireAt = max(earliest, now + (batchComplete ? 0 : Self.batchDebounce))
        search.emitScheduled = true
        queue.asyncAfter(deadline: DispatchTime(uptimeNanoseconds: fireAt)) { [weak self, weak search] in
            guard let self, let search else { return }
            search.emitScheduled = false
            guard search.dirty, !search.done else { return }
            self.emit(search, bestMove: nil, isFinal: false)
        }
    }

    private func emit(_ search: Search, bestMove: String?, isFinal: Bool) {
        guard let continuation = search.continuation else { return }
        let lines = search.lines.values.sorted { $0.multipv < $1.multipv }
        continuation.yield(EngineSnapshot(
            fen: search.fen,
            depth: search.lines[1]?.depth ?? lines.first?.depth ?? 0,
            lines: lines,
            nodes: search.nodes,
            nps: search.nps,
            timeMs: search.timeMs,
            bestMove: bestMove,
            isFinal: isFinal
        ))
        search.lastEmit = DispatchTime.now().uptimeNanoseconds
        search.dirty = false
    }
}

/// One `go` command and everything Stockfish prints for it. Mutated only on the engine queue,
/// which is what makes the `@unchecked Sendable` hand-offs (stream termination handler) safe.
private final class Search: @unchecked Sendable {
    let fen: String
    let whiteToMove: Bool
    let multiPV: Int
    var continuation: AsyncStream<EngineSnapshot>.Continuation?
    var onFinish: ((String?) -> Void)?

    var lines: [Int: EngineLine] = [:]
    var nodes = 0
    var nps = 0
    var timeMs = 0
    var errorMessage: String?

    var lastEmit: UInt64 = 0
    var emitScheduled = false
    var dirty = false
    var stopSent = false
    var cancelled = false
    var done = false

    init(fen: String, whiteToMove: Bool, multiPV: Int, continuation: AsyncStream<EngineSnapshot>.Continuation?) {
        self.fen = fen
        self.whiteToMove = whiteToMove
        self.multiPV = multiPV
        self.continuation = continuation
    }

    func finishStream() {
        let continuation = self.continuation
        self.continuation = nil
        continuation?.finish()
    }
}
