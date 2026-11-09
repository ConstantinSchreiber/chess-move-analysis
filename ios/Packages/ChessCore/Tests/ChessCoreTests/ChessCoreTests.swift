import XCTest
@testable import ChessCore

final class PerftTests: XCTestCase {
    private func perft(_ position: Position, _ depth: Int) -> Int {
        if depth == 0 { return 1 }
        let moves = position.legalMoves()
        if depth == 1 { return moves.count }
        var total = 0
        for move in moves {
            var next = position
            next.applyUnchecked(move)
            total += perft(next, depth - 1)
        }
        return total
    }

    private func check(_ fen: String, _ expected: [Int], file: StaticString = #filePath, line: UInt = #line) throws {
        let position = try Position(fen: fen)
        for (i, count) in expected.enumerated() {
            XCTAssertEqual(perft(position, i + 1), count, "depth \(i + 1) of \(fen)", file: file, line: line)
        }
    }

    func testStartPosition() throws {
        try check(Position.startFEN, [20, 400, 8902, 197_281])
    }

    func testKiwipete() throws {
        try check("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", [48, 2039, 97_862])
    }

    func testPosition3() throws {
        try check("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", [14, 191, 2812, 43_238])
    }

    func testPosition4() throws {
        try check("r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1", [6, 264, 9467])
    }

    func testPosition5() throws {
        try check("rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", [44, 1486, 62_379])
    }
}

final class NotationTests: XCTestCase {
    func testFENRoundTrip() throws {
        let fens = [
            Position.startFEN,
            "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
            "rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq c6 0 2",
        ]
        for fen in fens { XCTAssertEqual(try Position(fen: fen).fen, fen) }
        XCTAssertEqual(try Position(fen: "8/8/8/8/8/8/8/K6k").fen, "8/8/8/8/8/8/8/K6k w - - 0 1")
        XCTAssertThrowsError(try Position(fen: "rnbqkbnr/pppppppp/9/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"))
        XCTAssertThrowsError(try Position(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP w KQkq - 0 1"))
    }

    func testSANGeneration() throws {
        let p = try Position(fen: "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1")
        let sans = Set(p.legalMoves().map { p.san(for: $0) })
        XCTAssertTrue(sans.contains("O-O"))
        XCTAssertTrue(sans.contains("O-O-O"))
        XCTAssertTrue(sans.contains("Qxf6"))
        XCTAssertTrue(sans.contains("dxe6"))
        XCTAssertTrue(sans.contains("Nxd7"))
        XCTAssertTrue(sans.contains("Rb1"))
        XCTAssertTrue(sans.contains("Bxa6"))

        let disamb = try Position(fen: "4k3/8/8/8/8/8/1N3N2/4K3 w - - 0 1")
        XCTAssertEqual(disamb.san(for: Move(uci: "b2d3")!), "Nbd3")
        let rankDisamb = try Position(fen: "4k3/8/8/R7/8/8/R7/4K3 w - - 0 1")
        XCTAssertEqual(rankDisamb.san(for: Move(uci: "a5a4")!), "R5a4")

        let promo = try Position(fen: "4k3/1P6/8/8/8/8/8/4K3 w - - 0 1")
        XCTAssertEqual(promo.san(for: Move(uci: "b7b8q")!), "b8=Q+")
        let mate = try Position(fen: "6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1")
        XCTAssertEqual(mate.san(for: Move(uci: "a1a8")!), "Ra8#")
    }

    func testSANParsingAndLines() throws {
        var p = Position.start
        for san in ["e4", "e5", "Nf3", "Nc6", "Bb5", "a6", "O-O"] {
            let move = try XCTUnwrap(p.move(san: san), san)
            XCTAssertTrue(p.play(move))
        }
        XCTAssertEqual(p.fen, "r1bqkbnr/1ppp1ppp/p1n5/1B2p3/4P3/5N2/PPPP1PPP/RNBQ1RK1 b kq - 1 4")
        XCTAssertEqual(Position.start.sanLine(["e2e4", "e7e5", "g1f3", "zzzz", "b8c6"]), ["e4", "e5", "Nf3"])
    }

    func testEnPassantAndStatus() throws {
        var p = try Position(fen: "rnbqkbnr/ppp1p1pp/8/3pPp2/8/8/PPPP1PPP/RNBQKBNR w KQkq f6 0 3")
        XCTAssertEqual(p.san(for: Move(uci: "e5f6")!), "exf6")
        XCTAssertTrue(p.play(Move(uci: "e5f6")!))
        XCTAssertNil(p[Square("f5")!])

        let mated = try Position(fen: "R5k1/5ppp/8/8/8/8/8/6K1 b - - 1 1")
        XCTAssertEqual(mated.status, .checkmate(winner: .white))
        let stale = try Position(fen: "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")
        XCTAssertEqual(stale.status, .stalemate)
        XCTAssertEqual(try Position(fen: "8/8/4k3/8/8/2B5/4K3/8 w - - 0 1").status, .insufficientMaterial)
    }
}

final class ValidationTests: XCTestCase {
    func testIssues() throws {
        XCTAssertTrue(Position.start.setupIssues().isEmpty)
        XCTAssertEqual(try Position(fen: "8/8/8/8/8/8/8/K7 w - - 0 1").setupIssues(), [.missingKing(.black)])
        XCTAssertTrue(try Position(fen: "P3k3/8/8/8/8/8/8/4K3 w - - 0 1").setupIssues().contains(.pawnsOnBackRank))
        XCTAssertEqual(try Position(fen: "4k3/8/8/8/8/8/8/4K2R b - - 0 1").setupIssues(), [])
        XCTAssertEqual(try Position(fen: "4k2R/8/8/8/8/8/8/4K3 w - - 0 1").setupIssues(), [.opponentInCheck(.black)])
        XCTAssertTrue(try Position(fen: "8/8/8/3kK3/8/8/8/8 w - - 0 1").setupIssues().contains(.kingsAdjacent))
    }

    func testSanitize() throws {
        var p = try Position(fen: "r3k3/8/8/8/8/8/8/4K2R w KQkq e3 0 1")
        p.sanitize()
        XCTAssertEqual(p.castling, [.whiteKingside, .blackQueenside])
        XCTAssertNil(p.enPassant)
    }
}

final class MoveTreeTests: XCTestCase {
    func testBranchingAndPromotion() throws {
        var tree = MoveTree(root: .start)
        let e4 = try XCTUnwrap(tree.add(Move(uci: "e2e4")!, after: MoveTree.root))
        let e5 = try XCTUnwrap(tree.add(Move(uci: "e7e5")!, after: e4))
        let c5 = try XCTUnwrap(tree.add(Move(uci: "c7c5")!, after: e4))
        XCTAssertEqual(tree.add(Move(uci: "e7e5")!, after: e4), e5, "reuses existing child")
        XCTAssertNil(tree.add(Move(uci: "e2e4")!, after: e4), "illegal move")
        XCTAssertEqual(tree[c5].san, "c5")
        XCTAssertEqual(tree.line(through: MoveTree.root), [0, e4, e5])
        tree.promote(c5)
        XCTAssertEqual(tree.line(through: MoveTree.root), [0, e4, c5])
        XCTAssertEqual(tree.moveNumberLabel(for: c5), "1…")

        let end = tree.add(uciLine: ["g1f3", "d7d6", "d2d4"], after: c5)
        XCTAssertEqual(tree[end].ply, 5)
        let parent = tree.delete(c5)
        XCTAssertEqual(tree[parent].san, "e4")
        XCTAssertEqual(tree.nodes.count, 3)
        XCTAssertEqual(tree.line(through: MoveTree.root).map { tree[$0].san }, [nil, "e4", "e5"])
    }
}
