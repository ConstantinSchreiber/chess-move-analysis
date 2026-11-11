# Best Move — scan a chess position, get the best move

Point your iPhone at a chess board on any screen, or import a screenshot. Best Move reads the position
and works out whose move it is. Stockfish 19 then analyses it **on-device**. Move pieces to explore
variations; the engine follows along.

- **Scan** — live camera with board outline, Photos, clipboard, or bundled samples
- **Review** — recognised board with uncertain squares outlined, side to move inferred from the
  last-move highlight (or a check), castling rights, a full piece editor, and a photo comparison
- **Analyse** — Stockfish 19 (multi-threaded, NNUE), best-move arrow, eval bar, top lines,
  plain-language move descriptions, a branching move tree, flip board, copy FEN / open on lichess
- Everything runs offline; nothing leaves the device

## Repository layout

```
ios/
  project.yml              XcodeGen spec (the .xcodeproj is generated from it and committed)
  BestMove/                SwiftUI app
    App/                   entry point, AppModel (navigation, history, engine warm-up)
    Design/                colours, typography, buttons, cards
    Board/                 BoardView (Canvas squares + animated pieces), themes, piece sets
    Home/                  home screen, SceneKit hero (rendered off-main, cached)
    Scan/                  scan sheet, live camera, review + position editor
    Recognition/           Core ML pipeline (port of ml/tempo_vision/pipeline.py)
    Analysis/              AnalysisModel (move tree + engine), analysis screen
    Settings/, Storage/    preferences, recent positions
    Resources/             assets, Core ML models, NNUE (downloaded), samples
  BestMoveTests/           recognition unit + end-to-end tests
  BestMoveUITests/         board interaction UI test
  Packages/ChessCore/      move generation (perft-verified), FEN, SAN, validation, move tree
  Packages/StockfishKit/   Stockfish 19 in-process with an async Swift API
  scripts/                 fetch-nnue.sh (pre-build), setup-signing, release, screenshots, icon
ml/                        synthetic data, training, Core ML export, evaluation (see ml/README.md)
docs/                      publishing guide; support site + privacy policy (GitHub Pages)
```

## Build & run

Requirements: Xcode 27 (the App Store needs the iOS 26 SDK or later), iOS 17+ device or simulator.

```sh
brew install xcodegen               # only needed if you change project.yml
ios/scripts/setup-signing.sh        # once, after signing in to Xcode: sets your Team ID
open ios/BestMove.xcodeproj         # pick your iPhone, press Run
```

The first build downloads the Stockfish network (~94 MB) via `scripts/fetch-nnue.sh`.
Publishing (App Store record, upload, listing text, screenshots) is covered step by step in
[`docs/APP_STORE.md`](docs/APP_STORE.md). `ios/scripts/release.sh` archives and uploads a build.

Tests:

```sh
cd ios/Packages/ChessCore && swift test             # rules, perft, SAN, move tree
cd ios/Packages/StockfishKit && swift test          # engine bridge
xcodebuild test -project ios/BestMove.xcodeproj -scheme BestMove \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro'   # recognition + UI
```

Debug launch arguments (handy for screenshots): `-demoScan sample-photo`, `-demoReview`,
`-demoAnalysis "<FEN>"`, `-demoSetup`, `-demoSettings`. URL scheme: `bestmove://analyze?fen=<FEN>`.

## How recognition works

1. **BoardDetector** (Core ML, 384² input) predicts heat maps for the four board corners; a second
   pass on a zoomed crop refines them.
2. The board is perspective-corrected to 384×384.
3. **BoardReader** classifies all 64 squares at once (13 classes) and also predicts last-move
   highlights and whether the board is shown from Black's side.
4. Post-processing enforces one king per side and no pawns on the back ranks. It works out side to
   move from the highlight (the piece on the highlighted square just moved) or from a check.

Both networks are trained only on synthetic images rendered from openly licensed piece sets and
real game positions (lichess open database, CC0). See `ml/`.

## License

GPL-3.0 (Stockfish is GPL-3.0). Piece sets: cburnett & merida (GPLv2+), chessnut (Apache 2.0).
