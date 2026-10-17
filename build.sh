#!/bin/sh
# Build DEPTHS_OF_DOOM.CAR. Needs ca65/ld65 (cc65) and python3 on the PATH.
set -e
cd "$(dirname "$0")"
python3 gentables.py
python3 endart.py
ca65 -o depthsofdoom.o depthsofdoom.s
ca65 -o data.o data.s
ld65 -C game.cfg -o game.bin -m depthsofdoom.map depthsofdoom.o data.o
ca65 -o loader.o loader.s
ld65 -C loader.cfg -o loader.bin loader.o
python3 mkcar.py game.bin loader.bin DEPTHS_OF_DOOM.CAR imgb.bin ovl.bin ovl2.bin end.bin tunnel.bin tracks.bin osr.bin
