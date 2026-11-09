import UIKit
import CoreML
import ChessCore

/// On-device board recognition: BoardDetector finds the four board corners, the board is
/// perspective-corrected, and BoardReader classifies all 64 squares in one pass.
/// The numeric conventions mirror `ml/tempo_vision/pipeline.py` (see `ml/CONTRACT.md`).
final class BoardRecognizer: @unchecked Sendable {
    static let shared = BoardRecognizer()

    /// Longest side of the working image; larger photos are downscaled first.
    private let workingMaxSide: CGFloat = 2048
    /// Squares whose top class probability is below this are flagged for review.
    private let uncertaintyThreshold: Float = 0.80
    /// Minimum heatmap peak for a corner to count as found.
    private let cornerThreshold: Float = 0.15
    /// A square counts as last-move highlighted above this probability.
    private let highlightThreshold: Float = 0.5

    private let queue = DispatchQueue(label: "tempo.recognizer", qos: .userInitiated)
    private var detector: MLModel?
    private var reader: MLModel?

    private static let classes: [Piece?] = [nil] + "PNBRQKpnbrqk".map { Piece(fen: $0) }

    func recognize(_ image: UIImage) async throws -> RecognitionResult {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { continuation.resume(returning: try self.run(image)) } catch { continuation.resume(throwing: error) }
            }
        }
    }

    /// Loads the models ahead of time (they take a moment to compile for the Neural Engine).
    func preload() {
        queue.async { try? self.loadModels() }
    }

    // MARK: Pipeline

    private func loadModels() throws {
        if detector != nil, reader != nil { return }
        let config = MLModelConfiguration()
        config.computeUnits = .all
        guard let detectorURL = Bundle.main.url(forResource: "BoardDetector", withExtension: "mlmodelc"),
              let readerURL = Bundle.main.url(forResource: "BoardReader", withExtension: "mlmodelc") else {
            throw RecognitionError.modelUnavailable
        }
        detector = try MLModel(contentsOf: detectorURL, configuration: config)
        reader = try MLModel(contentsOf: readerURL, configuration: config)
    }

    private func run(_ input: UIImage) throws -> RecognitionResult {
        let started = Date()
        try loadModels()
        guard let detector, let reader else { throw RecognitionError.modelUnavailable }
        guard let source = RGBAImage(image: input, maxSide: workingMaxSide) else { throw RecognitionError.unreadableImage }

        // 1. Corners on the whole (letterboxed) image.
        var corners = try detectCorners(in: source, region: nil, model: detector)
        // 2. Refine on a zoomed crop around the first estimate.
        if let refined = try? detectCorners(in: source, region: Self.zoomRegion(around: corners, in: source), model: detector) {
            corners = refined
        }

        // 3. Rectify and read the squares.
        let readerSize = Self.inputSize(of: reader)
        let board = source.warped(quad: corners, size: readerSize)
        guard let boardBuffer = board.pixelBuffer() else { throw RecognitionError.unreadableImage }
        let out = try reader.prediction(from: MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: boardBuffer)]))
        guard let piecesArray = out.featureValue(for: "pieces")?.multiArrayValue,
              let highlightArray = out.featureValue(for: "highlight")?.multiArrayValue,
              let flippedArray = out.featureValue(for: "flipped")?.multiArrayValue else {
            throw RecognitionError.modelUnavailable
        }
        let probs = piecesArray.floats()          // [8][8][13]
        let highlight = highlightArray.floats()   // [8][8]
        let flippedProbability = flippedArray.floats().first ?? 0

        let interpretation = Self.interpret(probs: probs, highlight: highlight, flippedProbability: flippedProbability,
                                            uncertaintyThreshold: uncertaintyThreshold, highlightThreshold: highlightThreshold)

        return RecognitionResult(image: source.uiImage(),
                                 boardImage: board.uiImage(),
                                 corners: corners,
                                 position: interpretation.position,
                                 orientation: interpretation.orientation,
                                 uncertainSquares: interpretation.uncertain,
                                 evidence: interpretation.evidence,
                                 duration: Date().timeIntervalSince(started))
    }

    private func detectCorners(in source: RGBAImage, region: CGRect?, model: MLModel) throws -> [CGPoint] {
        let size = Self.inputSize(of: model)
        let crop = region ?? CGRect(x: 0, y: 0, width: source.width, height: source.height)
        let letterbox = Letterbox(crop: crop, target: size)
        guard let buffer = source.letterboxedPixelBuffer(letterbox) else { throw RecognitionError.unreadableImage }
        let out = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: buffer)]))
        guard let heatmaps = out.featureValue(for: "heatmaps")?.multiArrayValue else { throw RecognitionError.modelUnavailable }
        let shape = heatmaps.shape.map(\.intValue)
        let (h, w) = (shape[shape.count - 2], shape[shape.count - 1])
        let values = heatmaps.floats()
        let stride = CGFloat(size) / CGFloat(w)
        var points: [CGPoint] = []
        for c in 0..<4 {
            let (point, confidence) = HeatmapDecoder.peak(values, channel: c, width: w, height: h)
            guard confidence >= cornerThreshold else { throw RecognitionError.noBoardFound }
            points.append(letterbox.toSource(CGPoint(x: point.x * stride, y: point.y * stride)))
        }
        guard Self.isPlausibleQuad(points) else { throw RecognitionError.noBoardFound }
        return points
    }

    // MARK: Interpretation (pure, unit-testable)

    struct Interpretation {
        let position: Position
        let orientation: PieceColor
        let uncertain: Set<Square>
        let evidence: RecognitionResult.SideToMoveEvidence
    }

    static func interpret(probs: [Float], highlight: [Float], flippedProbability: Float,
                          uncertaintyThreshold: Float, highlightThreshold: Float) -> Interpretation {
        // Per-cell class ranking (row 0 = top of image).
        var labels = [Int](repeating: 0, count: 64)
        var confidence = [Float](repeating: 0, count: 64)
        for cell in 0..<64 {
            let p = probs[(cell * 13)..<(cell * 13 + 13)]
            let best = p.indices.max { p[$0] < p[$1] }!
            labels[cell] = best - cell * 13
            confidence[cell] = p[best]
        }

        // Exactly one king per side: keep the most confident, demote extras to their next-best class.
        for king in [6, 12] {
            let cells = (0..<64).filter { labels[$0] == king }
            if cells.count > 1 {
                for cell in cells.sorted(by: { probs[$0 * 13 + king] > probs[$1 * 13 + king] }).dropFirst() {
                    labels[cell] = secondBest(probs, cell: cell, excluding: [king])
                    confidence[cell] = 0
                }
            } else if cells.isEmpty {
                let cell = (0..<64).max { probs[$0 * 13 + king] < probs[$1 * 13 + king] }!
                if probs[cell * 13 + king] > 0.05 {
                    labels[cell] = king
                    confidence[cell] = 0
                }
            }
        }

        let flipped = flippedProbability == 0.5 ? Self.layoutSuggestsFlipped(labels) : flippedProbability > 0.5
        func square(_ cell: Int) -> Square {
            let row = cell / 8, col = cell % 8
            return flipped ? Square(file: 7 - col, rank: row) : Square(file: col, rank: 7 - row)
        }

        var position = Position()
        var uncertain = Set<Square>()
        for cell in 0..<64 {
            var piece = classes[labels[cell]]
            let sq = square(cell)
            // Pawns can't stand on the back ranks; fall back to the best non-pawn class.
            if piece?.kind == .pawn, sq.rank == 0 || sq.rank == 7 {
                piece = classes[secondBest(probs, cell: cell, excluding: [1, 7])]
                confidence[cell] = 0
            }
            position[sq] = piece
            if confidence[cell] < uncertaintyThreshold { uncertain.insert(sq) }
        }
        position.castling = position.possibleCastling

        // Side to move: the piece standing on a highlighted square just moved.
        var evidence = RecognitionResult.SideToMoveEvidence.unknown
        let lit = (0..<64).filter { highlight[$0] > highlightThreshold }.sorted { highlight[$0] > highlight[$1] }.prefix(2)
        if lit.count == 2 {
            let a = square(lit[lit.startIndex]), b = square(lit[lit.startIndex + 1])
            var from: Square?, to: Square?
            switch (position[a], position[b]) {
            case (nil, .some): (from, to) = (a, b)
            case (.some, nil): (from, to) = (b, a)
            default: break
            }
            if let from, let to, let mover = position[to] {
                position.sideToMove = mover.color.opposite
                evidence = .lastMove(Move(from: from, to: to))
            }
        }
        if case .unknown = evidence {
            let whiteInCheck = position.isInCheck(.white), blackInCheck = position.isInCheck(.black)
            if whiteInCheck != blackInCheck {
                position.sideToMove = whiteInCheck ? .white : .black
                evidence = .check(position.sideToMove)
            }
        }
        if case .lastMove = evidence, position.isInCheck(position.sideToMove.opposite) {
            // Contradiction (the side that just moved can't be in check) — trust the board instead.
            position.sideToMove = position.sideToMove.opposite
            evidence = .check(position.sideToMove)
        }
        return Interpretation(position: position, orientation: flipped ? .black : .white, uncertain: uncertain, evidence: evidence)
    }

    private static func secondBest(_ probs: [Float], cell: Int, excluding: Set<Int>) -> Int {
        (0..<13).filter { !excluding.contains($0) }.max { probs[cell * 13 + $0] < probs[cell * 13 + $1] }!
    }

    /// Fallback orientation heuristic: White's pieces usually sit nearer the bottom when White is at the bottom.
    static func layoutSuggestsFlipped(_ labels: [Int]) -> Bool {
        var score = 0.0
        for cell in 0..<64 where labels[cell] != 0 {
            let rowFromBottom = Double(7 - cell / 8) - 3.5
            score += labels[cell] <= 6 ? -rowFromBottom : rowFromBottom
        }
        return score < 0
    }

    // MARK: Geometry helpers

    static func inputSize(of model: MLModel) -> Int {
        model.modelDescription.inputDescriptionsByName["image"]?.imageConstraint?.pixelsWide ?? 384
    }

    /// Square crop around the quad, expanded by 15% of its size, used for the refinement pass.
    static func zoomRegion(around quad: [CGPoint], in image: RGBAImage) -> CGRect {
        let xs = quad.map(\.x), ys = quad.map(\.y)
        let minX = xs.min()!, maxX = xs.max()!, minY = ys.min()!, maxY = ys.max()!
        let side = max(maxX - minX, maxY - minY) * 1.15
        return CGRect(x: (minX + maxX - side) / 2, y: (minY + maxY - side) / 2, width: side, height: side)
    }

    static func isPlausibleQuad(_ q: [CGPoint]) -> Bool {
        guard q.count == 4 else { return false }
        // Convex, consistently wound, and not degenerate.
        var sign = 0.0
        for i in 0..<4 {
            let a = q[i], b = q[(i + 1) % 4], c = q[(i + 2) % 4]
            let cross = Double((b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x))
            if abs(cross) < 1 { return false }
            if sign == 0 { sign = cross.sign == .minus ? -1 : 1 } else if (cross < 0) != (sign < 0) { return false }
        }
        let side = hypot(q[1].x - q[0].x, q[1].y - q[0].y)
        return side > 24
    }
}

/// Peak finding with sub-cell refinement (parabola through log-values, as in `decode.py`).
enum HeatmapDecoder {
    static func peak(_ values: [Float], channel: Int, width w: Int, height h: Int) -> (CGPoint, Float) {
        let base = channel * w * h
        var best = 0
        var bestValue = -Float.infinity
        for i in 0..<(w * h) where values[base + i] > bestValue {
            bestValue = values[base + i]
            best = i
        }
        let i = best / w, j = best % w
        func v(_ y: Int, _ x: Int) -> Float { values[base + y * w + x] }
        let dx = (0 < j && j < w - 1) ? offset(v(i, j - 1), v(i, j), v(i, j + 1)) : 0
        let dy = (0 < i && i < h - 1) ? offset(v(i - 1, j), v(i, j), v(i + 1, j)) : 0
        return (CGPoint(x: Double(j) + dx + 0.5, y: Double(i) + dy + 0.5), bestValue)
    }

    private static func offset(_ a: Float, _ b: Float, _ c: Float) -> Double {
        let eps: Double = 1e-6
        let la = log(max(Double(a), eps)), lb = log(max(Double(b), eps)), lc = log(max(Double(c), eps))
        let denom = la - 2 * lb + lc
        if denom >= -1e-9 { return 0 }
        return max(-0.5, min(0.5, 0.5 * (la - lc) / denom))
    }
}

/// Maps between a crop of the source image and the model's square letterboxed input.
struct Letterbox {
    let crop: CGRect
    let target: Int
    let scale: CGFloat
    let padX: CGFloat
    let padY: CGFloat

    init(crop: CGRect, target: Int) {
        self.crop = crop
        self.target = target
        scale = CGFloat(target) / max(crop.width, crop.height)
        padX = (CGFloat(target) - crop.width * scale) / 2
        padY = (CGFloat(target) - crop.height * scale) / 2
    }

    func toSource(_ p: CGPoint) -> CGPoint {
        CGPoint(x: crop.minX + (p.x - padX) / scale, y: crop.minY + (p.y - padY) / scale)
    }
}

extension MLMultiArray {
    /// Contiguous Float copy in logical (row-major) order, honouring strides and data type.
    func floats() -> [Float] {
        let shape = self.shape.map(\.intValue)
        let strides = self.strides.map(\.intValue)
        let count = shape.reduce(1, *)
        var result = [Float](repeating: 0, count: count)
        func read(_ offset: Int) -> Float {
            switch dataType {
            case .float16:
                return Float(dataPointer.assumingMemoryBound(to: Float16.self)[offset])
            case .double:
                return Float(dataPointer.assumingMemoryBound(to: Double.self)[offset])
            case .int32:
                return Float(dataPointer.assumingMemoryBound(to: Int32.self)[offset])
            default:
                return dataPointer.assumingMemoryBound(to: Float.self)[offset]
            }
        }
        var index = [Int](repeating: 0, count: shape.count)
        for i in 0..<count {
            var offset = 0
            for d in 0..<shape.count { offset += index[d] * strides[d] }
            result[i] = read(offset)
            var d = shape.count - 1
            while d >= 0 {
                index[d] += 1
                if index[d] < shape[d] { break }
                index[d] = 0
                d -= 1
            }
        }
        return result
    }
}
