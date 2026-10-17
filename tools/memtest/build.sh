#!/bin/sh
# Build MEMTEST.CAR (8K cartridge, .CAR type 1). Needs ca65/ld65 (cc65) and python3.
set -e
cd "$(dirname "$0")"
ca65 -o memtest.o memtest.s
ld65 -C mt.cfg -o memtest.bin memtest.o
python3 -c "
import struct
d = open('memtest.bin', 'rb').read()
assert len(d) == 8192
open('MEMTEST.CAR', 'wb').write(b'CART' + struct.pack('>II', 1, sum(d)) + bytes(4) + d)
print('MEMTEST.CAR: type 1 (8K), checksum \$%08X' % sum(d))"
