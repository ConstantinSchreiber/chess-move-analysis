import UIKit
import ChessCore

/// What the recogniser read from a photo or screenshot.
struct RecognitionResult {
    enum SideToMoveEvidence: Equatable {
        /// A last-move highlight was found: `mover` just moved (`move` is known when one square was empty).
        case highlight(mover: PieceColor, move: Move?)
        /// This side's king is in check, so it must be their move.
        case check(PieceColor)
        /// No evidence — defaulted to White.
        case unknown
    }

    /// The photo, orientation-normalised.
    let image: UIImage
    /// The board region, perspective-corrected, as it appears in the photo (top row first).
    let boardImage: UIImage
    /// Board corners in `image` pixel coordinates: top-left, top-right, bottom-right, bottom-left.
    let corners: [CGPoint]
    let position: Position
    /// The side shown at the bottom of the photo.
    let orientation: PieceColor
    let uncertainSquares: Set<Square>
    let evidence: SideToMoveEvidence
    /// Seconds spent in recognition (for diagnostics).
    let duration: TimeInterval
}

enum RecognitionError: LocalizedError {
    case unreadableImage
    case modelUnavailable
    case noBoardFound

    var errorDescription: String? {
        switch self {
        case .unreadableImage: "That image couldn't be read."
        case .modelUnavailable: "The board recogniser isn't available in this build."
        case .noBoardFound: "No chess board found. Make sure all four corners of the board are visible."
        }
    }
}
