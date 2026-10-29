"""How things look: the exit's stripes point at the door from both sides (the
view of an exit, straight on, is mirror-symmetric as they scroll); on the
automap, the player arrow points the way you face (8 directions), the green
entrance mark covers just the entrance's wall tile, and the walls around you
show even if you never looked at them."""
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

# ---- the entrance mark: exactly its tile (a tile is 8 x 4 screen pixels)
res = []
for seed in ('0420', '2468', '5555'):
    g = Game(seed=5, tag='lk3'); g.start(seed); g.run(20)
    d = g.map().index(3); ex, ey = d & 31, d >> 5
    g.poke(SYM['amap'], 1); g.place(g.m[0x83], g.m[0x85], 0); g.run(20)
    im = np.asarray(Image.open(g.shot('lk3.ppm')).convert('RGB')).astype(int)
    green = (im[:, :, 1] > im[:, :, 0] + 40) & (im[:, :, 1] > im[:, :, 2] + 40)
    ys, xs = np.nonzero(green[20:180]); ys = ys + 20
    x0, y0 = (16 + 4*ex) * 2 + 8, 4*ey + 32
    res.append((xs.min(), xs.max()+1, ys.min(), ys.max()+1) == (x0, x0+8, y0, y0+4))
    g.close()
check(all(res), f'the green entrance mark covers just the entrance tile (3 seeds): {res}')

# ---- the tiles around you count as seen when you step into them
g = Game(seed=5, tag='lk4'); g.start('0420'); g.run(20)
M = g.map(); S = g.m[0xBC00:0xC000]
t = next(i for i in range(1024) if M[i] == 0 and all(S[i+d] == 0 for d in (-33, -32, -31, -1, 0, 1, 31, 32, 33)))
g.place(t & 31, t >> 5, 0); g.run(10)
S = g.m[0xBC00:0xC000]
check(all(S[t+d] for d in (-33, -32, -31, -1, 0, 1, 31, 32, 33)), 'stepping into an unseen spot puts the 8 tiles around it on the automap')
g.close()
done()
