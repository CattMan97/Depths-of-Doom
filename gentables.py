#!/usr/bin/env python3
"""Generate lookup tables, map, HUD text and sprite data for the 600XL raycaster.
Writes data.s (ca65 syntax)."""
import math
from collections import deque

out = []
def seg(name):
    out.append(f'.segment "{name}"')
def table(label, vals, export=True):
    if export:
        out.append(f'.export {label}')
    out.append(f'{label}:')
    for i in range(0, len(vals), 16):
        out.append('  .byte ' + ','.join(f'${v & 255:02X}' for v in vals[i:i+16]))

# ---------------------------------------------------------------- tuning
FOV_DEG   = 66.0
NRAYS     = 80
# view is 160 colour clocks (~1.6 scanlines each) x 128 scanlines; rows are 2 scanlines
K_ROWS    = (160 * 1.6 / 2) / math.tan(math.radians(FOV_DEG / 2)) / 4.0
MAXH      = 32       # half of view height in rows
SPEED     = 0.10     # tiles per game tick (1/20 s)
ANG       = 1024     # angle units per circle

# ---------------------------------------------------------------- page-aligned tables
seg("TABLES")
sq = [n * n // 4 for n in range(512)]
table('sqlo', [v & 255 for v in sq])
table('sqhi', [v >> 8 for v in sq])
sqm = [sq[abs(k - 255)] for k in range(512)]
table('sqmlo', [v & 255 for v in sqm])
table('sqmhi', [v >> 8 for v in sqm])

def inv(q):  # 1/cos(theta) for theta = q*90/256 deg, 8.8 fixed, saturating
    c = math.cos(math.radians(q * 90.0 / 256.0))
    if c < 1e-9:
        return 0xFFFF
    return min(0xFFFF, int(round(256.0 / c)))
invc = [inv(q) for q in range(256)]
invs = [inv(256 - q) for q in range(256)]
table('invcl', [v & 255 for v in invc]); table('invch', [v >> 8 for v in invc])
table('invsl', [v & 255 for v in invs]); table('invsh', [v >> 8 for v in invs])

mvx = [int(round(math.cos(2 * math.pi * k / 256) * SPEED * 256)) & 0xFFFF for k in range(256)]
mvy = [int(round(math.sin(2 * math.pi * k / 256) * SPEED * 256)) & 0xFFFF for k in range(256)]
table('movxl', [v & 255 for v in mvx]); table('movxh', [v >> 8 for v in mvx])
table('movyl', [v & 255 for v in mvy]); table('movyh', [v >> 8 for v in mvy])

# projected scale = half wall height in rows (unclamped, max 255).  Walls clamp
# it to 32; sprites and the depth buffer use it raw.
def sc_of(d):
    if d <= 0.01:
        return 255
    return max(0, min(255, int(round(K_ROWS / d))))

# ---- sprite scaling, indexed by scale s
XRATIO = (80 / math.tan(math.radians(FOV_DEG / 2))) / K_ROWS   # px of lateral per tile per unit s
SPR_W  = 0.55        # enemy width in tiles
SPR_H  = 0.80        # enemy height in tiles (wall = 1.0 = 2s rows)
uidx, sprm, sprsz, sprsh, htab, dvt = [], [], [], [], [], []
for sv in range(256):
    W = SPR_W * XRATIO * sv                 # ideal width in colour clocks
    m = 1 if W <= 9 else (2 if W <= 18 else 4)
    sprm.append(m); sprsz.append({1: 0, 2: 1, 4: 3}[m]); sprsh.append({1: 0, 2: 1, 4: 2}[m])
    for k in range(8):
        if W <= 0:
            uidx.append(255); continue
        du = 16.0 * m / W
        u = 8 + (k - 3.5) * du
        uidx.append(int(math.floor(u)) if 0 <= u < 16 else 255)
    H = max(1, min(255, int(round(SPR_H * 2 * sv))))
    htab.append(H)
    dvt.append(min(0xFFFF, int(round(16 * 256 / H))))
# distinct column mappings -> pattern index per scale; textures are pre-baked per pattern
PATS = []
spat = []
for sv in range(256):
    p = tuple(uidx[sv * 8: sv * 8 + 8])
    if p not in PATS:
        PATS.append(p)
    spat.append(PATS.index(p))
assert len(PATS) <= 32
SPRPATS = list(PATS)                       # (the music section reuses the name PATS)
table('spat', spat)
table('sprm', sprm)
table('sprhw', [4 * m for m in sprm])
table('sprsz', sprsz)
table('sprsh', sprsh)
table('htab', htab)
table('dvl', [v & 255 for v in dvt]); table('dvh', [v >> 8 for v in dvt])
# camera cos for sprite projection, s.7, half circle of the 1024-step angle (page aligned)
table('cs9', [int(round(127 * math.cos(2 * math.pi * k / 1024))) & 255 for k in range(512)])
# sprite scale as 8.8 fixed point over the same depth bins as scalea/scaleb
def s88(d):
    return 65535 if d <= 0.01 else min(65535, int(round(K_ROWS / d * 256)))
for nm, step in (('a', 64.0), ('b', 8.0)):
    v = [s88(i / step) for i in range(256)]
    table('s88l' + nm, [x & 255 for x in v]); table('s88h' + nm, [x >> 8 for x in v])

# The maze itself is generated at run time (see genmaze in depthsofdoom.s).
MAXEN = 8                                  # enemy tables in RAM are 8 bytes each

# ---------------------------------------------------------------- other data
seg("RODATA")
offs, cosf = [], []
t30 = math.tan(math.radians(FOV_DEG / 2))
for i in range(NRAYS):
    x = ((i + 0.5) - NRAYS / 2) / (NRAYS / 2) * t30
    a = math.atan(x)
    offs.append(int(round(a * ANG / (2 * math.pi))) & 0xFFFF)
    cosf.append(min(255, int(round(math.cos(a) * 256))))
table('offlo', [v & 255 for v in offs]); table('offhi', [v >> 8 for v in offs])
table('cosfix', cosf)

# GTIA mode 9 view: ceiling/floor brightness in 8 bands of 4 rows (row 0 = the
# top/bottom edge, band 7 = the horizon), as right nibble, left nibble, both
G = [10, 8, 7, 6, 4, 3, 2, 0]
table('gtab', G + [g << 4 for g in G] + [g * 17 for g in G])
table('nibr', [max(0, min(15, i - 8)) for i in range(32)])   # index = brightness + 8
table('nibl', [max(0, min(15, i - 8)) << 4 for i in range(32)])
# LMS high-byte offsets of the 64 rows (row * 40)
# wall brightness by scale / 4 (distance fog): lit faces, shaded faces
fl = [max(1, min(11, int(round(1 + 10 * min(1.0, (4 * i + 2) / 40.0) ** 0.8)))) for i in range(64)]   # walls top out at 11: the exit (15) glows
table('fogl', fl)
table('fogs', [max(1, v - 3) for v in fl])

def vis(s):                         # the text as shown: [..] marks inverse video
    return s.replace('[', '').replace(']', '')
def screencode(s):                  # (text in [brackets]: inverse, for keys and buttons)
    r = []
    inv = 0
    for ch in s:
        if ch in '[]':
            inv = 0x80 if ch == '[' else 0
            continue
        o = ord(ch)
        if 32 <= o < 96:
            r.append((o - 32) | inv)
        elif 96 <= o < 128:
            r.append(o | inv)
        else:
            r.append(0)
    return r
def msg(s):                         # message row text: left pad, characters, $FF
    pad = (40 - len(vis(s))) // 2
    return [pad] + screencode(s) + [0xFF]
def line40(s):
    pad = (40 - len(vis(s))) // 2
    return ' ' * pad + s + ' ' * (40 - pad - len(vis(s)))

HUD1 = " PISTOL  50  KILLS 0/0  ---  HEALTH 100%"
assert len(HUD1) == 40, len(HUD1)
table('hudline1', screencode(HUD1))
for name, pos in (('WPNPOS', HUD1.index("PISTOL")), ('AMMOPOS', HUD1.index("50")),
                  ('KILLPOS', HUD1.index("0/")), ('KEYPOS', HUD1.index("---")),
                  ('HEALTHPOS', HUD1.index("100"))):
    out.append(f'.export {name}')
    out.append(f'{name} = {pos}')
table('msg_level', msg("FIND THE EXIT DOOR!"))
out.append('.export LVLPOS')
out.append('LVLPOS = 0')
table('msg_empty', msg("OUT OF AMMO"))
table('msg_died', msg("YOU DIED - [R] RETRY SEED, [START] MENU"))
table('msg_tout', msg("OUT OF TIME - [R] RETRY, [START] MENU"))
# top bar, two lines: score / level / high score, then seed / heading / clock
TOP1 = " SCORE 000000    LEVEL 00    HIGH 000000"
TOP2 = " SEED ----" + " " * 6 + "." * 9 + " " * 5 + "TIME 00:00"
assert len(TOP1) == 40 and len(TOP2) == 40, (len(TOP1), len(TOP2))
HUD3 = TOP1 + TOP2
table('hudline3', screencode(HUD3))
for name, pos in (('SCOREPOS', HUD3.index("000000")), ('HIGHPOS', HUD3.index("000000", 10)),
                  ('SEEDPOS', HUD3.index("----")), ('TIMEPOS', HUD3.index("00:00")),
                  ('LVLTPOS', HUD3.index("LEVEL 00") + 6), ('DIRPOS', HUD3.index("........."))):
    out.append(f'.export {name}')
    out.append(f'{name} = {pos}')

# 16 columns, 2 colour clocks each, x=112..143.  G = gun (player 0, over the
# hand), H = hand (players 3 + 1).  Gun occupies columns 4-11 only.
PIC = [
    "......GG........",
    "......GG........",
    ".....GGGG.......",
    ".....GGGG.......",
    ".....GGGG.......",
    "....GGGGGG......",
    "....GGGGGG......",
    "....GG..GG......",
    "..HHGGGGGGHH....",
    ".HHHHGGGGHHHH...",
    ".HHHHGGGGHHHHH..",
    "HHHHHHGGHHHHHHH.",
    "HHHHHHHHHHHHHHH.",
    "HHHHHHHHHHHHHHHH",
    "HHHHHHHHHHHHHHHH",
    "HHHHHHHHHHHHHHHH",
]
def bits(s, ch):
    v = 0
    for c in s:
        v = (v << 1) | (c in ch)
    return v
for r in PIC:
    assert all(c != 'G' for c in r[:4] + r[12:]), "gun outside its player"
table('gungfx', [bits(r[4:12], 'G') for r in PIC])
# hand is one quad-width player: each bit covers two of the picture's columns.
# It fills under the gun on hand rows so the grip has no holes.
def handbits(r):
    ch = 'H' + ('G' if 'H' in r else '')
    v = 0
    for i in range(8):
        v = (v << 1) | (r[2 * i] in ch or r[2 * i + 1] in ch)
    return v
table('handq', [handbits(r) for r in PIC])

IMP = [
    "....##....##....",
    "....###..###....",
    ".....######.....",
    "....#.####.#....",
    "....########....",
    ".....##..##.....",
    "..############..",
    ".##############.",
    "##..########..##",
    "##..########..##",
    "#...########...#",
    "....########....",
    "....###..###....",
    "....###..###....",
    "...####..####...",
    "...####..####...",
]
CORPSE = ["................"] * 11 + [
    "................",
    "..##..####..##..",
    ".##############.",
    "################",
    ".##############.",
]
for name, pic in (('imp', IMP), ('corpse', CORPSE)):
    assert len(pic) == 16 and all(len(r) == 16 for r in pic)
    baked = []
    for p in PATS:                         # 16 rows per pattern, bit 7 = leftmost
        for r in pic:
            v = 0
            for u in p:
                v = (v << 1) | (u < 16 and r[u] == '#')
            baked.append(v)
    table(name + 'b', baked)
FLASH = [
    "...##...",
    "..#..#..",
    ".#.##.#.",
    "#.####.#",
    ".######.",
    "..####..",
    "...##...",
    "........",
]
table('flashgfx', [bits(r, '#') for r in FLASH])

# ---------------------------------------------------------------- music
# Original compositions (music.py): a title theme and one track per level.
# The track playing sits in MBUF; the rest wait in cartridge bank 9.
import music as MUS
TRK = MUS.all_tracks()
table('mfreq', MUS.FREQ)
out.append('.export MBUF')
out += MUS.track_lines(TRK[0], 'MBUF')            # the title theme, from power-on
for k, v in list(MUS.OFF.items()) + [('MTLEN', MUS.MTLEN)]:
    out.append(f'.exportzp {k}')
    out.append(f'{k} = {v}')
seg("TRACKS")                                     # bank 9: one page per track
for i, t in enumerate(TRK):
    out += MUS.track_lines(t)
    out.append(f'  .res {256 - MUS.MTLEN}')
seg("RODATA")


# ================================================================ stage 2 (image B)
seg("RODATA2")
WEAPONS = ["PISTOL ", "SHOTGUN", "SMG    "]
table('wpnname', screencode(''.join(WEAPONS)))
SHOTGUN_PIC = [                  # a Remington Model 10 trench gun, from behind: bayonet
                                 #   up over the muzzle, ventilated heat shield, pump
    ".......G........",
    "......GGG.......",
    "......GGG.......",
    "......GGG.......",
    ".....GGGGG......",
    ".....G.G.G......",
    ".....GGGGG......",
    ".....G.G.G......",
    "....GGGGGGG.....",
    "....GG...GG.....",
    "..HHGGGGGGGHH...",
    ".HHHHGGGGGHHH...",
    ".HHHHHGGGHHHHH..",
    "HHHHHHHGHHHHHHH.",
    "HHHHHHHHHHHHHHHH",
    "HHHHHHHHHHHHHHHH",
]
CHAIN_PIC = [
    "....G.GG.G......",
    "....G.GG.G......",
    "....G.GG.G......",
    "....GGGGGG......",
    "....G.GG.G......",
    "....G.GG.G......",
    "....GGGGGG......",
    "....GGGGGGG.....",
    "....GGGGGGG.....",
    "....GGGGGGG.....",
    "..HHGGGGGGGHH...",
    ".HHHHGGGGGHHH...",
    ".HHHHHGGGHHHHH..",
    "HHHHHHHGHHHHHHH.",
    "HHHHHHHHHHHHHHHH",
    "HHHHHHHHHHHHHHHH",
]
guns = []
for pic in (PIC, SHOTGUN_PIC, CHAIN_PIC):
    assert len(pic) == 16 and all(len(r) == 16 for r in pic)
    for r in pic:
        assert all(c != 'G' for c in r[:4] + r[12:]), "gun outside its player"
    guns += [bits(r[4:12], 'G') for r in pic]
table('gungfx3', guns)                      # 3 x 16 rows
table('handq3', [handbits(r) for pic in (PIC, SHOTGUN_PIC, CHAIN_PIC) for r in pic])

PICKUPS = {          # solid shapes: they're drawn small and half height
 'ammo': [
    "................",
    "................",
    "................",
    "....########....",
    "....########....",
    "....#..##..#....",
    "....########....",
    "....########....",
    "....#..##..#....",
    "....########....",
    "....########....",
    "....#..##..#....",
    "....########....",
    "....########....",
    "................",
    "................"],
 'health': [
    "................",
    "................",
    "..############..",
    "..############..",
    "..#####..#####..",
    "..#####..#####..",
    "..##........##..",
    "..##........##..",
    "..#####..#####..",
    "..#####..#####..",
    "..############..",
    "..############..",
    "..############..",
    "................",
    "................",
    "................"],
 'time': [
    "................",
    "..############..",
    "..############..",
    "...##########...",
    "....########....",
    ".....######.....",
    "......####......",
    ".......##.......",
    "......####......",
    ".....######.....",
    "....########....",
    "...##########...",
    "..############..",
    "..############..",
    "................",
    "................"],
 'shotgun': [                      # the trench gun, muzzle left: bayonet, vented
                                  #   heat shield, magazine tube, pump, stock
    "................",
    "................",
    "................",
    "................",
    "................",
    ".....#.#.#.#....",
    "################",
    "##..###########.",
    "......####..####",
    "............####",
    ".............###",
    "................",
    "................",
    "................",
    "................",
    "................",
    ],
 'chaingun': [                     # the SMG: a MAC-10, muzzle left (stubby barrel,
    "................",           #   boxy receiver, cocking knob on top, trigger
    "................",           #   guard, the magazine down through the grip)
    "................",
    "........##......",
    ".....#########..",
    "..############..",
    "..############..",
    ".....#########..",
    ".....#..#.###...",
    ".....####.###...",
    "..........###...",
    "..........###...",
    "..........###...",
    "..........###...",
    "................",
    "................"],
 'pistol': [                       # pistol ammo: a black semi-auto, muzzle left
    "................",
    "................",
    "................",
    "##########..##..",
    "##############..",
    "##########..####",
    "........##..####",
    "........########",
    "............####",
    "............####",
    "............####",
    "................",
    "................",
    "................",
    "................",
    "................",
    ],
 'key': [
    "................",
    "................",
    "................",
    "................",
    "..############..",
    "..############..",
    "................",
    "..############..",
    "..##..########..",
    "..##..########..",
    "..############..",
    "................",
    "................",
    "................",
    "................",
    "................"],
}
PKORDER = ['ammo', 'health', 'time', 'shotgun', 'chaingun', 'key', 'pistol']
for name in PKORDER:
    if name == 'pistol': seg("RODATA")     # (image B is full: this one goes in image A)
    pic = [r[:16].ljust(16, '.') for r in PICKUPS[name]]
    assert len(pic) == 16, name
    baked = []
    for p_ in SPRPATS:
        for r in pic:
            v = 0
            for u in p_:
                v = (v << 1) | (u < 16 and r[u] == '#')
            baked.append(v)
    table('pk_' + name, baked)
seg("RODATA2")
out.append('.export pklo, pkhi')
out.append('pklo: .byte ' + ','.join(f'<pk_{n}' for n in PKORDER))
out.append('pkhi: .byte ' + ','.join(f'>pk_{n}' for n in PKORDER))
table('pkcol', [0xC8, 0x44, 0x2E, 0x24, 0x06, 0x86, 0x00])   # super ammo green, health red, hourglass yellow,
                                                             # shotgun, SMG, key, pistol ammo black

table('msg_kill', msg("KILL THE MONSTERS TO GET THE KEYCARD!"))
for name, text in (('msg_gotkey', "KEYCARD ACCEPTED - THE EXIT IS OPEN"),
                   ('msg_health', "HEALTH +25"),
                   ('msg_time', "TIME +30 SECONDS"),
                   ('msg_shotgun', "SHOTGUN! (PRESS [2])"),
                   ('msg_chain', "SMG! (PRESS [3])"),
                   ('msg_noweapon', "YOU DON'T HAVE THAT WEAPON"),
                   ('msg_texon', "TEXTURES ON ([T])"),
                   ('msg_texoff', "TEXTURES OFF ([T]) - FASTER"),
                   ('msg_pause', "PAUSED - PRESS [P] OR [START]")):
    table(name, msg(text))
seg("RODATA")                       # (image A: room there)
table('msg_super', msg("SUPER AMMO - EVERY GUN FULL"))
for name, dig, text in (('msg_pammo', 'PAMDIG', "PISTOL AMMO +15"), ('msg_sammo', 'SAMDIG', "SHOTGUN SHELLS +15"),
                        ('msg_mammo', 'MAMDIG', "SMG AMMO +15")):
    table(name, msg(text))
    out.append(f'.export {dig}')
    out.append(f'{dig} = {line40(text).index("15")}')
seg("RODATA2")


# ---------------------------------------------------------------- stage 3: monster frames
def legs(top, bottom):
    return top + bottom
IMP2 = IMP[:6] + [
    "..############..",
    ".##############.",
    ".##.########.##.",
    "##..########..##",
    "##..########..##",
    "....########....",
    "....###..###....",
    "...###....###...",
    "..###......###..",
    "..##........##..",
]
IMPATK = [
    "##..##....##..##",
    "##..###..###..##",
    "##...######...##",
    "##..#.####.#..##",
    ".##.########.##.",
    "..###.#..#.###..",
    "...##########...",
    "....########....",
    "....########....",
    "....########....",
    "....########....",
    "....########....",
    "....###..###....",
    "....###..###....",
    "...####..####...",
    "...####..####...",
]
BRUTE1 = [
    "................",
    "................",
    "..#..........#..",
    "..##........##..",
    "...##########...",
    "..############..",
    ".###.######.###.",
    ".##############.",
    "################",
    "##.##########.##",
    "#..##########..#",
    "...##########...",
    "...###....###...",
    "...###....###...",
    "..####....####..",
    "..####....####..",
]
BRUTE2 = BRUTE1[:12] + [
    "...###....###...",
    "..###......###..",
    ".####......####.",
    ".###........###.",
]
BRUTEATK = [
    "................",
    "..#..........#..",
    "..##........##..",
    "...##########...",
    "..############..",
    ".###.######.###.",
    ".##..........##.",
    ".#.#.#.##.#.#.#.",
    "################",
    "##.##########.##",
    "#..##########..#",
    "...##########...",
    "...###....###...",
    "...###....###...",
    "..####....####..",
    "..####....####..",
]
SPIT1 = [
    "................",
    "................",
    "................",
    "................",
    "................",
    "....##....##....",
    "...####..####...",
    "..##.##..##.##..",
    ".##############.",
    "################",
    "################",
    ".##############.",
    "..############..",
    "..##.######.##..",
    ".###........###.",
    ".##..........##.",
]
SPIT2 = ["................"] + SPIT1[:5] + [
    "....##....##....",
    "...####..####...",
    "..##.##..##.##..",
    "################",
    "################",
    "################",
    "################",
    "###.########.###",
    "###..........###",
    "##............##",
]
SPITATK = SPIT1[:8] + [
    "################",
    "#..............#",
    "#.#.#.#..#.#.#.#",
    ".##############.",
    "..############..",
    "..##.######.##..",
    ".###........###.",
    ".##..........##.",
]
FIRE = ["................"] * 3 + [
    "......####......",
    ".....######.....",
    "....########....",
    "....########....",
    "....########....",
    ".....######.....",
    "......####......",
] + ["................"] * 6
FALL = ["................"] * 7 + [
    "......####......",
    ".....######.....",
    "...##########...",
    "..############..",
    ".##..######..##.",
    "....########....",
    "...####..####...",
    "..####....####..",
    ".####......####.",
]
for name, pic in (('imp2', IMP2), ('impatk', IMPATK), ('brute1', BRUTE1), ('brute2', BRUTE2),
                  ('bruteatk', BRUTEATK), ('spit1', SPIT1), ('spit2', SPIT2),
                  ('spitatk', SPITATK), ('fire', FIRE), ('fall', FALL)):
    assert len(pic) == 16 and all(len(r) == 16 for r in pic), name
    baked = []
    for p_ in SPRPATS:
        for r in pic:
            v = 0
            for u in p_:
                v = (v << 1) | (u < 16 and r[u] == '#')
            baked.append(v)
    table(name + 'b', baked)
TEX = ['imp', 'imp2', 'impatk', 'brute1', 'brute2', 'bruteatk',
       'spit1', 'spit2', 'spitatk', 'fire', 'fall', 'corpse']
out.append('.export texlo, texhi')
out.append('texlo: .byte ' + ','.join(f'<{n}b' for n in TEX))
out.append('texhi: .byte ' + ','.join(f'>{n}b' for n in TEX))


# ---------------------------------------------------------------- stage 4: wall textures
# Each wall column is split into 7 horizontal bands (fractions of the wall's height, in
# 32nds, symmetric about the horizon): course 0-7, mortar 7-8, course 8-15, mortar 15-17,
# course 17-24, mortar 24-25, course 25-32.  The top-half band ends come from tables
# indexed by scale; the bottom half mirrors them (row -> 64 - row).
seg("RODATA")
# (band ends are worked out at run time: 32 - s + k s / 8)
# quarter-circle sin/cos (s.7 magnitudes) for where a ray hits along the wall
table('qcos', [int(round(127 * math.cos(math.pi / 2 * a / 256))) for a in range(257)])   # (sin(a) = qcos[256 - a])
seg("RODATA2")
# 16 columns x 7 bands.  B = base, D = detail, R = door colour (PF0).
# Textures: 16 columns x 8 rows for the top half of a wall (row 0 at its top,
# row 7 at the horizon); the bottom half mirrors them.  Each character is an
# offset from the ray's own (distance-fogged) shade.
SHADE = {'=': 0, '-': -2, '_': -4, '#': -7, '+': 2, '^': 4, '*': 8}
TEXTURES = {
 'hull':    ["________________",      # corridor walls: a dark trim at the top and
             "================",      #   bottom and a rail at eye level (the same
             "================",      #   in every column, so no texture column is
             "================",      #   worked out, and only 3 runs: cheap)
             "================",
             "================",
             "================",
             "________________"],
 'door':    ["################",      # exit / locked exit: frame, double door
             "#______________#",
             "#_=====__=====_#",
             "#_=+===__=+===_#",
             "#_=====__=====_#",
             "#_=====__=====_#",
             "#_=====__=====_#",
             "#______________#"],
 'plates':  ["^^^^^^^_^^^^^^^_",
             "^======_^======_",
             "^======_^======_",
             "^==-===_^==-===_",
             "^======_^======_",
             "^======_^======_",
             "^======_^======_",
             "________________"],
 'vents':   ["================",
             "-^^^^^^^^^^^^^^-",
             "-##############-",
             "-^^^^^^^^^^^^^^-",
             "-##############-",
             "-^^^^^^^^^^^^^^-",
             "-##############-",
             "================"],
 'pillars': ["=_^^^^^^_=======",
             "=_-+^^+-_=======",
             "=_-+^^+-_==-====",
             "=_-+^^+-_=======",
             "=_-+^^+-_=======",
             "=_-+^^+-_====-==",
             "=_-+^^+-_=======",
             "=_-+^^+-_======="],
 'tech':    ["________________",
             "_^^^^^^__^^^^^^_",
             "_^____^__^____^_",
             "_^_**_^__^_--_^_",
             "_^____^__^____^_",
             "_^^^^^^__^^^^^^_",
             "================",
             "-==-==-==-==-==-"],
 'bricks':  ["________________",
             "+======_+======_",
             "=======_=======_",
             "________________",
             "===_+======_+===",
             "===_=======_====",
             "________________",
             "+======_+======_"],
 'hazard':  ["****####****####",      # bright stripes beside the exit
             "***####****####*",
             "**####****####**",
             "*####****####***",
             "####****####****",
             "###****####****#",
             "##****####****##",
             "#****####****###"],
 'pipes':   ["=-+^+-====-+^+-=",
             "=-+^+-====-+^+-=",
             "_^^^^^_==_^^^^^_",
             "=-+^+-====-+^+-=",
             "=-+^+-====-+^+-=",
             "=-+^+-====-+^+-=",
             "_^^^^^_==_^^^^^_",
             "=-+^+-====-+^+-="],
 'lights':  ["________________",
             "================",
             "_**************_",
             "________________",
             "================",
             "================",
             "======-==-======",
             "-==============-"],
 'grate':   ["________________",
             "_=_=_=_=_=_=_=_=",
             "________________",
             "_=_=_=_=_=_=_=_=",
             "________________",
             "_=_=_=_=_=_=_=_=",
             "________________",
             "_=_=_=_=_=_=_=_="],
 'ribs':    ["________________",
             "^+==-_##^+==-_##",
             "^+==-_##^+==-_##",
             "^+==-_##^+==-_##",
             "^+==-_##^+==-_##",
             "^+==-_##^+==-_##",
             "^+==-_##^+==-_##",
             "^+==-_##^+==-_##"],
 'circuit': ["--+-----------+-",
             "--+---^+++++--+-",
             "--+---+-----+++-",
             "--^+++^-------+-",
             "------+---^+++^-",
             "-+++--+---+-----",
             "-+-^++^---+-----",
             "-+--------^++++-"],
}
ORDER = ('hull', 'door', 'plates', 'vents', 'pillars', 'tech', 'bricks', 'hazard',
         'pipes', 'lights', 'grate', 'ribs', 'circuit')
# hazardm: the stripes mirrored, for the stripe tiles on the exit's west and north
#   sides (texture columns run with x or y), so every stripe points at the door
TEXTURES['hazardm'] = [r[::-1] for r in TEXTURES['hazard']]
ORDER += ('hazardm',)
TCOLS, TROWS = 16, 8
for nm in ORDER:
    assert len(TEXTURES[nm]) == TROWS and all(len(r) == TCOLS for r in TEXTURES[nm]), nm
NID = TCOLS * len(ORDER)
assert NID <= 256
# tdel[id * 4 + band] = offset + 8 (so offset + shade is 0-31: no clamping).
#   4 bands per half wall (2 texture rows each): each band takes the stronger
#   of its two rows, so thin lines (trims, rails) don't vanish
seg("RODATA")
def _strong(a, b): return a if abs(a) >= abs(b) else b
table('tdel', [_strong(SHADE[TEXTURES[nm][2 * b][u]], SHADE[TEXTURES[nm][2 * b + 1][u]]) + 8
               for nm in ORDER for u in range(TCOLS) for b in range(TROWS // 2)])
seg("RODATA2")
out.append('.export NID')
out.append(f'NID = {NID}')
# automap compass rose: (x, y) pixels in the right margin, $FF ends
GLYPH = {'N': ["#.#", "###", "###", "#.#", "#.#"], 'E': ["###", "#..", "##.", "#..", "###"],
         'S': [".##", "#..", ".#.", "..#", "##."], 'W': ["#.#", "#.#", "###", "###", "#.#"]}
CX, CY = 151, 31
pts = set()
for ch, (gx, gy) in (('N', (CX - 1, CY - 14)), ('S', (CX - 1, CY + 10)), ('W', (CX - 7, CY - 2)), ('E', (CX + 5, CY - 2))):
    for r, row in enumerate(GLYPH[ch]):
        for c, v in enumerate(row):
            if v == '#': pts.add((gx + c, gy + r))
for d in range(-6, 7):
    pts.add((CX, CY + d))
for d in range(-3, 4):
    pts.add((CX + d, CY))
assert all(0 <= x < 160 and 0 <= y < 64 for x, y in pts)
cp = []
for x, y in sorted(pts):
    cp += [x, y]
table('compass', cp + [0xFF])

# ---------------------------------------------------------------- overlay data
seg("OVL")
def mode7(s, colours):              # big text: bits 6-7 pick COLPF0-3
    r = []
    for ch, c in zip(s, colours):
        r.append(0 if ch == ' ' else (ord(ch) - 32) | (int(c) << 6))
    return r
TITLE = "   DEPTHS OF DOOM   "
TCOL  = "00000000001103333000"           # DEPTHS: PF0, OF: PF1, DOOM: PF3
table('mtitle', mode7(TITLE, TCOL))
OPT2 = line40("PLAY YOUR OWN SEED:  0000")
table('mopt1', screencode(line40("START WITH A RANDOM SEED")))
table('mopt2', screencode(OPT2))
table('mhint', screencode(line40("TYPE 4 DIGITS TO SET YOUR SEED")))
HS = line40("HIGH SCORE  000000")
table('mhs', screencode(HS))
table('mhelp1', screencode(line40("STICK TO CHOOSE, [FIRE] TO PLAY")))
table('mhelp2', screencode(line40("[P] PAUSE   [SELECT] MAP   [T] TEXTURES")))
table('mcols', [0x0A, 0x0E, 0x00, 0x44, 0x00])  # COLOR0-4: DEPTHS gray, text white, DOOM red, black
for name, pos in (('SEEDCOL', OPT2.index("0000")), ('HSCOL', HS.index("000000"))):
    out.append(f'.exportzp {name}')
    out.append(f'{name} = {pos}')
table('imsg1', msg("WHERE... AM I?"))
table('imsg2', msg("NO MEMORY OF HOW YOU GOT HERE."))
table('imsg3', msg("ONLY ONE THING IS CERTAIN:"))
table('imsg4', msg("YOU MUST ESCAPE."))
seg("RA3")
# keycard lines, built per level with the level's colour (items.s: build)
for name, text in (('kpre', "FIND THE "), ('ksuf', " KEYCARD, THEN EXIT!"),
                   ('npre', "LOCKED - FIND THE "), ('nsuf', " KEYCARD")):
    table(name, screencode(text) + [0xFF])
CN = ["GRAY", "GOLD", "VIOLET", "TEAL"]
cn, offs = [], []
for c in CN:
    offs.append(len(cn)); cn += screencode(c) + [0xFF]
table('cnames', cn)
THEMEC = [0, 1, 0, 2, 0, 3]          # theme1 hues: gray, gold, gray, lavender, gray, teal
table('cnoff', [offs[t] for t in THEMEC])
seg("PKM1")                                    # ($2BE5)
table('msg_amax', msg("AMMO MAX"))
table('msg_tmax', msg("TIME MAX"))
seg("PKM2")                                    # ($3FEF)
table('msg_hmax', msg("HEALTH MAX"))
seg("OVLC4")
table('msg_god', msg("GOD MODE"))
LSEL = "LEVEL 00? STICK, [FIRE]"
table('msg_lsel', msg(LSEL))
out.append('.exportzp LSCOL')
out.append(f'LSCOL = {(40 - len(vis(LSEL))) // 2 + vis(LSEL).index("00")}')
seg("OVLB4")
table('msg_demo', msg("DEMO - PRESS [ANY KEY] FOR THE MENU"))
GL = {'G': [".###.", "#....", "#....", "#.###", "#...#", "#...#", ".###."],
      'A': [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
      'M': ["#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"],
      'E': ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
      'O': [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
      'V': ["#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."],
      'R': ["####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"],
      ' ': ["....."] * 7}
bits = []
for r in range(7):
    row = ''.join(GL[c][r] + '.' for c in "GAME OVER")[:53].ljust(56, '.')
    bits += [int(row[i:i+8].replace('#', '1').replace('.', '0'), 2) for i in range(0, 56, 8)]
seg("OVLB3")
table('banbits', bits)

open('data.s', 'w').write('\n'.join(out) + '\n')
print("tables written")
