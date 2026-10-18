"""The machine level: code kept in the stack page survives play, RESET
restarts the game, and the cartridge copes with different memory sizes.

Stack page layout: $0100-$0177 tunvbi (its variables at $0173-$0176),
$0178-$01C9 keydrop, $01CA-$01DF the RESET stub; the stack itself must stay
at $01E0 and above."""
import os, sys; sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'lib'))
from dod import *

def dlist(g): return g.m[0x230] | g.m[0x231] << 8
def screen_text(m, s):
    """Is s on screen anywhere in RAM (as screen codes)?"""
    codes = bytes((ord(c) - 32) & 127 for c in s)
    return codes in m

# ---- the stack page: a long session leaves the code in it alone
g = Game(seed=5, tag='sy'); g.start('0420'); before = bytes(g.m[0x100:0x1E0])
for lv in range(4): g.finish_level()
for i in range(60): g.run(10, stick=[1, 4, 1, 8, 2][i % 5], trig=1 if i % 3 == 0 else 0)
g.poke(SYM['amreq'], 1); g.run(30); g.poke(SYM['amreq'], 1); g.run(30)    # automap on, off
g.poke(SYM['health'], 1); g.run(400); g.run(4, key=ord('r')); g.run(300)   # die, retry
after = bytes(g.m[0x100:0x1E0])
changed = [0x100+i for i in range(len(before)) if before[i] != after[i]]
check(set(changed) <= {0x173, 0x174, 0x175, 0x176}, f'code in $0100-$01DF untouched (changed: {[hex(a) for a in changed]})')
g.close()

# ---- the OS ROM is off while the game runs
g = Game(seed=5, tag='sy2'); g.start('0420')
check(0xC000 <= dlist(g) < 0xD000, f'the game runs its display lists from the RAM under the OS ROM (${dlist(g):04X})')
# ---- RESET (an XL resets the chips): back to the menu, and playable, three times
for lv in range(2): g.finish_level()
ok = True
for k in range(3):
    g.run(1, key=-2); g.run(240)
    ok &= dlist(g) < 0x1A00
    g.run(3, trig=1); g.run(200); g.run(5, trig=1); g.run(120)
    ok &= g.v('level') == 1 and g.v('dead') == 0
check(ok, 'RESET mid-game returns to the menu, and a new run plays (3 times)')
g.close()

# ---- memory sizes
g = Game(seed=5, tag='sy3', ram=16); g.run(200)
check(screen_text(g.m, 'NEEDS AN ATARI XL/XE'), 'a 16K machine (no RAM under the OS) gets the explanation screen')
g.close()
for ram in (128, 320):
    g = Game(seed=5, tag='sy4', ram=ram); g.start('0420')
    check(g.v('level') == 1 and g.v('dead') == 0 and g.msg() == 'FIND THE EXIT DOOR!', f'{ram}K (extended banks): the game runs')
    check(g.finish_level(), f'{ram}K: level 1 -> 2')
    g.close()
done()
