# Tempo board recognition (ML)

Two small Core ML models turn a screenshot or a photo of a screen into a FEN, fully on device:

1. **BoardDetector** — finds the 4 board corners (heatmaps, ResNet-18 + FPN, ~10 MB fp16).
2. **BoardReader** — reads the rectified board: piece per square, last-move highlights, orientation
   (ResNet-18 trunk, ~9 MB fp16).

The Swift port follows [`CONTRACT.md`](CONTRACT.md); the Python reference is
[`tempo_vision/pipeline.py`](tempo_vision/pipeline.py).

Both models are trained only on **synthetic** data rendered by [`tempo_vision/synth.py`](tempo_vision/synth.py):
38 lichess piece sets, lichess board textures + procedural colour pairs, realistic positions from the
CC0 lichess database (70 %) mixed with random placements (30 %), coordinates, last-move highlights,
arrows, move dots, check glow, UI clutter, phone/desktop/tablet screenshots and simulated photos of
screens (perspective, bezel, moiré, glare, blur, noise, JPEG, camera review UI).

## Setup

```sh
/opt/homebrew/bin/python3.11 -m venv ml/.venv          # arm64 Python (MPS)
ml/.venv/bin/pip install -r ml/requirements.txt
cd ml
.venv/bin/python scripts/fetch_assets.py               # lichess piece sets/boards + CC0 PGN -> .cache/
```

## Reproduce

```sh
.venv/bin/python scripts/gen_dataset.py detector data/det_v1    --n 60000 --seed 1
.venv/bin/python scripts/gen_dataset.py reader   data/reader_v1 --n 40000 --seed 2
scripts/run_frozen.sh det scripts/train.py detector --data data/det_v1 --out checkpoints/detector_v1.pt --epochs 2
scripts/run_frozen.sh rdr scripts/train.py reader --data data/reader_v1 --out checkpoints/reader_v1.pt --epochs 3
.venv/bin/python scripts/export_coreml.py --detector checkpoints/detector_v1.pt --reader checkpoints/reader_v1.pt \
    --out ../ios/Tempo/Resources/Models
.venv/bin/python scripts/eval_real.py --coreml ../ios/Tempo/Resources/Models testdata/real ../ios/Tempo/Resources/Samples
.venv/bin/python scripts/make_samples.py               # in-app "Try a sample image" pictures
```

`scripts/preview_synth.py <dir>` writes contact sheets of synthetic samples.

## Evaluation (`scripts/eval_real.py`, `scripts/eval_synth_e2e.py`)

Real images (Core ML fp16 files through the full reference pipeline): 20 lichess + 20 chess.com screenshots
(desktop 1280×800 and iPhone 390×844@3x, a third of them flipped), 1 real iPhone photo of a monitor, and the 2
in-app samples → **43/43 fully correct** (placement, orientation, side to move) for v1.0, v1.1 and v2.
Worst detected-corner error on the 40 screenshots < 0.6 % of the board side.

Synthetic end-to-end, 300 fresh scenes (seed 12345, 124 of them photos of screens):

| metric | v1.0 | **v1.1 (shipped)** | v2 (not shipped) |
|---|---|---|---|
| reader argmax, boards exact (image space) | 281/300 | **292/300** | 290/300 |
| reader argmax, square accuracy | 99.64 % | **99.80 %** | 99.82 % |
| realistic (database) positions: exact placement | 205/221 | **215/221** | 215/221 |
| realistic positions: orientation | 220/221 | **221/221** | 221/221 |
| side to move when a last-move highlight is shown | 137/145 | **144/145** | 143/145 |
| all scenes: exact placement · orientation | 224 · 271 | **242 · 280** | 243 · 288 |
| worst-corner error / board side: median · p95 · max | 0.32 % · 1.0 % · 37 % | **0.23 % · 0.75 % · 10 %** | (same detector) |

Photo-only check (200 photos of screens, seed 777): v1.1 vs v2 — reader exact 187 vs 188, realistic exact
145/151 vs 145/151, side to move 86/89 vs 87/89. v2 (reader fine-tuned on +41k samples incl. 14k photo-heavy)
was a wash, slightly better on photos and on orientation of random placements, slightly worse on
screenshots, so v1.1 stays. Models: v1.0 = detector epoch 1/2 + reader epoch 1/3; v1.1 = detector 2/2 +
reader 3/3 (`checkpoints/detector_v1.pt`, `checkpoints/reader_v1.pt`); v2 reader = `checkpoints/reader_v2.pt`.

The headline "placement exact" over all 300 scenes (224 → 242) understates quality: 30 % of synthetic
scenes use random placements, some with two same-coloured kings (on purpose, so the reader can't rely on
priors) which the chess-rule post-processing then "fixes", and without coordinates the orientation of a
random placement is undecidable. The reader-argmax and realistic-position rows are the meaningful ones.

## Test data

- `testdata/real/` — lichess.org analysis-board screenshots (desktop 1280×800 and iPhone-sized
  390×844 @3x, some flipped), captured with Playwright; `labels.json` has FEN, orientation, last move.
- `testdata/private/` (git-ignored) — chess.com captures and a real iPhone photo of a monitor.
  Third-party UI, kept out of the repo.

## Licences

Training assets (lichess piece sets/boards) are used for training only and are not shipped.
The in-app sample images use only cburnett pieces (BSD/GPL) and Pillow's bundled Aileron font (CC0).
