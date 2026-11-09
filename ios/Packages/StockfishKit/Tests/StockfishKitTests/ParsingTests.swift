@testable import StockfishKit
import XCTest

final class UCIInfoTests: XCTestCase {
    func testParsesFullPVLine() throws {
        let info = try XCTUnwrap(UCIInfo(line:
            "info depth 22 seldepth 31 multipv 2 score cp 35 wdl 120 820 60 nodes 1234567 nps 2345678 hashfull 120 tbhits 0 time 526 pv e2e4 e7e5 g1f3"))
        XCTAssertEqual(info.depth, 22)
        XCTAssertEqual(info.selDepth, 31)
        XCTAssertEqual(info.multipv, 2)
        XCTAssertEqual(info.score, EngineScore(value: .centipawns(35), bound: .exact))
        XCTAssertEqual(info.wdl, WDL(win: 120, draw: 820, loss: 60))
        XCTAssertEqual(info.nodes, 1_234_567)
        XCTAssertEqual(info.nps, 2_345_678)
        XCTAssertEqual(info.timeMs, 526)
        XCTAssertEqual(info.pv, ["e2e4", "e7e5", "g1f3"])
    }

    func testBlackToMoveIsConvertedToWhitePointOfView() throws {
        let info = try XCTUnwrap(UCIInfo(line: "info depth 10 seldepth 12 multipv 1 score cp 80 lowerbound wdl 300 600 100 nodes 10 nps 10 time 1 pv d7d5"))
        let line = try XCTUnwrap(info.line(whiteToMove: false))
        XCTAssertEqual(line.score, EngineScore(value: .centipawns(-80), bound: .upper))
        XCTAssertEqual(line.wdl, WDL(win: 100, draw: 600, loss: 300))

        let mate = try XCTUnwrap(UCIInfo(line: "info depth 5 seldepth 2 multipv 1 score mate 2 nodes 1 nps 1 time 1 pv d8d1"))
        XCTAssertEqual(mate.line(whiteToMove: false)?.score.value, .mate(-2))
        XCTAssertEqual(mate.line(whiteToMove: true)?.score.value, .mate(2))
    }

    func testRootMateAndNonPVLines() throws {
        let mated = try XCTUnwrap(UCIInfo(line: "info depth 0 score mate 0"))
        XCTAssertEqual(mated.line(whiteToMove: true)?.score.value, .mate(0))
        XCTAssertEqual(mated.line(whiteToMove: true)?.pv, [])

        XCTAssertNil(UCIInfo(line: "info depth 12 currmove e2e4 currmovenumber 1")?.line(whiteToMove: true))
        XCTAssertEqual(UCIInfo(line: "info string NNUE evaluation using nn.nnue")?.string, "NNUE evaluation using nn.nnue")
        XCTAssertNil(UCIInfo(line: "bestmove e2e4"))
    }
}

final class FENGuardTests: XCTestCase {
    func testAcceptsAndNormalizes() {
        XCTAssertEqual(FENGuard.sanitize("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")?.fen,
                       "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1")
        // Missing fields get defaults.
        XCTAssertEqual(FENGuard.sanitize("4k3/8/8/8/8/8/8/4K3")?.fen, "4k3/8/8/8/8/8/8/4K3 w - - 0 1")
        // Castling rights without king/rook at home are dropped; bad en passant cleared.
        XCTAssertEqual(FENGuard.sanitize("r3k3/8/8/8/8/8/8/4K2R b KQkq e3 3 40")?.fen,
                       "r3k3/8/8/8/8/8/8/4K2R b Kq e3 3 40")
        XCTAssertEqual(FENGuard.sanitize("4k3/8/8/8/8/8/8/4K3 w - e3 0 0")?.fen, "4k3/8/8/8/8/8/8/4K3 w - - 0 1")
        XCTAssertEqual(FENGuard.sanitize("4k3/8/8/8/8/8/8/4K3 b - - 0 1")?.whiteToMove, false)
    }

    func testRejectsBrokenPositions() {
        XCTAssertNil(FENGuard.sanitize(""))
        XCTAssertNil(FENGuard.sanitize("hello world"))
        XCTAssertNil(FENGuard.sanitize("4k3/8/8/8/8/8/8/4KK2 w - - 0 1"), "two white kings")
        XCTAssertNil(FENGuard.sanitize("8/8/8/8/8/8/8/4K3 w - - 0 1"), "no black king")
        XCTAssertNil(FENGuard.sanitize("P3k3/8/8/8/8/8/8/4K3 w - - 0 1"), "pawn on 8th rank")
        XCTAssertNil(FENGuard.sanitize("4k3/8/8/8/8/8/8/4K3 x - - 0 1"), "bad side")
        XCTAssertNil(FENGuard.sanitize("4k3/8/8/8/8/8/8/4K4 w - - 0 1"), "rank too long")
        XCTAssertNil(FENGuard.sanitize("4k3/8/8/8/8/8/4K3 w - - 0 1"), "seven ranks")
        XCTAssertNil(FENGuard.sanitize("4k3/4R3/8/8/8/8/8/4K3 w - - 0 1"), "side not to move in check (rook)")
        XCTAssertNil(FENGuard.sanitize("4k3/3P4/8/8/8/8/8/4K3 w - - 0 1"), "side not to move in check (pawn)")
        XCTAssertNil(FENGuard.sanitize("4k3/8/8/b7/8/8/8/4K3 b - - 0 1"), "side not to move in check (bishop)")
        XCTAssertNil(FENGuard.sanitize("QQQQkQQQ/QQQQQQQQ/8/8/8/8/8/4K3 w - - 0 1"), "impossible material")
        // Side to move in check is fine.
        XCTAssertNotNil(FENGuard.sanitize("4k3/4R3/8/8/8/8/8/4K3 b - - 0 1"))
    }
}
