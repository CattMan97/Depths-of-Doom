"""Levels 1-4 on seed 0420: what each level holds, pickups, weapons, the
locked exit and its keycard, and moving between levels."""
import os, sys; sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'lib'))
from dod import *

g = Game(seed=5, tag='gp')
g.start('0420')
print('level 1:', g.msg())
th = g.things(); kinds = sorted(NAMES.get(t[1], 'imp') for t in th)
print('  things:', kinds)
check(kinds.count('imp') == 4 and kinds.count('ammo') == 2 and 'health' in kinds and 'time' in kinds
      and 'key' not in kinds and 'shotgun' not in kinds, 'level 1 has 4 imps, 2 ammo, health, time; no key or weapon')
check(g.v('locked') == 0 and 'KEY' not in g.hud() and '---' not in g.hud(), 'level 1 exit is not locked')
# pickups: ammo, health, time
a0 = g.m[AMMO]; g.take(0x80)
check(g.m[AMMO] == min(99, a0+16) and 'AMMO +16' in g.msg(), f'ammo pickup: {a0} -> {g.m[AMMO]}, message "{g.msg()}"')
g.poke(SYM['health'], 40); g.run(2); g.take(0x81)
check(g.v('health') == 65, f'health pickup: 40 -> {g.v("health")}')
c0 = g.clock(); g.take(0x82); g.run(5)
check(g.clock()-c0 in (29, 30), f'time pickup (+30 s): clock {c0} -> {g.clock()}')
g.run(260); check('FIND THE EXIT DOOR!' in g.msg(), f'message reverts to the level line: "{g.msg()}"')
# pistol: one shot = 1 ammo, an imp takes 3
imp = next((t[0] for t in g.things() if t[1] == 0 and g.facing(t[0])), None)
if check(imp is not None, 'found an imp with a straight line of fire'):
    g.poke(EWAKE+imp, 0); g.run(15)
    a0 = g.m[AMMO]
    for k in range(3): g.run(2, trig=1); g.run(24)
    g.run(10)
    check(g.m[AMMO] == a0-3 and g.m[EST+imp] == 2, f'pistol: 3 shots, ammo {a0} -> {g.m[AMMO]}, imp state {g.m[EST+imp]} (2 = dead)')
g.run(4, key=ord('2')); g.run(6)
check(g.v('weapon') == 0 and "DON'T HAVE" in g.msg(), f'key 2 without a shotgun: "{g.msg()}"')
check(g.finish_level(), 'level 1 -> 2 through the exit')
# ---- level 2: shotgun
th = g.things(); print('level 2 things:', sorted(NAMES.get(t[1], 'imp') for t in th))
check(any(t[1] == 0x83 for t in th) and not any(t[1] == 0x84 for t in th), 'level 2 has a shotgun, no chaingun')
a0 = g.m[AMMO]; g.take(0x83)
check(g.v('weapon') == 1 and 'SHOTGUN' in g.hud() and g.m[AMMO] == min(99, a0+10),
      f'shotgun pickup: weapon {g.v("weapon")}, HUD "{g.hud().strip()}"')
imp = next((t[0] for t in g.things() if t[1] == 0 and g.facing(t[0])), None)
if check(imp is not None, 'found an imp with a straight line of fire'):
    g.poke(EWAKE+imp, 0); g.run(15); a0 = g.m[AMMO]
    g.run(2, trig=1); g.run(60)
    check(g.m[EST+imp] == 2 and g.m[AMMO] == a0-2, f'shotgun: one blast kills (state {g.m[EST+imp]}), ammo {a0} -> {g.m[AMMO]}')
    a1 = g.m[AMMO]; g.run(30, trig=1); g.run(5)
    check(g.m[AMMO] == a1-2, f'shotgun is semi-automatic: holding fire 0.5 s used {a1-g.m[AMMO]} ammo (one shot)')
g.run(4, key=ord('1')); g.run(6); check(g.v('weapon') == 0 and 'PISTOL' in g.hud(), 'key 1 switches to the pistol')
g.run(4, key=ord('2')); g.run(6); check(g.v('weapon') == 1, 'key 2 switches back to the shotgun')
check(g.finish_level(), 'level 2 -> 3')
check(g.v('weapon') == 1 and g.v('guncol') == 0x22 and g.m[0x2C0] == 0x22,
      f'the shotgun keeps its brown into the next level (colour ${g.m[0x2C0]:02X})')
# ---- level 3: locked exit + keycard
print('level 3:', g.msg())
check(g.v('locked') == 1 and g.msg() == 'FIND THE EXIT DOOR!' and '---' in g.hud(),
      'level 3 exit is locked, HUD shows ---, line says find the exit until you see it')
check(4 in g.map() and 2 not in g.map(), 'locked exit is barred (tile 4)')
M = g.map(); st = g.m[0x85]*32+g.m[0x83]; d = [i for i in range(1024) if M[i] in (2, 4)][0]
dS = bfs(M, st)
dE = {}
for o in (1, -1, 32, -32):             # (the first open side, as the game takes it)
    if 0 <= d+o < 1024 and M[d+o] == 0: dE = bfs(M, d+o); break
best = max(min(dS[t], dE[t]) for t in dS)
g.reveal_key(); k = [t for t in g.things() if t[1] == 0x85][0]; kt = k[3]*32+k[2]
check(min(dS[kt], dE[kt]) == best, f'keycard is as far as possible from start and exit (min distance {min(dS[kt], dE[kt])}, best {best})')
lv = g.v('level')
nx, ny, ang = g.exit_approach()
g.place(nx, ny, ang); g.run(40, stick=1)
for _ in range(5):          # (the RAM snapshot can land mid-rewrite of the line)
    if 'LOCKED' in g.msg(): break
    g.run(1, stick=1)
check(g.v('level') == lv and 'LOCKED' in g.msg(), f'locked door blocks: "{g.msg()}"')
g.take(0x85); check(g.v('havekey') == 1 and 'KEY' in g.hud(), f'keycard collected: "{g.msg()}", HUD "{g.hud().strip()}"')
g.run(2); check(g.map()[d] == 2, f'exit opens (tile 4 -> {g.map()[d]}) once you have the keycard')
check(g.finish_level(), 'level 3 -> 4 with the keycard')
# ---- level 4: chaingun (SMG)
th = g.things(); print('level 4 things:', sorted(NAMES.get(t[1], 'imp') for t in th))
check(any(t[1] == 0x84 for t in th), 'level 4 has the SMG')
g.take(0x84); g.poke(AMMO, 90); g.run(2)
check(g.v('weapon') == 2 and 'SMG' in g.hud() and 'SMG!' in g.msg(), 'SMG pickup switches weapon (HUD and message say SMG)')
a0 = g.m[AMMO]; g.run(60, trig=1); g.run(5); used = a0-g.m[AMMO]
check(5 <= used <= 10, f'SMG is automatic: holding fire 1 s used {used} ammo')
g.poke(AMMO, 0); g.run(2); g.run(10, trig=1); g.run(3)
check('OUT OF AMMO' in g.msg(), f'out of ammo message: "{g.msg()}"')
g.poke(AMMO, 50)
check(g.finish_level() and g.v('weapon') == 2 and g.m[0x2C0] == 0x08,
      f'level 4 -> 5: the SMG keeps its silver (colour ${g.m[0x2C0]:02X})')
g.close()
done()
