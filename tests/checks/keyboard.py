"""The controls.  The options screen (the main
menu's third row) picks the joystick or the keyboard; the game then reads
just that one, while the menus take both.  Keyboard: W / S walk, A / D turn,
Q / E strafe, SHIFT fires (also while walking); O music, M map either way.
The keyboard reports one key at a time; SHIFT reads on its own."""
import os, sys; sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'lib'))
from dod import *

SHIFT = 2                                 # (harness: trig 2 = SHIFT held)
g = Game(seed=5, tag='kb'); g.start('0420', keyboard=True); g.run(10)
M = g.map()
x, y = next((i & 31, i >> 5) for i in range(1024)
            if all(M[i+k] == 0 for k in range(-3, 4)) and M[i-32] == 0 and M[i+32] == 0)
def pos(): return (g.m[0x83] + g.m[0x82]/256, g.m[0x85] + g.m[0x84]/256, g.m[0x86] | g.m[0x87] << 8)
def hold(k):
    g.place(x, y, 0); g.run(5); p0 = pos(); g.run(30, key=ord(k)); g.run(2); return p0, pos()
(x0, y0, _), (x1, y1, a1) = hold('w'); check(x1 > x0 + 0.5 and y1 == y0, f'W walks forward (east): {x0:.2f} -> {x1:.2f}')
(x0, y0, _), (x1, y1, a1) = hold('s'); check(x1 < x0 - 0.5 and y1 == y0, f'S walks back: {x0:.2f} -> {x1:.2f}')
_, (_, _, aa) = hold('a'); _, (_, _, ad) = hold('d')
check(512 < aa < 1024 and 0 < ad < 512 and abs((1024 - aa) - ad) <= 16, f'A turns left, D right (angles {aa}, {ad})')
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

# ---- keyboard chosen: the joystick does nothing in the game
g = Game(seed=5, tag='kb3'); g.start('0420', keyboard=True); g.run(10)
g.place(x, y, 0); g.run(5); p0 = pos(); a0 = g.m[AMMOP]; g.run(30, stick=1); g.run(4, trig=1); g.run(20)
check(pos() == p0 and g.m[AMMOP] == a0, f'keyboard chosen: the stick and its button do nothing ({p0} -> {pos()})')
g.close()

# ---- joystick (the default): the movement keys and SHIFT do nothing in the game
g = Game(seed=5, tag='kb4'); g.start('0420'); g.run(10)
g.place(x, y, 0); g.run(5); p0 = pos(); a0 = g.m[AMMOP]
for k in 'wsadqe': g.run(15, key=ord(k))
g.run(4, trig=SHIFT); g.run(20)
check(pos() == p0 and g.m[AMMOP] == a0, f'joystick chosen: W/S/A/D/Q/E and SHIFT do nothing ({p0} -> {pos()})')
g.place(x, y, 0); g.run(5); p0 = pos(); g.run(30, stick=1); g.run(2)
check(pos()[0] > p0[0] + 0.5, 'and the stick walks')
m0 = g.v('muson'); g.run(4, key=ord('o')); g.run(4)
check(g.v('muson') == 1 - m0, 'O still switches the music')
g.close()

# ---- the options screen, from the menu: down twice, fire; right; fire back
dl = lambda g: g.m[0x230] | g.m[0x231] << 8
def lines(g):
    """The text (mode 2) lines on screen, read through the display list."""
    a, out = dl(g), []
    for _ in range(60):
        op = g.m[a]
        if op == 0x41: break
        if op & 15 >= 2 and op & 0x40:            # (a mode line with its address)
            lms = g.m[a+1] | g.m[a+2] << 8
            if op & 15 == 2:
                out.append(''.join(chr((c & 127) + 32) if (c & 127) < 64 else chr(c & 127) for c in g.m[lms:lms+40]).strip())
            a += 3
        elif op & 15 == 1: break
        else: a += 1
    return out
g = Game(seed=5, tag='kb5'); g.run(100)
mdl = dl(g)
check(lines(g)[:2] == ['START', 'OPTIONS'] and not any('DIGITS' in l for l in lines(g)),
      f'the main menu: just START and OPTIONS ({lines(g)})')
g.run(4, stick=2); g.run(4); g.run(4, stick=2); g.run(4)          # (down twice: stops at OPTIONS)
g.run(3, trig=1); g.run(10)
check(dl(g) != mdl and 'JOYSTICK' in g.screen_text() if hasattr(g, 'screen_text') else dl(g) != mdl,
      'fire on OPTIONS opens the options screen')
c0 = g.v('ctlm'); g.run(4, stick=8); g.run(6); c1 = g.v('ctlm'); g.run(4, key=ord('d')); g.run(6); c2 = g.v('ctlm')
check((c0, c1, c2) == (0, 1, 0), f'right (stick), then D (keyboard): joystick -> keyboard -> joystick ({c0}, {c1}, {c2})')
g.run(4, stick=4); g.run(6)
check(g.v('ctlm') == 1, 'left: keyboard')
check(any('W/S WALK' in l for l in lines(g)), f'the options screen describes the keyboard controls: {lines(g)}')
g.run(3, trig=1); g.run(10)
check(dl(g) == mdl, 'fire goes back to the menu')
check(any('WASD MOVE' in l for l in lines(g)), f"the menu's hint line shows the keyboard controls: {lines(g)}")
g.run(4, stick=1); g.run(4)                    # (up: START)
g.run(3, trig=1); g.run(10)
check(dl(g) == mdl and lines(g)[:4] == ['START WITH A RANDOM SEED', 'PLAY YOUR OWN SEED:  0000', 'BACK', ''],
      f'START: the seed page, no typing hint ({lines(g)[:4]})')
g.run(4, stick=2); g.run(4); g.run(4, stick=2); g.run(4); g.run(4, stick=2); g.run(4)
g.run(3, trig=1); g.run(10)
check(lines(g)[:2] == ['START', 'OPTIONS'], f'BACK: the main menu again ({lines(g)[:2]})')
for c in '1234': g.run(4, key=ord(c)); g.run(6)
check(lines(g)[1] == 'PLAY YOUR OWN SEED:  1234', f'typing a seed on the main menu: the seed page, your own seed ({lines(g)[:2]})')
g.run(4, stick=1); g.run(4)                    # (up: a random seed)
g.run(3, trig=1); g.run(130)
check(dl(g) != mdl and g.v('ctlnow') == 2, f'play: the game reads just the keyboard (ctlnow {g.v("ctlnow")})')
g.close()

# ---- the menu: SHIFT (START, then a random seed) starts a run
g = Game(seed=5, tag='kb2'); g.run(100)
g.run(3, trig=SHIFT); g.run(10); g.run(3, trig=SHIFT); g.run(130)
check((g.m[0x230] | g.m[0x231] << 8) >= 0x1A00, 'SHIFT on the menu starts a run (the game display list is up)')
g.close()
done()
