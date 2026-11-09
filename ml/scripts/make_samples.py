"""Render the two in-app "Try a sample image" pictures.

Only cburnett pieces (BSD/GPL) and Pillow's bundled CC0 font (Aileron) are used, on an app-neutral UI.
"""
import json, math, os, random, sys
import chess
import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from tempo_vision.synth import Assets, parse_placement, moire

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))), "ios/Tempo/Resources/Samples")


def font(size):
    return ImageFont.load_default(size=size)


def play(moves):
    b = chess.Board()
    last = None
    for san in moves.split():
        m = b.parse_san(san)
        last = (m.from_square, m.to_square)
        b.push(m)
    return b, last


def board_img(rng, A, n, b, last, light, dark, flipped=False):
    """Deterministic board: fixed colours, cburnett, last-move tint, coordinates."""
    placement = parse_placement(b.fen())
    img = np.zeros((n, n, 3), np.uint8)
    edges = [int(round(i * n / 8)) for i in range(9)]
    for r in range(8):
        for c in range(8):
            img[edges[r]:edges[r + 1], edges[c]:edges[c + 1]] = light if (r + c) % 2 == 0 else dark
    tint = np.array([246, 226, 120], np.float32)
    for sq in last:
        f, rk = sq % 8, sq // 8
        r, c = (rk, 7 - f) if flipped else (7 - rk, f)
        roi = img[edges[r]:edges[r + 1], edges[c]:edges[c + 1]].astype(np.float32)
        img[edges[r]:edges[r + 1], edges[c]:edges[c + 1]] = (roi * 0.45 + tint * 0.55).astype(np.uint8)
    pil = Image.fromarray(img)
    d = ImageDraw.Draw(pil)
    fz = font(int(n / 8 * 0.2))
    for r in range(8):
        col = dark if r % 2 == 0 else light
        d.text((edges[0] + n / 8 * 0.06, edges[r] + n / 8 * 0.04), str(8 - r), fill=tuple(int(v) for v in col), font=fz)
    for c in range(8):
        col = dark if (7 + c) % 2 == 0 else light
        d.text((edges[c + 1] - n / 8 * 0.2, edges[8] - n / 8 * 0.26), "abcdefgh"[c], fill=tuple(int(v) for v in col), font=fz)
    img = np.asarray(pil).copy()
    pieces = A.sets["cburnett"]
    ps = int(n / 8 * 0.9)
    cache = {}
    for r in range(8):
        for c in range(8):
            sq = (7 - r) * 8 + c
            k = int(placement[sq])
            if not k:
                continue
            if k not in cache:
                cache[k] = cv2.resize(pieces[k], (ps, ps), interpolation=cv2.INTER_AREA)
            p = cache[k]
            x = int((edges[c] + edges[c + 1]) / 2 - ps / 2)
            y = int((edges[r] + edges[r + 1]) / 2 - ps / 2)
            a = p[..., 3:4] / 255.0
            roi = img[y:y + ps, x:x + ps].astype(np.float32)
            img[y:y + ps, x:x + ps] = (roi * (1 - a) + p[..., :3] * a).astype(np.uint8)
    return img


def rounded(d, box, r, fill):
    d.rounded_rectangle(box, radius=r, fill=fill)


def phone_screenshot(A, b, last):
    W, H = 1179, 2556
    bg = (18, 19, 24)
    pil = Image.new("RGB", (W, H), bg)
    d = ImageDraw.Draw(pil)
    d.text((90, 52), "9:41", fill=(240, 240, 240), font=font(46))
    d.text((60, 190), "Rapid · 10 min", fill=(150, 150, 160), font=font(40))
    d.text((60, 240), "Casual game", fill=(245, 245, 245), font=font(64))
    # opponent row
    d.ellipse((60, 420, 160, 520), fill=(90, 70, 140))
    d.text((190, 430), "Opponent", fill=(240, 240, 240), font=font(46))
    d.text((190, 482), "1712", fill=(140, 140, 150), font=font(36))
    rounded(d, (W - 280, 430, W - 60, 510), 18, (40, 42, 50))
    d.text((W - 250, 445), "4:21", fill=(240, 240, 240), font=font(48))
    n = W
    y0 = 560
    board = board_img(None, A, n, b, last, np.array([238, 220, 190]), np.array([168, 122, 90]))
    img = np.asarray(pil).copy()
    img[y0:y0 + n, 0:n] = board
    pil = Image.fromarray(img)
    d = ImageDraw.Draw(pil)
    yb = y0 + n + 40
    d.ellipse((60, yb, 160, yb + 100), fill=(60, 120, 160))
    d.text((190, yb + 10), "You", fill=(240, 240, 240), font=font(46))
    d.text((190, yb + 62), "1688", fill=(140, 140, 150), font=font(36))
    rounded(d, (W - 280, yb + 10, W - 60, yb + 90), 18, (230, 230, 235))
    d.text((W - 250, yb + 25), "3:57", fill=(20, 20, 24), font=font(48))
    # move list
    yl = yb + 170
    rounded(d, (40, yl, W - 40, yl + 300), 28, (28, 29, 36))
    moves = []
    tmp = chess.Board()
    for m in b.move_stack:
        moves.append(tmp.san(m))
        tmp.push(m)
    x, y = 80, yl + 40
    for i in range(0, len(moves), 2):
        t = f"{i // 2 + 1}. {moves[i]} {moves[i + 1] if i + 1 < len(moves) else ''}"
        w = d.textlength(t, font=font(38)) + 40
        if x + w > W - 80:
            x, y = 80, y + 60
        d.text((x, y), t, fill=(200, 200, 210), font=font(38))
        x += w
    # bottom bar
    yb2 = H - 260
    for i, label in enumerate(["Resign", "Draw", "Chat", "Menu"]):
        cx = 60 + i * (W - 120) / 4
        rounded(d, (cx + 10, yb2, cx + (W - 120) / 4 - 10, yb2 + 120), 26, (34, 36, 44))
        d.text((cx + 40, yb2 + 38), label, fill=(220, 220, 228), font=font(40))
    corners = np.array([[0, y0], [n, y0], [n, y0 + n], [0, y0 + n]], np.float32)
    return np.asarray(pil), corners


def desktop_screen(A, b, last):
    W, H = 1600, 1000
    pil = Image.new("RGB", (W, H), (44, 46, 52))
    d = ImageDraw.Draw(pil)
    rounded(d, (0, 0, W, 64), 0, (30, 31, 36))
    d.text((30, 14), "Analysis", fill=(230, 230, 235), font=font(32))
    n = 840
    x0, y0 = 120, 110
    board = board_img(None, A, n, b, last, np.array([226, 230, 233]), np.array([128, 150, 165]))
    img = np.asarray(pil).copy()
    img[y0:y0 + n, x0:x0 + n] = board
    pil = Image.fromarray(img)
    d = ImageDraw.Draw(pil)
    rounded(d, (1020, 110, 1560, 950), 16, (32, 33, 38))
    tmp = chess.Board()
    y = 140
    ms = []
    for m in b.move_stack:
        ms.append(tmp.san(m))
        tmp.push(m)
    for i in range(0, len(ms), 2):
        d.text((1050, y), f"{i // 2 + 1}.", fill=(140, 140, 150), font=font(28))
        d.text((1120, y), ms[i], fill=(230, 230, 235), font=font(28))
        if i + 1 < len(ms):
            d.text((1300, y), ms[i + 1], fill=(230, 230, 235), font=font(28))
        y += 46
    corners = np.array([[x0, y0], [x0 + n, y0], [x0 + n, y0 + n], [x0, y0 + n]], np.float32)
    return np.asarray(pil), corners


def photo_of(screen, corners, seed=11):
    rng = random.Random(seed)
    h, w = screen.shape[:2]
    bz = 34
    framed = np.full((h + 2 * bz, w + 2 * bz, 3), 16, np.uint8)
    framed[bz:bz + h, bz:bz + w] = screen
    corners = corners + bz
    h, w = framed.shape[:2]
    PW, PH = 1536, 2048
    src = np.array([[0, 0], [w, 0], [w, h], [0, h]], np.float32)
    dst = np.array([[-20, 560], [1600, 500], [1555, 1580], [10, 1540]], np.float32)
    M = cv2.getPerspectiveTransform(src - 0.5, dst - 0.5)
    warped = cv2.warpPerspective(framed, M, (PW, PH), flags=cv2.INTER_LINEAR)
    mask = cv2.warpPerspective(np.ones((h, w), np.float32), M, (PW, PH))
    yy = np.linspace(0, 1, PH, dtype=np.float32)[:, None, None]
    bg = (np.array([62, 52, 44], np.float32) * (1 - yy) + np.array([28, 24, 22], np.float32) * yy)
    bg = np.broadcast_to(bg, (PH, PW, 3))
    img = bg * (1 - mask[..., None]) + warped.astype(np.float32) * mask[..., None] * np.array([1.0, 0.98, 0.93])
    img = np.clip(img, 0, 255).astype(np.uint8)
    img = moire(rng, img)
    yy, xx = np.mgrid[0:PH, 0:PW].astype(np.float32)
    a = np.exp(-((xx - 1150) ** 2 + (yy - 700) ** 2) / (2 * 520 ** 2)) * 0.18
    img = np.clip(img * (1 - a[..., None]) + 255 * a[..., None], 0, 255).astype(np.uint8)
    img = cv2.GaussianBlur(img, (0, 0), 0.9)
    noise = np.random.default_rng(seed).normal(0, 3.5, img.shape)
    img = np.clip(img.astype(np.float32) + noise, 0, 255).astype(np.uint8)
    bc = cv2.perspectiveTransform(corners[None] - 0.5, M)[0] + 0.5
    return img, bc


def main():
    os.makedirs(OUT, exist_ok=True)
    A = Assets(positions=False)
    samples = []
    b1, last1 = play("e4 e5 Nf3 Nc6 Bc4 Bc5 c3 Nf6 d4 exd4 cxd4 Bb4+ Nc3 Nxe4 O-O Bxc3 d5")
    shot, c1 = phone_screenshot(A, b1, last1)
    Image.fromarray(shot).save(os.path.join(OUT, "sample-screenshot.jpg"), quality=90)
    samples.append(dict(file="sample-screenshot.jpg", fen=b1.fen(), kind="screenshot",
                        title="Screenshot", corners=c1.round(1).tolist(),
                        last_move=[chess.square_name(last1[0]), chess.square_name(last1[1])]))
    b2, last2 = play("d4 d5 c4 e6 Nc3 Nf6 Bg5 Be7 e3 O-O Nf3 Nbd7 Rc1 c6 Bd3 dxc4 Bxc4 Nd5")
    screen, c2 = desktop_screen(A, b2, last2)
    photo, pc = photo_of(screen, c2)
    Image.fromarray(photo).save(os.path.join(OUT, "sample-photo.jpg"), quality=88)
    samples.append(dict(file="sample-photo.jpg", fen=b2.fen(), kind="photo", title="Photo of a screen",
                        corners=pc.round(1).tolist(), last_move=[chess.square_name(last2[0]), chess.square_name(last2[1])]))
    json.dump(dict(samples=samples, note="Rendered with cburnett pieces (BSD/GPL, Colin M.L. Burnett) and Pillow's "
                   "bundled Aileron font (CC0). Corners: TL,TR,BR,BL in image pixels."),
              open(os.path.join(OUT, "samples.json"), "w"), indent=1)
    print(json.dumps(samples, indent=1))


if __name__ == "__main__":
    main()
