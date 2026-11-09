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
