"""Detector-only synthetic check: worst-corner error (% of board side), argmax vs geometry-aware decode, +zoom."""
import os
for _k in ("OMP_NUM_THREADS", "VECLIB_MAXIMUM_THREADS"):
    os.environ.setdefault(_k, "2")
import argparse, random, sys
import numpy as np, torch
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from tempo_vision.models import BoardDetector
from tempo_vision.synth import Assets, make_scene
from tempo_vision import pipeline as P
from tempo_vision.decode import decode_heatmaps, decode_quad

ap = argparse.ArgumentParser()
ap.add_argument("ckpt")
ap.add_argument("--n", type=int, default=200)
ap.add_argument("--seed", type=int, default=4242)
a = ap.parse_args()
torch.set_num_threads(2)
m = BoardDetector(pretrained=False).eval()
m.load_state_dict(torch.load(a.ckpt, map_location="cpu"))


class B:
    S = 384

    def detect(self, img):
        with torch.no_grad():
            return m(torch.from_numpy(img.astype(np.float32) / 255).permute(2, 0, 1)[None])[0].numpy()


be = B()
A = Assets()
rng = random.Random(a.seed)
res = {"argmax": [], "quad": [], "quad+zoom": []}
for _ in range(a.n):
    img, g, _ = make_scene(rng, A)
    side = np.linalg.norm(g[1] - g[0])
    lb, (sx, sy, ox, oy) = P.letterbox(img, 384)
    hm = be.detect(lb)
    for name, fn in (("argmax", decode_heatmaps), ("quad", decode_quad)):
        pts, _ = fn(hm, 4)
        pts = (pts - np.array([ox, oy])) / np.array([sx, sy])
        res[name].append(np.linalg.norm(pts - g, axis=1).max() / side * 100)
    c1, k1 = P.detect_pass(be, img)
    crop, off = P.zoom_crop(img, c1)
    c2, k2 = P.detect_pass(be, crop)
    c2 = c2 + off
    c = c2 if (k2 >= P.ZOOM_MIN_CONF_RATIO * k1 and P.quad_ok(c2)) else c1
    res["quad+zoom"].append(np.linalg.norm(c - g, axis=1).max() / side * 100)
for k, v in res.items():
    v = np.array(v)
    print(f"{k:10s} median {np.median(v):.2f}%  p95 {np.percentile(v, 95):.2f}%  >2%: {(v > 2).mean() * 100:.1f}%  >5%: {(v > 5).mean() * 100:.1f}%")
