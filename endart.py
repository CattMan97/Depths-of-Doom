#!/usr/bin/env python3
"""Pictures for the ending (cartridge banks 6-7), written as end.bin plus
enddata.s (where each item is: bank and address).

  corridor   80x96 GTIA mode 9 (16 grey levels): the last corridor, with
             daylight pouring through a door at its end
  wasteland  80x96, shown in an orange hue: a ruined city under a dusty sun
  walk       the escapee seen from behind, walking to the door: one
             player-missile frame per animation step (2 players, 16 colour
             clocks wide, 2-line resolution), shrinking with distance
  stand      the escapee, standing, looking out over the wasteland
  theend     the words THE END as nibble masks (fade in, in the overlay)

Pictures are packed: 0nnnnnnn = n+1 literal bytes, 10nnnnnn = a run of
n+2 copies of the next byte, 11nnnnnn = n+1 bytes copied from the row
above (40 bytes back).
"""
import math, random, sys
from PIL import Image, ImageDraw

W, H = 80, 96                  # mode 9 pixels: 2 colour clocks x 2 scanlines
ASPECT = 1.72                  # one pixel is ~1.72x as wide as it is tall
SL_PER_CC = 1.72               # a colour clock is ~1.72 scanlines wide

def clamp(v, lo=0, hi=15):
    return max(lo, min(hi, int(v)))

# ------------------------------------------------------------------ corridor
VX, VY = 40, 46                # vanishing point (pixels)
F = 60.0                       # focal length (rows)
HW, EYE, CEIL = 1.5, 1.6, 1.3  # corridor half width, eye height, ceiling above eye
ZEND = 5.4                     # the end wall, with the door
DOORW, DOORH = 0.55, 2.25      # door half width, height

def proj(X, Y, Z):
    return VX + F * X / (Z * ASPECT), VY - F * Y / Z

def corridor():
    img = [[0] * W for _ in range(H)]
    for py in range(H):
        for px in range(W):
            dx = (px + 0.5 - VX) * ASPECT / F
            dy = -(py + 0.5 - VY) / F
            best = None
            # walls x = +-HW, floor y = -EYE, ceiling y = CEIL, end z = ZEND
            cands = []
            if dx: cands.append(('wall', HW / abs(dx)))
            if dy < 0: cands.append(('floor', EYE / -dy))
            if dy > 0: cands.append(('ceil', CEIL / dy))
            cands.append(('end', ZEND))
            kind, z = min(cands, key=lambda c: c[1])
            X, Y = dx * z, dy * z
            near = z / ZEND                         # 0 near .. 1 at the door
            if kind == 'end':
                if abs(X) < DOORW and Y < DOORH - EYE:
                    v = 15                          # daylight
                elif abs(X) < DOORW + 0.12 and Y < DOORH - EYE + 0.12:
                    v = 12                          # glare round the frame
                else:
                    v = 5 + 3 * max(0, 1 - (abs(X) - DOORW) / 1.0)
            elif kind == 'wall':
                v = 1.5 + 6.5 * near ** 2.2
                if (z % 0.9) < 0.07: v -= 2            # panel seams
                if -0.35 < Y < -0.2: v -= 1.5          # a dark rail
                if abs(Y - 0.55) < 0.06: v += 1        # a lighter rib
                # light spilling from the door onto the walls near it
                if z > ZEND - 1.4 and Y < DOORH - EYE:
                    v += 3 * (z - (ZEND - 1.4)) / 1.4
            elif kind == 'floor':
                v = 1 + 7 * near ** 2.0
                if (z % 0.45) < 0.05: v -= 1           # grating
                # the pool of daylight on the floor, widening toward us
                spread = DOORW + (ZEND - z) * 0.18
                if abs(X) < spread and z > ZEND - 2.6:
                    v += 5 * (1 - (ZEND - z) / 2.6)
            else:  # ceiling
                v = 0.5 + 4 * near ** 2.0
                if (z % 1.8) < 0.08: v += 2            # dead light strips
            img[py][px] = clamp(round(v))
    return img

# ------------------------------------------------------------------ wasteland
HORIZON = 60

def wasteland():
    rnd = random.Random(1945)
    img = [[0] * W for _ in range(H)]
    SX, SY, SR = 58, 38, 7.0                     # sun (rows); x radius = r/ASPECT
    for y in range(H):
        for x in range(W):
            if y < HORIZON:
                t = y / HORIZON
                v = 3 + 8.5 * t ** 1.6
                ddx = (x + 0.5 - SX) * ASPECT
                ddy = y + 0.5 - SY
                d = math.hypot(ddx, ddy)
                if d < SR: v = 15
                elif d < SR * 3.2: v += 4.0 * (1 - (d - SR) / (SR * 2.2))
                # smoke bands drifting across the sky
                for (cy, ch, cs, amp) in ((24, 3.0, 0.11, 2.2), (31, 2.0, 0.07, 1.6), (45, 2.5, 0.05, 1.8)):
                    yy = cy + 1.6 * math.sin(x * cs + cy)
                    if abs(y - yy) < ch:
                        v -= amp * (1 - abs(y - yy) / ch)
                img[y][x] = clamp(round(v), 2)
            else:
                t = (y - HORIZON) / (H - HORIZON)
                img[y][x] = clamp(round(4.2 - 3.2 * t))
    # far skyline: hazy ruins just lighter than the ground
    def tower(x0, w, h, lum, rnd, broken=True, windows=False, base=HORIZON):
        cut = rnd.choice((-1, 1)) if broken else 0
        for i in range(w):
            top = base - h
            if broken:
                top += int(abs(cut * (i if cut > 0 else w - 1 - i)) * rnd.uniform(0.4, 1.3))
                top += rnd.choice((0, 0, 0, 1, 2))
            for y in range(max(0, top), base):
                x = x0 + i
                if 0 <= x < W:
                    img[y][x] = lum
        if windows:                             # blown-out windows: sky
            for y in range(base - h + 3, base - 2, 3):
                for i in range(1, w - 1, 2):
                    if rnd.random() < 0.3 and 0 <= x0 + i < W:
                        img[y][x0 + i] = clamp(round(3 + 8.5 * (y / HORIZON) ** 1.6))
            for y in range(max(0, base - h), base - h + h // 3):   # bare girders
                for i in range(1, w, 2):
                    if 0 <= x0 + i < W and rnd.random() < 0.8:
                        img[y][x0 + i] = clamp(round(3 + 8.5 * (y / HORIZON) ** 1.6))
    x = 0
    while x < W:                                # far layer
        w = rnd.randint(2, 5)
        h = rnd.randint(4, 12)
        if rnd.random() < 0.8:
            tower(x, w, h, 7, rnd)
        x += w + rnd.randint(0, 2)
    x = -1
    near = [(0, 6, 26), (7, 4, 18), (13, 5, 30), (21, 3, 12), (27, 6, 22),
            (40, 4, 15), (47, 3, 9), (66, 5, 24), (72, 4, 33), (77, 4, 20)]
    for (x0, w, h) in near:                     # near layer: dark wrecks
        tower(x0, w, h, 3, rnd, windows=(w >= 5))
    # the ground: a broken road running to the horizon
    for y in range(HORIZON, H):
        t = (y - HORIZON + 1) / (H - HORIZON)
        half = 1 + 22 * t
        cx = 44 - 6 * t
        for x in range(W):
            if abs(x + 0.5 - cx) < half / ASPECT * 1.0:
                v = 5 - 2 * t
                if abs(x + 0.5 - cx) < 0.6 and (y // 3) % 2 == 0 and y > HORIZON + 4:
                    v += 3                      # the centre line
                img[y][x] = clamp(round(v))
        # rubble at the sides
        for _ in range(int(2 + 6 * t)):
            x = rnd.randrange(W)
            img[y][x] = clamp(img[y][x] + rnd.choice((-1, 1, 2)))
    # the ledge the escapee stands on (lower left) -- black
    for y in range(78, H):
        edge = 30 - (y - 78) * 0.0 + 3 * math.sin(y * 0.9)
        rise = (y - 78)
        for x in range(W):
            if x < 26 + 4 * math.sin(y * 0.5) + rise * 0.4:
                img[y][x] = 0 if y > 80 else 1
    # a dead tree on the right
    def branch(x, y, ang, ln, th):
        for i in range(int(ln)):
            xx = x + math.cos(ang) * i / ASPECT
            yy = y - math.sin(ang) * i
            for k in range(th):
                if 0 <= int(yy) < H and 0 <= int(xx + k * 0.5) < W:
                    img[int(yy)][int(xx + k * 0.5)] = 0
        return x + math.cos(ang) * ln / ASPECT, y - math.sin(ang) * ln
    bx, by = branch(70, 95, 1.62, 30, 2)
    branch(bx, by, 2.4, 10, 1)
    bx2, by2 = branch(bx, by, 1.2, 12, 1)
    branch(bx2, by2, 0.6, 6, 1)
    branch(70.5, 80, 0.5, 9, 1)
    branch(70, 86, 2.7, 8, 1)
    # keep THE END's patch of sky clean
    return img

# ------------------------------------------------------------------ the escapee
def figure(H_rows, phase=None, stride=0.0, width_cc=16):
    """1-bit silhouette, H_rows tall (2 scanlines per row), 16 colour clocks
    wide, seen from behind.  phase: walking phase (radians) or None."""
    SS = 8
    sl = H_rows * 2.0                          # person height in scanlines
    Wpx, Hpx = width_cc * SS, H_rows * SS
    im = Image.new('L', (Wpx, Hpx), 0)
    d = ImageDraw.Draw(im)
    def P(x, y):                               # person units -> image pixels
        return (Wpx / 2 + x * sl / SL_PER_CC * SS, y * sl / 2 * SS)
    def poly(pts): d.polygon([P(*p) for p in pts], fill=255)
    def limb(x0, y0, x1, y1, w0, w1):
        ang = math.atan2(y1 - y0, x1 - x0) + math.pi / 2
        c, s = math.cos(ang), math.sin(ang)
        poly([(x0 + c * w0, y0 + s * w0), (x1 + c * w1, y1 + s * w1),
              (x1 - c * w1, y1 - s * w1), (x0 - c * w0, y0 - s * w0)])
        cx, cy = P(x1, y1); rx = w1 * sl / SL_PER_CC * SS; ry = w1 * sl / 2 * SS
        d.ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=255)
    bob = 0.0
    lift = [0.0, 0.0]
    swing = [0.0, 0.0]
    if phase is not None:
        bob = 0.012 * abs(math.cos(phase))
        for i in range(2):
            s = math.sin(phase + i * math.pi)
            lift[i] = 0.07 * max(0.0, s)       # the leg going forward lifts
            swing[i] = 0.04 * s
    y0 = bob
    # head and neck
    cx, cy = P(0, y0 + 0.062)
    rx, ry = 0.047 * sl / SL_PER_CC * SS, 0.062 * sl / 2 * SS
    d.ellipse((cx - rx, cy - ry, cx + rx, cy + ry), fill=255)
    limb(0, y0 + 0.1, 0, y0 + 0.16, 0.022, 0.024)
    # torso: shoulders, waist, hips
    poly([(-0.088, y0 + 0.16), (-0.1, y0 + 0.19), (-0.075, y0 + 0.43), (-0.082, y0 + 0.52),
          (0.082, y0 + 0.52), (0.075, y0 + 0.43), (0.1, y0 + 0.19), (0.088, y0 + 0.16),
          (0.025, y0 + 0.145), (-0.025, y0 + 0.145)])
    # arms (swinging opposite to the legs), held a little off the body
    for i, sx in enumerate((-1, 1)):
        hy = 0.49 - 0.03 * abs(swing[1 - i]) / 0.04
        limb(sx * 0.098, y0 + 0.185, sx * (0.128 + swing[1 - i] * 0.25), y0 + hy, 0.024, 0.02)
    # legs
    for i, sx in enumerate((-1, 1)):
        fy = 0.985 - lift[i]
        kx = sx * (0.048 + swing[i] * 0.15)
        ky = y0 + 0.75 - lift[i] * 0.5
        limb(sx * 0.045, y0 + 0.5, kx, ky, 0.037, 0.028)
        limb(kx, ky, sx * 0.05, fy, 0.028, 0.022)
    small = im.resize((width_cc, H_rows), Image.BOX)
    rows = []
    for y in range(H_rows):
        bits = 0
        for x in range(width_cc):
            bits = bits << 1 | (small.getpixel((x, y)) > 100)
        rows.append(bits)
    return rows

# walking from z0 to the door, one frame every STEP 1/60 s
WALK_FRAMES, WALK_STEP = 48, 5
Z0, Z1 = 2.25, ZEND - 0.15
PERSON = 1.75
STEPS = []
def walk():
    frames = []
    last = 0
    for k in range(WALK_FRAMES):
        t = k / (WALK_FRAMES - 1)
        z = Z0 + (Z1 - Z0) * t
        dist = (z - Z0)
        phase = dist / 0.75 * math.pi          # one step per 0.75 units
        n = int(dist / 0.75 + 0.5)
        STEPS.append(1 if n != last or k == 0 else 0); last = n
        hrow = F * PERSON / z
        feet = VY + F * EYE / z
        h = max(4, int(round(hrow)))
        rows = figure(h, phase)
        top = int(round(feet)) - h
        # trim empty rows
        while rows and rows[0] == 0: rows.pop(0); top += 1
        while rows and rows[-1] == 0: rows.pop()
        frames.append((top, rows))
    return frames

# ------------------------------------------------------------------ THE END
FONT = {'T': ["#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."],
        'H': ["#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
        'E': ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
        'N': ["#...#", "##..#", "#.#.#", "#.#.#", "#..##", "#...#", "#...#"],
        'D': ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
        ' ': ["....."] * 7}
END_X, END_Y = 20, 9                           # pixel, row (top left)
END_TEXT = "THE END"
END_ROWS = 14                                  # 7-row font, doubled
def theend():
    px = []
    for r in range(7):
        line = '.'.join(FONT[c][r] for c in END_TEXT)
        px.append(line)
    wpx = len(px[0])
    wb = (END_X + wpx + 1) // 2 - END_X // 2
    masks = []
    for r in range(END_ROWS):
        line = px[r // 2]
        for b in range(wb):
            m = 0
            for n in range(2):
                x = (END_X // 2 + b) * 2 + n - END_X
                if 0 <= x < wpx and line[x] == '#':
                    m |= 0xF0 >> (4 * n)
            masks.append(m)
    return wb, masks

# ------------------------------------------------------------------ packing
def tobytes(img):
    out = []
    for y in range(H):
        for x in range(0, W, 2):
            out.append(img[y][x] << 4 | img[y][x + 1])
    return out

def pack(data):
    n = len(data)
    # dynamic programming over positions: cost in bytes
    INF = 1 << 30
    cost = [INF] * (n + 1)
    how = [None] * (n + 1)
    cost[n] = 0
    for i in range(n - 1, -1, -1):
        # run
        j = i
        while j < n and data[j] == data[i] and j - i < 65: j += 1
        for L in range(2, j - i + 1):
            c = 2 + cost[i + L]
            if c < cost[i]: cost[i], how[i] = c, ('run', L)
        # copy from the row above
        j = i
        while j < n and j >= 40 and data[j] == data[j - 40] and j - i < 64: j += 1
        for L in range(1, j - i + 1):
            c = 1 + cost[i + L]
            if c < cost[i]: cost[i], how[i] = c, ('up', L)
        # literal
        for L in range(1, min(128, n - i) + 1):
            c = 1 + L + cost[i + L]
            if c < cost[i]: cost[i], how[i] = c, ('lit', L)
            if L > 24: break
    out = []
    i = 0
    while i < n:
        k, L = how[i]
        if k == 'run': out += [0x80 | (L - 2), data[i]]
        elif k == 'up': out += [0xC0 | (L - 1)]
        else: out += [L - 1] + data[i:i + L]
        i += L
    return out

def unpack(p, n):
    out = []
    i = 0
    while len(out) < n:
        b = p[i]; i += 1
        if b < 0x80: out += p[i:i + b + 1]; i += b + 1
        elif b < 0xC0: out += [p[i]] * ((b & 0x3F) + 2); i += 1
        else:
            for _ in range((b & 0x3F) + 1): out.append(out[-40])
    return out

def preview(img, hue, fn, scale=4):
    # rough NTSC-ish colours for a look before the emulator
    base = {0: (1, 1, 1), 2: (1.0, 0.72, 0.38)}[hue]
    im = Image.new('RGB', (W, H))
    for y in range(H):
        for x in range(W):
            l = img[y][x] / 15
            im.putpixel((x, y), tuple(int(255 * min(1, l * c + (l ** 3) * 0.25)) for c in base))
    im.resize((int(W * ASPECT * scale / 1.72 * 1.72), H * scale), Image.NEAREST).save(fn)

# ------------------------------------------------------------------ the tunnel
# between levels: 80x64 GTIA mode 10 (each nibble picks a colour register).
# Rectangular rings in perspective; the overlay rotates the six colours.
TUNREG = [0, 1, 2, 3, 4, 7]           # PM0-3, PF0, PF3 (the HUD's DLIs own PF1/PF2)
def tunnel():
    out = []
    for y in range(64):
        for xb in range(40):
            b = 0
            for n in range(2):
                x = xb * 2 + n
                d = max(abs(x + 0.5 - 40) / 40, abs(y + 0.5 - 32) / 32)
                if d < 0.11:
                    v = 8                      # the vanishing point: background
                else:
                    k = int(5.0 / d)           # depth: rings bunch up toward the middle
                    v = TUNREG[k % 6]
                b = b << 4 | v
            out.append(b)
    return out

if __name__ == '__main__':
    cor, was = corridor(), wasteland()
    frames = walk()
    stand = figure(46, None)
    while stand and stand[-1] == 0: stand.pop()
    endw, endm = theend()

    banks = [bytearray(b'\xff' * 8192), bytearray(b'\xff' * 8192)]
    fill = [0, 0]
    items = []
    def put(name, data):
        data = bytes(data)
        b = 0 if fill[0] + len(data) <= 8192 else 1
        assert fill[b] + len(data) <= 8192, name
        banks[b][fill[b]:fill[b] + len(data)] = data
        items.append((name, 6 + b, 0x8000 + fill[b], len(data)))
        fill[b] += len(data)
    for name, img in (('pcor', cor), ('pwas', was)):
        raw = tobytes(img)
        pk = pack(raw)
        assert unpack(pk, len(raw)) == raw
        put(name, pk)
    # walking frames: top row, row count, then (P0, P1) pairs
    wf = []
    offs = []
    for top, rows in frames:
        offs.append(len(wf))
        wf += [top, len(rows)]
        for r in rows: wf += [r >> 8, r & 255]
    put('fwalk', wf)
    sf = [0, len(stand)]
    for r in stand: sf += [r >> 8, r & 255]
    put('fstand', sf)

    out = ['; generated by endart.py -- the ending\'s data in cartridge banks 6-7']
    for name, bank, addr, ln in items:
        out.append(f'{name}_BANK = {bank}')
        out.append(f'{name} = ${addr:04X}          ; {ln} bytes')
    out.append(f'WALK_FRAMES = {WALK_FRAMES}')
    out.append(f'WALK_STEP = {WALK_STEP}')
    out.append(f'STAND_ROWS = {len(stand)}')
    out.append(f'END_X = {END_X}')
    out.append(f'END_Y = {END_Y}')
    out.append(f'END_W = {endw}')
    out.append(f'END_ROWS = {END_ROWS}')
    out.append('.segment "OVL2"')
    out.append('fwoff:  .word ' + ', '.join(f'fwalk+{o}' for o in offs))
    out.append('fstep:  .byte ' + ', '.join(str(v) for v in STEPS))
    out.append('endmask:')
    for r in range(END_ROWS):
        out.append('        .byte ' + ', '.join(f'${m:02X}' for m in endm[r * endw:(r + 1) * endw]))
    open('enddata.s', 'w').write('\n'.join(out) + '\n')
    open('end.bin', 'wb').write(bytes(banks[0] + banks[1]))
    open('tunnel.bin', 'wb').write(bytes(tunnel()))
    print('ending:', ', '.join(f'{n} {ln}B (bank {b})' for n, b, a, ln in items))
    if len(sys.argv) > 1:
        d = sys.argv[1]
        preview(cor, 0, d + '/cor.png'); preview(was, 2, d + '/was.png')
        # walking frames contact sheet
        sheet = Image.new("L", (34 * len(frames), 100), 30)
        for k, (top, rows) in enumerate(frames):
            for y, r in enumerate(rows):
                for x in range(16):
                    if r >> (15 - x) & 1:
                        sheet.putpixel((k * 34 + x * 2, top + y), 255)
                        sheet.putpixel((k * 34 + x * 2 + 1, top + y), 255)
        sheet.resize((sheet.width * 2, 400), Image.NEAREST).save(d + '/walk.png')
