"""Download training assets into ml/.cache: lichess piece sets + board textures, a CC0 PGN dump,
rasterise the SVG pieces, and sample positions."""
import os, subprocess, sys
ML = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
C = os.path.join(ML, ".cache")
PY = sys.executable
SKIP = {"disguised", "mono", "letter", "shapes", "kiwen-suwi"}


def sh(*a, **k):
    print("+", " ".join(a))
    subprocess.run(a, check=True, **k)


os.makedirs(C, exist_ok=True)
lila = os.path.join(C, "lila")
if not os.path.exists(lila):
    sh("git", "clone", "-q", "--depth", "1", "--filter=blob:none", "--sparse", "https://github.com/lichess-org/lila.git", lila)
    sh("git", "-C", lila, "sparse-checkout", "set", "--no-cone", "public/piece", "public/images/board", "/COPYING.md")
pgn = os.path.join(C, "lichess_2013-01.pgn.zst")
if not os.path.exists(pgn):
    sh("curl", "-sL", "-o", pgn, "https://database.lichess.org/standard/lichess_db_standard_rated_2013-01.pgn.zst")

from PIL import Image  # noqa: E402
src = os.path.join(lila, "public/piece")
dst = os.path.join(C, "pieces_png")
for name in sorted(os.listdir(src)):
    if name in SKIP:
        continue
    os.makedirs(os.path.join(dst, name), exist_ok=True)
    for f in os.listdir(os.path.join(src, name)):
        stem, ext = os.path.splitext(f)
        out = os.path.join(dst, name, stem + ".png")
        if os.path.exists(out):
            continue
        if ext == ".svg":
            sh("rsvg-convert", "-w", "192", "-h", "192", "--keep-aspect-ratio", os.path.join(src, name, f), "-o", out)
        else:
            Image.open(os.path.join(src, name, f)).convert("RGBA").resize((192, 192), Image.LANCZOS).save(out)

pos = os.path.join(C, "positions.jsonl")
if not os.path.exists(pos):
    sh(PY, os.path.join(ML, "scripts/extract_positions.py"), pgn, pos, "--games", "20000", "--per-game", "5")
print("assets ready in", C)
