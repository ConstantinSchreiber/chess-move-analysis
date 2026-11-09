# Local modifications to Stockfish

`src/` is Stockfish **sf_19** (commit in `STOCKFISH_VERSION`), GPLv3 (`Copying.txt`, `AUTHORS`).
Removed: `main.cpp` (replaced by `bridge/sfkit_bridge.cpp`), `Makefile`, `universal/`.

All changes are guarded by `#ifdef STOCKFISHKIT` (defined in `Package.swift`), so the upstream
behaviour is unchanged without it. Purpose: an app must never be terminated by the engine.

| File | Change |
|------|--------|
| `src/shm.h` | Don't define `USE_UNIX_SHM` → the network uses the local-memory fallback instead of cross-process shared memory (Unix sockets under `/tmp`, an `atexit` hook, a server thread), which a sandboxed app neither needs nor may use. |
| `src/engine.h` / `src/engine.cpp` | `Engine::set_position` restores the start position and records `positionValid = false` when a FEN/move list is rejected (upstream leaves a zeroed `Position`). `Engine::go` answers `info string ERROR: …` + `bestmove (none)` (after waiting for any running search, preserving output order) when the position is invalid or the NNUE file is not loaded, instead of `exit()`-ing in `verify_network()`. Adds `Engine::network_loaded()`. |
| `src/uci.cpp` | `UCIEngine::position` prints `info string ERROR: <reason>` instead of `terminate_on_critical_error` (`std::exit(1)`). |

To upgrade: copy the new `src/` (minus `main.cpp`, `Makefile`, `universal/`), re-apply the
table above (search for `STOCKFISHKIT`), update `STOCKFISH_VERSION`, run `ios/scripts/fetch-nnue.sh`
(it reads the net name from `src/evaluate.h`) and `swift test` in `ios/Packages/StockfishKit`.
