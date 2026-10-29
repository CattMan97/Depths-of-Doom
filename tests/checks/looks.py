"""How things look: the exit's stripes point at the door from both sides (the
view of an exit, straight on, is mirror-symmetric as they scroll), and the
automap's player arrow points the way you face (8 directions)."""
import os, sys; sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'lib'))
from dod import *
from PIL import Image
import numpy as np

DIRS = {0: (1, 0), 256: (0, 1), 512: (-1, 0), 768: (0, -1)}   # (256 = south: y grows down)

# ---- exit stripes: one seed for each way an exit can face
for seed in ('2468', '0076', '5555', '3141'):
    g = Game(seed=5, tag='lk'); g.start(seed); g.run(4, key=ord('g')); g.run(5)
    nx, ny, ang = g.exit_approach()
    dx, dy = DIRS[ang]; sx, sy = -dy, dx
    for k in range(4):                 # open floor in front of the door, so both sides show
        for j in range(-2, 3):
            x, y = nx - dx*k + sx*j, ny - dy*k + sy*j
            if 1 <= x <= 30 and 1 <= y <= 30: g.poke(0xC00 + y*32 + x, 0)
    g.place(nx - dx*3, ny - dy*3, ang); g.run(25)
    worst = 0
    for f in range(3):                 # (three moments: the scroll keeps it symmetric)
        a = np.asarray(Image.open(g.shot('lk.ppm')).convert('L')).astype(int)[34:100]
        worst = max(worst, min(np.abs(a[:, c-150:c] - a[:, c+150:c:-1]).mean() for c in range(160, 176)))
        g.run(3)
    check(worst < 9, f'seed {seed}, exit seen facing {ang}: the stripes mirror each other (difference {worst:.1f}; '
                     f'one-way stripes give 11+)')
    g.close()

# ---- the automap arrow
ARROWS = [["..#..", "...#.", "#####", "...#.", "..#.."], ["#....", ".#...", "..#.#", "...##", "..###"],
          ["..#..", "..#..", "#.#.#", ".###.", "..#.."], ["....#", "...#.", "#.#..", "##...", "###.."],
          ["..#..", ".#...", "#####", ".#...", "..#.."], ["###..", "##...", "#.#..", "...#.", "....#"],
          ["..#..", ".###.", "#.#.#", "..#..", "..#.."], ["..###", "...##", "..#.#", ".#...", "#...."]]
g = Game(seed=5, tag='lk2'); g.start('0420'); g.run(20)
M = g.map()
x, y = next((i & 31, i >> 5) for i in range(1024)
            if 8 < (i & 31) < 24 and 8 < (i >> 5) < 24 and all(M[i+d] == 0 for d in (0, 1, -1, 32, -32)))
g.poke(SYM['amap'], 1)
ok = []
for k in range(8):
    g.place(x, y, k * 128); g.run(20)
    im = np.asarray(Image.open(g.shot('lk2.ppm')).convert('RGB')).astype(int)
    white = (im.min(axis=2) > 150)     # (the arrow is the map's white; walls are red)
    cx, cy = (16 + 4*x + 2) * 2 + 8, (2*y + 1) * 2 + 32
    want = np.array([[c == '#' for c in r] for r in ARROWS[k]])
    found = False
    for ox in range(-8, 9):            # (find the arrow's pixel grid near where you are)
        for oy in range(-8, 9):
            got = np.array([[white[cy + oy + 2*r, cx + ox + 2*c] for c in range(5)] for r in range(5)])
            if (got == want).all(): found = True
    ok.append(found)
check(all(ok), f'automap arrow for each of 8 facings (E, SE, S, SW, W, NW, N, NE): {ok}')
g.close()
done()
