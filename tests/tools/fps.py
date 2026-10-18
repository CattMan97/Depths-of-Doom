"""Frame rate while walking about on three seeds (monsters live).

    python3 tests/tools/fps.py [CART.car]"""
import os, sys; sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'lib'))
from dod import *
car = sys.argv[1] if len(sys.argv) > 1 else None
for seed in ('0420', '1111', '2468'):
    g = Game(seed=5, car=car, tag='fps'); g.start(seed)
    f0 = g.m[FCOUNT]; tot = 0
    for k in range(12):
        g.run(60, stick=[1, 9, 5, 8, 1, 1][k % 6]); f1 = g.m[FCOUNT]; tot += (f1-f0) % 256; f0 = f1
    print(seed, f'{tot/12:.1f} fps'); g.close()
