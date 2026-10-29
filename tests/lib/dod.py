"""Shared helpers for the Depths of Doom tests.

    import sys, os; sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'lib'))
    from dod import *

Game() drives the emulator interactively (the harness's "-" mode): run frames
with joystick / trigger / key input, poke RAM, take screenshots.  After every
run() the whole 64K is in g.m.  Variable addresses come from the source
(SYM['health'], ...), so they follow the code as it changes.

Input encoding: stick = directions pressed as a bit mask (1 up, 2 down,
4 left, 8 right; 0 = centred); trig 1 = pressed.
"""
import os, re, subprocess, sys
from collections import deque

TESTS = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
REPO = os.path.dirname(TESTS)
TOOLS = os.path.join(TESTS, '.tools')
WORK = os.path.join(TESTS, '.work')          # screenshots, RAM dumps, test builds
HARNESS = os.path.join(TOOLS, 'bin', 'harness')
CC65BIN = os.path.join(TOOLS, 'cc65', 'bin')
CAR = os.environ.get('DOD_CAR', os.path.join(REPO, 'DEPTHS_OF_DOOM.CAR'))
os.makedirs(WORK, exist_ok=True)
if not os.path.exists(HARNESS):
    sys.exit('no harness: run tests/setup.sh first')

# ---------------------------------------------------------------- symbols
# RAM variables are declared with .res in fixed-address BSS segments; walk
# each segment's declarations from its start address.
_src = open(os.path.join(REPO, 'depthsofdoom.s')).read()
_isrc = open(os.path.join(REPO, 'items.s')).read()
MAXTH = 24          # thing slots (depthsofdoom.s MAXTH)

def _syms(src, seg, base):
    body = src.split(f'.segment "{seg}"')[1].split('.segment')[0]
    a = base; d = {}
    for l in body.splitlines():
        mm = re.match(r'^(\w+):\s*\.res\s+(\w+)', l)
        if mm:
            n = mm.group(2); n = MAXTH if n == 'MAXTH' else int(n)
            d[mm.group(1)] = a; a += n
    return d

SYM = _syms(_src, 'ZEROPAGE', 0x80)
for _seg, _base in (('BSS', 0xB80), ('BSS2', 0x1B00), ('BSS3', 0xB800), ('BSS4', 0x400), ('BSS5', 0xBA00)):
    SYM.update(_syms(_src, _seg, _base))
SYM.update(_syms(_isrc, 'BSSR', 0xB780))
EXL, EXH, EYL, EYH, EST, EHP, EPAIN, EWAKE, ETIM, ETYP = \
    [SYM[k] for k in 'EXL EXH EYL EYH EST EHP EPAIN EWAKE ETIM ETYP'.split()]
NTH = MAXTH
# fixed addresses: zero page $80 frame counter, $81 ammo (the gun in hand's: a copy,
# made when the bottom bar is drawn; each gun's own is at AMMOP+gun), $82-$87 player
# x (frac, whole), y (frac, whole), angle; the map at $0C00 (32x32 tiles)
FCOUNT, AMMO = 0x80, 0x81
AMMOP = SYM['ammop']        # pistol, shotgun, SMG
NAMES = {0x80: 'super ammo', 0x81: 'health', 0x82: 'time', 0x83: 'shotgun', 0x84: 'chaingun', 0x85: 'key',
         0x86: 'pistol ammo'}

# ---------------------------------------------------------------- checks
_ok = True
def check(cond, label):
    """Print PASS/FAIL for one expectation."""
    global _ok
    print(('  PASS ' if cond else '  FAIL ') + label, flush=True)
    _ok &= bool(cond)
    return cond

def done():
    """End of a check script: summary line and exit status."""
    print('ALL PASS' if _ok else 'SOME FAILED')
    sys.exit(0 if _ok else 1)

# ---------------------------------------------------------------- emulator
class Game:
    def __init__(self, seed=5, car=None, tag='g', ram=None, wav=None, audlog=False):
        if not os.path.exists(car or CAR): raise FileNotFoundError(car or CAR)
        self.ro = os.path.join(WORK, f'ram_{tag}.bin')
        env = {'SEED': str(seed), 'RAMOUT': self.ro, 'PATH': os.environ.get('PATH', '')}
        if ram: env['RAM'] = str(ram)
        if wav: env['WAV'] = wav
        self.audlog = os.path.join(WORK, f'aud_{tag}.bin') if audlog else None
        if audlog: env['AUDLOG'] = self.audlog
        self.p = subprocess.Popen([HARNESS, os.path.abspath(car or CAR), os.path.join(WORK, tag), '-'],
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE, cwd=WORK, env=env)
        self.m = None
    def _cmd(self, line):
        self.p.stdin.write((line + '\n').encode()); self.p.stdin.flush()
        while True:
            l = self.p.stdout.readline()
            if not l: raise RuntimeError('harness exited')
            if l.strip() == b'#DONE': return
    def run(self, frames, stick=0, trig=0, key=0):
        """Run frames with this input.  key: ATASCII code held, or -2 = RESET."""
        self._cmd(f'{frames} {stick} {trig} {key}')
        self.m = open(self.ro, 'rb').read(); return self.m
    def poke(self, a, v): self._cmd(f'P {a} {v}')
    def shot(self, name):
        """Screenshot to tests/.work/NAME (PPM).  Returns the path."""
        p = os.path.join(WORK, name); self._cmd(f'S {p}'); return p
    def wavend(self): self._cmd('W')
    def audio(self):
        """With audlog=True: per frame so far, (AUDF1-4, AUDC1-4) as two 4-tuples."""
        self.p.stdin.flush(); d = open(self.audlog, 'rb').read()
        return [(tuple(d[i:i+4]), tuple(d[i+4:i+8])) for i in range(0, len(d) - 7, 8)]
    def close(self):
        self.p.stdin.close(); self.p.wait()

    # ---- game-level helpers
    def start(self, seed_digits=None):
        """From power-on: type the seed (or take a random one), start, skip the
        wake-up scene, and return once level 1 is running."""
        self.run(100)
        if seed_digits:
            for c in seed_digits: self.run(4, key=ord(c)); self.run(6)
        self.run(3, trig=1)
        m = self.run(10)
        for _ in range(40):          # level built, then the wake-up scene (fire skips it)
            m = self.run(5)
            if m[SYM['intro']] == 0 and m[SYM['dead']]: break
        m = self.run(5, trig=1)
        while m[SYM['dead']]: m = self.run(5)
        return self.run(30)          # level built, start button seen released
    def v(self, name): return self.m[SYM[name]]
    def things(self):
        """Live things: (slot, type, tile x, tile y).  Monsters < $80, pickups $80+."""
        return [(i, self.m[ETYP+i], self.m[EXH+i], self.m[EYH+i]) for i in range(NTH) if self.m[EST+i] == 1]
    def place(self, x, y, ang=0, xl=128, yl=128):
        """Put the player at tile (x, y), angle 0-1023 (0 = east, 256 = south: y grows downwards)."""
        for a, v in ((0x83, x), (0x82, xl), (0x85, y), (0x84, yl), (0x86, ang & 255), (0x87, ang >> 8)):
            self.poke(a, v)
    def msg(self): return ''.join(chr((c & 127) + 32) for c in self.m[0xA28:0xA50]).strip()
    def hud(self): return ''.join(chr((c & 127) + 32) for c in self.m[0xA00:0xA28])
    def clock(self): return self.m[SYM['mins']] * 60 + self.m[SYM['secs']]
    def map(self): return self.m[0xC00:0x1000]
    def score(self): return int.from_bytes(self.m[SYM['score']:SYM['score']+3], 'little')
    def reveal_key(self):
        """As if the keycard's carrier had died: the keycard back where it was placed."""
        if self.v('keyby') != 255:
            self.poke(EST+self.v('keysl'), 1); self.poke(SYM['keyby'], 255); self.run(1)
    def goto_level(self, n):
        """L (level select), step to level n, start it."""
        self.run(4, key=ord('l')); self.run(6)
        cur = self.v('level')
        while cur != n:
            self.run(4, stick=1); self.run(6); cur = cur % 15 + 1
        self.run(3, trig=1); self.run(40)
    def exit_approach(self):
        """An open tile beside the exit door and the angle facing it."""
        M = self.map(); d = [i for i in range(1024) if M[i] in (2, 4)][0]; dx, dy = d & 31, d >> 5
        for (ox, oy, ang) in ((1, 0, 512), (-1, 0, 0), (0, 1, 768), (0, -1, 256)):
            nx, ny = dx + ox, dy + oy
            if 0 <= nx < 32 and 0 <= ny < 32 and M[ny*32+nx] == 0: return nx, ny, ang
    def finish_level(self):
        """Walk into the exit (collecting the keycard first if the level is locked).
        True if the next level started."""
        if self.v('locked') and not self.v('havekey'):
            self.reveal_key()
            k = [t for t in self.things() if t[1] == 0x85][0]
            self.place(k[2], k[3]); self.run(20)
        nx, ny, ang = self.exit_approach()
        lv = self.v('level'); self.place(nx, ny, ang); self.run(40, stick=1)
        self.run(30)
        for _ in range(12):             # (the tunnel between levels takes a while)
            if self.v('level') != lv and not self.v('tunon'): break
            self.run(10)
        self.run(10)
        return self.v('level') == lv + 1
    def take(self, typ):
        """Walk onto the first pickup of this type."""
        t = [t for t in self.things() if t[1] == typ][0]
        self.place(t[2], t[3]); self.run(15); return t
    def facing(self, idx, dist=2):
        """Stand dist tiles from thing idx, in a straight open line, facing it."""
        M = self.map(); ex, ey = self.m[EXH+idx], self.m[EYH+idx]
        for dx, dy, ang in ((1, 0, 512), (-1, 0, 0), (0, 1, 768), (0, -1, 256)):
            if all(M[(ey+k*dy)*32+ex+k*dx] == 0 for k in range(1, dist+1)):
                self.place(ex+dist*dx, ey+dist*dy, ang); return True
        return False
    def only(self, keep):
        """Remove every monster but thing keep."""
        for t in self.things():
            if t[1] < 0x80 and t[0] != keep: self.poke(EST+t[0], 0)
    def monsters(self): return [t for t in self.things() if t[1] < 3]

def script(steps, seed=12345, car=None, ram=None, tag='sc'):
    """Script mode (see harness.c): run the steps from power-on, return the RAM."""
    if not os.path.exists(car or CAR): raise FileNotFoundError(car or CAR)
    env = {'SEED': str(seed), 'PATH': os.environ.get('PATH', '')}
    if ram: env['RAM'] = str(ram)
    subprocess.run([HARNESS, os.path.abspath(car or CAR), os.path.join(WORK, tag), steps],
                   capture_output=True, cwd=WORK, env=env, check=True)
    return open(os.path.join(WORK, 'ram.bin'), 'rb').read()

def bfs(M, start):
    """Walking distances over open tiles (0) from start (tile index y*32+x)."""
    d = {start: 0}; q = deque([start])
    while q:
        t = q.popleft()
        for o in (1, -1, 32, -32):
            n = t + o
            if M[n] == 0 and n not in d: d[n] = d[t] + 1; q.append(n)
    return d

def ppm_bytes(path): return open(path, 'rb').read()

# ---------------------------------------------------------------- builds
def build():
    """Build DEPTHS_OF_DOOM.CAR (build.sh) with the tools from setup.sh."""
    env = dict(os.environ, PATH=CC65BIN + os.pathsep + os.environ.get('PATH', ''))
    subprocess.run(['sh', 'build.sh'], cwd=REPO, env=env, check=True, stdout=subprocess.DEVNULL)

def build_variant(name, *defines, labels=False):
    """A test build with extra assembler defines, e.g. build_variant('frozen',
    'E_SPEED=0', 'BENCH').  Run build() first (it makes the shared parts).
    labels=True also writes tests/.work/NAME.labels (for the profiler).
    Returns the path of tests/.work/NAME.car."""
    env = dict(os.environ, PATH=CC65BIN + os.pathsep + os.environ.get('PATH', ''))
    w = lambda f: os.path.join(WORK, f'{name}_{f}')
    args = ['-g'] if labels else []
    for d in defines: args += ['-D', d]
    subprocess.run(['ca65', *args, '-o', w('game.o'), 'depthsofdoom.s'], cwd=REPO, env=env, check=True)
    cfg = open(os.path.join(REPO, 'game.cfg')).read()
    outs = {}
    def sub(mm):
        outs[mm.group(1)] = w(mm.group(1) + '.bin'); return f'file = "{outs[mm.group(1)]}"'
    cfg = re.sub(r'file = "(imgb|ovl|ovl2|osr)\.bin"', sub, cfg)
    open(w('game.cfg'), 'w').write(cfg)
    lab = ['-Ln', os.path.join(WORK, name + '.labels')] if labels else []
    subprocess.run(['ld65', '-C', w('game.cfg'), '-o', w('game.bin'), *lab, w('game.o'), 'data.o'],
                   cwd=REPO, env=env, check=True)
    car = os.path.join(WORK, name + '.car')
    subprocess.run(['python3', 'mkcar.py', w('game.bin'), 'loader.bin', car, outs['imgb'], outs['ovl'],
                    outs['ovl2'], 'end.bin', 'tunnel.bin', 'tracks.bin', outs['osr']],
                   cwd=REPO, env=env, check=True, stdout=subprocess.DEVNULL)
    return car
