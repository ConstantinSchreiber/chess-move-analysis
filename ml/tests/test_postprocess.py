"""Post-processing unit tests (run: .venv/bin/python -m pytest tests -q, or python tests/test_postprocess.py)."""
import os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from tempo_vision import CLASSES
from tempo_vision.pipeline import (side_to_move, castling_rights, en_passant, placement_fen, fix_kings,
                                   fix_back_rank_pawns, decide_flipped, cell_to_square)
from tempo_vision.synth import parse_placement, sq_to_cell
import chess


def sq(n):
    return chess.parse_square(n)


def test_cell_mapping_roundtrip():
    for flipped in (False, True):
        for s in range(64):
            r, c = sq_to_cell(s, flipped)
            assert cell_to_square(r, c, flipped) == s


def test_stm_from_highlight():
    b = parse_placement("rn1qkb1r/ppp1pppp/5n2/3p2B1/3P4/1P3b2/P1P1PPPP/RN1QKB1R")
    stm, src, last = side_to_move(b, [(sq("f3"), 0.95), (sq("g4"), 0.9)])
    assert (stm, src, last) == ("w", "highlight", (sq("g4"), sq("f3")))


def test_stm_check_fallback():
    # black king on e8 attacked by a white rook on e1, no highlight -> black to move
    b = parse_placement("4k3/8/8/8/8/8/8/K3R3")
    assert side_to_move(b, [])[:2] == ("b", "check")
    assert side_to_move(parse_placement("4k3/8/8/8/8/8/8/K7"), [])[:2] == ("w", "default")


def test_stm_highlight_contradicted_by_check():
    # highlight says white just moved (white piece on to-square) but white's own king is in check -> white to move
    b = parse_placement("4r1k1/8/8/8/8/8/3N4/4K3")
    stm, src, _ = side_to_move(b, [(sq("d2"), 0.9), (sq("b1"), 0.8)])
    assert (stm, src) == ("w", "check")


def test_castling_and_ep():
    b = parse_placement("r3k2r/8/8/8/4P3/8/8/R3K2R")
    assert castling_rights(b) == "KQkq"
    assert en_passant(b, (sq("e2"), sq("e4")), "b") == "e3"
    assert en_passant(b, (sq("e3"), sq("e4")), "b") == "-"


def test_fix_kings_and_pawns():
    probs = np.full((8, 8, 13), 0.001, np.float32)
    probs[..., 0] = 0.9
    probs[0, 0, 6] = 0.95; probs[0, 0, 0] = 0.0   # two white kings
    probs[3, 3, 6] = 0.6; probs[3, 3, 5] = 0.39; probs[3, 3, 0] = 0.0
    probs[7, 4, 7] = 0.7; probs[7, 4, 10] = 0.29; probs[7, 4, 0] = 0.0  # pawn on back rank -> rook
    cls = probs.argmax(-1)
    cls = fix_back_rank_pawns(fix_kings(cls, probs), probs)
    assert cls[0, 0] == 6 and cls[3, 3] == 5 and cls[7, 4] == 10


def test_orientation_layout():
    start = np.zeros((8, 8), int)
    b = parse_placement("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR")
    for s in range(64):
        r, c = sq_to_cell(s, True)
        start[r, c] = b[s]
    assert decide_flipped(0.5, start) is True or decide_flipped(0.5, start) == True


if __name__ == "__main__":
    for k, v in list(globals().items()):
        if k.startswith("test_"):
            v()
            print("ok", k)
