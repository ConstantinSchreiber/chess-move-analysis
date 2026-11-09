# Board recognition — Core ML contract & Swift porting guide

Source of truth for the Swift implementation. The Python reference is
[`tempo_vision/pipeline.py`](tempo_vision/pipeline.py) (+ [`decode.py`](tempo_vision/decode.py));
port it 1:1. Run `scripts/eval_real.py` to see what "correct" looks like on real images.

## Conventions

- **Continuous image coordinates.** Pixel `(i, j)` (row, col) covers `[j, j+1) × [i, i+1)`, origin
  top-left, y down. Board corners are points in this space (the board's outer edge, not square
  centres). CoreImage is y-up: `y_ci = imageHeight - y`.
- **Corner order** everywhere: `TL, TR, BR, BL` **in image space** (not chess space).
- **Squares**: a1 = 0 … h8 = 63. **Cells**: `(row, col)`, row 0 = top of the rectified board image.
- **Classes** (index → FEN char): `0 empty, 1 P, 2 N, 3 B, 4 R, 5 Q, 6 K, 7 p, 8 n, 9 b, 10 r, 11 q, 12 k`.
- Apply the photo's EXIF/UIImage orientation first (render to an upright CGImage).

## Models (`ios/Tempo/Resources/Models/`)

Both are ML Programs, fp16 weights/compute, minimum deployment iOS 17. Read the input size from
the model description (`imageConstraint.pixelsWide`) — don't hard-code 384.

### `BoardDetector.mlpackage`
| | name | type | notes |
|---|---|---|---|
| in | `image` | Image RGB, S×S (S = 384) | scale 1/255 baked in; letterboxed (below) |
| out | `heatmaps` | Float32 MultiArray `[1, 4, S/4, S/4]` | post-sigmoid; channel order TL, TR, BR, BL |

### `BoardReader.mlpackage`
| | name | type | notes |
|---|---|---|---|
| in | `image` | Image RGB, R×R (R = 384) | board rectified corner-to-corner |
| out | `pieces` | Float32 `[1, 8, 8, 13]` | softmax over the last axis; `[0, row, col, class]` |
| out | `highlight` | Float32 `[1, 8, 8]` | sigmoid; square tinted as last-move highlight |
| out | `flipped` | Float32 `[1]` | sigmoid; P(board shown from Black's side, h1 top-left) |

Flat index into `pieces`: `((row * 8) + col) * 13 + class` (check `strides` if you use the raw pointer).

## Pipeline (constants in `pipeline.py`)

1. **Letterbox** the upright image `w × h` into S×S:
   `scale = S / max(w, h)`, `nw = round(w * scale)`, `nh = round(h * scale)`,
   `ox = floor((S - nw) / 2)`, `oy = floor((S - nh) / 2)`; draw the resized image at `(ox, oy)` on a
   black canvas (area/high-quality downscale). Forward map: `x' = x * nw / w + ox`, `y' = y * nh / h + oy`.
2. **Detect** → `heatmaps`, then pick the corners with `decode_quad()` (geometry-aware; plain
   per-channel argmax picks e.g. the bottom of a move list under a phone-width board):
   - **Candidates** per channel `c`: 3×3 local maxima (`h[i,j] ≥` all 8 neighbours, out-of-bounds
     neighbours count as −1) with value `≥ PEAK_MIN (0.1)`; keep the top `PEAKS_PER_CORNER (4)` by value
     (ties: row-major order). If a channel has none → fall back to plain argmax for all four.
   - **Sub-cell refinement** of each candidate with a parabola through the logs (exact for Gaussians),
     `EPS = 1e-6`: `off(a, b, c) = 0.5 * (ln a − ln c) / (ln a − 2 ln b + ln c)` using `max(v, EPS)`;
     0 if the denominator ≥ −1e-9; clamp to [−0.5, 0.5]. `dx = off(h[i, j−1], h[i, j], h[i, j+1])`
     (0 at the border), `dy` likewise along rows. Point in letterbox px:
     `x' = (j + dx + 0.5) * 4`, `y' = (i + dy + 0.5) * 4`.
   - **Choose** the combination (≤ 4⁴ = 256) that is a convex clockwise quad (all four consecutive
     `cross(b − a, c − b) > 0`, y-down) maximising
     `Σ ln(max(v, EPS)) − GEO_WEIGHT (1.5) * shape`, where with side lengths top, right, bottom, left:
     `shape = |ln(top/bottom)| + |ln(left/right)| + |ln((top+bottom)/(left+right))|`.
     No convex combination → plain argmax per channel.
   - Back to image px: `x = (x' − ox) * w / nw`, `y = (y' − oy) * h / nh`.
   - `conf = min of the 4 chosen peak values`.
3. **Reject** if `conf < DETECT_MIN_CONF (0.25)` or the quad fails `quad_ok`: all four
   `cross((b − a), (d − b)) > 0` for consecutive corners (convex, clockwise in y-down coords),
   shortest side > 16 px, longest/shortest side < 4. → "No board found".
4. **Zoom pass** (improves precision for small boards):
   `side = ZOOM_EXPAND (1.25) * max(bbox_w, bbox_h)` of the quad; centre = mean of the 4 corners;
   `x0 = round(cx − side/2)`, `y0 = round(cy − side/2)`, `sd = max(8, round(side))`.
   Crop the `sd × sd` square at `(x0, y0)` (outside the image = black), run steps 1–2 on the crop
   (square ⇒ `ox = oy = 0`), add `(x0, y0)` back. Accept if `conf2 ≥ ZOOM_MIN_CONF_RATIO (0.6) * conf`
   and `quad_ok`; then `conf = max(conf, conf2)`.
5. **Rectify** to R×R. `side = mean of the 4 side lengths`. If `side > PREDOWNSCALE_FACTOR (2.0) * R`,
   first downscale the whole image by `f = 1.5 * R / side` (area/Lanczos) and scale the corners by `f`.
   Then a bilinear perspective warp mapping the corners to `(0,0), (R,0), (R,R), (0,R)` (continuous
   coords; with OpenCV: subtract 0.5 from both point sets). `CIPerspectiveCorrection` followed by a
   resize to exactly R×R is fine — the reader was trained with ±2 % corner jitter and mixed interpolation.
6. **Read** → `pieces`, `highlight`, `flipped`. Per cell `cls = argmax`.
7. **Kings**: if a colour has >1 king, keep the one with the highest king prob and give the others
   their best non-king class. If a colour has none, promote the cell with the highest king prob when
   that prob > `KING_MIN_PROB (0.2)` (and the cell isn't a king of the other colour).
8. **Back-rank pawns**: rows 0 and 7 are rank 1/8 in either orientation → any pawn there gets its
   best non-pawn class.
9. **Orientation**: `p = flipped`. If `|p − 0.5| > FLIP_CONFIDENT (0.25)` → `flipped = p > 0.5`.
   Else `logit = ln(p/(1−p)) − LAYOUT_WEIGHT (1.2) * layout`, `flipped = logit > 0`, where
   `layout = (mean row of white pieces − mean row of black pieces) / 2` (0 if a colour is absent).
10. **Cells → squares**: unflipped `sq = (7 − row) * 8 + col`; flipped `sq = row * 8 + (7 − col)`.
11. **Uncertain squares**: `p = pieces[row, col, cls]` (prob of the class finally reported, after
    steps 7–8) `< UNCERTAIN_PROB (0.85)` → outline them in the confirm UI.
12. **Side to move** (`side_to_move()`): highlighted squares = `highlight > HIGHLIGHT_PROB (0.5)`,
    sorted by prob, keep the top 2.
    - exactly one of the two is occupied ⇒ that piece's colour just moved; last move = (empty → occupied);
    - both occupied by the same colour (castling shown as king+rook) ⇒ that colour just moved;
    - a single highlighted square, occupied ⇒ that colour just moved.
    Side to move = the other colour (source `highlight`) — unless that leaves the side that just moved
    in check while the other king is safe; then swap (source `check`).
    No usable highlight: the king in check moves (source `check`); otherwise White (source `default`,
    show "check who is to move").
13. **Castling**: `K` if white K on e1 and R on h1, `Q` if K e1 and R a1; same for black (e8/h8/a8).
    **En passant**: if the detected last move is a pawn double step of the mover, ep = the skipped square.
14. **FEN** = placement + side + castling + ep + `0 1`.

## Re-reading with user-adjusted corners
If the UI lets the user drag the 4 corners, skip steps 1–4 and run 5–14 with those corners
(`scan(..., corners=quad)` in Python).

## Training data facts the app relies on
- Top-left square is light in ~98 % of training boards (true for every real board).
- Coordinates, highlights (yellow/green/blue/outline), arrows, move dots, check glow, premove tints
  and drop shadows are all in the training set, so they don't need to be removed before reading.
