"""Where do end-to-end errors come from? Same scenes as eval_synth_e2e (seed 12345):
per scene type, image-space square errors with detected corners vs ground-truth corners."""
import os
os.environ.setdefault("OMP_NUM_THREADS", "1")
import argparse, collections, random, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from tempo_vision import CLASSES
from tempo_vision.synth import Assets, make_scene, placement_to_cells
from tempo_vision.pipeline import CoreMLBackend, scan

ap = argparse.ArgumentParser()
ap.add_argument("--coreml", required=True)
ap.add_argument("--n", type=int, default=300)
ap.add_argument("--seed", type=int, default=12345)
a = ap.parse_args()
be = CoreMLBackend(a.coreml)
A = Assets()
rng = random.Random(a.seed)
np.random.seed(a.seed)
st = collections.defaultdict(lambda: collections.Counter())
for i in range(a.n):
    img, corners, info = make_scene(rng, A)
    kind = info.get("scene", "?")
    side = float(np.linalg.norm(corners[1] - corners[0]))
    for mode, c in (("det", None), ("gt", corners)):
        res = scan(be, img, corners=c)
        if not res.found:
            st[kind][mode + "_notfound"] += 1
            continue
        pred = placement_to_cells(np.array([CLASSES.index(x) for x in res.board]), res.flipped)
        wrong = int((pred != info["cells"]).sum())
        st[kind][mode + "_sqwrong"] += wrong
        st[kind][mode + "_boardsok"] += wrong == 0
        st[kind][mode + "_orient_ok"] += res.flipped == info["flipped"]
    st[kind]["n"] += 1
    st[kind]["small(<200px)"] += side < 200
for k, c in sorted(st.items()):
    n = c["n"]
    print(f"{k:8s} n={n:3d} small={c['small(<200px)']:3d} | detected corners: boards ok {c['det_boardsok']}/{n}, "
          f"wrong squares {c['det_sqwrong']}, orient ok {c['det_orient_ok']} | GT corners: boards ok {c['gt_boardsok']}/{n}, "
          f"wrong squares {c['gt_sqwrong']}")
