import Foundation
import Observation

/// User preferences, persisted to UserDefaults.
@Observable
final class AppSettings {
    private let defaults: UserDefaults

    var boardThemeID: String { didSet { defaults.set(boardThemeID, forKey: Keys.boardTheme) } }
    var pieceSetID: String { didSet { defaults.set(pieceSetID, forKey: Keys.pieceSet) } }
    /// Number of engine lines shown (MultiPV).
    var engineLines: Int { didSet { defaults.set(engineLines, forKey: Keys.lines) } }
    /// Depth at which analysis pauses automatically to save battery.
    var maxDepth: Int { didSet { defaults.set(maxDepth, forKey: Keys.depth) } }
    var showBestMoveArrow: Bool { didSet { defaults.set(showBestMoveArrow, forKey: Keys.arrow) } }
    var haptics: Bool { didSet { defaults.set(haptics, forKey: Keys.haptics) } }

    var boardTheme: BoardTheme { BoardTheme.named(boardThemeID) }
    var pieceSet: PieceSet { PieceSet(rawValue: pieceSetID) ?? .cburnett }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        boardThemeID = defaults.string(forKey: Keys.boardTheme) ?? BoardTheme.walnut.id
        pieceSetID = defaults.string(forKey: Keys.pieceSet) ?? PieceSet.cburnett.rawValue
        engineLines = (defaults.object(forKey: Keys.lines) as? Int) ?? 3
        maxDepth = (defaults.object(forKey: Keys.depth) as? Int) ?? 30
        showBestMoveArrow = (defaults.object(forKey: Keys.arrow) as? Bool) ?? true
        haptics = (defaults.object(forKey: Keys.haptics) as? Bool) ?? true
    }

    private enum Keys {
        static let boardTheme = "boardTheme"
        static let pieceSet = "pieceSet"
        static let lines = "engineLines"
        static let depth = "maxDepth"
        static let arrow = "showBestMoveArrow"
        static let haptics = "haptics"
    }
}
