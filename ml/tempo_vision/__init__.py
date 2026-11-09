"""Tempo board-recognition: synthetic data, models, and the reference inference pipeline."""

CLASSES = ["empty", "P", "N", "B", "R", "Q", "K", "p", "n", "b", "r", "q", "k"]
CLASS_INDEX = {c: i for i, c in enumerate(CLASSES)}
# file names of the rasterized piece PNGs, indexed by class (1..12)
PIECE_CODES = [None, "wP", "wN", "wB", "wR", "wQ", "wK", "bP", "bN", "bB", "bR", "bQ", "bK"]

DETECTOR_SIZE = 384
DETECTOR_STRIDE = 4
READER_SIZE = 384
