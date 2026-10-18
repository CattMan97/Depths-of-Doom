"""The game's flow: menu -> wake-up scene (and skipping it), the attract-mode
demo, and the ending after level 15."""
import os, sys; sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'lib'))
from dod import *
from PIL import Image, ImageStat

def dlist(g): return g.m[0x230] | g.m[0x231] << 8
def at_menu(g): return dlist(g) < 0x1A00

# ---- the wake-up scene: its lines in order, then the clock starts
g = Game(seed=5, tag='fl'); g.run(100)
check(at_menu(g), 'power-on shows the menu')
g.run(3, trig=1)
lines = []
for k in range(140):
    g.run(5); s = g.msg()
    if s and (not lines or lines[-1] != s): lines.append(s)
    if g.v('dead') == 0 and g.v('intro') == 0 and k > 20: break
want = ['WHERE... AM I?', 'NO MEMORY OF HOW YOU GOT HERE.', 'ONLY ONE THING IS CERTAIN:', 'YOU MUST ESCAPE.', 'FIND THE EXIT DOOR!']
check(all(w in lines for w in want) and [l for l in lines if l in want][-len(want):] == want,
      f'wake-up lines in order: {lines}')
check(g.v('dead') == 0, 'the run starts after the wake-up scene')
g.close()
g = Game(seed=5, tag='fl2'); g.run(100); g.run(3, trig=1); g.run(100); g.run(3, trig=1); g.run(30)
check(g.v('dead') == 0 and g.msg() == 'FIND THE EXIT DOOR!', 'fire skips the wake-up scene')
g.close()

# ---- demo: left alone, the menu plays a demo, then comes back
g = Game(seed=5, tag='fl3'); g.run(1900)
check(g.v('demo') != 0, 'idle on the menu: the demo starts')
x0, y0 = g.m[0x83], g.m[0x85]; g.run(600)
check((g.m[0x83], g.m[0x85]) != (x0, y0) and g.v('dead') == 0, 'the demo player moves')
g.run(3000)
check(at_menu(g), 'the demo returns to the menu')
g.run(3, trig=1); g.run(130)
check(g.v('dead') == 1 and g.v('demo') == 0, 'fire after the demo starts a real run (wake-up scene)')
g.close()

# ---- the ending: finishing level 15
g = Game(seed=5, tag='fl4'); g.start('0420')
g.poke(SYM['level'], 15)
g.finish_level()
g.run(600)
im = Image.open(g.shot('fl_end.ppm')).convert('RGB').crop((0, 30, 336, 200))
r, gg, b = ImageStat.Stat(im).mean
check(r > 60 and r > b + 15, f'the ending reaches the wasteland (mean colour {r:.0f},{gg:.0f},{b:.0f})')
g.run(500); g.run(10, trig=1); g.run(60)
check(at_menu(g), 'fire after THE END returns to the menu')
g.close()
done()
