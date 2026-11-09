# StockfishKit

Stockfish 19 (`sf_19`, GPLv3) running in-process for iOS 17+ and macOS 14+, behind a small
Swift API. No subprocess, no pipes, no file descriptors: the UCI loop runs on its own thread and
talks through in-memory `std::cin`/`std::cout` buffers (`Sources/CStockfish/bridge`).

```swift
import StockfishKit

try await StockfishEngine.shared.prepare()          // boot + verify the NNUE net (idempotent)
for await snapshot in StockfishEngine.shared.analyze(fen: fen, multiPV: 3) {
    snapshot.lines                                   // [EngineLine], scores from White's POV
    if snapshot.isFinal { print(snapshot.bestMove ?? "no legal move") }
}
```

- Starting a new `analyze` stops the previous search and finishes its stream; cancelling the
  consuming task stops the search; `stop()` ends it with a final snapshot (`isFinal`, `bestMove`).
- Snapshots arrive at most ~12×/s; each MultiPV batch lands together. Scores, bounds and WDL are
  normalized to White's point of view. `mate(0)` = the side to move is checkmated.
- Invalid FENs (wrong king count, pawns on rank 1/8, side not to move in check, impossible
  material) return an already-finished stream; sloppy castling/en-passant fields are repaired.
  The vendored engine is also patched never to `exit()` on bad input (`Sources/CStockfish/PATCHES.md`).

## The network file

`StockfishEngine.networkFileName` (currently `nn-1a298aa575a0.nnue`, ~94 MB; Stockfish 19 uses a
single net) is not in git. `ios/scripts/fetch-nnue.sh [destDir]` downloads it (default
`ios/Tempo/Resources/NNUE/`), checks the SHA-256 prefix in its name, and is a no-op when current.

In the app target:
1. Pre-build script phase: `"$SRCROOT/scripts/fetch-nnue.sh"` (adjust the path to the project
   root) with **`ENABLE_USER_SCRIPT_SANDBOXING = NO`** (it writes to the source tree and downloads).
2. Add `Resources/NNUE` as a **folder reference** so the file lands at `<App>.app/NNUE/<name>`.
   `prepare()` looks there, then at the bundle root, or use `Configuration(netDirectory:)`.

## Build notes

- arm64: `USE_NEON=8`, `USE_POPCNT`, `-mcpu=apple-a12` on iOS. Dot-product instructions are off
  (`useDotProd` in `Package.swift`) because iOS 17 still supports A12 devices, which lack them;
  flip it once the deployment target is iOS 26 (A13+).
- x86_64 (Intel-Mac simulator) compiles Stockfish's generic code, so it works there but slowly.
- The engine is compiled with `-O3` even in Debug builds.

## Tests

`swift test` (macOS) or `xcodebuild test -scheme StockfishKit -destination 'platform=iOS Simulator,name=iPhone 16'`.
They need the net (`ios/scripts/fetch-nnue.sh` first; override the location with
`STOCKFISHKIT_NET_DIR`). `testReportNPS` prints a speed line tagged `NPS-REPORT`.

## License

Stockfish is GPLv3 (`Sources/CStockfish/Copying.txt`); distributing an app that links it means
offering the app's complete corresponding source under GPLv3.
