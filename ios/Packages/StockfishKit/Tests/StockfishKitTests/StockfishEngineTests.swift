@testable import StockfishKit
import XCTest

/// Integration tests against the real engine and network (ios/scripts/fetch-nnue.sh must have run).
/// The engine is a process-wide singleton, so these share one booted instance.
final class StockfishEngineTests: XCTestCase {
    static let netDirectory: URL = {
        if let override = ProcessInfo.processInfo.environment["STOCKFISHKIT_NET_DIR"] {
            return URL(fileURLWithPath: override)
        }
        // Tests/StockfishKitTests/<file> → package root → ios/
        return URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Tempo/Resources/NNUE")
    }()

    static let startpos = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    static let startposMoves: Set<String> = [
        "a2a3", "a2a4", "b2b3", "b2b4", "c2c3", "c2c4", "d2d3", "d2d4", "e2e3", "e2e4",
        "f2f3", "f2f4", "g2g3", "g2g4", "h2h3", "h2h4", "b1a3", "b1c3", "g1f3", "g1h3",
    ]
    /// K+Q vs K: none of its moves exist in the start position.
    static let queenEnding = "4k3/8/8/8/8/8/8/4K2Q w - - 0 1"
    static let queenEndingMoves: Set<String> = {
        var moves: Set<String> = ["e1d1", "e1d2", "e1e2", "e1f2", "e1f1"]
        for target in ["g1", "f1", "a8", "b7", "c6", "d5", "e4", "f3", "g2"] { moves.insert("h1\(target)") }
        for rank in 2...8 { moves.insert("h1h\(rank)") }
        return moves
    }()

    let engine = StockfishEngine.shared

    override func setUp() async throws {
        try await engine.prepare(.init(threads: 4, hashMB: 64, netDirectory: Self.netDirectory))
        XCTAssertTrue(engine.isReady)
    }

    /// Collects a whole stream, failing (and stopping the engine) if it doesn't finish in time.
    func collect(_ stream: AsyncStream<EngineSnapshot>, timeout: TimeInterval = 30,
                 file: StaticString = #filePath, line: UInt = #line) async throws -> [EngineSnapshot] {
        try await withThrowingTaskGroup(of: [EngineSnapshot]?.self) { group in
            group.addTask {
                var snapshots: [EngineSnapshot] = []
                for await snapshot in stream { snapshots.append(snapshot) }
                return snapshots
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                return nil
            }
            let first = try await group.next() ?? nil
            group.cancelAll()
            guard let first else {
                engine.stop()
                XCTFail("stream did not finish within \(timeout)s", file: file, line: line)
                return []
            }
            return first
        }
    }

    func cp(_ score: EngineScore?) -> Int? {
        if case .centipawns(let value)? = score?.value { return value }
        return nil
    }

    // MARK: -

    func testStartposDepth15() async throws {
        let snapshots = try await collect(engine.analyze(fen: Self.startpos, multiPV: 1, limit: .depth(15)))
        let last = try XCTUnwrap(snapshots.last)
        XCTAssertTrue(last.isFinal)
        XCTAssertEqual(snapshots.filter(\.isFinal).count, 1)
        XCTAssertTrue(Self.startposMoves.contains(last.bestMove ?? ""), "bestmove \(last.bestMove ?? "nil")")
        XCTAssertGreaterThanOrEqual(last.depth, 15)
        XCTAssertTrue(snapshots.allSatisfy { $0.fen == Self.startpos })
        XCTAssertEqual(last.lines.first?.pv.first, last.bestMove)
        XCTAssertNotNil(last.lines.first?.wdl)
        XCTAssertGreaterThan(last.nodes, 0)
    }

    func testMateInOneForWhite() async throws {
        let snapshots = try await collect(engine.analyze(fen: "6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1", multiPV: 1, limit: .depth(10)))
        let last = try XCTUnwrap(snapshots.last)
        XCTAssertEqual(last.bestMove, "d1d8")
        XCTAssertEqual(last.lines.first?.score.value, .mate(1))
    }

    func testBlackScoresAreWhitePointOfView() async throws {
        // Black mates in one: negative mate from White's side.
        let mate = try await collect(engine.analyze(fen: "3r2k1/5ppp/8/8/8/8/5PPP/6K1 b - - 0 1", multiPV: 1, limit: .depth(10)))
        XCTAssertEqual(mate.last?.bestMove, "d8d1")
        XCTAssertEqual(mate.last?.lines.first?.score.value, .mate(-1))

        // White is a queen down, Black to move → clearly negative for White, WDL favours Black.
        let down = try await collect(engine.analyze(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNB1KBNR b KQkq - 0 1", multiPV: 1, limit: .depth(12)))
        let downLine = try XCTUnwrap(down.last?.lines.first)
        XCTAssertLessThan(try XCTUnwrap(cp(downLine.score)), -500)
        let wdl = try XCTUnwrap(downLine.wdl)
        XCTAssertGreaterThan(wdl.loss, wdl.win)

        // Mirror: Black is a queen down, White to move → clearly positive.
        let up = try await collect(engine.analyze(fen: "rnb1kbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", multiPV: 1, limit: .depth(12)))
        XCTAssertGreaterThan(try XCTUnwrap(cp(up.last?.lines.first?.score)), 500)
    }

    func testMultiPV3() async throws {
        let snapshots = try await collect(engine.analyze(fen: Self.startpos, multiPV: 3, limit: .depth(12)))
        let last = try XCTUnwrap(snapshots.last)
        XCTAssertEqual(last.lines.map(\.multipv), [1, 2, 3])
        let firstMoves = last.lines.compactMap(\.pv.first)
        XCTAssertEqual(Set(firstMoves).count, 3)
        XCTAssertTrue(firstMoves.allSatisfy(Self.startposMoves.contains))
        let scores = last.lines.compactMap { cp($0.score) }
        XCTAssertEqual(scores, scores.sorted(by: >), "White to move: best line first")
        // Intermediate snapshots should be whole batches, never more lines than requested.
        XCTAssertTrue(snapshots.allSatisfy { $0.lines.count <= 3 })
    }

    func testMultiPVLargerThanLegalMoveCount() async throws {
        // White king in check from h1 rook: only Ka2 and Kb2.
        let snapshots = try await collect(engine.analyze(fen: "k7/8/8/8/8/8/8/K6r w - - 0 1", multiPV: 5, limit: .depth(10)))
        let last = try XCTUnwrap(snapshots.last)
        XCTAssertEqual(Set(last.lines.compactMap(\.pv.first)), ["a1a2", "a1b2"])
    }

    func testCheckmateAndStalemateAtRoot() async throws {
        let mated = try await collect(engine.analyze(fen: "k7/8/8/8/8/8/5PPP/r5K1 w - - 0 1", limit: .depth(5)), timeout: 5)
        let matedLast = try XCTUnwrap(mated.last)
        XCTAssertTrue(matedLast.isFinal)
        XCTAssertNil(matedLast.bestMove)
        XCTAssertEqual(matedLast.lines.first?.score.value, .mate(0))

        let stalemate = try await collect(engine.analyze(fen: "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1", limit: .depth(5)), timeout: 5)
        XCTAssertNil(stalemate.last?.bestMove)
        XCTAssertEqual(stalemate.last?.lines.first?.score.value, .centipawns(0))
    }

    func testInvalidPositionsNeverReachOrCrashTheEngine() async throws {
        for fen in ["hello", "4k3/8/8/8/8/8/8/4KK2 w - - 0 1", "P3k3/8/8/8/8/8/8/4K3 w - - 0 1",
                    "4k3/4R3/8/8/8/8/8/4K3 w - - 0 1"] {
            let snapshots = try await collect(engine.analyze(fen: fen, limit: .infinite), timeout: 2)
            XCTAssertTrue(snapshots.isEmpty, fen)
        }
        // Bypass the Swift guard: the patched engine must answer `bestmove (none)` instead of exit().
        for fen in ["8/8/8/8/8/8/8/8 w - - 0 1", "4k3/4R3/8/8/8/8/8/4K3 w - - 0 1", "garbage w"] {
            let snapshots = try await collect(engine.analyzeUnchecked(fen: fen, limit: .infinite), timeout: 5)
            XCTAssertTrue(snapshots.isEmpty, fen)
        }
        // Still healthy afterwards.
        let after = try await collect(engine.analyze(fen: Self.startpos, multiPV: 1, limit: .depth(8)))
        XCTAssertTrue(Self.startposMoves.contains(after.last?.bestMove ?? ""))
    }

    func testRapidAnalyzeStopCyclesNeverCrossResults() async throws {
        let positions = [(Self.startpos, Self.startposMoves), (Self.queenEnding, Self.queenEndingMoves)]
        var consumers: [Task<[EngineSnapshot], Never>] = []
        var expected: [(fen: String, moves: Set<String>)] = []

        for cycle in 0..<50 {
            let (fen, moves) = positions[cycle % 2]
            let stream = engine.analyze(fen: fen, multiPV: 1 + cycle % 3, limit: cycle % 7 == 0 ? .depth(6) : .infinite)
            let consumer = Task {
                var received: [EngineSnapshot] = []
                for await snapshot in stream { received.append(snapshot) }
                return received
            }
            consumers.append(consumer)
            expected.append((fen, moves))

            try await Task.sleep(nanoseconds: UInt64((cycle % 4) * 15_000_000))
            switch cycle % 5 {
            case 1: consumer.cancel()            // consumer walks away
            case 3: engine.stop()                // explicit stop, stream gets its final snapshot
            default: break                       // superseded by the next analyze
            }
        }

        // A final search must still run to completion with its own results.
        let final = try await collect(engine.analyze(fen: Self.queenEnding, multiPV: 2, limit: .depth(10)), timeout: 20)
        let finalLast = try XCTUnwrap(final.last)
        XCTAssertTrue(finalLast.isFinal)
        XCTAssertTrue(Self.queenEndingMoves.contains(finalLast.bestMove ?? ""))

        var total = 0
        for (index, consumer) in consumers.enumerated() {
            let received = await consumer.value
            total += received.count
            for snapshot in received {
                XCTAssertEqual(snapshot.fen, expected[index].fen, "cycle \(index)")
                for line in snapshot.lines {
                    if let move = line.pv.first {
                        XCTAssertTrue(expected[index].moves.contains(move), "cycle \(index): \(move) not legal in \(snapshot.fen)")
                    }
                }
                if let best = snapshot.bestMove {
                    XCTAssertTrue(expected[index].moves.contains(best), "cycle \(index): bestmove \(best)")
                }
            }
        }
        XCTAssertGreaterThan(total, 0)
    }

    func testSnapshotsAreThrottled() async throws {
        let fen = "r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4"
        let stream = engine.analyze(fen: fen, multiPV: 3, limit: .infinite)
        let consumer = Task { () -> [(Date, EngineSnapshot)] in
            var received: [(Date, EngineSnapshot)] = []
            for await snapshot in stream { received.append((Date(), snapshot)) }
            return received
        }
        try await Task.sleep(nanoseconds: 2_000_000_000)
        engine.stop()
        let received = await consumer.value
        let live = received.filter { !$0.1.isFinal }
        XCTAssertGreaterThanOrEqual(live.count, 5)
        XCTAssertLessThanOrEqual(live.count, 2 * 12 + 2, "more than ~12 snapshots/s")
        let gaps = zip(live.dropFirst(), live).map { $0.0.timeIntervalSince($1.0) }
        XCTAssertGreaterThanOrEqual(gaps.min() ?? 1, 0.04)
        XCTAssertEqual(received.last?.1.isFinal, true)
        XCTAssertNotNil(received.last?.1.bestMove)
    }

    func testMissingNetworkThrowsAndEngineSurvives() async throws {
        let bogus = URL(fileURLWithPath: "/nonexistent/nnue")
        do {
            try await engine.prepare(.init(threads: 4, hashMB: 64, netDirectory: bogus))
            XCTFail("expected networkNotFound")
        } catch let error as StockfishError {
            guard case .networkNotFound = error else { return XCTFail("\(error)") }
        }
        let after = try await collect(engine.analyze(fen: Self.startpos, multiPV: 1, limit: .depth(6)))
        XCTAssertNotNil(after.last?.bestMove)
    }

    /// Not an assertion of speed, just a report: `swift test --filter testReportNPS`.
    func testReportNPS() async throws {
        try await engine.prepare(.init(threads: 8, hashMB: 256, netDirectory: Self.netDirectory))
        engine.newGame()
        let fen = "r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4"
        let snapshots = try await collect(engine.analyze(fen: fen, multiPV: 1, limit: .movetime(5000)))
        let last = try XCTUnwrap(snapshots.last)
        print("NPS-REPORT threads=8 nps=\(last.nps) depth=\(last.depth) nodes=\(last.nodes) time=\(last.timeMs)ms best=\(last.bestMove ?? "-")")
        XCTAssertGreaterThan(last.nps, 0)
    }
}
