"""Seeds: the same seed gives the same levels whatever the power-on state;
different seeds differ; game over, retry (R) and back to the menu (START)."""
import os, sys; sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'lib'))
from dod import *

def run(steps, boot): return script(steps, seed=boot, tag='sd')   # boot: POKEY's power-on state
SKIP = ' 100,0,0 3,0,1 30,0,0'   # past the wake-up scene
def typed(digits): return ' '.join(f'4,0,0,K,{ord(c)} 6,0,0' for c in digits)
seedtxt = lambda m: ''.join(chr((c & 127)+32) for c in m[0x3A00+46:0x3A00+50])
state = lambda m: (bytes(m[0xC00:0x1000]), tuple((m[EXH+i], m[EYH+i]) for i in range(16) if m[EST+i]), m[0x83], m[0x85])
def door_walk(pre, boot):        # finish level 1: teleport beside the exit and walk in
    m = run(pre, boot); M = m[0xC00:0x1000]; d = M.index(2); dx, dy = d & 31, d >> 5
    for (ox, oy, ang) in ((1, 0, 512), (-1, 0, 0), (0, 1, 768), (0, -1, 256)):
        nx, ny = dx+ox, dy+oy
        if 0 <= nx < 32 and 0 <= ny < 32 and M[ny*32+nx] == 0: break
    return run(pre+SKIP+f' 1,0,0,p,{nx},128,{ny},128,{ang&255},{ang>>8} 40,1,0 150,0,0', boot)

P = '100,0,0 '+typed('0420')+' 3,0,1 40,0,0'
a = run(P, 1); b = run(P, 777); c = run(P, 31337)
check(seedtxt(a) == '0420', f'typed seed shows: {seedtxt(a)}')
check(state(a) == state(b) == state(c), 'seed 0420: same maze, monsters and start after 3 different power-ons')
a2 = door_walk(P, 1); b2 = door_walk(P, 999)
check(a2[SYM['level']] == 2 and b2[SYM['level']] == 2, 'reached level 2 both times')
check(state(a2) == state(b2) and state(a2) != state(a), 'level 2 of seed 0420 is the same both times, and differs from level 1')
check(state(run('100,0,0 '+typed('0421')+' 3,0,1 40,0,0', 1)) != state(a), 'seed 0421 gives a different maze')
r1 = run('100,0,0 3,0,1 40,0,0', 5); r2 = run('75,0,0 3,0,1 40,0,0', 6)
check(seedtxt(r1) != seedtxt(r2) and state(r1) != state(r2), f'random seeds differ: {seedtxt(r1)} {seedtxt(r2)}')
# game over (the clock runs out), then: fire does nothing, R retries, START -> menu
mins, secs, dead = SYM['mins'], SYM['secs'], SYM['dead']
G = P+SKIP+f' 60,0,0 1,0,0,m,{mins>>8},{mins&255},0,1 1,0,0,m,{secs>>8},{secs&255},1,1 200,0,0'
check(run(G, 1)[dead] == 1, 'the clock running out ends the game')
check(run(G+' 30,0,1 30,0,0', 1)[dead] == 1, 'fire keeps the game-over screen')
retry = run(G+' 4,0,0,K,114 60,0,0', 1)
check(seedtxt(retry) == '0420' and state(retry)[0] == state(a)[0] and retry[SYM['level']] == 1 and retry[dead] == 0,
      'R retries the same seed from level 1')
menu = run(G+' 3,0,0,T 60,0,0', 1)
check((menu[0x230] | menu[0x231] << 8) < 0x1A00, 'START goes back to the menu')
new = run(G+' 3,0,0,T 60,0,0 3,0,1 60,0,0', 1)
check(state(new)[0] != state(a)[0], f'fire on the menu starts a new random seed ({seedtxt(new)})')
done()
