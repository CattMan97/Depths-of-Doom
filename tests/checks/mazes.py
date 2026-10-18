"""Every level of a few seeds (through L, level select): a sound maze with one
exit and one entrance, the exit reachable, things on open floor, and no long
dead ends (only very short ones: at most 4 tiles)."""
import os, sys; sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'lib'))
from dod import *

def deadends(M):
    """Length in tiles of each dead-end corridor (from its end to a junction)."""
    O = lambda x, y: 0 <= x < 32 and 0 <= y < 32 and M[y*32+x] == 0
    nb = lambda x, y: [(x+dx, y+dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)) if O(x+dx, y+dy)]
    out = []
    for y in range(32):
        for x in range(32):
            if O(x, y) and len(nb(x, y)) == 1:
                prev = None; c = (x, y); n = 0
                while True:
                    ns = [p for p in nb(*c) if p != prev]
                    if len(nb(*c)) > 2 or not ns: break
                    prev, c = c, ns[0]; n += 1
                    if len(nb(*c)) != 2: break
                out.append(n)
    return out

problems = []; longest = 0; levels = 0
for seed in ('0420', '1234', '9876'):
    g = Game(seed=5, tag='mz'); g.start(seed); g.run(4, key=ord('g')); g.run(5)
    for lv in range(1, 16):
        if lv > 1: g.goto_level(lv)
        M = g.map(); where = f'{seed} level {lv}'; levels += 1
        if g.v('level') != lv: problems.append(f'{where}: level select reached {g.v("level")}'); continue
        if any(M[i] == 0 for i in range(1024) if i < 32 or i >= 992 or i % 32 in (0, 31)):
            problems.append(f'{where}: the border is open')
        st = g.m[0x85]*32 + g.m[0x83]
        if M[st] != 0: problems.append(f'{where}: the player starts in a wall')
        ex = [i for i in range(1024) if M[i] in (2, 4)]
        if len(ex) != 1: problems.append(f'{where}: {len(ex)} exits'); continue
        if sum(1 for t in M if t == 3) != 1: problems.append(f'{where}: no single entrance')
        dist = bfs(M, st)
        if not any(ex[0]+o in dist for o in (1, -1, 32, -32)): problems.append(f'{where}: the exit is unreachable')
        for t in g.things():
            if M[t[3]*32+t[2]] != 0: problems.append(f'{where}: thing {t} in a wall')
        if g.v('locked') and g.v('keyby') == 255 and not any(t[1] == 0x85 for t in g.things()):
            problems.append(f'{where}: a locked exit but no keycard anywhere')
        d = deadends(M); longest = max([longest] + d)
        if d and max(d) > 4: problems.append(f'{where}: a dead end {max(d)} tiles long')
    g.close()
for p in problems: print('   ', p)
check(not problems, f'{levels} levels (3 seeds x 15): sound mazes, one exit, one entrance, exit reachable, things on the floor')
check(longest <= 4, f'longest dead end {longest} tiles (limit 4)')
done()
