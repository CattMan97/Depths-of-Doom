"""Depths of Doom music: a title theme and one track per level (16 in all).

Original compositions in a slow, somber, industrial style: a low buzzing
drone or pulse in the bass (POKEY distortion C), a sparse pure-tone lament
on top, and a mechanical beat on the hit-sound channel.

Each track is one 192-byte block (MTLEN), copied into MBUF when its level
starts.  Layout (offsets):
   0 frames per 16th - 1        1 the same when time is short (faster)
   2 bass AUDC tone bits        3 lead AUDC tone bits
   4 bass attack volume         6 lead attack volume
   7 bass floor (sustain)       8 lead floor
   9 lead decay rate (AND mask on the frame counter)
  10-25 drum level for each 16th of the bar (0 = none)
  26-41 the bass's 16 notes (AUDF values, chromatic)
  42-53 pattern pointers (low)  54-65 (high)
  66-90 bass order: (pattern, transpose) pairs, $FF = loop
  91-115 lead order
 116-   patterns: (note+1 or 0 = rest, 16ths) pairs, $FF end
"""
import random

MTLEN = 224
OFF = dict(MT_TICK=0, MT_FAST=1, MT_BDIST=2, MT_LDIST=3, MT_ATK=4, MT_BFLOOR=7,
           MT_LFLOOR=8, MT_LRATE=9, MT_DRUM=10, MT_BFREQ=26, MT_PLO=50, MT_PHI=62,
           MT_ORDB=74, MT_ORDL=99, MT_PAT=124)
NBF = 24                                   # bass notes per track (2 octaves)
MAXPAT = 12
MAXORD = 12
R = None

# mfreq: index i = MIDI 48 + i (C3 ..), pure tone, 64 kHz clock.  With the
# buzzy tone (distortion C) a value sounds lower: see GRIND below.
NOTES = 41
def audf(i):
    f = 440.0 * 2 ** ((48 + i - 69) / 12)
    return max(0, min(255, int(round(63921.0 / (2 * f))) - 1))
FREQ = [audf(i) for i in range(NOTES)]

SCALES = {'aeolian': [0, 2, 3, 5, 7, 8, 10], 'phrygian': [0, 1, 3, 5, 7, 8, 10],
          'harmonic': [0, 2, 3, 5, 7, 8, 11], 'locrian': [0, 1, 3, 5, 6, 8, 10]}
# Sequenced bass lines, one bar each (16ths); 12 = up an octave.
BASS = {
    'drive':   [(0, 2)] * 8,                                      # straight 8ths
    'pursuit': [(0, 2), (0, 1), (12, 1)] * 4,                     # 8th + octave flick
    'gallop':  [(0, 1), (0, 1), (R, 2)] * 4,                      # machine gallop
    'octave':  [(0, 2), (12, 2)] * 4,                             # octave bounce
    'sync':    [(0, 3), (0, 3), (0, 2), (0, 3), (0, 3), (12, 2)], # tresillo
    'pulse':   [(0, 4)] * 4,
    'stab':    [(0, 2), (R, 2), (0, 1), (0, 1), (R, 2), (12, 2), (R, 2), (0, 2), (R, 2)],
}
# Drum hits (level = loudness) on the 16ths of a bar: four on the floor with
# off-beat ticks, in a few shapes.
DRUMS = {
    'floor':   {0: 5, 4: 5, 8: 5, 12: 5},
    'hats':    {0: 5, 2: 1, 4: 5, 6: 1, 8: 5, 10: 1, 12: 5, 14: 1},
    'hammer':  {0: 6, 3: 2, 4: 5, 6: 2, 8: 6, 11: 2, 12: 5, 14: 2},
    'piston':  {0: 5, 3: 2, 6: 3, 8: 5, 11: 2, 14: 3},
    'march':   {0: 5, 4: 3, 8: 5, 10: 2, 12: 3},
    'pound':   {0: 6, 2: 2, 4: 6, 6: 2, 7: 2, 8: 6, 10: 2, 12: 6, 14: 2, 15: 1},
    'heart':   {0: 4, 3: 2, 8: 4, 11: 2},
}
RHYTHMS = [[4, 4, 8], [2, 2, 4, 8], [4, 2, 2, 8], [6, 2, 8], [8, 4, 4], [8, 8],
           [4, 4, 4, 4], [6, 6, 4], [2, 2, 2, 2, 8], [12, 4]]

# name, lead key (mfreq index of the tonic), scale, 16th length (frames;
# 8 = 112 BPM, 7 = 128 BPM), bass styles, buzzy bass?, chord roots
# (semitones), drums, seed.  Built on levels 1 and 15 of the first set.
TRACKS = [
    ('title',    9,  'aeolian',  9, ['pulse', 'drive'],    True,  [0, 8, 5, 7],  'heart',   2),
    ('level 1',  9,  'aeolian',  8, ['drive', 'pursuit'],  True,  [0, 8, 5, 7],  'floor',   2),
    ('level 2',  13, 'phrygian', 8, ['gallop', 'drive'],   True,  [0, 1, 0, 1],  'march',   3),
    ('level 3',  7,  'harmonic', 8, ['pursuit', 'octave'], True,  [0, 5, 8, 7],  'hats',    4),
    ('level 4',  12, 'aeolian',  8, ['sync', 'drive'],     True,  [0, 8, 3, 10], 'piston',  5),
    ('level 5',  4,  'phrygian', 8, ['octave', 'gallop'],  True,  [0, 0, 1, 0],  'hammer',  6),
    ('level 6',  11, 'aeolian',  8, ['stab', 'pursuit'],   True,  [0, 10, 8, 7], 'floor',   7),
    ('level 7',  9,  'locrian',  8, ['gallop', 'octave'],  True,  [0, 1, 6, 1],  'piston',  8),
    ('level 8',  13, 'harmonic', 7, ['pursuit', 'drive'],  True,  [0, 5, 7, 0],  'hats',    9),
    ('level 9',  6,  'aeolian',  7, ['drive', 'sync'],     True,  [0, 3, 8, 7],  'hammer', 10),
    ('level 10', 10, 'phrygian', 7, ['octave', 'stab'],    True,  [0, 1, 3, 1],  'pound',  11),
    ('level 11', 13, 'aeolian',  7, ['sync', 'pursuit'],   True,  [0, 8, 10, 7], 'march',  12),
    ('level 12', 5,  'harmonic', 7, ['pursuit', 'gallop'], True,  [0, 0, 8, 7],  'piston', 13),
    ('level 13', 8,  'locrian',  7, ['gallop', 'drive'],   True,  [0, 1, 0, 6],  'pound',  14),
    ('level 14', 11, 'phrygian', 7, ['octave', 'pursuit'], True,  [0, 1, 8, 7],  'hammer', 15),
    ('level 15', 9,  'harmonic', 7, ['pursuit', 'drive'],  True,  [0, 8, 5, 7],  'pound',  16),
]

# The bass has its own 16-note chromatic table per track (MT_BFREQ).  The
# buzzy tone (distortion C) samples the 4-bit poly once per divider period;
# the poly runs at the machine clock (28 per 64 kHz tick), so with a period
# d = AUDF + 1 coprime to 15 the pattern repeats every 15 samples and the
# note is 63921 / (15 d) Hz.  (d a multiple of 3 or 5 gives a short cycle:
# those values are never used.)
def bass_audf(midi, buzzy):
    f = 440.0 * 2 ** ((midi - 69) / 12)
    if not buzzy:
        return max(0, min(255, int(round(63921.0 / (2 * f))) - 1))
    import math
    best = None
    for d in range(2, 257):
        if d % 3 == 0 or d % 5 == 0:
            continue
        err = abs(math.log(63921.0 / (15 * d) / f))
        if best is None or err < best[0]:
            best = (err, d)
    return best[1] - 1


def compose(spec):
    name, key, scale, tick, bstyles, buzzy, prog, drums, seed = spec
    rnd = random.Random(seed * 7919)
    sc = SCALES[scale]
    pats = []
    def pat(p):
        for i, q in enumerate(pats):
            if q == p:
                return i
        pats.append(p)
        return len(pats) - 1
    # ---- bass: roots of the progression, two passes (second with the other style)
    if buzzy:                                   # MIDI E1 .. D#2, the deep growl
        broot = 28 + ((key + 48 - 28) % 12)
    else:                                       # C3 .. B3, as low as a pure tone goes
        broot = 48 + (key % 12)
    # bass roots: each chord's root, folded so they all fit 16 semitones
    roots = []
    for root in prog:
        m = broot + root
        while m - broot > 9: m -= 12
        roots.append(m)
    base = min(roots)
    bfreq = [bass_audf(base + k, buzzy) for k in range(NBF)]
    border = []
    for half in range(3):
        style = bstyles[min(half, len(bstyles) - 1)] if half < 2 else bstyles[0]
        for m in roots:
            lo = min(n for n, d in BASS[style] if n is not None)
            # (pattern notes are stored from 0 up: 0 means a rest)
            bp = [(None if n is None else n - lo, d) for n, d in BASS[style]]
            border.append((pat(bp), m - base + lo))
    # ---- lead: a lament over each chord; bars 1-4 rest (the bass alone first)
    lead_lo = key            # mfreq index of the tonic, octave 1
    def chord_tones(root):
        deg = [d for d in range(7) if sc[d] == root % 12] or [0]
        d0 = deg[0]
        return [sc[(d0 + k) % 7] + 12 * ((d0 + k) // 7) for k in (0, 2, 4)]
    def motif(root, var):
        r = rnd.choice(RHYTHMS)
        tones = chord_tones(root)
        out = []
        # start on a chord tone up high, drift down by scale steps
        cur = rnd.choice(tones) + 12 * rnd.choice((0, 1))
        for i, d in enumerate(r):
            if i > 0 and rnd.random() < 0.18:
                out.append((R, d))
                continue
            note = lead_lo + cur
            while note > 33: note -= 12
            while note < 2: note += 12
            out.append((note, d))
            # next: mostly a step down the scale, sometimes a leap to a chord tone
            if rnd.random() < 0.65:
                deg = min(range(len(sc) * 2), key=lambda k: abs((sc[k % 7] + 12 * (k // 7)) - cur))
                deg = max(0, deg - rnd.choice((1, 1, 2)))
                cur = sc[deg % 7] + 12 * (deg // 7)
            else:
                cur = rnd.choice(tones) + 12 * rnd.choice((0, 1))
        if var:            # the answer phrase ends on a long low tone
            out[-1] = ((lead_lo + tones[0]) if lead_lo + tones[0] <= 33 else lead_lo + tones[0] - 12, out[-1][1])
        return out
    rest = [(R, 16)]
    lorder = [(pat(rest), 0)] * len(prog)
    first = [pat(motif(root, 0)) for root in prog]
    lorder += [(i, 0) for i in first]
    nb = sum(2 * len(p) + 1 for p in pats)
    for k, root in enumerate(prog):              # answer phrases, while they fit
        m = motif(root, 1)
        if nb + 2 * len(m) + 1 <= MTLEN - OFF['MT_PAT'] - 8 and len(pats) < MAXPAT:
            lorder.append((pat(m), 0)); nb += 2 * len(m) + 1
        else:
            lorder.append((first[k], 0))
    assert len(border) <= MAXORD and len(lorder) <= MAXORD, name
    assert len(pats) <= MAXPAT, (name, len(pats))
    for p in pats:
        assert sum(d for _, d in p) == 16, (name, p)
    # ---- check every note fits its frequency table
    for order, top in ((border, NBF), (lorder, NOTES)):
        for pi, tr in order:
            for n, d in pats[pi]:
                if n is not None:
                    assert 0 <= n + tr < top, (name, n, tr)
    # ---- envelopes
    hdr = [0] * OFF['MT_DRUM']
    hdr[0] = tick - 1
    hdr[1] = tick - 3                      # (when the clock is short)
    hdr[2] = 0xC0 if buzzy else 0xA0
    hdr[3] = 0xA0
    hdr[4] = 9                             # bass attack: plucked, decays a step a frame
    hdr[6] = 7                             # lead attack
    hdr[7] = 2                             # bass floor
    hdr[8] = 3                             # lead floor
    hdr[9] = 3 if tick >= 8 else 1         # lead decays every 4 (or 2) frames
    drum = [DRUMS[drums].get(i, 0) for i in range(16)]
    return dict(name=name, hdr=hdr, drum=drum, bfreq=bfreq, pats=pats, border=border,
                lorder=lorder, tick=tick)


def track_lines(t, label=None):
    """Assembler lines for one track block (MTLEN bytes) as it sits in MBUF."""
    data = []                      # list of strings (bytes or expressions)
    data += [str(v) for v in t['hdr']]
    data += [str(v) for v in t['drum']]
    data += [str(v) for v in t['bfreq']]
    # patterns
    pbytes, poff = [], []
    for p in t['pats']:
        poff.append(len(pbytes))
        for n, d in p:
            pbytes += [0 if n is None else n + 1, d]
        pbytes.append(0xFF)
    np = len(t['pats'])
    lo = [f'<(MBUF+{OFF["MT_PAT"] + o})' for o in poff] + ['0'] * (MAXPAT - np)
    hi = [f'>(MBUF+{OFF["MT_PAT"] + o})' for o in poff] + ['0'] * (MAXPAT - np)
    data += lo + hi
    def order(o):
        b = []
        for pi, tr in o:
            b += [str(pi), str(tr)]
        b.append('$FF')
        return b + ['0'] * (2 * MAXORD + 1 - len(b))
    data += order(t['border']) + order(t['lorder'])
    assert len(data) == OFF['MT_PAT'], len(data)
    data += [str(v) for v in pbytes]
    assert len(data) <= MTLEN, (t['name'], len(data))
    data += ['0'] * (MTLEN - len(data))
    lines = [] if label is None else [f'{label}:']
    for i in range(0, len(data), 16):
        lines.append('  .byte ' + ','.join(data[i:i + 16]))
    return lines


def all_tracks():
    return [compose(s) for s in TRACKS]


if __name__ == '__main__':
    for t in all_tracks():
        n = len(track_lines(t))
        used = OFF['MT_PAT'] + sum(2 * len(p) + 1 for p in t['pats'])
        print(f"{t['name']:9s} tick {t['tick']}  patterns {len(t['pats'])}  bytes {used}/{MTLEN}")
