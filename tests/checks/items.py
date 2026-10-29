"""Pickups refused at full stats (with HEALTH/AMMO/TIME MAX), and the keycard
flow: a random monster carries it; the level line walks you through it."""
import os, sys; sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'lib'))
from dod import *

def msg_soon(g, n=10):
    """The message line, polled (a snapshot can land while it is being redrawn)."""
    for k in range(n):
        if g.msg(): return g.msg()
        g.run(1)
    return g.msg()

# ---- full stats: the pickup stays, and the line says why
g = Game(seed=5, tag='it'); g.start('0420')
h = [t for t in g.things() if t[1] == 0x81][0]; g.place(h[2], h[3]); g.run(10)
check(any(t[0] == h[0] for t in g.things()) and 'HEALTH MAX' in msg_soon(g), f'health at 100%: pack stays, "{g.msg()}"')
g.poke(SYM['health'], 50); g.run(5)
check(g.v('health') == 75 and not any(t[0] == h[0] for t in g.things()), f'health 50: taken, now {g.v("health")}')
g.poke(AMMOP, 100); pa = [t for t in g.things() if t[1] == 0x86]; a = pa[0]; g.place(a[2], a[3]); g.run(10)
check(any(t[0] == a[0] for t in g.things()) and 'AMMO MAX' in msg_soon(g), f'pistol ammo at 100: pistol ammo stays, "{g.msg()}"')
a = pa[1]; g.poke(ETYP+a[0], 0x80); g.place(a[2], a[3]); g.run(10)   # (made into super ammo: it's rare)
check(any(t[0] == a[0] for t in g.things()) and 'AMMO MAX' in msg_soon(g), f'every gun you have full: super ammo stays, "{g.msg()}"')
g.poke(SYM['mins'], 5); g.poke(SYM['secs'], 0)
tm = [t for t in g.things() if t[1] == 0x82][0]; g.place(tm[2], tm[3]); g.run(10)
check(any(t[0] == tm[0] for t in g.things()) and 'TIME MAX' in msg_soon(g), f'time 5:00: hourglass stays, "{g.msg()}"')
g.run(120)    # standing on it while the clock runs down: taken once there's room
check(not any(t[0] == tm[0] for t in g.things()) and 'TIME +30' in g.msg(), f'once below the cap it is taken: "{g.msg()}"')
g.close()

def kill(g, i):
    """Shoot monster i dead (one hit point, stood next to it, god mode on)."""
    M = g.map()
    for attempt in range(40):
        if g.m[EST+i] != 1: return True
        g.poke(EHP+i, 1)
        ex, ey = g.m[EXH+i], g.m[EYH+i]
        for dx, dy, ang in ((1, 0, 512), (-1, 0, 0), (0, 1, 768), (0, -1, 256)):
            if M[(ey+dy)*32+ex+dx] == 0: break
        g.place(ex+dx, ey+dy, ang); g.run(2); g.run(6, trig=1); g.run(6)
    return g.m[EST+i] != 1

# ---- every monster but the keycard's carrier leaves health or ammo for a gun you have
g = Game(seed=5, tag='it3'); g.start('0420'); g.run(4, key=ord('g')); g.run(5)
mons = [t[0] for t in g.monsters()]
spots = {}
for i in mons:
    kill(g, i); spots[i] = (g.m[EXH+i], g.m[EYH+i], g.m[EXL+i], g.m[EYL+i])
nx, ny, ang = g.exit_approach(); g.place(nx, ny, ang)  # well away from the bodies
g.run(20)
g.run(100)
got = {i: (g.m[EST+i], g.m[ETYP+i]) for i in mons}
check(all(e == 1 and t in (0x86, 0x81) for e, t in got.values()),
      f'all {len(mons)} dead monsters turned into pistol ammo (the only gun yet) or health: {[NAMES.get(t, t) for e, t in got.values()]}')
check(all((g.m[EXH+i], g.m[EYH+i], g.m[EXL+i], g.m[EYL+i]) == spots[i] for i in mons), 'each where its monster fell')
g.close()
types = set()
for seed in ('1111', '2468'):          # (both kinds turn up: it's a coin toss each time)
    g = Game(seed=5, tag='it4'); g.start(seed); g.run(4, key=ord('g')); g.run(5)
    ms = [t[0] for t in g.monsters()]
    for i in ms: kill(g, i)
    nx, ny, ang = g.exit_approach(); g.place(nx, ny, ang); g.run(120)
    types |= {g.m[ETYP+i] for i in ms if g.m[EST+i] == 1}
    g.close()
check(types == {0x86, 0x81}, f'drops include both ammo and health ({sorted(NAMES.get(t, t) for t in types)})')

# ---- the keycard (level 4 of seed 0420: a locked exit)
g = Game(seed=5, tag='it2'); g.start('0420'); g.run(4, key=ord('g')); g.run(5); g.goto_level(4)
check(g.v('level') == 4 and g.v('locked') == 1, 'level 4 (L level select): the exit is locked')
check(g.msg() == 'FIND THE EXIT DOOR!', f'until the exit is seen: "{g.msg()}"')
check(not any(t[1] == 0x85 for t in g.things()) and g.v('keyby') != 255, 'the keycard is not lying about: a monster carries it')
M = g.map(); d = M.index(4); dx, dy = d & 31, d >> 5
for (ox, oy, ang) in ((2, 0, 512), (-2, 0, 0), (0, 2, 768), (0, -2, 256)):
    nx, ny = dx+ox, dy+oy; mx, my = dx+ox//2, dy+oy//2
    if 0 <= nx < 32 and 0 <= ny < 32 and M[ny*32+nx] == 0 and M[my*32+mx] == 0: break
g.place(nx, ny, ang); g.run(20)
check('KEYCARD, THEN EXIT!' in g.msg() and g.msg().startswith('FIND THE '), f'exit seen: "{g.msg()}"')
g.run(200)
check(g.msg() == 'KILL THE MONSTERS TO GET THE KEYCARD!', f'then: "{g.msg()}"')
kb = g.v('keyby')
check(kill(g, kb), 'killed the carrier')
g.run(5)
k = [t for t in g.things() if t[1] == 0x85]
check(len(k) == 1 and g.v('keyby') == 255, 'the carrier drops the keycard')
nx2, ny2, ang2 = g.exit_approach(); g.place(nx2, ny2, ang2); g.run(260)  # (its body: 80 ticks)
check(g.m[EST+kb] == 0 and sum(1 for t in g.things() if t[1] == 0x85) == 1,
      f'the carrier drops only the keycard (its body: state {g.m[EST+kb]}, type ${g.m[ETYP+kb]:02X})')
g.place(k[0][2], k[0][3]); g.run(10)
check(g.v('havekey') == 1 and 'KEYCARD ACCEPTED' in g.msg(), f'picked up: "{g.msg()}"')
g.run(200)
check(g.msg() == 'FIND THE EXIT DOOR!', f'afterwards: "{g.msg()}"')
check(g.finish_level(), 'level 4 -> 5 with the keycard')
g.close()
done()
