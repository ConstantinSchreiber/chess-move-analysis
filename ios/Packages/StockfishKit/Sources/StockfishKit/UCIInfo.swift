import Foundation

/// One parsed `info …` line, still in the side-to-move point of view.
struct UCIInfo: Equatable {
    var depth: Int?
    var selDepth: Int?
    var multipv: Int?
    var score: EngineScore?
    var wdl: WDL?
    var nodes: Int?
    var nps: Int?
    var timeMs: Int?
    var pv: [String]?
    /// Text after `info string`, if this is a string message.
    var string: String?

    init?(line: String) {
        let tokens = line.split(separator: " ", omittingEmptySubsequences: true)
        guard tokens.first == "info" else { return nil }

        var index = 1
        func int(at offset: Int) -> Int? {
            let position = index + offset
            return position < tokens.count ? Int(tokens[position]) : nil
        }

        while index < tokens.count {
            switch tokens[index] {
            case "depth": depth = int(at: 1); index += 2
            case "seldepth": selDepth = int(at: 1); index += 2
            case "multipv": multipv = int(at: 1); index += 2
            case "nodes": nodes = int(at: 1); index += 2
            case "nps": nps = int(at: 1); index += 2
            case "time": timeMs = int(at: 1); index += 2
            case "score":
                guard index + 2 < tokens.count, let amount = Int(tokens[index + 2]) else { return nil }
                let value: EngineScore.Value
                switch tokens[index + 1] {
                case "cp": value = .centipawns(amount)
                case "mate": value = .mate(amount)
                default: return nil
                }
                index += 3
                var bound = EngineScore.Bound.exact
                if index < tokens.count {
                    if tokens[index] == "lowerbound" { bound = .lower; index += 1 }
                    else if tokens[index] == "upperbound" { bound = .upper; index += 1 }
                }
                score = EngineScore(value: value, bound: bound)
            case "wdl":
                if let win = int(at: 1), let draw = int(at: 2), let loss = int(at: 3) {
                    wdl = WDL(win: win, draw: draw, loss: loss)
                }
                index += 4
            case "pv":
                pv = tokens[(index + 1)...].map(String.init)
                index = tokens.count
            case "string":
                string = tokens[(index + 1)...].joined(separator: " ")
                index = tokens.count
            case "currmove", "hashfull", "tbhits", "cpuload", "currmovenumber", "refutation", "currline":
                index += 2
            default:
                index += 1
            }
        }
    }

    /// This line, converted to White's point of view.
    func line(whiteToMove: Bool) -> EngineLine? {
        guard let score else { return nil }
        // `info depth 0 score mate 0` / `score cp 0` is how Stockfish reports mate/stalemate at the root.
        guard pv != nil || depth == 0 else { return nil }
        return EngineLine(
            multipv: multipv ?? 1,
            depth: depth ?? 0,
            selDepth: selDepth ?? depth ?? 0,
            score: whiteToMove ? score : score.flipped,
            wdl: wdl.map { whiteToMove ? $0 : WDL(win: $0.loss, draw: $0.draw, loss: $0.win) },
            pv: pv ?? []
        )
    }
}

extension EngineScore {
    /// The same evaluation from the other side's point of view (bounds swap with the sign).
    var flipped: EngineScore {
        let value: Value
        switch self.value {
        case .centipawns(let cp): value = .centipawns(-cp)
        case .mate(let moves): value = .mate(-moves)
        }
        let bound: Bound
        switch self.bound {
        case .exact: bound = .exact
        case .lower: bound = .upper
        case .upper: bound = .lower
        }
        return EngineScore(value: value, bound: bound)
    }
}
