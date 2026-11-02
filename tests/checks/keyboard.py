"""The keyboard controls (keyboard-controls branch): W / S walk, A / D turn,
Q / E strafe, SHIFT fires (also while walking), O music, M map.  The
keyboard reports one key at a time; SHIFT reads on its own."""
import os, sys; sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'lib'))
from dod import *

SHIFT = 2                                 # (harness: trig 2 = SHIFT held)
g = Game(seed=5, tag='kb'); g.start('0420'); g.run(10)
M = g.map()
x, y = next((i & 31, i >> 5) for i in range(1024)
            if all(M[i+k] == 0 for k in range(-3, 4)) and M[i-32] == 0 and M[i+32] == 0)
def pos(): return (g.m[0x83] + g.m[0x82]/256, g.m[0x85] + g.m[0x84]/256, g.m[0x86] | g.m[0x87] << 8)
def hold(k):
    g.place(x, y, 0); g.run(5); p0 = pos(); g.run(30, key=ord(k)); g.run(2); return p0, pos()
(x0, y0, _), (x1, y1, a1) = hold('w'); check(x1 > x0 + 0.5 and y1 == y0, f'W walks forward (east): {x0:.2f} -> {x1:.2f}')
(x0, y0, _), (x1, y1, a1) = hold('s'); check(x1 < x0 - 0.5 and y1 == y0, f'S walks back: {x0:.2f} -> {x1:.2f}')
_, (_, _, aa) = hold('a'); _, (_, _, ad) = hold('d')
check(512 < aa < 1024 and 0 < ad < 512 and abs((1024 - aa) - ad) <= 8, f'A turns left, D right (angles {aa}, {ad})')
(x0, y0, _), (x1, y1, a1) = hold('q'); check(y1 < y0 - 0.5 and x1 == x0 and a1 == 0, f'Q strafes left (north, facing east): y {y0:.2f} -> {y1:.2f}')
(x0, y0, _), (x1, y1, a1) = hold('e'); check(y1 > y0 + 0.5 and x1 == x0 and a1 == 0, f'E strafes right (south): y {y0:.2f} -> {y1:.2f}')
g.place(x, y, 0); g.run(5); a0 = g.m[AMMOP]; g.run(2, trig=SHIFT); g.run(20)
check(g.m[AMMOP] == a0 - 1, f'SHIFT fires: ammo {a0} -> {g.m[AMMOP]}')
g.place(x, y, 0); g.run(5); a0 = g.m[AMMOP]; p0 = pos(); g.run(10, trig=SHIFT, key=ord('w')); g.run(20)
check(g.m[AMMOP] == a0 - 1 and pos()[0] > p0[0], f'SHIFT fires while W walks: ammo {a0} -> {g.m[AMMOP]}, x {p0[0]:.2f} -> {pos()[0]:.2f}')
m0 = g.v('muson'); g.run(4, key=ord('o')); g.run(4)
check(g.v('muson') == 1 - m0, f'O switches the music ({m0} -> {g.v("muson")})')
g.run(4, key=ord('m')); g.run(20); check(g.v('amap') == 1, 'M opens the automap')
g.run(4, key=ord('m')); g.run(20); check(g.v('amap') == 0, 'M closes it')
g.close()

# ---- the menu: SHIFT starts a run
g = Game(seed=5, tag='kb2'); g.run(100)
g.run(3, trig=SHIFT); g.run(130)
check((g.m[0x230] | g.m[0x231] << 8) >= 0x1A00, 'SHIFT on the menu starts a run (the game display list is up)')
g.close()
done()
