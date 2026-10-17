#!/usr/bin/env python3
"""Assemble the 128K switchable XEGS image (.CAR type 35):
   banks 0-1   game image (RAM $4000-$7FFF)
   banks 2-3   image B (RAM $8000-$B7FF)
   bank 4      overlay: main menu, demo bot, game-over banner (RAM $1000-$1AFF)
   bank 5      overlay 2: the ending (RAM $1000-$1AFF)
   banks 6-7   the ending's pictures, read from the cartridge
   bank 8      the tunnel between levels (2560 bytes, copied to a frame buffer)
   bank 9      music: the title theme and 15 level tracks, a page each
   banks 10-11 code for the RAM under the OS ROM (13K, copied by the loader)
   banks 12-14 free ($FF)
   bank 15     loader + cartridge header (fixed at $A000-$BFFF)"""
import struct, sys
CART_TYPE_SWXEGS_128 = 35
game = open(sys.argv[1], 'rb').read()
loader = open(sys.argv[2], 'rb').read()
imgb = open(sys.argv[4], 'rb').read() if len(sys.argv) > 4 else b''
ovl = open(sys.argv[5], 'rb').read() if len(sys.argv) > 5 else b''
ovl2 = open(sys.argv[6], 'rb').read() if len(sys.argv) > 6 else b''
endb = open(sys.argv[7], 'rb').read() if len(sys.argv) > 7 else b''
tun = open(sys.argv[8], 'rb').read() if len(sys.argv) > 8 else b''
trk = open(sys.argv[9], 'rb').read() if len(sys.argv) > 9 else b''
osr = open(sys.argv[10], 'rb').read() if len(sys.argv) > 10 else b''
assert len(osr) <= 16384, len(osr)
assert len(ovl) <= 8192, len(ovl)
assert len(ovl2) <= 8192 and len(endb) <= 16384
assert len(game) == 16384, len(game)
assert len(imgb) <= 16384, len(imgb)
assert len(loader) == 8192, len(loader)
rom = bytearray(b'\xff' * 131072)
rom[0:16384] = game
rom[16384:16384 + len(imgb)] = imgb       # banks 2-3: image B ($8000-$B7FF)
rom[4 * 8192:4 * 8192 + len(ovl)] = ovl   # bank 4: overlay (menu, demo, banner)
rom[5 * 8192:5 * 8192 + len(ovl2)] = ovl2  # bank 5: the ending
rom[6 * 8192:6 * 8192 + len(endb)] = endb  # banks 6-7: its pictures
rom[8 * 8192:8 * 8192 + len(tun)] = tun    # bank 8: the tunnel
rom[9 * 8192:9 * 8192 + len(trk)] = trk    # bank 9: music
rom[10 * 8192:10 * 8192 + len(osr)] = osr  # banks 10-11: RAM under the OS
rom[15 * 8192:] = loader
checksum = sum(rom) & 0xFFFFFFFF
with open(sys.argv[3], 'wb') as f:
    f.write(b'CART' + struct.pack('>II', CART_TYPE_SWXEGS_128, checksum) + b'\0\0\0\0' + rom)
print(f"{sys.argv[3]}: type {CART_TYPE_SWXEGS_128} (switchable XEGS 128K), checksum ${checksum:08X}")
