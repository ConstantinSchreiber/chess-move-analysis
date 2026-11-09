"""Synthetic training data: digital chess boards in screenshots and photos of screens.

Conventions
- Board squares: 0..63, a1 = 0, h8 = 63 (python-chess numbering).
- Image cells: (row, col) with row 0 = top of the image, col 0 = left.
- Continuous image coordinates: pixel (i, j) covers [j, j+1) x [i, i+1); board corners are
  given in this space. OpenCV warps use pixel centres at integers, so cv = continuous - 0.5.
"""
from __future__ import annotations

import glob
import io
import json
import math
import os
import random
import string

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

from . import CLASSES, PIECE_CODES

ML_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.environ.get("TEMPO_ML_CACHE", os.path.join(ML_ROOT, ".cache"))

# Sets that look like what people actually play on get sampled more often.
COMMON_SETS = {
    "cburnett": 6, "merida": 4, "alpha": 4, "california": 3, "cardinal": 3, "maestro": 3,
    "companion": 3, "staunty": 4, "chessnut": 3, "pirouetti": 2, "leipzig": 2, "fresca": 2,
    "tatiana": 2, "kosal": 2, "gioco": 2, "governor": 2, "dubrovny": 2, "icpieces": 2,
    "riohacha": 2, "mpchess": 2, "cooke": 2, "fantasy": 2, "spatial": 2, "celtic": 2,
    "chess7": 2, "reillycraig": 2, "rhosgfx": 2, "libra": 2, "caliente": 2, "firi": 1,
    "monarchy": 1, "papercut": 1, "pixel": 1, "minimal-warmth": 1, "totoy": 1,
    "anarcandy": 0.4, "horsey": 0.5, "shahi-ivory-brown": 0.5, "xkcd": 0.5,
}

FONT_PATHS = [
    "/System/Library/Fonts/Helvetica.ttc",
    "/System/Library/Fonts/HelveticaNeue.ttc",
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "/System/Library/Fonts/Supplemental/Georgia.ttf",
    "/System/Library/Fonts/Supplemental/Georgia Bold.ttf",
    "/System/Library/Fonts/Avenir Next.ttc",
    "/System/Library/Fonts/Menlo.ttc",
    "/System/Library/Fonts/Supplemental/Verdana Bold.ttf",
    "/System/Library/Fonts/Supplemental/Trebuchet MS Bold.ttf",
]

# (light, dark) pairs seen in popular apps and sites.
PALETTES = [
    ("#F0D9B5", "#B58863"),  # lichess brown
    ("#EEEED2", "#769656"),  # chess.com green
    ("#EBECD0", "#779556"),
    ("#EDD6B0", "#B88762"),
    ("#DEE3E6", "#8CA2AD"),  # lichess blue
    ("#FFFFDD", "#86A666"),  # lichess green
    ("#ECECEC", "#C1C18E"),  # ic
    ("#9F90B0", "#7D4A8D"),  # purple
    ("#DCDCDC", "#ABABAB"),
    ("#E8EDF9", "#B7C0D8"),
    ("#F3E4CF", "#CEB3A2"),
    ("#E0C094", "#A87C5A"),
    ("#D9E4E8", "#7B9BA6"),
    ("#EFEFEF", "#8877B7"),
    ("#F0F1F0", "#C4D8E4"),
    ("#E6D3B3", "#946F51"),
    ("#FFCE9E", "#D18B47"),  # classic
    ("#EAE9D2", "#4B7399"),
    ("#E3C16F", "#B88B4A"),
    ("#CACAC8", "#535353"),
    ("#EBEBEB", "#353535"),
    ("#F2F6FA", "#DFE6EE"),
]

HIGHLIGHT_TINTS = [
    ((255, 255, 51), (0.45, 0.6)),   # chess.com yellow
    ((247, 247, 105), (0.7, 1.0)),
    ((187, 203, 43), (0.6, 1.0)),
    ((155, 199, 0), (0.35, 0.5)),    # lichess
    ((205, 210, 106), (0.6, 1.0)),
    ((170, 162, 58), (0.5, 0.9)),
    ((97, 156, 207), (0.4, 0.7)),    # blue
    ((20, 85, 30), (0.3, 0.5)),
    ((255, 170, 0), (0.35, 0.6)),
    ((130, 151, 105), (0.5, 0.9)),
    ((255, 255, 255), (0.25, 0.45)),
]

ARROW_COLORS = [(21, 120, 27), (255, 170, 0), (136, 32, 32), (0, 48, 136), (159, 207, 63), (255, 165, 0)]


def hex_rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def parse_placement(fen):
    """FEN -> np.int64[64] class indices (a1 = 0)."""
    board = np.zeros(64, np.int64)
    rows = fen.split()[0].split("/")
    for r, row in enumerate(rows):
        rank = 7 - r
        f = 0
        for ch in row:
            if ch.isdigit():
                f += int(ch)
            else:
                board[rank * 8 + f] = CLASSES.index(ch)
                f += 1
    return board


def sq_to_cell(sq, flipped):
    f, r = sq % 8, sq // 8
    return (r, 7 - f) if flipped else (7 - r, f)


def placement_to_cells(board, flipped):
    cells = np.zeros((8, 8), np.int64)
    for sq in range(64):
        r, c = sq_to_cell(sq, flipped)
        cells[r, c] = board[sq]
    return cells


class Assets:
    def __init__(self, cache=CACHE, positions=True):
        root = os.path.join(cache, "pieces_png")
        self.sets = {}
        for name in sorted(os.listdir(root)):
            pieces = [None]
            ok = True
            for code in PIECE_CODES[1:]:
                p = os.path.join(root, name, code + ".png")
                if not os.path.exists(p):
                    ok = False
                    break
                pieces.append(np.asarray(Image.open(p).convert("RGBA")))
            if ok:
                self.sets[name] = pieces
        self.set_names = list(self.sets)
        w = np.array([COMMON_SETS.get(n, 1.0) for n in self.set_names], np.float64)
        self.set_weights = w / w.sum()

        self.textures = []
        for p in sorted(glob.glob(os.path.join(cache, "lila/public/images/board/*"))):
            b = os.path.basename(p)
            if "thumbnail" in b or b.startswith("horsey.") and b.count(".") > 1 or os.path.isdir(p):
                continue
            if b.startswith("ncf-board"):
                continue
            im = Image.open(p).convert("RGB").resize((512, 512), Image.LANCZOS)
            self.textures.append(np.asarray(im))

        self.positions = []
        pos_path = os.path.join(cache, "positions.jsonl")
        if positions and os.path.exists(pos_path):
            with open(pos_path) as fh:
                for line in fh:
                    self.positions.append(line)
        self.fonts = [p for p in FONT_PATHS if os.path.exists(p)]
        self._font_cache = {}

    def font(self, path, size):
        key = (path, size)
        f = self._font_cache.get(key)
        if f is None:
            f = ImageFont.truetype(path, size)
            if len(self._font_cache) > 400:
                self._font_cache.clear()
            self._font_cache[key] = f
        return f


# ----------------------------------------------------------------------------- positions

def random_position(rng: random.Random):
    """Random (mostly non-legal) placements so the reader doesn't lean on game priors."""
    board = np.zeros(64, np.int64)
    u = rng.random()
    if u < 0.04:
        return board, None, None
    if u < 0.09:
        return parse_placement("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR"), None, "w"
    n = int(rng.triangular(2, 32, 10))
    free = list(range(64))
    rng.shuffle(free)
    if rng.random() < 0.95:
        board[free.pop()] = 6
    if rng.random() < 0.95:
        board[free.pop()] = 12
    kinds = [1, 2, 3, 4, 5, 6]
    weights = [0.42, 0.14, 0.14, 0.15, 0.1, 0.05]
    while free and n > 0:
        sq = free.pop()
        k = rng.choices(kinds, weights)[0]
        if k == 1 and sq // 8 in (0, 7) and rng.random() < 0.97:
            continue
        board[sq] = k + (6 if rng.random() < 0.5 else 0)
        n -= 1
    last = None
    occ = [s for s in range(64) if board[s]]
    emp = [s for s in range(64) if not board[s]]
    if occ and emp:
        last = (rng.choice(emp), rng.choice(occ))
    return board, last, None


def sample_position(rng: random.Random, assets: Assets):
    """Returns (board[64], last_move (from, to) or None, side_to_move or None, in_check_king_sq)."""
    if assets.positions and rng.random() < 0.7:
        rec = json.loads(rng.choice(assets.positions))
        board = parse_placement(rec["fen"])
        stm = rec["fen"].split()[1]
        last = tuple(rec["last"]) if rec.get("last") else None
        return board, last, stm
    return random_position(rng)


# ----------------------------------------------------------------------------- drawing helpers

def blend_rect(img, x0, y0, x1, y1, color, alpha):
    if x1 <= x0 or y1 <= y0:
        return
    roi = img[y0:y1, x0:x1].astype(np.float32)
    roi = roi * (1 - alpha) + np.array(color, np.float32) * alpha
    img[y0:y1, x0:x1] = np.clip(roi, 0, 255).astype(np.uint8)


def alpha_paste(dst, rgba, x, y, opacity=1.0):
    """Alpha-composite rgba (h,w,4 uint8) onto dst at integer (x, y) with clipping."""
    h, w = rgba.shape[:2]
    H, W = dst.shape[:2]
    x0, y0 = max(x, 0), max(y, 0)
    x1, y1 = min(x + w, W), min(y + h, H)
    if x1 <= x0 or y1 <= y0:
        return
    src = rgba[y0 - y:y1 - y, x0 - x:x1 - x].astype(np.float32)
    a = (src[..., 3:4] / 255.0) * opacity
    roi = dst[y0:y1, x0:x1].astype(np.float32)
    dst[y0:y1, x0:x1] = np.clip(roi * (1 - a) + src[..., :3] * a, 0, 255).astype(np.uint8)


def overlay_blend(dst, overlay_rgb, alpha_mask):
    a = alpha_mask[..., None].astype(np.float32)
    dst[:] = np.clip(dst.astype(np.float32) * (1 - a) + overlay_rgb.astype(np.float32) * a, 0, 255).astype(np.uint8)


def random_light_dark(rng):
    u = rng.random()
    if u < 0.6:
        l, d = rng.choice(PALETTES)
        l, d = np.array(hex_rgb(l), np.float32), np.array(hex_rgb(d), np.float32)
        l += rng.uniform(-8, 8)
        d += np.array([rng.uniform(-10, 10) for _ in range(3)], np.float32)
        return np.clip(l, 0, 255), np.clip(d, 0, 255)
    # random HSV pair
    hue = rng.random()
    import colorsys
    ls = rng.uniform(0.0, 0.25)
    lv = rng.uniform(0.78, 1.0)
    ds = rng.uniform(0.0, 0.7)
    dv = rng.uniform(0.3, 0.72)
    hue2 = (hue + rng.uniform(-0.08, 0.08)) % 1.0
    l = np.array(colorsys.hsv_to_rgb(hue, ls, lv), np.float32) * 255
    d = np.array(colorsys.hsv_to_rgb(hue2, ds, dv), np.float32) * 255
    return l, d


def smooth_noise(rng, h, w, scale, octaves=2):
    out = np.zeros((h, w), np.float32)
    amp = 1.0
    for o in range(octaves):
        gh, gw = max(2, int(h / scale) + 2), max(2, int(w / scale) + 2)
        g = np.array([rng.random() for _ in range(gh * gw)], np.float32).reshape(gh, gw)
        out += amp * cv2.resize(g, (w, h), interpolation=cv2.INTER_CUBIC)
        amp *= 0.5
        scale /= 2.5
    out -= out.mean()
    return out / (out.std() + 1e-6)


def wood_grain(rng, h, w):
    """Cheap wood-ish grain field in [-1, 1]."""
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    n = smooth_noise(rng, h, w, max(8, w / 6), 3)
    freq = rng.uniform(0.04, 0.15)
    ang = rng.choice([0, math.pi / 2]) + rng.uniform(-0.05, 0.05)
    t = xx * math.cos(ang) + yy * math.sin(ang)
    return np.sin(t * freq + n * rng.uniform(2, 6)).astype(np.float32)


def recolor_piece(rgba, mult, add):
    out = rgba.astype(np.float32).copy()
    out[..., :3] = out[..., :3] * mult + add
    return np.clip(out, 0, 255).astype(np.uint8)


def draw_arrow(overlay, mask, p0, p1, width, color):
    p0 = np.array(p0, np.float32)
    p1 = np.array(p1, np.float32)
    d = p1 - p0
    L = float(np.linalg.norm(d))
    if L < 1:
        return
    d /= L
    nrm = np.array([-d[1], d[0]], np.float32)
    head_len = width * 2.2
    head_w = width * 2.0
    shaft_end = p1 - d * head_len
    poly_shaft = np.array([p0 + nrm * width / 2, shaft_end + nrm * width / 2,
                           shaft_end - nrm * width / 2, p0 - nrm * width / 2])
    poly_head = np.array([shaft_end + nrm * head_w / 2, p1, shaft_end - nrm * head_w / 2])
    for poly in (poly_shaft, poly_head):
        pts = np.round(poly * 4).astype(np.int32)
        cv2.fillPoly(overlay, [pts], color, lineType=cv2.LINE_AA, shift=2)
        cv2.fillPoly(mask, [pts], 1.0, lineType=cv2.LINE_AA, shift=2)


# ----------------------------------------------------------------------------- board

def render_board(rng: random.Random, assets: Assets, n: int, board=None, last=None, stm=None,
                 flipped=None, set_name=None):
    """Render an n x n board. Returns dict(img, cells, hl, flipped, coords_inside)."""
    if board is None:
        board, last, stm = sample_position(rng, assets)
    if flipped is None:
        flipped = rng.random() < 0.3
    edges = [int(round(i * n / 8)) for i in range(9)]
    s = n / 8.0

    # --- base squares
    swap = rng.random() < 0.02
    if assets.textures and rng.random() < 0.28:
        tex = rng.choice(assets.textures)
        k = rng.choice([0, 2])
        tex = np.rot90(tex, k)
        if rng.random() < 0.5:
            tex = tex.transpose(1, 0, 2)
        img = cv2.resize(np.ascontiguousarray(tex), (n, n), interpolation=cv2.INTER_AREA if n < 512 else cv2.INTER_LINEAR)
        img = img.copy()
        light = img[edges[0]:edges[1], edges[0]:edges[1]].reshape(-1, 3).mean(0)
        dark = img[edges[0]:edges[1], edges[1]:edges[2]].reshape(-1, 3).mean(0)
    else:
        light, dark = random_light_dark(rng)
        if swap:
            light, dark = dark, light
        img = np.zeros((n, n, 3), np.float32)
        for r in range(8):
            for c in range(8):
                img[edges[r]:edges[r + 1], edges[c]:edges[c + 1]] = light if (r + c) % 2 == 0 else dark
        u = rng.random()
        if u < 0.12:
            g = wood_grain(rng, n, n)[..., None]
            img *= 1 + g * rng.uniform(0.03, 0.1)
        elif u < 0.25:
            g = smooth_noise(rng, n, n, rng.uniform(8, 60), 3)[..., None]
            img *= 1 + g * rng.uniform(0.02, 0.07)
        if rng.random() < 0.15:  # vertical lighting gradient
            yy = np.linspace(-1, 1, n, dtype=np.float32)[:, None, None]
            img *= 1 + yy * rng.uniform(-0.08, 0.08)
        img = np.clip(img, 0, 255).astype(np.uint8)
        if rng.random() < 0.08:  # thin grid lines
            col = tuple(int(v) for v in (dark * rng.uniform(0.4, 0.9)))
            th = max(1, int(round(s * rng.uniform(0.01, 0.03))))
            for e in edges:
                cv2.line(img, (e, 0), (e, n - 1), col, th)
                cv2.line(img, (0, e), (n - 1, e), col, th)

    cells = placement_to_cells(board, flipped)
    hl = np.zeros((8, 8), np.float32)

    # --- last-move highlight
    if last is not None and rng.random() < 0.65:
        tint, (amin, amax) = rng.choice(HIGHLIGHT_TINTS)
        tint = np.clip(np.array(tint, np.float32) + rng.uniform(-15, 15), 0, 255)
        alpha = rng.uniform(amin, amax)
        both = rng.random() < 0.93
        for i, sq in enumerate(last):
            if i == 0 and not both:
                continue
            r, c = sq_to_cell(sq, flipped)
            a = alpha * (rng.uniform(0.85, 1.15) if rng.random() < 0.3 else 1.0)
            if rng.random() < 0.08:  # outline-only style highlight
                th = max(2, int(s * 0.07))
                sub = img[edges[r]:edges[r + 1], edges[c]:edges[c + 1]]
                ov = sub.copy()
                cv2.rectangle(ov, (0, 0), (sub.shape[1] - 1, sub.shape[0] - 1), tuple(int(v) for v in tint), th)
                sub[:] = ov
            else:
                blend_rect(img, edges[c], edges[r], edges[c + 1], edges[r + 1], tint, min(a, 1.0))
            hl[r, c] = 1.0

    # --- other square tints that are NOT last-move highlights (premove / selected in another colour)
    if rng.random() < 0.06:
        tint = (rng.choice([(20, 30, 85), (170, 40, 40), (90, 90, 90)]))
        for _ in range(rng.randint(1, 2)):
            r, c = rng.randrange(8), rng.randrange(8)
            if hl[r, c] == 0:
                blend_rect(img, edges[c], edges[r], edges[c + 1], edges[r + 1], tint, rng.uniform(0.3, 0.5))

    # --- check glow
    king_cells = [(r, c) for r in range(8) for c in range(8) if cells[r, c] in (6, 12)]
    if king_cells and rng.random() < 0.06:
        r, c = rng.choice(king_cells)
        cx, cy = (edges[c] + edges[c + 1]) / 2, (edges[r] + edges[r + 1]) / 2
        x0, y0, x1, y1 = edges[c], edges[r], edges[c + 1], edges[r + 1]
        yy, xx = np.mgrid[y0:y1, x0:x1].astype(np.float32)
        d = np.sqrt((xx + 0.5 - cx) ** 2 + (yy + 0.5 - cy) ** 2) / (s * 0.7)
        a = np.clip(1 - d, 0, 1) * rng.uniform(0.6, 1.0)
        sub = img[y0:y1, x0:x1]
        overlay_blend(sub, np.broadcast_to(np.array([255, 0, 0], np.float32), sub.shape), a)

    # --- coordinates
    coords_after = rng.random() < 0.2
    coord_style = None
    if rng.random() < 0.65:
        coord_style = dict(
            font=rng.choice(assets.fonts),
            size=max(8, int(s * rng.uniform(0.16, 0.28))),
            rank_side=rng.choice(["left", "left", "right"]),
            file_side=rng.choice(["bottom", "bottom", "top"]),
            corner_files=rng.choice(["right", "right", "left"]),
            color_mode=rng.choice(["opposite", "opposite", "fixed"]),
            fixed=tuple(int(v) for v in rng.choice([(255, 255, 255), (30, 30, 30), (120, 120, 120)])),
            pad=rng.uniform(0.04, 0.1),
        )

    def draw_coords():
        if coord_style is None:
            return
        pil = Image.fromarray(img)
        dr = ImageDraw.Draw(pil)
        font = assets.font(coord_style["font"], coord_style["size"])
        pad = int(s * coord_style["pad"])
        files = "abcdefgh"
        for r in range(8):
            rank_label = str(8 - r) if not flipped else str(r + 1)
            c = 0 if coord_style["rank_side"] == "left" else 7
            col = coord_style["fixed"] if coord_style["color_mode"] == "fixed" else (
                tuple(int(v) for v in (dark if (r + c) % 2 == 0 else light)))
            x = edges[c] + pad if c == 0 else edges[c + 1] - pad - font.getlength(rank_label)
            dr.text((x, edges[r] + pad * 0.6), rank_label, fill=col, font=font)
        for c in range(8):
            file_label = files[c] if not flipped else files[7 - c]
            r = 7 if coord_style["file_side"] == "bottom" else 0
            col = coord_style["fixed"] if coord_style["color_mode"] == "fixed" else (
                tuple(int(v) for v in (dark if (r + c) % 2 == 0 else light)))
            tw = font.getlength(file_label)
            x = edges[c + 1] - pad - tw if coord_style["corner_files"] == "right" else edges[c] + pad
            y = edges[r + 1] - pad * 0.6 - coord_style["size"] * 1.05 if r == 7 else edges[r] + pad * 0.6
            dr.text((x, y), file_label, fill=col, font=font)
        img[:] = np.asarray(pil)

    if not coords_after:
        draw_coords()

    # --- pieces
    if set_name is None:
        set_name = assets.set_names[min(len(assets.set_names) - 1, int(np.searchsorted(np.cumsum(assets.set_weights), rng.random())))]
        set_name = set_name if set_name in assets.sets else rng.choice(assets.set_names)
    pieces = assets.sets[set_name]
    scale = rng.uniform(0.78, 1.0) if rng.random() < 0.85 else rng.uniform(0.65, 0.78)
    psize = max(4, int(round(s * scale)))
    white_mult = black_mult = np.ones(3, np.float32)
    white_add = black_add = np.zeros(3, np.float32)
    if rng.random() < 0.25:
        white_mult = np.array([rng.uniform(0.82, 1.0) for _ in range(3)], np.float32)
    if rng.random() < 0.25:
        black_add = np.array([rng.uniform(0, 60) for _ in range(3)], np.float32)
        black_mult = np.full(3, rng.uniform(0.7, 1.0), np.float32)
    shadow = rng.random() < 0.2
    resized = {}
    jitter = s * (0.04 if rng.random() < 0.3 else 0.01)
    for r in range(8):
        for c in range(8):
            k = int(cells[r, c])
            if k == 0:
                continue
            if k not in resized:
                p = cv2.resize(pieces[k], (psize, psize), interpolation=cv2.INTER_AREA)
                if k <= 6:
                    p = recolor_piece(p, white_mult, white_add)
                else:
                    p = recolor_piece(p, black_mult, black_add)
                resized[k] = p
            p = resized[k]
            cx = (edges[c] + edges[c + 1]) / 2 + rng.uniform(-jitter, jitter)
            cy = (edges[r] + edges[r + 1]) / 2 + rng.uniform(-jitter, jitter)
            x, y = int(round(cx - psize / 2)), int(round(cy - psize / 2))
            if shadow:
                sh = p.copy()
                sh[..., :3] = 0
                sh[..., 3] = cv2.GaussianBlur(sh[..., 3], (0, 0), max(0.5, s * 0.03))
                alpha_paste(img, sh, x + int(s * 0.03), y + int(s * 0.04), opacity=0.35)
            alpha_paste(img, p, x, y)

    if coords_after:
        draw_coords()

    # --- legal-move dots / capture rings
    if rng.random() < 0.1:
        ov = np.zeros_like(img)
        mask = np.zeros(img.shape[:2], np.float32)
        col = rng.choice([(0, 0, 0), (20, 85, 30), (40, 40, 40), (255, 255, 255)])
        for _ in range(rng.randint(2, 9)):
            r, c = rng.randrange(8), rng.randrange(8)
            cx, cy = int((edges[c] + edges[c + 1]) / 2), int((edges[r] + edges[r + 1]) / 2)
            if cells[r, c] == 0:
                cv2.circle(ov, (cx, cy), max(1, int(s * rng.uniform(0.12, 0.18))), col, -1, cv2.LINE_AA)
                cv2.circle(mask, (cx, cy), max(1, int(s * rng.uniform(0.12, 0.18))), 1.0, -1, cv2.LINE_AA)
            else:
                cv2.circle(ov, (cx, cy), int(s * 0.46), col, max(1, int(s * 0.08)), cv2.LINE_AA)
                cv2.circle(mask, (cx, cy), int(s * 0.46), 1.0, max(1, int(s * 0.08)), cv2.LINE_AA)
        overlay_blend(img, ov, mask * rng.uniform(0.15, 0.35))

    # --- arrows
    if rng.random() < 0.12:
        for _ in range(rng.randint(1, 3)):
            ov = np.zeros_like(img)
            mask = np.zeros(img.shape[:2], np.float32)
            r0, c0, r1, c1 = (rng.randrange(8) for _ in range(4))
            if (r0, c0) == (r1, c1):
                continue
            p0 = ((edges[c0] + edges[c0 + 1]) / 2, (edges[r0] + edges[r0 + 1]) / 2)
            p1 = ((edges[c1] + edges[c1 + 1]) / 2, (edges[r1] + edges[r1 + 1]) / 2)
            draw_arrow(ov, mask, p0, p1, s * rng.uniform(0.14, 0.24), rng.choice(ARROW_COLORS))
            overlay_blend(img, ov, mask * rng.uniform(0.5, 0.85))

    return dict(img=img, cells=cells, hl=hl, flipped=flipped, light=light, dark=dark, set_name=set_name,
                stm=stm, board=board, last=last)


# ----------------------------------------------------------------------------- scenes

def rand_ui_color(rng, dark_theme):
    if dark_theme:
        v = rng.uniform(10, 60)
        return np.array([v + rng.uniform(-6, 6) for _ in range(3)], np.float32)
    v = rng.uniform(200, 255)
    return np.array([v + rng.uniform(-8, 8) for _ in range(3)], np.float32)


def random_text(rng, n):
    alphabet = string.ascii_letters + string.digits + "    .:-+()"
    return "".join(rng.choice(alphabet) for _ in range(n))


def draw_clutter(rng, img, avoid, assets, set_name, dark_theme, density=1.0):
    """Panels, text, avatars, buttons, captured-piece icons. avoid = (x0, y0, x1, y1) board box."""
    H, W = img.shape[:2]
    ax0, ay0, ax1, ay1 = avoid
    fg = (230, 230, 230) if dark_theme else (40, 40, 40)

    def ok(x0, y0, x1, y1):
        return x1 < ax0 or x0 > ax1 or y1 < ay0 or y0 > ay1

    unit = max(W, H) / 100.0
    for _ in range(int(rng.randint(4, 14) * density)):
        kind = rng.random()
        w = int(rng.uniform(4, 45) * unit)
        h = int(rng.uniform(1.5, 10) * unit)
        x0 = rng.randrange(0, max(1, W - w))
        y0 = rng.randrange(0, max(1, H - h))
        if not ok(x0, y0, x0 + w, y0 + h):
            continue
        if kind < 0.35:  # panel / button
            col = tuple(int(v) for v in np.clip(rand_ui_color(rng, dark_theme) + rng.uniform(-25, 25), 0, 255))
            if rng.random() < 0.2:
                col = tuple(rng.randrange(256) for _ in range(3))
            cv2.rectangle(img, (x0, y0), (x0 + w, y0 + h), col, -1, cv2.LINE_AA)
        elif kind < 0.75:  # text line
            sc = max(0.3, rng.uniform(0.3, 1.2) * unit / 10 * 4)
            text = random_text(rng, rng.randint(4, 24))
            font = rng.choice([cv2.FONT_HERSHEY_SIMPLEX, cv2.FONT_HERSHEY_DUPLEX, cv2.FONT_HERSHEY_PLAIN])
            th = rng.randint(1, 2)
            (tw, tht), base = cv2.getTextSize(text, font, sc, th)
            if not ok(x0 - 2, y0 + h - tht - 2, x0 + tw + 2, y0 + h + base + 2):
                continue
            cv2.putText(img, text, (x0, y0 + h), font, sc, fg if rng.random() < 0.8 else (200, 160, 60), th, cv2.LINE_AA)
        elif kind < 0.85:  # avatar
            rad = int(rng.uniform(1.5, 4) * unit)
            cx, cy = x0 + rad, y0 + rad
            if ok(cx - rad, cy - rad, cx + rad, cy + rad):
                cv2.circle(img, (cx, cy), rad, tuple(rng.randrange(256) for _ in range(3)), -1, cv2.LINE_AA)
        else:  # captured pieces row
            pieces = assets.sets[set_name]
            ps = int(rng.uniform(1.5, 4) * unit)
            if ps < 4:
                continue
            for i in range(rng.randint(1, 6)):
                px = x0 + i * int(ps * 0.7)
                if ok(px, y0, px + ps, y0 + ps):
                    alpha_paste(img, cv2.resize(pieces[rng.randint(1, 12)], (ps, ps), interpolation=cv2.INTER_AREA), px, y0)


def make_board_frame(rng, b, light, dark, assets):
    """Optional frame around the board with outside coordinates. Returns (img, offset)."""
    n = b.shape[0]
    m = int(n * rng.uniform(0.03, 0.07))
    col = np.clip(np.array(dark) * rng.uniform(0.4, 0.9), 0, 255) if rng.random() < 0.6 else rand_ui_color(rng, rng.random() < 0.5)
    out = np.empty((n + 2 * m, n + 2 * m, 3), np.uint8)
    out[:] = col.astype(np.uint8)
    out[m:m + n, m:m + n] = b
    if rng.random() < 0.7:
        pil = Image.fromarray(out)
        dr = ImageDraw.Draw(pil)
        font = assets.font(rng.choice(assets.fonts), max(8, int(m * 0.7)))
        fg = (230, 230, 230) if col.mean() < 128 else (30, 30, 30)
        flipped = rng.random() < 0.5
        for i in range(8):
            y = m + (i + 0.5) * n / 8 - m * 0.4
            dr.text((m * 0.25, y), str(8 - i) if not flipped else str(i + 1), fill=fg, font=font)
            x = m + (i + 0.5) * n / 8 - m * 0.2
            dr.text((x, m + n + m * 0.1), "abcdefgh"[i] if not flipped else "hgfedcba"[i], fill=fg, font=font)
        out = np.asarray(pil).copy()
    return out, m


def board_corners(x0, y0, n):
    return np.array([[x0, y0], [x0 + n, y0], [x0 + n, y0 + n], [x0, y0 + n]], np.float32)


def screen_scene(rng, assets, kind, max_side=1400):
    """A synthetic screenshot. Returns (img, corners or None, board_info)."""
    dark_theme = rng.random() < 0.6
    if kind == "phone":
        W = rng.randint(380, 760)
        H = int(W * rng.uniform(1.7, 2.2))
        n = int(W * rng.uniform(0.86, 1.0))
        x0 = (W - n) // 2 + rng.randint(-int(W * 0.02), int(W * 0.02))
        y0 = int(H * rng.uniform(0.12, 0.45))
    elif kind == "tablet":
        W = rng.randint(700, 1100)
        H = int(W * rng.uniform(0.7, 1.45))
        n = int(min(W, H) * rng.uniform(0.55, 0.92))
        x0 = rng.randint(0, W - n)
        y0 = rng.randint(0, H - n)
    elif kind == "crop":
        n = rng.randint(220, 900)
        ml, mr, mt, mb = (int(n * rng.uniform(0, 0.08)) if rng.random() < 0.7 else 0 for _ in range(4))
        W, H = n + ml + mr, n + mt + mb
        x0, y0 = ml, mt
    else:  # desktop
        W = rng.randint(900, max_side)
        H = int(W * rng.choice([9 / 16, 10 / 16, 0.75, 0.6]))
        n = int(H * rng.uniform(0.45, 0.95))
        x0 = rng.randint(0, W - n)
        y0 = rng.randint(0, H - n)
    n = max(min(n, W, H), 64)
    W, H = max(W, n), max(H, n)
    x0 = int(min(max(x0, 0), W - n))
    y0 = int(min(max(y0, 0), H - n))
    img = np.empty((H, W, 3), np.uint8)
    img[:] = rand_ui_color(rng, dark_theme).astype(np.uint8)
    if rng.random() < 0.3:
        g = smooth_noise(rng, H, W, max(W, H) / 3, 1)[..., None]
        img[:] = np.clip(img.astype(np.float32) * (1 + g * 0.05), 0, 255).astype(np.uint8)

    info = render_board(rng, assets, n)
    b = info["img"]
    framed = rng.random() < 0.1 and kind != "crop"
    if framed:
        fb, m = make_board_frame(rng, b, info["light"], info["dark"], assets)
        fx, fy = x0 - m, y0 - m
        if fx >= 0 and fy >= 0 and fx + fb.shape[1] <= W and fy + fb.shape[0] <= H:
            img[fy:fy + fb.shape[0], fx:fx + fb.shape[1]] = fb
        else:
            framed = False
    if not framed:
        if rng.random() < 0.25:  # rounded board corners
            rad = int(n * rng.uniform(0.01, 0.03))
            mask = np.zeros((n, n), np.uint8)
            cv2.rectangle(mask, (rad, 0), (n - rad - 1, n - 1), 1, -1)
            cv2.rectangle(mask, (0, rad), (n - 1, n - rad - 1), 1, -1)
            for cx, cy in ((rad, rad), (n - rad - 1, rad), (rad, n - rad - 1), (n - rad - 1, n - rad - 1)):
                cv2.circle(mask, (cx, cy), rad, 1, -1)
            roi = img[y0:y0 + n, x0:x0 + n]
            roi[mask > 0] = b[mask > 0]
        else:
            img[y0:y0 + n, x0:x0 + n] = b
        if rng.random() < 0.15:  # board drop shadow / border line
            col = (0, 0, 0) if rng.random() < 0.5 else tuple(int(v) for v in info["dark"])
            cv2.rectangle(img, (x0 - 1, y0 - 1), (x0 + n, y0 + n), col, 1)
        if kind != "crop" and rng.random() < 0.18:  # evaluation bar hugging the board
            bw = max(3, int(n * rng.uniform(0.015, 0.045)))
            gap = int(n * rng.uniform(0, 0.012))
            bx = x0 - gap - bw if rng.random() < 0.8 else x0 + n + gap
            if 0 <= bx and bx + bw <= W:
                split = y0 + int(n * rng.uniform(0.05, 0.95))
                top, bot = ((60, 60, 60), (245, 245, 245)) if rng.random() < 0.8 else ((245, 245, 245), (60, 60, 60))
                cv2.rectangle(img, (bx, y0), (bx + bw - 1, split), top, -1)
                cv2.rectangle(img, (bx, split), (bx + bw - 1, y0 + n - 1), bot, -1)

    if kind != "crop":
        draw_clutter(rng, img, (x0 - 2, y0 - 2, x0 + n + 2, y0 + n + 2), assets, info["set_name"], dark_theme)
        if kind == "phone" and rng.random() < 0.6:
            fg = (240, 240, 240) if dark_theme else (20, 20, 20)
            cv2.putText(img, f"{rng.randint(0, 23)}:{rng.randint(0, 59):02d}", (int(W * 0.1), int(H * 0.03)),
                        cv2.FONT_HERSHEY_SIMPLEX, W / 900, fg, 2, cv2.LINE_AA)
    return img, board_corners(x0, y0, n), info


def moire(rng, img):
    H, W = img.shape[:2]
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    # smoothly warped coordinates -> curved bands like real screen moiré
    wx = smooth_noise(rng, H, W, max(H, W) / 2, 1) * rng.uniform(0, 25)
    wy = smooth_noise(rng, H, W, max(H, W) / 2, 1) * rng.uniform(0, 25)
    X, Y = xx + wx, yy + wy
    mod = np.zeros((H, W, 3), np.float32)
    for _ in range(rng.randint(1, 3)):
        period = rng.uniform(3, 30)
        ang = rng.uniform(0, math.pi)
        f = 2 * math.pi / period
        ph = rng.uniform(0, 2 * math.pi)
        amp = rng.uniform(0.02, 0.12)
        base = X * math.cos(ang) * f + Y * math.sin(ang) * f + ph
        chan_shift = rng.uniform(0, 2.2) if rng.random() < 0.6 else 0
        for ch in range(3):
            mod[..., ch] += amp * np.sin(base + ch * chan_shift)
    return np.clip(img.astype(np.float32) * (1 + mod), 0, 255).astype(np.uint8)


def photo_background(rng, H, W, assets):
    u = rng.random()
    if u < 0.4:
        c0 = np.array([rng.uniform(20, 200) for _ in range(3)], np.float32)
        c1 = np.array([rng.uniform(0, 160) for _ in range(3)], np.float32)
        t = np.linspace(0, 1, H, dtype=np.float32)[:, None, None]
        bg = c0 * (1 - t) + c1 * t
        bg = np.broadcast_to(bg, (H, W, 3)).copy()
    elif u < 0.7 and assets.textures:
        bg = cv2.resize(rng.choice(assets.textures), (W, H)).astype(np.float32)
        bg = cv2.GaussianBlur(bg, (0, 0), rng.uniform(2, 12))
    else:
        bg = np.empty((H, W, 3), np.float32)
        bg[:] = np.array([rng.uniform(0, 255) for _ in range(3)], np.float32)
        bg *= (1 + smooth_noise(rng, H, W, max(H, W) / 4, 2)[..., None] * 0.25)
    bg = np.clip(bg, 0, 255).astype(np.uint8)
    for _ in range(rng.randint(0, 6)):  # desk objects, lamps, other screens
        x0, y0 = rng.randrange(W), rng.randrange(H)
        w, h = rng.randint(W // 20, W // 2), rng.randint(H // 20, H // 3)
        col = tuple(rng.randrange(256) for _ in range(3))
        cv2.rectangle(bg, (x0, y0), (x0 + w, y0 + h), col, -1)
    return bg


def photo_scene(rng, assets):
    """A photo of a monitor / phone / tablet showing a board."""
    kind = rng.choices(["desktop", "phone", "tablet", "crop"], [0.6, 0.15, 0.15, 0.1])[0]
    screen, corners, info = screen_scene(rng, assets, kind)
    h, w = screen.shape[:2]
    # bezel
    bz = int(max(h, w) * rng.uniform(0.0, 0.05))
    if bz > 0:
        col = rng.choice([(10, 10, 12), (25, 25, 28), (60, 60, 64), (170, 170, 175)])
        framed = np.empty((h + 2 * bz, w + 2 * bz, 3), np.uint8)
        framed[:] = col
        framed[bz:bz + h, bz:bz + w] = screen
        screen = framed
        corners = corners + bz
        h, w = screen.shape[:2]

    # photo canvas
    aspect = rng.choices([4 / 3, 3 / 4, 16 / 9, 1.0], [0.55, 0.25, 0.12, 0.08])[0]  # H / W
    PW = rng.randint(640, 1100)
    PH = int(PW * aspect)
    board_side = float(np.linalg.norm(corners[1] - corners[0]))

    for _ in range(20):
        # desired board size in photo
        target = rng.uniform(0.35, 0.95) * min(PW, PH)
        sc = target / board_side
        ang = math.radians(rng.gauss(0, 7)) if rng.random() < 0.9 else math.radians(rng.uniform(-25, 25))
        src = np.array([[0, 0], [w, 0], [w, h], [0, h]], np.float32)
        c = np.array([w / 2, h / 2], np.float32)
        R = np.array([[math.cos(ang), -math.sin(ang)], [math.sin(ang), math.cos(ang)]], np.float32)
        dst = (src - c) @ R.T * sc
        # perspective: perturb each corner
        persp = rng.uniform(0, 0.14)
        dst += np.array([[rng.uniform(-1, 1), rng.uniform(-1, 1)] for _ in range(4)], np.float32) * persp * target
        # place board centre near photo centre
        Hm = cv2.getPerspectiveTransform(src - 0.5, dst - 0.5)
        bc = cv2.perspectiveTransform(corners[None] - 0.5, Hm)[0] + 0.5
        shift = np.array([PW / 2, PH / 2], np.float32) - bc.mean(0) + np.array(
            [rng.uniform(-0.2, 0.2) * PW, rng.uniform(-0.2, 0.2) * PH], np.float32)
        dst += shift
        bc += shift
        m = 3
        if (bc[:, 0].min() > m and bc[:, 1].min() > m and bc[:, 0].max() < PW - m and bc[:, 1].max() < PH - m):
            break
    else:
        return None
    Hm = cv2.getPerspectiveTransform(src - 0.5, dst - 0.5)
    interp = rng.choice([cv2.INTER_LINEAR, cv2.INTER_AREA, cv2.INTER_CUBIC])
    if interp == cv2.INTER_AREA:
        interp = cv2.INTER_LINEAR
    warped = cv2.warpPerspective(screen, Hm, (PW, PH), flags=interp, borderMode=cv2.BORDER_CONSTANT)
    mask = cv2.warpPerspective(np.ones((h, w), np.float32), Hm, (PW, PH), flags=cv2.INTER_LINEAR)
    bg = photo_background(rng, PH, PW, assets)
    img = (bg.astype(np.float32) * (1 - mask[..., None]) + warped.astype(np.float32) * mask[..., None])

    # screen emits light: brightness / white balance shift of the screen region relative to the room
    img = img * np.array([rng.uniform(0.8, 1.15) for _ in range(3)], np.float32)
    img = np.clip(img, 0, 255).astype(np.uint8)
    if rng.random() < 0.75:
        img = moire(rng, img)
    if rng.random() < 0.3:  # glare
        gx, gy = rng.uniform(0, PW), rng.uniform(0, PH)
        yy, xx = np.mgrid[0:PH, 0:PW].astype(np.float32)
        r = rng.uniform(0.1, 0.5) * max(PW, PH)
        a = np.exp(-((xx - gx) ** 2 + (yy - gy) ** 2) / (2 * r * r)) * rng.uniform(0.1, 0.45)
        img = np.clip(img.astype(np.float32) * (1 - a[..., None]) + 255 * a[..., None], 0, 255).astype(np.uint8)
    corners = bc

    if rng.random() < 0.25:  # iOS camera review UI: black bars + buttons
        FW = PW
        FH = int(FW * rng.uniform(2.0, 2.2))
        frame = np.zeros((FH, FW, 3), np.uint8)
        oy = int((FH - PH) * rng.uniform(0.35, 0.5))
        if oy < 0:
            oy = 0
        hh = min(PH, FH - oy)
        frame[oy:oy + hh] = img[:hh]
        sc = FW / 600
        cv2.putText(frame, "Retake", (int(FW * 0.04), int(FH * 0.93)), cv2.FONT_HERSHEY_SIMPLEX, sc, (255, 255, 255), 2, cv2.LINE_AA)
        cv2.putText(frame, "Use Photo", (int(FW * 0.7), int(FH * 0.93)), cv2.FONT_HERSHEY_SIMPLEX, sc, (255, 255, 255), 2, cv2.LINE_AA)
        img = frame
        corners = corners + np.array([0, oy], np.float32)
        if corners[:, 1].max() > oy + hh - 2:
            return None
    return img, corners, info


def degrade(rng, img, photo):
    """Camera / compression degradations applied to the full scene."""
    img = img.astype(np.float32)
    if photo:
        if rng.random() < 0.7:
            img = img * rng.uniform(0.6, 1.3) + rng.uniform(-30, 30)
        if rng.random() < 0.5:
            gamma = rng.uniform(0.7, 1.4)
            img = 255 * (np.clip(img, 0, 255) / 255) ** gamma
        if rng.random() < 0.5:
            img = img * np.array([rng.uniform(0.85, 1.15) for _ in range(3)], np.float32)
        img = np.clip(img, 0, 255).astype(np.uint8)
        if rng.random() < 0.6:
            img = cv2.GaussianBlur(img, (0, 0), rng.uniform(0.3, 1.8))
        if rng.random() < 0.15:  # motion blur
            k = rng.randint(3, 9)
            ker = np.zeros((k, k), np.float32)
            ang = rng.uniform(0, 180)
            ker[k // 2, :] = 1
            M = cv2.getRotationMatrix2D((k / 2 - 0.5, k / 2 - 0.5), ang, 1)
            ker = cv2.warpAffine(ker, M, (k, k))
            ker /= ker.sum() + 1e-6
            img = cv2.filter2D(img, -1, ker)
        if rng.random() < 0.6:
            noise = np.random.default_rng(rng.randrange(1 << 30)).normal(0, rng.uniform(1, 9), img.shape)
            img = np.clip(img.astype(np.float32) + noise, 0, 255).astype(np.uint8)
    else:
        img = np.clip(img, 0, 255).astype(np.uint8)
        if rng.random() < 0.25:  # screenshots get resized by messengers
            h, w = img.shape[:2]
            f = rng.uniform(0.4, 0.9)
            img = cv2.resize(cv2.resize(img, (max(8, int(w * f)), max(8, int(h * f))), interpolation=cv2.INTER_AREA),
                             (w, h), interpolation=cv2.INTER_LINEAR)
    if rng.random() < (0.8 if photo else 0.4):
        q = rng.randint(35, 95)
        ok, enc = cv2.imencode(".jpg", img[..., ::-1], [cv2.IMWRITE_JPEG_QUALITY, q])
        img = cv2.imdecode(enc, cv2.IMREAD_COLOR)[..., ::-1]
    return np.ascontiguousarray(img)


def make_scene(rng, assets):
    """Returns (img RGB uint8, corners float32[4,2] TL,TR,BR,BL or None, info)."""
    u = rng.random()
    if u < 0.4:
        for _ in range(5):
            out = photo_scene(rng, assets)
            if out is not None:
                img, corners, info = out
                return degrade(rng, img, True), corners, info
    kind = rng.choices(["phone", "desktop", "crop", "tablet"], [0.38, 0.27, 0.22, 0.13])[0]
    img, corners, info = screen_scene(rng, assets, kind)
    return degrade(rng, img, False), corners, info


def negative_scene(rng, assets):
    W, H = rng.randint(400, 1000), rng.randint(400, 1400)
    dark = rng.random() < 0.5
    img = np.empty((H, W, 3), np.uint8)
    img[:] = rand_ui_color(rng, dark).astype(np.uint8)
    draw_clutter(rng, img, (-10, -10, -5, -5), assets, rng.choice(assets.set_names), dark, density=2.0)
    return degrade(rng, img, rng.random() < 0.5), None, None


# ----------------------------------------------------------------------------- model inputs

def letterbox(img, S):
    """Resize so the longer side is S, centre on a black S x S canvas.

    Returns (canvas, (sx, sy, ox, oy)) with x' = x * sx + ox in continuous coordinates.
    """
    h, w = img.shape[:2]
    scale = S / max(h, w)
    nw, nh = max(1, int(round(w * scale))), max(1, int(round(h * scale)))
    interp = cv2.INTER_AREA if scale < 1 else cv2.INTER_LINEAR
    resized = cv2.resize(img, (nw, nh), interpolation=interp)
    ox, oy = (S - nw) // 2, (S - nh) // 2
    out = np.zeros((S, S, 3), np.uint8)
    out[oy:oy + nh, ox:ox + nw] = resized
    return out, (nw / w, nh / h, ox, oy)


def warp_board(img, corners, R, interp=cv2.INTER_LINEAR):
    """Perspective-warp so corners (TL,TR,BR,BL, continuous coords) land on the R x R image corners."""
    src = np.asarray(corners, np.float32) - 0.5
    dst = np.array([[0, 0], [R, 0], [R, R], [0, R]], np.float32) - 0.5
    M = cv2.getPerspectiveTransform(src, dst)
    return cv2.warpPerspective(img, M, (R, R), flags=interp, borderMode=cv2.BORDER_CONSTANT)


def heatmap_targets(corners, S, stride, sigma):
    """Gaussian corner heatmaps [4, S/stride, S/stride]."""
    hs = S // stride
    hm = np.zeros((4, hs, hs), np.float32)
    if corners is None:
        return hm
    yy, xx = np.mgrid[0:hs, 0:hs].astype(np.float32)
    for k, (x, y) in enumerate(corners):
        u, v = x / stride - 0.5, y / stride - 0.5
        hm[k] = np.exp(-((xx - u) ** 2 + (yy - v) ** 2) / (2 * sigma * sigma))
    return hm


def detector_sample(rng, assets, S=384, zoom_prob=0.3):
    """Image (S,S,3) uint8, corners in input coords (or None), heatmap target."""
    if rng.random() < 0.03:
        img, corners, _ = negative_scene(rng, assets)
    else:
        img, corners, _ = make_scene(rng, assets)
    if corners is not None and rng.random() < zoom_prob:
        # emulate the second (zoomed) pass: square crop around the board, expansion as in the pipeline
        img, corners = zoom_crop(img, corners, expand=rng.uniform(1.12, 1.45),
                                 jitter=rng.uniform(0, 0.06), rng=rng)
    lb, (sx, sy, ox, oy) = letterbox(img, S)
    if corners is not None:
        corners = corners * np.array([sx, sy], np.float32) + np.array([ox, oy], np.float32)
    return lb, corners


def zoom_crop(img, corners, expand=1.25, jitter=0.0, rng=None):
    """Square crop centred on the quad; side = expand * max(bbox w, h). Pads with black."""
    cx, cy = corners.mean(0)
    side = expand * max(np.ptp(corners[:, 0]), np.ptp(corners[:, 1]))
    if rng is not None and jitter > 0:
        cx += rng.uniform(-jitter, jitter) * side
        cy += rng.uniform(-jitter, jitter) * side
    x0, y0 = int(round(cx - side / 2)), int(round(cy - side / 2))
    sd = int(round(side))
    out = np.zeros((sd, sd, 3), np.uint8)
    H, W = img.shape[:2]
    sx0, sy0 = max(0, x0), max(0, y0)
    sx1, sy1 = min(W, x0 + sd), min(H, y0 + sd)
    if sx1 > sx0 and sy1 > sy0:
        out[sy0 - y0:sy1 - y0, sx0 - x0:sx1 - x0] = img[sy0:sy1, sx0:sx1]
    return out, corners - np.array([x0, y0], np.float32)


def reader_sample(rng, assets, R=384):
    """Warped board (R,R,3) uint8 from jittered corners + labels."""
    while True:
        img, corners, info = make_scene(rng, assets)
        if corners is not None:
            break
    side = float(np.mean([np.linalg.norm(corners[i] - corners[(i + 1) % 4]) for i in range(4)]))
    u = rng.random()
    if u < 0.5:
        jit = np.array([[rng.gauss(0, 0.006), rng.gauss(0, 0.006)] for _ in range(4)], np.float32)
    elif u < 0.85:
        jit = np.array([[rng.uniform(-0.02, 0.02), rng.uniform(-0.02, 0.02)] for _ in range(4)], np.float32)
    else:
        jit = np.zeros((4, 2), np.float32)
    c = corners + jit * side
    interp = rng.choice([cv2.INTER_LINEAR, cv2.INTER_LINEAR, cv2.INTER_CUBIC, cv2.INTER_NEAREST])
    if side > 2.2 * R and rng.random() < 0.5:
        # big boards: downscale first (like CoreImage's Lanczos path), then warp
        f = 1.5 * R / side
        small = cv2.resize(img, None, fx=f, fy=f, interpolation=cv2.INTER_AREA)
        warped = warp_board(small, c * f, R, interp)
    else:
        warped = warp_board(img, c, R, interp)
    if rng.random() < 0.2:
        warped = cv2.GaussianBlur(warped, (0, 0), rng.uniform(0.3, 1.2))
    return warped, info["cells"], info["hl"], float(info["flipped"])
