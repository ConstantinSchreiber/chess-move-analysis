"""Run the full reference pipeline on labelled real images and report per-image results.

  python scripts/eval_real.py --coreml ../ios/Tempo/Resources/Models testdata/real testdata/private
  python scripts/eval_real.py --torch checkpoints/detector.pt checkpoints/reader.pt testdata/real
"""
import argparse, json, os, sys
import cv2, numpy as np
from PIL import Image, ImageOps
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from tempo_vision.pipeline import CoreMLBackend, TorchBackend, scan, placement_fen

ap = argparse.ArgumentParser()
ap.add_argument("dirs", nargs="+")
ap.add_argument("--coreml")
ap.add_argument("--torch", nargs=2)
ap.add_argument("--viz")
ap.add_argument("--no-zoom", action="store_true")
a = ap.parse_args()
be = CoreMLBackend(a.coreml) if a.coreml else TorchBackend(*a.torch)
if a.viz:
    os.makedirs(a.viz, exist_ok=True)
tot = dict(n=0, placement=0, orient=0, stm=0, squares=0, full=0)
for d in a.dirs:
    if os.path.exists(os.path.join(d, "labels.json")):
        labels = json.load(open(os.path.join(d, "labels.json")))
    else:  # in-app samples (ios/Tempo/Resources/Samples/samples.json)
        import chess
        labels = []
        for smp in json.load(open(os.path.join(d, "samples.json")))["samples"]:
            labels.append(dict(file=smp["file"], fen=smp["fen"], flipped=False, side_to_move=smp["fen"].split()[1],
                               last_move=smp["last_move"]))
    for L in labels:
        img = np.asarray(ImageOps.exif_transpose(Image.open(os.path.join(d, L["file"]))).convert("RGB"))
        res = scan(be, img, zoom=not a.no_zoom)
        gt_place = L["fen"].split()[0]
        if not res.found:
            print(f"{L['file']:32s} NOT FOUND conf={res.detector_conf:.2f}")
            tot["n"] += 1
            continue
        pred_place = res.fen.split()[0]
        # square-level diff
        import chess
        gb, pb = chess.Board(L["fen"]), chess.Board(res.fen)
        diff = [chess.square_name(s) for s in chess.SQUARES if gb.piece_at(s) != pb.piece_at(s)]
        ok_place = pred_place == gt_place
        ok_orient = res.flipped == L["flipped"]
        ok_stm = res.side_to_move == L["side_to_move"]
        tot["n"] += 1
        tot["placement"] += ok_place
        tot["orient"] += ok_orient
        tot["stm"] += ok_stm
        tot["squares"] += 64 - len(diff)
        tot["full"] += ok_place and ok_stm
        print(f"{L['file']:32s} place={'OK' if ok_place else 'XX'} orient={'OK' if ok_orient else 'XX'}(p={res.flipped_prob:.2f}) "
              f"stm={'OK' if ok_stm else 'XX'}({res.side_to_move},{res.stm_source}) conf={res.detector_conf:.2f} "
              f"wrong={diff} uncertain={res.uncertain} last={res.last_move}")
        if a.viz:
            v = img.copy()
            cv2.polylines(v, [np.round(res.corners).astype(np.int32)], True, (255, 0, 255), max(2, img.shape[1] // 300))
            cv2.imwrite(os.path.join(a.viz, L["file"].rsplit(".", 1)[0] + "_det.jpg"), v[..., ::-1])
            cv2.imwrite(os.path.join(a.viz, L["file"].rsplit(".", 1)[0] + "_warp.jpg"), res.warped[..., ::-1])
n = max(tot["n"], 1)
print(f"\nimages {tot['n']}: placement {tot['placement']}/{n}, orientation {tot['orient']}/{n}, "
      f"side-to-move {tot['stm']}/{n}, fully correct {tot['full']}/{n}, square acc {tot['squares'] / (64 * n):.4f}")
