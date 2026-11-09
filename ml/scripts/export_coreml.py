"""Export trained checkpoints to Core ML ML Programs (fp16, iOS 17)."""
import argparse, os, sys
import coremltools as ct
import numpy as np
import torch
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from tempo_vision.models import BoardDetector, BoardReader
from tempo_vision import CLASSES

ap = argparse.ArgumentParser()
ap.add_argument("--detector", required=True)
ap.add_argument("--reader", required=True)
ap.add_argument("--out", required=True)
ap.add_argument("--S", type=int, default=384)
ap.add_argument("--R", type=int, default=384)
ap.add_argument("--version", default="1.0")
a = ap.parse_args()
os.makedirs(a.out, exist_ok=True)

det = BoardDetector(pretrained=False).eval()
det.load_state_dict(torch.load(a.detector, map_location="cpu"))
tr = torch.jit.trace(det, torch.rand(1, 3, a.S, a.S))
m = ct.convert(tr, inputs=[ct.ImageType(name="image", shape=(1, 3, a.S, a.S), scale=1 / 255.0, color_layout=ct.colorlayout.RGB)],
               outputs=[ct.TensorType(name="heatmaps")], convert_to="mlprogram",
               minimum_deployment_target=ct.target.iOS17, compute_precision=ct.precision.FLOAT16)
m.short_description = ("Chess board corner detector. Input: letterboxed RGB image (longer side scaled to the input size, "
                       "centred, black padding). Output: sigmoid heatmaps [1,4,S/4,S/4] for corners TL,TR,BR,BL in image space.")
m.author = "Tempo"
m.license = "GPL-3.0-or-later"
m.version = a.version
m.user_defined_metadata.update({"stride": "4", "corner_order": "TL,TR,BR,BL", "letterbox": "centered,black"})
m.save(os.path.join(a.out, "BoardDetector.mlpackage"))

rdr = BoardReader(pretrained=False, size=a.R).eval()
rdr.load_state_dict(torch.load(a.reader, map_location="cpu"))
tr = torch.jit.trace(rdr, torch.rand(1, 3, a.R, a.R))
m = ct.convert(tr, inputs=[ct.ImageType(name="image", shape=(1, 3, a.R, a.R), scale=1 / 255.0, color_layout=ct.colorlayout.RGB)],
               outputs=[ct.TensorType(name="pieces"), ct.TensorType(name="highlight"), ct.TensorType(name="flipped")],
               convert_to="mlprogram", minimum_deployment_target=ct.target.iOS17, compute_precision=ct.precision.FLOAT16)
m.short_description = ("Chess board reader. Input: board rectified corner-to-corner. Outputs: pieces [1,8,8,13] softmax "
                       "(row 0 = top, classes " + ",".join(CLASSES) + "), highlight [1,8,8] sigmoid (last-move tint), "
                       "flipped [1] sigmoid (board shown from Black's side).")
m.author = "Tempo"
m.license = "GPL-3.0-or-later"
m.version = a.version
m.user_defined_metadata.update({"classes": ",".join(CLASSES), "layout": "row0=top,col0=left"})
m.save(os.path.join(a.out, "BoardReader.mlpackage"))

# parity check torch vs coreml
from PIL import Image
x = (np.random.default_rng(0).random((a.S, a.S, 3)) * 255).astype(np.uint8)
ref = det(torch.from_numpy(x.astype(np.float32) / 255).permute(2, 0, 1)[None]).detach().numpy()
got = ct.models.MLModel(os.path.join(a.out, "BoardDetector.mlpackage")).predict({"image": Image.fromarray(x)})["heatmaps"]
print("detector max abs diff", float(np.abs(ref - got).max()))
x = (np.random.default_rng(1).random((a.R, a.R, 3)) * 255).astype(np.uint8)
ref = rdr(torch.from_numpy(x.astype(np.float32) / 255).permute(2, 0, 1)[None])
got = ct.models.MLModel(os.path.join(a.out, "BoardReader.mlpackage")).predict({"image": Image.fromarray(x)})
print("reader pieces max abs diff", float(np.abs(ref[0].detach().numpy() - got["pieces"]).max()),
      "shapes", got["pieces"].shape, got["highlight"].shape, np.asarray(got["flipped"]).shape)
