"""Train BoardDetector or BoardReader on pre-rendered synthetic datasets.

  python scripts/train.py detector --data data/det_v1 --out checkpoints/detector.pt
  python scripts/train.py reader   --data data/reader_v1 --out checkpoints/reader.pt
"""
import argparse, math, os, random, sys, time
import cv2
import numpy as np
import torch
import torch.nn.functional as F
from torch.utils.data import ConcatDataset, DataLoader, Dataset

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from tempo_vision.models import BoardDetector, BoardReader
from tempo_vision.synth import heatmap_targets
from tempo_vision.decode import decode_heatmaps

SIGMA = 1.5
STRIDE = 4


def color_aug(img, rng):
    img = img.astype(np.float32)
    if rng.random() < 0.15:
        img = img[..., rng.sample([0, 1, 2], 3)]
    if rng.random() < 0.05:
        img[:] = img.mean(-1, keepdims=True)
    if rng.random() < 0.6:
        img = img * rng.uniform(0.75, 1.25) + rng.uniform(-25, 25)
    if rng.random() < 0.3:
        img = img * np.array([rng.uniform(0.9, 1.1) for _ in range(3)], np.float32)
    return np.clip(img, 0, 255)


class DetData(Dataset):
    def __init__(self, root, idx, train):
        self.root, self.idx, self.train = root, idx, train
        self.corners = np.load(os.path.join(root, "labels.npz"))["corners"]

    def __len__(self):
        return len(self.idx)

    def __getitem__(self, k):
        i = self.idx[k]
        img = cv2.imread(os.path.join(self.root, "images", f"{i:07d}.jpg"))[..., ::-1]
        c = self.corners[i].copy()
        has = not np.isnan(c).any()
        S = img.shape[0]
        if self.train:
            rng = random.Random()
            img = color_aug(img, rng)
            if rng.random() < 0.5:  # horizontal mirror: TL<->TR, BR<->BL
                img = img[:, ::-1]
                if has:
                    c[:, 0] = S - c[:, 0]
                    c = c[[1, 0, 3, 2]]
            if rng.random() < 0.15:  # vertical mirror: TL<->BL, TR<->BR
                img = img[::-1]
                if has:
                    c[:, 1] = S - c[:, 1]
                    c = c[[3, 2, 1, 0]]
        hm = heatmap_targets(c if has else None, S, STRIDE, SIGMA)
        x = torch.from_numpy(np.ascontiguousarray(img, dtype=np.float32) / 255.0).permute(2, 0, 1)
        return x, torch.from_numpy(hm), torch.from_numpy(np.nan_to_num(c, nan=-1.0).astype(np.float32)), has


class ReaderData(Dataset):
    def __init__(self, root, idx, train):
        self.root, self.idx, self.train = root, idx, train
        d = np.load(os.path.join(root, "labels.npz"))
        self.cells, self.hl, self.flipped = d["cells"], d["hl"], d["flipped"]

    def __len__(self):
        return len(self.idx)

    def __getitem__(self, k):
        i = self.idx[k]
        img = cv2.imread(os.path.join(self.root, "images", f"{i:07d}.jpg"))[..., ::-1]
        if self.train:
            img = color_aug(img, random.Random())
        x = torch.from_numpy(np.ascontiguousarray(img, dtype=np.float32) / 255.0).permute(2, 0, 1)
        return (x, torch.from_numpy(self.cells[i].astype(np.int64)), torch.from_numpy(self.hl[i].astype(np.float32)),
                torch.tensor(float(self.flipped[i])))


def split(n, val):
    idx = list(range(n))
    return idx[:-val], idx[-val:]


def det_loss(pred, gt):
    p = pred.clamp(1e-4, 1 - 1e-4)
    bce = -(gt * torch.log(p) + (1 - gt) * torch.log(1 - p))
    return (bce * (1 + 50 * gt)).mean() * 10


def evaluate_detector(model, loader, dev):
    model.eval()
    errs, conf_pos, conf_neg = [], [], []
    with torch.no_grad():
        for x, hm, c, has in loader:
            out = model(x.to(dev)).float().cpu().numpy()
            for b in range(out.shape[0]):
                pts, conf = decode_heatmaps(out[b], STRIDE)
                if has[b]:
                    errs.append(np.linalg.norm(pts - c[b].numpy(), axis=1))
                    conf_pos.append(conf.min())
                else:
                    conf_neg.append(conf.max())
    model.train()
    e = np.concatenate(errs) if errs else np.zeros(1)
    worst = np.stack(errs).max(1) if errs else np.zeros(1)
    return dict(mean_px=float(e.mean()), median_px=float(np.median(e)), p95_px=float(np.percentile(e, 95)),
                boards_all_corners_lt4px=float((worst < 4).mean()), boards_all_lt8px=float((worst < 8).mean()),
                conf_pos_min_mean=float(np.mean(conf_pos)) if conf_pos else 0.0,
                conf_neg_max_mean=float(np.mean(conf_neg)) if conf_neg else 0.0)


def evaluate_reader(model, loader, dev):
    model.eval()
    sq_ok = sq_n = board_ok = board_n = 0
    tp = fp = fn = 0
    flip_ok = 0
    with torch.no_grad():
        for x, cells, hl, fl in loader:
            piece, hlp, flp = model.forward_logits(x.to(dev))
            pred = piece.argmax(1).cpu()
            ok = (pred == cells)
            sq_ok += ok.sum().item()
            sq_n += ok.numel()
            board_ok += ok.flatten(1).all(1).sum().item()
            board_n += ok.shape[0]
            hb = (torch.sigmoid(hlp).cpu() > 0.5)
            tp += (hb & (hl > 0.5)).sum().item()
            fp += (hb & (hl < 0.5)).sum().item()
            fn += (~hb & (hl > 0.5)).sum().item()
            flip_ok += ((torch.sigmoid(flp).cpu() > 0.5).float() == fl).sum().item()
    model.train()
    return dict(square_acc=sq_ok / sq_n, board_acc=board_ok / board_n,
                hl_precision=tp / max(tp + fp, 1), hl_recall=tp / max(tp + fn, 1), flip_acc=flip_ok / board_n)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("kind", choices=["detector", "reader"])
    ap.add_argument("--data", nargs="+", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--epochs", type=int, default=8)
    ap.add_argument("--bs", type=int, default=32)
    ap.add_argument("--lr", type=float, default=1e-3)
    ap.add_argument("--val", type=int, default=1500)
    ap.add_argument("--workers", type=int, default=8)
    ap.add_argument("--init", default=None)
    ap.add_argument("--max-steps", type=int, default=0)
    a = ap.parse_args()
    dev = torch.device("mps" if torch.backends.mps.is_available() else "cpu")
    torch.manual_seed(0)

    trains, vals = [], []
    for root in a.data:
        n = len(os.listdir(os.path.join(root, "images")))
        tr, va = split(n, a.val)
        D = DetData if a.kind == "detector" else ReaderData
        trains.append(D(root, tr, True))
        vals.append(D(root, va, False))
    train_ds, val_ds = ConcatDataset(trains), ConcatDataset(vals)
    tl = DataLoader(train_ds, batch_size=a.bs, shuffle=True, num_workers=a.workers, drop_last=True,
                    persistent_workers=True, prefetch_factor=4)
    vl = DataLoader(val_ds, batch_size=64, shuffle=False, num_workers=a.workers)

    model = (BoardDetector() if a.kind == "detector" else BoardReader()).to(dev)
    if a.init:
        model.load_state_dict(torch.load(a.init, map_location="cpu"))
    backbone = [p for n, p in model.named_parameters() if n.startswith(("stem", "layer1", "layer2", "layer3"))]
    head = [p for n, p in model.named_parameters() if not n.startswith(("stem", "layer1", "layer2", "layer3"))]
    opt = torch.optim.AdamW([{"params": backbone, "lr": a.lr * 0.5}, {"params": head, "lr": a.lr}], weight_decay=1e-4)
    total = a.epochs * len(tl) if not a.max_steps else a.max_steps
    sched = torch.optim.lr_scheduler.OneCycleLR(opt, max_lr=[a.lr * 0.5, a.lr], total_steps=total, pct_start=0.05)
    os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)

    step = 0
    t0 = time.time()
    best = None
    for ep in range(a.epochs):
        run = 0.0
        for batch in tl:
            if a.kind == "detector":
                x, hm, _, _ = batch
                loss = det_loss(model(x.to(dev)), hm.to(dev))
            else:
                x, cells, hl, fl = batch
                piece, hlp, flp = model.forward_logits(x.to(dev))
                loss = (F.cross_entropy(piece, cells.to(dev), label_smoothing=0.02)
                        + 0.5 * F.binary_cross_entropy_with_logits(hlp, hl.to(dev), pos_weight=torch.tensor(4.0, device=dev))
                        + 0.3 * F.binary_cross_entropy_with_logits(flp, fl.to(dev)))
            opt.zero_grad(set_to_none=True)
            loss.backward()
            opt.step()
            sched.step()
            step += 1
            run += loss.item()
            if step % 100 == 0:
                print(f"ep {ep} step {step}/{total} loss {run / 100:.4f} {time.time() - t0:.0f}s", flush=True)
                run = 0.0
            if a.max_steps and step >= a.max_steps:
                break
        m = (evaluate_detector if a.kind == "detector" else evaluate_reader)(model, vl, dev)
        print(f"== epoch {ep} val {m}", flush=True)
        torch.save(model.state_dict(), a.out)
        if a.max_steps and step >= a.max_steps:
            break
    print("saved", a.out)


if __name__ == "__main__":
    main()
