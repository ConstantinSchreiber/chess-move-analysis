"""End-to-end synthetic evaluation: fresh scenes (unseen seed) through the full pipeline."""
import os
for _k in ("OMP_NUM_THREADS", "MKL_NUM_THREADS", "OPENBLAS_NUM_THREADS", "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS"):
    os.environ.setdefault(_k, "1")  # one thread per process: the machine is shared

import argparse, os, random, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from tempo_vision.synth import Assets, make_scene
from tempo_vision.pipeline import CoreMLBackend, TorchBackend, scan, placement_fen

ap = argparse.ArgumentParser()
ap.add_argument("--coreml")
ap.add_argument("--torch", nargs=2)
ap.add_argument("--n", type=int, default=300)
ap.add_argument("--seed", type=int, default=12345)
a = ap.parse_args()
be = CoreMLBackend(a.coreml) if a.coreml else TorchBackend(*a.torch)
A = Assets()
rng = random.Random(a.seed)
np.random.seed(a.seed)
n = found = place = orient = sq = 0
stm_n = stm_ok = 0
corner_err = []
for i in range(a.n):
    img, corners, info = make_scene(rng, A)
    res = scan(be, img)
    n += 1
    if not res.found:
        continue
    found += 1
    corner_err.append(np.linalg.norm(res.corners - corners, axis=1).max() / np.linalg.norm(corners[1] - corners[0]))
    gt = placement_fen(info["board"])
    pred = res.fen.split()[0]
    place += gt == pred
    orient += res.flipped == info["flipped"]
    sq += sum(1 for s in range(64) if res.board[s] == ("empty" if info["board"][s] == 0 else __import__("tempo_vision").CLASSES[info["board"][s]]))
    if info["stm"] is not None and info["hl"].sum() > 0:
        stm_n += 1
        stm_ok += res.side_to_move == info["stm"]
ce = np.array(corner_err)
print(f"scenes {n}: found {found}, placement exact {place}/{n} ({place / n:.3f}), orientation {orient}/{found}, "
      f"square acc {sq / max(found * 64, 1):.4f}, side-to-move (highlight shown) {stm_ok}/{stm_n}")
print(f"worst-corner error / board side: median {np.median(ce):.4f}, p95 {np.percentile(ce, 95):.4f}, max {ce.max():.4f}")
