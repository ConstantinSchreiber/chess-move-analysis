import UIKit
import CoreML
import ChessCore

/// On-device board recognition: BoardDetector finds the four board corners, the board is
/// perspective-corrected, and BoardReader classifies all 64 squares in one pass.
/// A 1:1 port of `ml/tempo_vision/pipeline.py`; constants and conventions are in `ml/CONTRACT.md`.
final class BoardRecognizer: @unchecked Sendable {
    static let shared = BoardRecognizer()

    // Constants from pipeline.py.
    static let detectorStride: CGFloat = 4
    static let detectMinConfidence: Float = 0.25
    static let zoomExpand: CGFloat = 1.25
    static let zoomMinConfidenceRatio: Float = 0.6
    static let predownscaleFactor: CGFloat = 2.0
    static let uncertainProbability: Float = 0.85
    static let highlightProbability: Float = 0.5
    static let flipConfident: Float = 0.25
    static let layoutWeight: Float = 1.2
    static let kingMinProbability: Float = 0.2

    /// Longest side of the working image; larger photos are downscaled first.
    private let workingMaxSide: CGFloat = 2048
    private let queue = DispatchQueue(label: "tempo.recognizer", qos: .userInitiated)
    private var detector: MLModel?
    private var reader: MLModel?

    /// Class index → piece (index 0 = empty).
    static let classes: [Piece?] = [nil] + "PNBRQKpnbrqk".map { Piece(fen: $0) }

    func recognize(_ image: UIImage) async throws -> RecognitionResult {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { continuation.resume(returning: try self.run(image)) } catch { continuation.resume(throwing: error) }
            }
        }
    }

    /// Loads the models ahead of time (the first load compiles them for the Neural Engine).
    func preload() {
        queue.async { try? self.loadModels() }
    }

    /// First-pass corner detection for the live camera preview (no zoom pass, no reading).
    /// Returns corners in `frame` pixels, or nil when no board is visible.
    func detectCornersForPreview(in frame: RGBAImage) -> [CGPoint]? {
        queue.sync {
            guard (try? loadModels()) != nil, let detector else { return nil }
            let full = CGRect(x: 0, y: 0, width: frame.width, height: frame.height)
            guard let (corners, confidence) = try? detect(in: frame, crop: full, model: detector),
                  confidence >= Self.detectMinConfidence, Self.quadIsValid(corners) else { return nil }
            return corners
        }
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
        let fullFrame = CGRect(x: 0, y: 0, width: source.width, height: source.height)

        // 1–3. Corners on the whole letterboxed image.
        var (corners, confidence) = try detect(in: source, crop: fullFrame, model: detector)
        guard confidence >= Self.detectMinConfidence, Self.quadIsValid(corners) else { throw RecognitionError.noBoardFound }

        // 4. Zoom pass on a square crop around the first estimate.
        let zoom = Self.zoomCrop(around: corners)
        if let (refined, refinedConfidence) = try? detect(in: source, crop: zoom, model: detector),
           refinedConfidence >= Self.zoomMinConfidenceRatio * confidence, Self.quadIsValid(refined) {
            corners = refined
            confidence = max(confidence, refinedConfidence)
        }

        // 5. Rectify (downscaling first when the board is much larger than the reader input).
        let readerSize = Self.inputSize(of: reader)
        let meanSide = (0..<4).map { distance(corners[$0], corners[($0 + 1) % 4]) }.reduce(0, +) / 4
        var warpSource = source
        var warpCorners = corners
        if meanSide > Self.predownscaleFactor * CGFloat(readerSize) {
            let f = 1.5 * CGFloat(readerSize) / meanSide
            if let smaller = source.scaled(by: f) {
                warpSource = smaller
                warpCorners = corners.map { CGPoint(x: $0.x * f, y: $0.y * f) }
            }
        }
        let board = warpSource.warped(quad: warpCorners, size: readerSize)

        // 6. Read the squares.
        guard let boardBuffer = board.pixelBuffer() else { throw RecognitionError.unreadableImage }
        let out = try reader.prediction(from: MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: boardBuffer)]))
        guard let piecesArray = out.featureValue(for: "pieces")?.multiArrayValue,
              let highlightArray = out.featureValue(for: "highlight")?.multiArrayValue,
              let flippedArray = out.featureValue(for: "flipped")?.multiArrayValue else {
            throw RecognitionError.modelUnavailable
        }
        let interpretation = Self.interpret(probs: piecesArray.floats(), highlight: highlightArray.floats(),
                                            flippedProbability: flippedArray.floats().first ?? 0.5)

        return RecognitionResult(image: source.uiImage(),
                                 boardImage: board.uiImage(),
                                 corners: corners,
                                 position: interpretation.position,
                                 orientation: interpretation.orientation,
                                 uncertainSquares: interpretation.uncertain,
                                 evidence: interpretation.evidence,
                                 duration: Date().timeIntervalSince(started))
    }

    /// Steps 1–2: letterbox `crop` of the image, run the detector, decode the four peaks.
    /// Returns corners in source-image pixels and the minimum peak confidence.
    private func detect(in source: RGBAImage, crop: CGRect, model: MLModel) throws -> ([CGPoint], Float) {
        let letterbox = Letterbox(crop: crop, target: Self.inputSize(of: model))
        guard let buffer = source.letterboxedPixelBuffer(letterbox) else { throw RecognitionError.unreadableImage }
        let out = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: buffer)]))
        guard let heatmaps = out.featureValue(for: "heatmaps")?.multiArrayValue else { throw RecognitionError.modelUnavailable }
        let shape = heatmaps.shape.map(\.intValue)
        let (h, w) = (shape[shape.count - 2], shape[shape.count - 1])
        let values = heatmaps.floats()
        var points: [CGPoint] = []
        var confidence = Float.infinity
        for c in 0..<4 {
            let (cell, peak) = HeatmapDecoder.peak(values, channel: c, width: w, height: h)
            confidence = min(confidence, peak)
            points.append(letterbox.toSource(CGPoint(x: cell.x * Self.detectorStride, y: cell.y * Self.detectorStride)))
        }
        return (points, confidence)
    }

    // MARK: Interpretation (steps 7–14; pure, unit-testable)

    struct Interpretation {
        let position: Position
        let orientation: PieceColor
        let uncertain: Set<Square>
        let evidence: RecognitionResult.SideToMoveEvidence
    }

    /// - Parameters:
    ///   - probs: `[8][8][13]` class probabilities, row 0 = top of the rectified image.
    ///   - highlight: `[8][8]` last-move highlight probabilities.
    static func interpret(probs: [Float], highlight: [Float], flippedProbability: Float) -> Interpretation {
        func p(_ cell: Int, _ k: Int) -> Float { probs[cell * 13 + k] }
        func best(_ cell: Int, excluding: Set<Int> = []) -> Int {
            (0..<13).filter { !excluding.contains($0) }.max { p(cell, $0) < p(cell, $1) }!
        }

        var labels = (0..<64).map { best($0) }
        let confidence = (0..<64).map { p($0, labels[$0]) }
        var adjusted = Set<Int>()

        // 7. At most one king per colour; promote a missing king if the model saw one somewhere.
        for king in [6, 12] {
            let cells = (0..<64).filter { labels[$0] == king }
            if cells.count > 1 {
                let keep = cells.max { p($0, king) < p($1, king) }!
                for cell in cells where cell != keep {
                    labels[cell] = best(cell, excluding: [king])
                    adjusted.insert(cell)
                }
            } else if cells.isEmpty {
                let cell = (0..<64).max { p($0, king) < p($1, king) }!
                if p(cell, king) > kingMinProbability, labels[cell] != 6, labels[cell] != 12 {
                    labels[cell] = king
                    adjusted.insert(cell)
                }
            }
        }

        // 8. Rows 0 and 7 are always rank 1/8 whatever the orientation: no pawns there.
        for cell in Array(0..<8) + Array(56..<64) where labels[cell] == 1 || labels[cell] == 7 {
            labels[cell] = best(cell, excluding: [1, 7])
            adjusted.insert(cell)
        }

        // 9. Orientation: trust a confident model, otherwise blend with the piece layout.
        let flipped: Bool
        if abs(flippedProbability - 0.5) > flipConfident {
            flipped = flippedProbability > 0.5
        } else {
            let q = min(max(flippedProbability, 1e-4), 1 - 1e-4)
            flipped = log(q / (1 - q)) - layoutWeight * layoutScore(labels) > 0
        }

        // 10–11. Cells → squares; flag uncertain ones (and ones changed by the fixes above).
        func square(_ cell: Int) -> Square {
            let row = cell / 8, col = cell % 8
            return flipped ? Square(file: 7 - col, rank: row) : Square(file: col, rank: 7 - row)
        }
        var position = Position()
        var uncertain = Set<Square>()
        var lit: [(square: Square, probability: Float)] = []
        for cell in 0..<64 {
            let sq = square(cell)
            position[sq] = classes[labels[cell]]
            if confidence[cell] < uncertainProbability || adjusted.contains(cell) { uncertain.insert(sq) }
            if highlight[cell] > highlightProbability { lit.append((sq, highlight[cell])) }
        }
        lit.sort { $0.probability > $1.probability }

        // 12. Side to move.
        let (side, evidence) = sideToMove(position, highlighted: Array(lit.prefix(2).map(\.square)))
        position.sideToMove = side

        // 13. Castling rights from home squares; en passant after a detected double pawn step.
        position.castling = position.possibleCastling
        if case .highlight(_, let move?) = evidence, position[move.to] == Piece(side.opposite, .pawn),
           move.from.file == move.to.file, abs(move.from.rank - move.to.rank) == 2 {
            position.enPassant = Square(file: move.to.file, rank: (move.from.rank + move.to.rank) / 2)
        }
        return Interpretation(position: position, orientation: flipped ? .black : .white, uncertain: uncertain, evidence: evidence)
    }

    /// > 0 when the layout looks like White at the bottom (unflipped).
    static func layoutScore(_ labels: [Int]) -> Float {
        let whiteRows = (0..<64).filter { (1...6).contains(labels[$0]) }.map { Float($0 / 8) }
        let blackRows = (0..<64).filter { labels[$0] >= 7 }.map { Float($0 / 8) }
        guard !whiteRows.isEmpty, !blackRows.isEmpty else { return 0 }
        return (whiteRows.reduce(0, +) / Float(whiteRows.count) - blackRows.reduce(0, +) / Float(blackRows.count)) / 2
    }

    static func sideToMove(_ position: Position, highlighted: [Square]) -> (PieceColor, RecognitionResult.SideToMoveEvidence) {
        let occupied = highlighted.filter { position[$0] != nil }
        let empty = highlighted.filter { position[$0] == nil }
        var mover: PieceColor?
        var move: Move?
        if highlighted.count == 2, occupied.count == 1 {
            mover = position[occupied[0]]!.color
            move = Move(from: empty[0], to: occupied[0])
        } else if occupied.count == 2, position[occupied[0]]!.color == position[occupied[1]]!.color {
            mover = position[occupied[0]]!.color
        } else if highlighted.count == 1, occupied.count == 1 {
            mover = position[occupied[0]]!.color
        }
        let whiteInCheck = position.isInCheck(.white), blackInCheck = position.isInCheck(.black)
        if let mover {
            let side = mover.opposite
            // The side that just moved can't still be in check.
            if (side == .black && whiteInCheck && !blackInCheck) || (side == .white && blackInCheck && !whiteInCheck) {
                return (mover, .check(mover))
            }
            return (side, .highlight(mover: mover, move: move))
        }
        if whiteInCheck && !blackInCheck { return (.white, .check(.white)) }
        if blackInCheck && !whiteInCheck { return (.black, .check(.black)) }
        return (.white, .unknown)
    }

    // MARK: Geometry helpers

    static func inputSize(of model: MLModel) -> Int {
        model.modelDescription.inputDescriptionsByName["image"]?.imageConstraint?.pixelsWide ?? 384
    }

    /// Square crop centred on the quad, `zoomExpand` × its bounding box (may extend past the image).
    static func zoomCrop(around quad: [CGPoint]) -> CGRect {
        let xs = quad.map(\.x), ys = quad.map(\.y)
        let cx = xs.reduce(0, +) / 4, cy = ys.reduce(0, +) / 4
        let side = zoomExpand * max(xs.max()! - xs.min()!, ys.max()! - ys.min()!)
        let x0 = (cx - side / 2).rounded(), y0 = (cy - side / 2).rounded()
        let sd = max(8, side.rounded())
        return CGRect(x: x0, y: y0, width: sd, height: sd)
    }

    /// Convex, clockwise in y-down image coordinates, not degenerate.
    static func quadIsValid(_ q: [CGPoint]) -> Bool {
        guard q.count == 4 else { return false }
        for i in 0..<4 {
            let a = q[i], b = q[(i + 1) % 4], d = q[(i + 2) % 4]
            if (b.x - a.x) * (d.y - b.y) - (b.y - a.y) * (d.x - b.x) <= 0 { return false }
        }
        let sides = (0..<4).map { distance(q[$0], q[($0 + 1) % 4]) }
        return sides.min()! > 16 && sides.max()! / sides.min()! < 4
    }
}

private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

/// Peak finding with sub-cell refinement (parabola through log-values, as in `decode.py`).
enum HeatmapDecoder {
    /// Returns the peak in heatmap-cell units (cell centres at +0.5) and its value.
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
        let eps = 1e-6
        let la = log(max(Double(a), eps)), lb = log(max(Double(b), eps)), lc = log(max(Double(c), eps))
        let denom = la - 2 * lb + lc
        if denom >= -1e-9 { return 0 }
        return max(-0.5, min(0.5, 0.5 * (la - lc) / denom))
    }
}

/// Maps between a crop of the source image and the model's square letterboxed input (pipeline.py `letterbox`).
struct Letterbox {
    let crop: CGRect
    let target: Int
    /// Size of the resized crop inside the target, and its integer offset.
    let nw: Int, nh: Int, ox: Int, oy: Int

    init(crop: CGRect, target: Int) {
        self.crop = crop
        self.target = target
        let scale = CGFloat(target) / max(crop.width, crop.height)
        nw = max(1, Int((crop.width * scale).rounded()))
        nh = max(1, Int((crop.height * scale).rounded()))
        ox = (target - nw) / 2
        oy = (target - nh) / 2
    }

    var sx: CGFloat { CGFloat(nw) / crop.width }
    var sy: CGFloat { CGFloat(nh) / crop.height }

    func toSource(_ p: CGPoint) -> CGPoint {
        CGPoint(x: crop.minX + (p.x - CGFloat(ox)) / sx, y: crop.minY + (p.y - CGFloat(oy)) / sy)
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
