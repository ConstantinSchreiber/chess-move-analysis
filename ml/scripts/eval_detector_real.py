"""Detector-only check on labelled real images: worst-corner error as % of board side, pass 1 vs zoom."""
import os
for _k in ("OMP_NUM_THREADS", "VECLIB_MAXIMUM_THREADS"):
    os.environ.setdefault(_k, "2")
import argparse, json, sys
import cv2, numpy as np, torch
from PIL import Image, ImageOps
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from tempo_vision.models import BoardDetector
from tempo_vision.pipeline import detect_pass, zoom_crop, quad_ok, ZOOM_MIN_CONF_RATIO

ap = argparse.ArgumentParser()
ap.add_argument("ckpt")
ap.add_argument("dirs", nargs="+")
ap.add_argument("--viz")
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
if a.viz:
    os.makedirs(a.viz, exist_ok=True)
for d in a.dirs:
    for L in json.load(open(os.path.join(d, "labels.json"))):
        img = np.asarray(ImageOps.exif_transpose(Image.open(os.path.join(d, L["file"]))).convert("RGB"))
        c1, k1 = detect_pass(be, img)
        crop, off = zoom_crop(img, c1)
        c2, k2 = detect_pass(be, crop)
        c2 = c2 + off
        use2 = k2 >= ZOOM_MIN_CONF_RATIO * k1 and quad_ok(c2)
        line = f"{L['file']:30s} conf1={k1:.2f} conf2={k2:.2f} zoom={'Y' if use2 else 'N'}"
        if "corners" in L:
            g = np.array(L["corners"], np.float32)
            side = np.linalg.norm(g[1] - g[0])
            e1 = np.linalg.norm(c1 - g, axis=1).max() / side * 100
            e2 = np.linalg.norm(c2 - g, axis=1).max() / side * 100
            line += f" err1={e1:.2f}% err2={e2:.2f}%"
        print(line, flush=True)
        if a.viz:
            v = img.copy()
            cv2.polylines(v, [np.round(c2 if use2 else c1).astype(np.int32)], True, (255, 0, 255), max(2, img.shape[1] // 250))
            cv2.imwrite(os.path.join(a.viz, L["file"].rsplit(".", 1)[0] + ".jpg"), v[..., ::-1])
