"""Heatmap decoding shared by training, eval and the reference pipeline (port 1:1 to Swift)."""
import math

import numpy as np

EPS = 1e-6


def _parabola_offset(a, b, c):
    """Sub-cell peak offset from three samples via a parabola through their logs (exact for Gaussians)."""
    la, lb, lc = math.log(max(a, EPS)), math.log(max(b, EPS)), math.log(max(c, EPS))
    denom = la - 2.0 * lb + lc
    if denom >= -1e-9:
        return 0.0
    return max(-0.5, min(0.5, 0.5 * (la - lc) / denom))


def decode_heatmaps(hm, stride=4):
    """hm: [4, H, W] sigmoid heatmaps. Returns (points [4,2] in input pixels, confidences [4])."""
    k, H, W = hm.shape
    pts = np.zeros((k, 2), np.float32)
    conf = np.zeros(k, np.float32)
    for c in range(k):
        h = hm[c]
        flat = int(np.argmax(h))
        i, j = divmod(flat, W)
        conf[c] = h[i, j]
        dx = _parabola_offset(h[i, j - 1], h[i, j], h[i, j + 1]) if 0 < j < W - 1 else 0.0
        dy = _parabola_offset(h[i - 1, j], h[i, j], h[i + 1, j]) if 0 < i < H - 1 else 0.0
        pts[c] = ((j + dx + 0.5) * stride, (i + dy + 0.5) * stride)
    return pts, conf


# ----------------------------------------------------------------------------- geometric consistency
PEAK_MIN = 0.1          # local maxima below this are ignored
PEAKS_PER_CORNER = 4    # top-K local maxima per channel
GEO_WEIGHT = 1.5        # weight of the shape penalty vs. sum of log-confidences


def local_peaks(h, k=PEAKS_PER_CORNER, vmin=PEAK_MIN):
    """Top-k 3x3 local maxima (i, j, value) of a heatmap, highest first (ties: keep first in row-major order)."""
    H, W = h.shape
    pad = np.pad(h, 1, constant_values=-1.0)
    is_max = np.ones_like(h, bool)
    for di in (-1, 0, 1):
        for dj in (-1, 0, 1):
            if di or dj:
                is_max &= h >= pad[1 + di:1 + di + H, 1 + dj:1 + dj + W]
    ii, jj = np.nonzero(is_max & (h >= vmin))
    order = np.argsort(-h[ii, jj], kind="stable")[:k]
    return [(int(ii[o]), int(jj[o]), float(h[ii[o], jj[o]])) for o in order]


def refine(h, i, j, stride):
    H, W = h.shape
    dx = _parabola_offset(h[i, j - 1], h[i, j], h[i, j + 1]) if 0 < j < W - 1 else 0.0
    dy = _parabola_offset(h[i - 1, j], h[i, j], h[i + 1, j]) if 0 < i < H - 1 else 0.0
    return np.array([(j + dx + 0.5) * stride, (i + dy + 0.5) * stride], np.float32)


def shape_penalty(q):
    """0 for a square; grows with opposite-side mismatch and aspect ratio. q: [4,2] TL,TR,BR,BL."""
    top, right = np.linalg.norm(q[1] - q[0]), np.linalg.norm(q[2] - q[1])
    bottom, left = np.linalg.norm(q[3] - q[2]), np.linalg.norm(q[0] - q[3])
    if min(top, right, bottom, left) < 1e-3:
        return 1e9
    return abs(math.log(top / bottom)) + abs(math.log(left / right)) + abs(math.log((top + bottom) / (left + right)))


def convex_cw(q):
    for k in range(4):
        a, b, c = q[k], q[(k + 1) % 4], q[(k + 2) % 4]
        if (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0]) <= 0:
            return False
    return True


def decode_quad(hm, stride=4):
    """Best corner combination among the top local maxima of each channel.

    score = sum(ln v_c) - GEO_WEIGHT * shape_penalty(quad), over convex clockwise quads.
    Falls back to per-channel argmax if no combination is convex.
    Returns (points [4,2], confidences [4]).
    """
    cands = []
    for c in range(4):
        pk = local_peaks(hm[c])
        if not pk:
            return decode_heatmaps(hm, stride)
        cands.append([(refine(hm[c], i, j, stride), v) for i, j, v in pk])
    best, best_score = None, -1e18
    for a in cands[0]:
        for b in cands[1]:
            for c in cands[2]:
                for d in cands[3]:
                    q = np.stack([a[0], b[0], c[0], d[0]])
                    if not convex_cw(q):
                        continue
                    s = sum(math.log(max(x[1], EPS)) for x in (a, b, c, d)) - GEO_WEIGHT * shape_penalty(q)
                    if s > best_score:
                        best_score, best = s, (q, np.array([a[1], b[1], c[1], d[1]], np.float32))
    if best is None:
        return decode_heatmaps(hm, stride)
    return best
