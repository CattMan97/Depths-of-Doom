"""Render the same 32 views with two carts and compare the pictures (the 3D
view only).  Use it to check that an optimisation changes nothing visible.

    python3 tests/tools/compare.py OLD.car NEW.car

Build both with -D E_SPEED=0 -D BENCH (frozen monsters), e.g. with
dod.build_variant(); git stash / git worktree gives you the old source."""
import os, sys; sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'lib'))
from dod import *
from PIL import Image, ImageChops
def views(car, tag):
    out = []
    g = Game(seed=5, car=car, tag=tag); g.start('0420'); g.run(4, key=ord('g')); g.run(5)
    M = g.map(); opens = [i for i in range(1024) if M[i] == 0][::37][:8]
    for t in opens:
        for ang in (0, 300, 640, 900):
            g.place(t & 31, t >> 5, ang); g.run(40); out.append(g.shot(f'{tag}_{t}_{ang}.ppm'))
    g.close(); return out
a = views(sys.argv[1], 'cva'); b = views(sys.argv[2], 'cvb'); bad = 0
for x, y in zip(a, b):
    d = ImageChops.difference(Image.open(x).crop((0, 30, 336, 159)), Image.open(y).crop((0, 30, 336, 159))).getbbox()
    if d: bad += 1; print('differs', os.path.basename(x), d)
print(f'{len(a)} views, {bad} differ')
sys.exit(1 if bad else 0)
