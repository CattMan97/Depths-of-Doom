"""6502 profile: where the cycles go while walking a set route (seed 0420),
by routine (the nearest label below each PC).

    python3 tests/tools/profile.py            (profiles a fresh BENCH build)

Builds tests/.work/prof.car with labels, runs the route in the harness with
the profiler on (the H script flag), and prints the top 40."""
import os, sys, struct, re, collections, bisect, subprocess
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'lib'))
from dod import *
build(); car = build_variant('prof', 'BENCH', labels=True)
steps = ['100,0,0'] + [f'4,0,0,K,{ord(c)} 6,0,0' for c in '0420'] + ['3,0,1', '300,0,0', '3,0,1', '60,0,0', '1,0,0,H']
pat = [(50, 1), (12, 4), (40, 1), (20, 8), (60, 1), (8, 4), (30, 1), (25, 8), (45, 1), (15, 4)]
for rep in range(8):
    for f, st in pat: steps.append(f'{f},{st},0')
r = subprocess.run([HARNESS, car, os.path.join(WORK, 'pp'), ' '.join(steps)], capture_output=True, text=True, cwd=WORK)
print(r.stdout.strip())
h = struct.unpack('65536I', open(os.path.join(WORK, 'pchist.bin'), 'rb').read())
labs = sorted((int(m.group(1), 16), m.group(2)) for l in open(os.path.join(WORK, 'prof.labels'))
              for m in [re.match(r'al ([0-9A-F]+) \.(\S+)', l)] if m and not m.group(2).startswith(('@', '__')))
keys = [a for a, _ in labs]; tot = collections.Counter(); T = sum(h)
for pc in range(65536):
    if h[pc]:
        i = bisect.bisect_right(keys, pc) - 1
        n = labs[i][1] if i >= 0 and pc - keys[i] < 2048 else f'?{pc:04X}'
        if 0x0500 <= pc < 0x0800: n = 'colwriters($0500)'
        tot[n] += h[pc]
print('total cycles', T)
for n, c in tot.most_common(40): print(f'{n:22s} {100*c/T:5.1f}%')
