"""Monsters: the spitter's fireballs, brute speed, animation, death and score.
The animation check uses the frozen test build (monsters don't move)."""
import os, sys, math; sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'lib'))
from dod import *

EVX, EVY = SYM['EVX'], SYM['EVY']
FB = (MAXTH-2, MAXTH-1)          # fireball slots
def pos(g, i): return (g.m[EXH+i]+g.m[EXL+i]/256, g.m[EYH+i]+g.m[EYL+i]/256)
def first_facing(g, dist):
    return next((m[0] for m in g.monsters() if g.facing(m[0], dist)), None)

# ---- spitter: in sight at range -> fireballs that fly, hurt, and stop at walls
g = Game(seed=5, tag='ms'); g.start('0420')
sp = first_facing(g, 3)
check(sp is not None, 'stood 3 tiles from a monster, facing it')
g.only(sp)
g.poke(ETYP+sp, 2); g.poke(EHP+sp, 4); g.poke(ETIM+sp, 0)
g.facing(sp, 3); g.poke(EWAKE+sp, 1); g.run(1)
h0 = g.v('health'); seen = 0; inwall = 0; maxv = 0
for f in range(260):
    g.run(1); M = g.map()
    for i in FB:
        if g.m[EST+i] == 1 and g.m[ETYP+i] == 3:
            seen += 1; x, y = pos(g, i)
            if M[int(y)*32+int(x)]: inwall += 1
            vx = g.m[EVX+i]; vx -= 256*(vx > 127); vy = g.m[EVY+i]; vy -= 256*(vy > 127)
            maxv = max(maxv, math.hypot(vx, vy))
check(seen > 0, f'spitter fires (fireball seen on {seen} frames)')
check(inwall == 0, f'fireballs never inside a wall ({inwall})')
check(10 <= maxv <= 30, f'fireball speed {maxv:.0f}/256 tile per tick (1/20 s)')
check(g.v('health') < h0, f'fireballs hurt: health {h0} -> {g.v("health")}')
check(g.m[EST+sp] == 1 and abs(pos(g, sp)[0]-(g.m[EXH+sp]+.5)) < 1, 'spitter holds its ground at range')
g.poke(SYM['health'], 100)
for k in range(5): g.run(3, trig=1); g.run(12)
check(g.m[EST+sp] == 2 or g.m[EHP+sp] < 4, f'shooting through fireballs still hits the spitter (HP {g.m[EHP+sp]}, state {g.m[EST+sp]})')
g.close()

# ---- fireballs in the air die out (wall or age) once the spitter is gone
g = Game(seed=5, tag='ms2'); g.start('0420')
sp = first_facing(g, 3); g.only(sp); g.poke(ETYP+sp, 2); g.poke(ETIM+sp, 0)
g.facing(sp, 3); g.poke(EWAKE+sp, 1)
for f in range(60):
    g.run(1)
    if any(g.m[EST+i] == 1 for i in FB): break
g.poke(EST+sp, 0)
g.run(700)
check(not any(g.m[EST+i] == 1 and g.m[ETYP+i] == 3 for i in FB), 'fireballs fizzle (wall or age)')
g.close()

# ---- a brute is faster than an imp
def walked(typ):
    g = Game(seed=5, tag='ms3'); g.start('0420')
    t = g.monsters()[0][0]; g.only(t); g.poke(ETYP+t, typ); g.poke(EWAKE+t, 1)
    g.run(1); p0 = pos(g, t); dist = 0
    for k in range(30):
        g.run(1); p1 = pos(g, t); dist += math.hypot(p1[0]-p0[0], p1[1]-p0[1]); p0 = p1
    g.close(); return dist
di, db = walked(0), walked(1)
check(db > di*1.3, f'brute walks {db:.2f} tiles vs imp {di:.2f} in 30 frames')

# ---- animation (frozen build): an awake imp's picture changes while it stands
frozen = os.path.join(WORK, 'frozen.car')
if not os.path.exists(frozen): build_variant('frozen', 'E_SPEED=0', 'BENCH')
F = Game(seed=5, car=frozen, tag='ms4'); F.start('0420')
t = first_facing(F, 3); F.only(t); F.facing(t, 3); F.poke(EWAKE+t, 1)
imgs = []
for k in range(12):
    F.run(1); imgs.append(ppm_bytes(F.shot(f'ms_anim{k}.ppm')))
check(len(set(imgs)) >= 2, f'awake imp animates while standing ({len(set(imgs))} distinct frames of 12)')
F.close()

# ---- death: falls, then a corpse; a brute scores 200
g = Game(seed=5, tag='ms5'); g.start('0420')
t = first_facing(g, 2); g.only(t); g.poke(ETYP+t, 1); g.poke(EHP+t, 1); g.facing(t, 2)
sc0 = g.score()
g.run(20)   # (a still view only redraws once it changes: let the new one appear)
for k in range(30):
    g.run(1, trig=1)
    if g.m[EST+t] == 2: break
g.run(33)
check(g.m[EST+t] == 2 and g.score()-sc0 == 200, f'brute kill scores {g.score()-sc0}')
g.close()
done()
