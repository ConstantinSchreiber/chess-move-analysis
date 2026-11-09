"""Pre-render a synthetic dataset to disk (JPEG + npz labels) with a process pool."""
import os
for _k in ("OMP_NUM_THREADS", "MKL_NUM_THREADS", "OPENBLAS_NUM_THREADS", "VECLIB_MAXIMUM_THREADS", "NUMEXPR_NUM_THREADS"):
    os.environ.setdefault(_k, "1")  # one thread per process: the machine is shared

import argparse, os, random, sys, time
from multiprocessing import Pool
import cv2, numpy as np
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from tempo_vision.synth import Assets, detector_sample, reader_sample

A = None

def init():
    global A
    cv2.setNumThreads(0)
    A = Assets()

def work(args):
    kind, out, start, count, seed = args
    rng = random.Random(seed)
    np.random.seed(seed % (2**32))
    res = []
    for i in range(start, start + count):
        if kind == "detector":
            img, corners = detector_sample(rng, A)
            lab = np.full((4, 2), np.nan, np.float32) if corners is None else corners.astype(np.float32)
        else:
            img, cells, hl, fl = reader_sample(rng, A)
            lab = (cells.astype(np.int8), hl.astype(np.uint8), np.uint8(fl))
        cv2.imwrite(os.path.join(out, "images", f"{i:07d}.jpg"), img[..., ::-1], [cv2.IMWRITE_JPEG_QUALITY, 94])
        res.append((i, lab))
    save_labels(os.path.join(out, "shards", f"{start:07d}.npz"), kind, dict(res))
    return res


def save_labels(path, kind, results):
    """Labels for the given {index: label} dict; `idx` lists which image each row belongs to."""
    idx = sorted(results)
    if kind == "detector":
        np.savez(path, idx=np.array(idx), corners=np.stack([results[i] for i in idx]))
    else:
        np.savez(path, idx=np.array(idx), cells=np.stack([results[i][0] for i in idx]),
                 hl=np.stack([results[i][1] for i in idx]), flipped=np.array([results[i][2] for i in idx]))

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("kind", choices=["detector", "reader"])
    ap.add_argument("out")
    ap.add_argument("--n", type=int, default=50000)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--workers", type=int, default=6)
    ap.add_argument("--chunk", type=int, default=250)
    a = ap.parse_args()
    os.makedirs(os.path.join(a.out, "images"), exist_ok=True)
    os.makedirs(os.path.join(a.out, "shards"), exist_ok=True)
    jobs = [(a.kind, a.out, s, min(a.chunk, a.n - s), a.seed * 1_000_003 + s) for s in range(0, a.n, a.chunk)]
    t = time.time()
    results = {}
    with Pool(a.workers, initializer=init) as pool:
        for k, res in enumerate(pool.imap_unordered(work, jobs)):
            for i, lab in res:
                results[i] = lab
            if k % 20 == 0:
                print(f"{len(results)}/{a.n} {time.time() - t:.0f}s", flush=True)
    save_labels(os.path.join(a.out, "labels.npz"), a.kind, results)
    print("done", len(results), f"{time.time() - t:.0f}s")
