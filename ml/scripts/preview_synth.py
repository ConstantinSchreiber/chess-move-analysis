import random, sys, time, os
import numpy as np, cv2
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from tempo_vision.synth import Assets, detector_sample, reader_sample
from tempo_vision import CLASSES

out = sys.argv[1]
os.makedirs(out, exist_ok=True)
t = time.time(); A = Assets(); print("assets", time.time() - t, len(A.sets), len(A.textures), len(A.positions))
rng = random.Random(int(sys.argv[2]) if len(sys.argv) > 2 else 1)
t = time.time()
tiles = []
for i in range(12):
    img, c = detector_sample(rng, A)
    img = img.copy()
    if c is not None:
        for k, (x, y) in enumerate(c):
            cv2.circle(img, (int(x), int(y)), 4, [(255,0,0),(0,255,0),(0,0,255),(255,255,0)][k], -1)
    tiles.append(img)
print("det/sample", (time.time() - t) / 12)
grid = np.vstack([np.hstack(tiles[i*4:(i+1)*4]) for i in range(3)])
cv2.imwrite(os.path.join(out, "det.jpg"), grid[..., ::-1])
t = time.time()
tiles = []
for i in range(8):
    w, cells, hl, fl = reader_sample(rng, A)
    w = w.copy()
    for r in range(8):
        for cc in range(8):
            if hl[r, cc]:
                cv2.rectangle(w, (cc*48+2, r*48+2), (cc*48+45, r*48+45), (255,0,255), 2)
    cv2.putText(w, "FLIP" if fl else "norm", (5, 380), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255,0,0), 2)
    tiles.append(w)
    if i == 0:
        print("\n".join("".join(CLASSES[k] if k else "." for k in row) for row in cells))
print("reader/sample", (time.time() - t) / 8)
grid = np.vstack([np.hstack(tiles[i*4:(i+1)*4]) for i in range(2)])
cv2.imwrite(os.path.join(out, "reader.jpg"), grid[..., ::-1])
