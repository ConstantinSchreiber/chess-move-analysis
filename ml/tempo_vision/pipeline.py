"""Reference inference pipeline: photo/screenshot -> FEN. The Swift app ports this 1:1.

Every tunable number lives in the CONSTANTS block and is documented in ml/CONTRACT.md.
"""
from __future__ import annotations

import os
from dataclasses import dataclass, field

import cv2
import numpy as np

from . import CLASSES
from .decode import decode_heatmaps, decode_quad

# ----------------------------------------------------------------------------- CONSTANTS
DETECTOR_STRIDE = 4            # heatmap cell = 4 input px
DETECT_MIN_CONF = 0.25         # min over the 4 corner peaks; below -> "no board found"
ZOOM_EXPAND = 1.25             # pass-2 crop side = ZOOM_EXPAND * max(quad bbox w, h)
ZOOM_MIN_CONF_RATIO = 0.6      # accept pass 2 if its conf >= ratio * pass-1 conf
PREDOWNSCALE_FACTOR = 2.0      # if board side > factor * R, downscale image to 1.5 * R board side before warping
UNCERTAIN_PROB = 0.85          # square flagged uncertain if max class prob < this
HIGHLIGHT_PROB = 0.5           # square counts as last-move highlight if p > this
FLIP_CONFIDENT = 0.25          # use model orientation if |p - 0.5| > this, else blend with layout heuristic
LAYOUT_WEIGHT = 1.2            # logit weight of the layout heuristic (rows)
KING_MIN_PROB = 0.2            # promote best king candidate if a side has no king and p(K) > this


@dataclass
class ScanResult:
    found: bool
    fen: str = ""
    corners: np.ndarray | None = None          # [4,2] TL,TR,BR,BL in original image px (continuous coords)
    detector_conf: float = 0.0
    board: list = field(default_factory=list)   # 64 class names, a1..h8
    probs: np.ndarray | None = None             # [64] max prob per square (a1..h8)
    uncertain: list = field(default_factory=list)  # square names
    flipped: bool = False
    flipped_prob: float = 0.0
    side_to_move: str = "w"
    stm_source: str = "default"                  # highlight | check | default
    last_move: tuple | None = None               # (from, to) square names if detected
    castling: str = "-"
    ep: str = "-"
    warped: np.ndarray | None = None


# ----------------------------------------------------------------------------- backends

class CoreMLBackend:
    def __init__(self, models_dir):
        import coremltools as ct
        self.det = ct.models.MLModel(os.path.join(models_dir, "BoardDetector.mlpackage"))
        self.rdr = ct.models.MLModel(os.path.join(models_dir, "BoardReader.mlpackage"))
        self.S = self.det.get_spec().description.input[0].type.imageType.width
        self.R = self.rdr.get_spec().description.input[0].type.imageType.width

    def detect(self, img):
        from PIL import Image
        return self.det.predict({"image": Image.fromarray(img)})["heatmaps"][0]

    def read(self, img):
        from PIL import Image
        out = self.rdr.predict({"image": Image.fromarray(img)})
        return out["pieces"][0], out["highlight"][0], float(np.asarray(out["flipped"]).reshape(-1)[0])


class TorchBackend:
    def __init__(self, det_ckpt, rdr_ckpt, S=384, R=384, device="cpu"):
        import torch
        from .models import BoardDetector, BoardReader
        self.torch = torch
        self.dev = device
        self.det = BoardDetector(pretrained=False).eval().to(device)
        self.det.load_state_dict(torch.load(det_ckpt, map_location="cpu"))
        self.rdr = BoardReader(pretrained=False, size=R).eval().to(device)
        self.rdr.load_state_dict(torch.load(rdr_ckpt, map_location="cpu"))
        self.S, self.R = S, R

    def _t(self, img):
        return self.torch.from_numpy(img.astype(np.float32) / 255.0).permute(2, 0, 1)[None].to(self.dev)

    def detect(self, img):
        with self.torch.no_grad():
            return self.det(self._t(img))[0].cpu().numpy()

    def read(self, img):
        with self.torch.no_grad():
            p, h, f = self.rdr(self._t(img))
        return p[0].cpu().numpy(), h[0].cpu().numpy(), float(f[0])


# ----------------------------------------------------------------------------- geometry

def letterbox(img, S):
    h, w = img.shape[:2]
    scale = S / max(h, w)
    nw, nh = max(1, int(round(w * scale))), max(1, int(round(h * scale)))
    resized = cv2.resize(img, (nw, nh), interpolation=cv2.INTER_AREA if scale < 1 else cv2.INTER_LINEAR)
    ox, oy = (S - nw) // 2, (S - nh) // 2
    out = np.zeros((S, S, 3), np.uint8)
    out[oy:oy + nh, ox:ox + nw] = resized
    return out, (nw / w, nh / h, ox, oy)


def detect_pass(backend, img):
    lb, (sx, sy, ox, oy) = letterbox(img, backend.S)
    hm = backend.detect(lb)
    pts, conf = decode_quad(hm, DETECTOR_STRIDE)
    pts = (pts - np.array([ox, oy], np.float32)) / np.array([sx, sy], np.float32)
    return pts, float(conf.min())


def zoom_crop(img, corners, expand=ZOOM_EXPAND):
    cx, cy = corners.mean(0)
    side = expand * max(np.ptp(corners[:, 0]), np.ptp(corners[:, 1]))
    x0, y0 = int(round(cx - side / 2)), int(round(cy - side / 2))
    sd = max(8, int(round(side)))
    out = np.zeros((sd, sd, 3), np.uint8)
    H, W = img.shape[:2]
    sx0, sy0, sx1, sy1 = max(0, x0), max(0, y0), min(W, x0 + sd), min(H, y0 + sd)
    if sx1 > sx0 and sy1 > sy0:
        out[sy0 - y0:sy1 - y0, sx0 - x0:sx1 - x0] = img[sy0:sy1, sx0:sx1]
    return out, np.array([x0, y0], np.float32)


def quad_ok(c):
    """Convex, clockwise (in image coords y-down), non-degenerate."""
    cross = []
    for i in range(4):
        a, b, d = c[i], c[(i + 1) % 4], c[(i + 2) % 4]
        cross.append((b[0] - a[0]) * (d[1] - b[1]) - (b[1] - a[1]) * (d[0] - b[0]))
    sides = [np.linalg.norm(c[i] - c[(i + 1) % 4]) for i in range(4)]
    return all(x > 0 for x in cross) and min(sides) > 16 and max(sides) / min(sides) < 4


def warp_board(img, corners, R):
    side = float(np.mean([np.linalg.norm(corners[i] - corners[(i + 1) % 4]) for i in range(4)]))
    c = corners.astype(np.float32)
    if side > PREDOWNSCALE_FACTOR * R:
        f = 1.5 * R / side
        img = cv2.resize(img, None, fx=f, fy=f, interpolation=cv2.INTER_AREA)
        c = c * f
    src = c - 0.5
    dst = np.array([[0, 0], [R, 0], [R, R], [0, R]], np.float32) - 0.5
    M = cv2.getPerspectiveTransform(src, dst)
    return cv2.warpPerspective(img, M, (R, R), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_CONSTANT)


# ----------------------------------------------------------------------------- chess post-processing

def cell_to_square(r, c, flipped):
    """Image cell -> square index (a1 = 0)."""
    return r * 8 + (7 - c) if flipped else (7 - r) * 8 + c


def sq_name(sq):
    return "abcdefgh"[sq % 8] + str(sq // 8 + 1)


def is_white(k):
    return 1 <= k <= 6


def fix_kings(cls, probs):
    """At most one king per colour; promote a missing king if the model saw one somewhere."""
    cls = cls.copy()
    for king in (6, 12):
        idx = np.argwhere(cls == king)
        if len(idx) > 1:
            best = max(idx, key=lambda rc: probs[rc[0], rc[1], king])
            for r, c in idx:
                if (r, c) != tuple(best):
                    p = probs[r, c].copy()
                    p[king] = -1
                    cls[r, c] = int(np.argmax(p))
        elif len(idx) == 0:
            r, c = np.unravel_index(np.argmax(probs[..., king]), (8, 8))
            if probs[r, c, king] > KING_MIN_PROB and cls[r, c] not in (6, 12):
                cls[r, c] = king
    return cls


def fix_back_rank_pawns(cls, probs):
    """Rows 0 and 7 are always rank 1/8 whatever the orientation: no pawns there."""
    cls = cls.copy()
    for r in (0, 7):
        for c in range(8):
            if cls[r, c] in (1, 7):
                p = probs[r, c].copy()
                p[1] = p[7] = -1
                cls[r, c] = int(np.argmax(p))
    return cls


def layout_score(cls):
    """> 0 when the layout looks like White at the bottom (unflipped)."""
    wr = [r for r in range(8) for c in range(8) if is_white(cls[r, c])]
    br = [r for r in range(8) for c in range(8) if cls[r, c] >= 7]
    if not wr or not br:
        return 0.0
    return (np.mean(wr) - np.mean(br)) / 2.0


def decide_flipped(p_model, cls):
    if abs(p_model - 0.5) > FLIP_CONFIDENT:
        return p_model > 0.5
    logit = np.log(max(p_model, 1e-4) / max(1 - p_model, 1e-4)) - LAYOUT_WEIGHT * layout_score(cls)
    return logit > 0


def king_in_check(board, white):
    """board: 64 class idx (a1=0). Is the given side's king attacked?"""
    import chess
    b = chess.Board(None)
    for sq in range(64):
        if board[sq]:
            b.set_piece_at(sq, chess.Piece.from_symbol(CLASSES[board[sq]]))
    ksq = b.king(chess.WHITE if white else chess.BLACK)
    if ksq is None:
        return False
    return b.is_attacked_by(chess.BLACK if white else chess.WHITE, ksq)


def side_to_move(board, hl_sq):
    """hl_sq: list of (square, prob) above threshold, sorted by prob desc. Returns (stm, source, last)."""
    hl_sq = hl_sq[:2]
    mover = None
    last = None
    occ = [(s, p) for s, p in hl_sq if board[s]]
    emp = [(s, p) for s, p in hl_sq if not board[s]]
    if len(hl_sq) == 2 and len(occ) == 1:
        mover = "w" if is_white(board[occ[0][0]]) else "b"
        last = (emp[0][0], occ[0][0])
    elif len(occ) == 2 and is_white(board[occ[0][0]]) == is_white(board[occ[1][0]]):
        mover = "w" if is_white(board[occ[0][0]]) else "b"
    elif len(hl_sq) == 1 and len(occ) == 1:
        mover = "w" if is_white(board[occ[0][0]]) else "b"
    wc, bc = king_in_check(board, True), king_in_check(board, False)
    if mover is not None:
        stm = "b" if mover == "w" else "w"
        # the side that just moved can't still be in check
        if (stm == "b" and wc and not bc) or (stm == "w" and bc and not wc):
            stm = "w" if stm == "b" else "b"
            return stm, "check", None
        return stm, "highlight", last
    if wc and not bc:
        return "w", "check", None
    if bc and not wc:
        return "b", "check", None
    return "w", "default", None


def castling_rights(board):
    K, R, k, r = 6, 4, 12, 10
    s = ""
    if board[4] == K:
        if board[7] == R:
            s += "K"
        if board[0] == R:
            s += "Q"
    if board[60] == k:
        if board[63] == r:
            s += "k"
        if board[56] == r:
            s += "q"
    return s or "-"


def en_passant(board, last, stm):
    if last is None:
        return "-"
    fr, to = last
    pawn = 1 if stm == "b" else 7  # the mover's pawn
    if board[to] != pawn or fr % 8 != to % 8 or abs(fr // 8 - to // 8) != 2:
        return "-"
    return sq_name((fr + to) // 2)


def placement_fen(board):
    rows = []
    for rank in range(7, -1, -1):
        row, empty = "", 0
        for f in range(8):
            k = board[rank * 8 + f]
            if k == 0:
                empty += 1
            else:
                if empty:
                    row += str(empty)
                    empty = 0
                row += CLASSES[k]
        if empty:
            row += str(empty)
        rows.append(row)
    return "/".join(rows)


# ----------------------------------------------------------------------------- main entry

def scan(backend, img, zoom=True, corners=None):
    """img: RGB uint8 (EXIF orientation already applied). `corners` skips detection (e.g. user-adjusted quad)."""
    if corners is not None:
        return read_board(backend, img, np.asarray(corners, np.float32), 1.0)
    corners, conf = detect_pass(backend, img)
    if conf < DETECT_MIN_CONF or not quad_ok(corners):
        return ScanResult(found=False, corners=corners, detector_conf=conf)
    if zoom:
        crop, off = zoom_crop(img, corners)
        c2, conf2 = detect_pass(backend, crop)
        c2 = c2 + off
        if conf2 >= ZOOM_MIN_CONF_RATIO * conf and quad_ok(c2):
            corners, conf = c2, max(conf, conf2)
    return read_board(backend, img, corners, conf)


def read_board(backend, img, corners, conf):
    warped = warp_board(img, corners, backend.R)
    probs, hl, p_flip = backend.read(warped)
    cls = probs.argmax(-1)
    cls = fix_kings(cls, probs)
    cls = fix_back_rank_pawns(cls, probs)
    flipped = decide_flipped(p_flip, cls)

    board = np.zeros(64, np.int64)
    sqprob = np.zeros(64, np.float32)
    hl_list = []
    for r in range(8):
        for c in range(8):
            sq = cell_to_square(r, c, flipped)
            board[sq] = cls[r, c]
            sqprob[sq] = probs[r, c, cls[r, c]]  # prob of the class we report (may differ from argmax after fixes)
            if hl[r, c] > HIGHLIGHT_PROB:
                hl_list.append((sq, float(hl[r, c])))
    hl_list.sort(key=lambda t: -t[1])
    stm, src, last = side_to_move(board, hl_list)
    cast = castling_rights(board)
    ep = en_passant(board, last, stm)
    fen = f"{placement_fen(board)} {stm} {cast} {ep} 0 1"
    return ScanResult(
        found=True, fen=fen, corners=corners, detector_conf=conf, board=[CLASSES[k] for k in board],
        probs=sqprob, uncertain=[sq_name(s) for s in range(64) if sqprob[s] < UNCERTAIN_PROB],
        flipped=bool(flipped), flipped_prob=p_flip, side_to_move=stm, stm_source=src,
        last_move=(sq_name(last[0]), sq_name(last[1])) if last else None, castling=cast, ep=ep, warped=warped)
