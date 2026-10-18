"""Fire button (taps, holding, cooldown, latency), being hurt, and the sound
around a level change: the music stops for the tunnel's rush, then the next
level's music starts.
Sound channels: 1 gun / tunnel / monsters, 2 thumps and drums, 3-4 music."""
import os, sys; sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'lib'))
from dod import *

g = Game(seed=5, tag='in', audlog=True); g.start('0420'); g.run(30)
a0 = g.m[AMMO]
for i in range(10): g.run(1, trig=1); g.run(29)
check(a0-g.m[AMMO] == 10, f'10 one-frame taps 0.5 s apart: {a0-g.m[AMMO]} shots')
a0 = g.m[AMMO]; g.run(90, trig=1); g.run(10)
check(a0-g.m[AMMO] == 1, f'holding fire 1.5 s with the pistol: {a0-g.m[AMMO]} shot')
a0 = g.m[AMMO]
for i in range(10): g.run(1, trig=1); g.run(4)
g.run(60)
check(a0-g.m[AMMO] == 5, f'10 taps 5 frames apart (cooldown 12 frames): {a0-g.m[AMMO]} shots')
lat = []
for k in range(24):
    g.run(30+k % 7)                   # (past the cooldown; vary the phase)
    a0 = g.m[AMMO]; g.run(1, trig=1); n = 1
    while g.m[AMMO] == a0 and n < 30: g.run(1); n += 1
    lat.append(n)
check(sum(lat)/len(lat) <= 2.5 and max(lat) <= 3, f'press to shot: average {sum(lat)/len(lat):.1f} frames, worst {max(lat)}')

# ---- level change: music (channels 3-4) silent during the tunnel, rush on 1
g.run(120)
n0 = len(g.audio())
nx, ny, ang = g.exit_approach(); g.place(nx, ny, ang)
tun = []
for k in range(240):                  # (frame by frame: tunon and the sound line up)
    g.run(1, stick=1 if k < 30 else 0); tun.append(g.v('tunon'))
A = g.audio()[n0:]
during = [A[i] for i in range(len(tun)) if tun[i]]
check(len(during) > 30, f'the tunnel shows ({len(during)} frames)')
check(all(c[2] & 15 == 0 and c[3] & 15 == 0 for f, c in during), 'no music during the tunnel (channels 3-4 silent)')
check(sum(1 for f, c in during if c[0] & 15) > len(during)//2, 'the tunnel rush plays on channel 1')
g.run(240)
A = g.audio()[-200:]
check(g.v('level') == 2 and any(c[2] & 15 or c[3] & 15 for f, c in A), 'level 2 starts with its music')
g.close()

# ---- being hurt: health drops, the hit thump sounds, no gun flash
g = Game(seed=777, tag='in2'); g.start()
e = next((t[0] for t in g.monsters() if t[1] == 0), None)
M = g.map(); ex, ey = g.m[EXH+e], g.m[EYH+e]
for dx, dy, ang in ((1, 0, 512), (-1, 0, 0), (0, 1, 768), (0, -1, 256)):
    if M[(ey+dy)*32+ex+dx] == 0: break
g.place(ex+dx, ey+dy, ang)
flash = 0; thump = 0
for k in range(40):
    g.run(3)
    flash += g.v('flash') != 0
    thump = max(thump, g.v('thump'))
check(g.v('health') < 100, f'an imp beside you hurts: health {g.v("health")}')
check(thump > 0, 'the hit thump sounds')
check(flash == 0, 'no gun flash when you are hit')
g.close()
done()
