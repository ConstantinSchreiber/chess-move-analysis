import XCTest
import ChessCore
@testable import Tempo

final class InterpretationTests: XCTestCase {
    /// Builds reader outputs for a board given as FEN placement, seen from `flipped` side.
    private func outputs(placement fen: String, flipped: Bool, highlighted: [String] = [], confidence: Float = 0.97)
        -> (probs: [Float], highlight: [Float]) {
        let position = try! Position(fen: fen)
        var probs = [Float](repeating: (1 - confidence) / 12, count: 64 * 13)
        var highlight = [Float](repeating: 0.02, count: 64)
        for cell in 0..<64 {
            let row = cell / 8, col = cell % 8
            let sq = flipped ? Square(file: 7 - col, rank: row) : Square(file: col, rank: 7 - row)
            let k = position[sq].map { BoardRecognizer.classes.firstIndex(of: $0)! } ?? 0
            probs[cell * 13 + k] = confidence
            if highlighted.contains(sq.name) { highlight[cell] = 0.9 }
        }
        return (probs, highlight)
    }

    func testUserPhotoPositionWithHighlight() {
        // The reference photo: Black's bishop just went g4→f3, so White is to move.
        let fen = "rn1qkb1r/ppp1pppp/5n2/3p2B1/3P4/1P3b2/P1P1PPPP/RN1QKB1R"
        let (probs, highlight) = outputs(placement: fen, flipped: false, highlighted: ["g4", "f3"])
        let result = BoardRecognizer.interpret(probs: probs, highlight: highlight, flippedProbability: 0.03)
        XCTAssertEqual(result.position.fen, fen + " w KQkq - 0 1")
        XCTAssertEqual(result.orientation, .white)
        XCTAssertEqual(result.evidence, .highlight(mover: .black, move: Move(uci: "g4f3")))
        XCTAssertTrue(result.uncertain.isEmpty)
    }

    func testFlippedBoardAndEnPassant() {
        let fen = "rnbqkbnr/ppp1pppp/8/8/3pP3/8/PPPP1PPP/RNBQKBNR"
        let (probs, highlight) = outputs(placement: fen, flipped: true, highlighted: ["e2", "e4"])
        let result = BoardRecognizer.interpret(probs: probs, highlight: highlight, flippedProbability: 0.95)
        XCTAssertEqual(result.orientation, .black)
        XCTAssertEqual(result.position.fen, fen + " b KQkq e3 0 1")
    }

    func testLayoutDecidesUncertainOrientation() {
        let fen = "r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R"
        let (probs, highlight) = outputs(placement: fen, flipped: true)
        let result = BoardRecognizer.interpret(probs: probs, highlight: highlight, flippedProbability: 0.5)
        XCTAssertEqual(result.orientation, .black)
        XCTAssertEqual(result.position.boardFEN, fen)
        XCTAssertEqual(result.evidence, .unknown)
    }

    func testCheckDecidesSideToMove() {
        let fen = "4k3/8/8/8/8/8/8/R3K2r"   // White king on e1 attacked by the rook on h1
        let (probs, highlight) = outputs(placement: fen, flipped: false)
        let result = BoardRecognizer.interpret(probs: probs, highlight: highlight, flippedProbability: 0.02)
        XCTAssertEqual(result.position.sideToMove, .white)
        XCTAssertEqual(result.evidence, .check(.white))
    }

    func testDuplicateKingsAndBackRankPawnsAreFixed() {
        let base = outputs(placement: "4k3/8/8/8/8/8/8/4K3", flipped: false)
        var probs = base.probs
        // Cell (7, 0) = a1: claim a second white king with lower confidence, and a pawn on a8.
        probs[56 * 13 + 0] = 0.1; probs[56 * 13 + 6] = 0.6; probs[56 * 13 + 4] = 0.3
        probs[0 * 13 + 0] = 0.3; probs[0 * 13 + 1] = 0.7
        let result = BoardRecognizer.interpret(probs: probs, highlight: base.highlight, flippedProbability: 0.02)
        XCTAssertEqual(result.position[.a1], Piece(.white, .rook))
        XCTAssertNil(result.position[.a8])
        XCTAssertTrue(result.uncertain.contains(.a1))
        XCTAssertTrue(result.uncertain.contains(.a8))
    }
}

/// End-to-end: the bundled sample images through the real Core ML models.
final class SampleRecognitionTests: XCTestCase {
    struct Samples: Decodable {
        struct Sample: Decodable { let file: String; let fen: String }
        let samples: [Sample]
    }

    func testBundledSamples() async throws {
        guard Bundle.main.url(forResource: "BoardDetector", withExtension: "mlmodelc") != nil else {
            throw XCTSkip("Recognition models are not bundled yet")
        }
        let url = try XCTUnwrap(Bundle.main.url(forResource: "samples", withExtension: "json"))
        let samples = try JSONDecoder().decode(Samples.self, from: Data(contentsOf: url)).samples
        for sample in samples {
            let image = try XCTUnwrap(UIImage(contentsOfFile: Bundle.main.path(forResource: sample.file, ofType: nil)!))
            let result = try await BoardRecognizer.shared.recognize(image)
            let expected = try Position(fen: sample.fen)
            XCTAssertEqual(result.position.boardFEN, expected.boardFEN, sample.file)
            XCTAssertEqual(result.position.sideToMove, expected.sideToMove, sample.file)
            print("[\(sample.file)] \(result.position.fen) in \(Int(result.duration * 1000)) ms, uncertain: \(result.uncertainSquares.map(\.name).sorted())")
        }
    }
}

/// Swift-vs-Python parity: every labelled real image in `ml/testdata` (lichess screenshots, plus the
/// gitignored chess.com captures and the reference iPhone photo when present on this machine).
final class RealImageRecognitionTests: XCTestCase {
    struct Label: Decodable {
        let file: String
        let fen: String
        let flipped: Bool
        let side_to_move: String?
    }

    func testRealImages() async throws {
        guard Bundle.main.url(forResource: "BoardDetector", withExtension: "mlmodelc") != nil else {
            throw XCTSkip("Recognition models are not bundled yet")
        }
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var total = 0, correct = 0
        var failures: [String] = []
        for folder in ["real", "private"] {
            let dir = repo.appendingPathComponent("ml/testdata/\(folder)")
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("labels.json")) else { continue }
            for label in try JSONDecoder().decode([Label].self, from: data) {
                guard let image = UIImage(contentsOfFile: dir.appendingPathComponent(label.file).path) else { continue }
                total += 1
                let expected = try Position(fen: label.fen)
                do {
                    let result = try await BoardRecognizer.shared.recognize(image)
                    var problems: [String] = []
                    if result.position.boardFEN != expected.boardFEN { problems.append("board \(result.position.boardFEN)") }
                    if (result.orientation == .black) != label.flipped { problems.append("orientation") }
                    if let side = label.side_to_move, (result.position.sideToMove == .white ? "w" : "b") != side {
                        problems.append("side to move \(result.position.sideToMove)")
                    }
                    if problems.isEmpty { correct += 1 } else { failures.append("\(label.file): \(problems.joined(separator: ", "))") }
                } catch {
                    failures.append("\(label.file): \(error.localizedDescription)")
                }
            }
        }
        print("[real images] \(correct)/\(total) fully correct")
        failures.forEach { print("[real images] FAIL \($0)") }
        XCTAssertGreaterThan(total, 0)
        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }
}
