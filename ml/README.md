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
.venv/bin/python scripts/gen_dataset.py reader   data/reader_v1 --n 60000 --seed 2
.venv/bin/python scripts/train.py detector --data data/det_v1    --out checkpoints/detector.pt --epochs 3
.venv/bin/python scripts/train.py reader   --data data/reader_v1 --out checkpoints/reader.pt   --epochs 3
.venv/bin/python scripts/export_coreml.py --detector checkpoints/detector.pt --reader checkpoints/reader.pt \
    --out ../ios/Tempo/Resources/Models
.venv/bin/python scripts/eval_real.py --coreml ../ios/Tempo/Resources/Models testdata/real ../ios/Tempo/Resources/Samples
.venv/bin/python scripts/make_samples.py               # in-app "Try a sample image" pictures
```

`scripts/preview_synth.py <dir>` writes contact sheets of synthetic samples.

## Test data

- `testdata/real/` — lichess.org analysis-board screenshots (desktop 1280×800 and iPhone-sized
  390×844 @3x, some flipped), captured with Playwright; `labels.json` has FEN, orientation, last move.
- `testdata/private/` (git-ignored) — chess.com captures and a real iPhone photo of a monitor.
  Third-party UI, kept out of the repo.

## Licences

Training assets (lichess piece sets/boards) are used for training only and are not shipped.
The in-app sample images use only cburnett pieces (BSD/GPL) and Pillow's bundled Aileron font (CC0).
