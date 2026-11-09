"""Sample realistic positions (with their last move) from a lichess CC0 PGN dump.

Output: JSON lines {"fen": ..., "last": [from_sq, to_sq] or null} where squares are 0..63 (a1=0).
"""
import argparse, io, json, random
import chess, chess.pgn, zstandard

ap = argparse.ArgumentParser()
ap.add_argument("pgn_zst")
ap.add_argument("out")
ap.add_argument("--games", type=int, default=20000)
ap.add_argument("--per-game", type=int, default=5)
args = ap.parse_args()

rng = random.Random(0)
n = 0
with open(args.pgn_zst, "rb") as fh, open(args.out, "w") as out:
    stream = io.TextIOWrapper(zstandard.ZstdDecompressor().stream_reader(fh), encoding="utf-8", errors="ignore")
    for g in range(args.games):
        game = chess.pgn.read_game(stream)
        if game is None:
            break
        moves = list(game.mainline_moves())
        if len(moves) < 2:
            continue
        plies = sorted(rng.sample(range(1, len(moves) + 1), min(args.per_game, len(moves))))
        board = game.board()
        last = None
        k = 0
        for i, mv in enumerate(moves, start=1):
            board.push(mv)
            if k < len(plies) and i == plies[k]:
                out.write(json.dumps({"fen": board.fen(), "last": [mv.from_square, mv.to_square]}) + "\n")
                n += 1
                k += 1
            if k >= len(plies):
                break
print("positions", n)
