"""Speed benchmark: 100 fixed views on two seeds, monsters frozen, god mode.
Prints the mean frame rate and the worst and best views.

    python3 tests/tools/bench.py              (builds tests/.work/frozen.car)
    python3 tests/tools/bench.py OTHER.car    (a cart built with -D E_SPEED=0 -D BENCH)

Reference (NTSC, emulated): 14.2 fps mean, worst 7.5, best 20.0 at v1.0-osram;
10.2 / 6.0 / 13.5 before the OS-RAM rework."""
import os, sys; sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'lib'))
from dod import *
car = sys.argv[1] if len(sys.argv) > 1 else None
if not car: build(); car = build_variant('frozen', 'E_SPEED=0', 'BENCH')
res = []
for seed in ('0420', '1111'):
    g = Game(seed=5, car=car, tag='bn'); g.start(seed); g.run(4, key=ord('g')); g.run(5)
    M = g.map(); opens = [i for i in range(1024) if M[i] == 0][::23][:10]
    for t in opens:
        for ang in (0, 256, 512, 768, 128):
            g.place(t & 31, t >> 5, ang); g.run(10)
            f0 = g.m[FCOUNT]; g.run(120); res.append(((g.m[FCOUNT]-f0) % 256)/2)
    g.close()
print(f'{os.path.basename(car)}: mean {sum(res)/len(res):.2f} fps over {len(res)} views, worst {min(res)}, best {max(res)}')
