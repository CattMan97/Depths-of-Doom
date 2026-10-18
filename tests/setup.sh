#!/bin/sh
# Set up the build and test tools in tests/.tools (not in git):
#   cc65    the assembler and linker (ca65, ld65), built from source
#   atari800  the emulator as a library (libatari800), with a small patch
#           for the profiler, and the test harness linked against it
# Needs git, make, gcc, autoconf, automake and zlib headers; python3 with
# Pillow for the tests.  Takes a few minutes; run it once.
set -e
T="$(cd "$(dirname "$0")" && pwd)"
D="$T/.tools"
CC65_REV=71746c829e77f74c2b601a7d16821170c2610df3      # cc65 V2.19, Oct 2026
A800_REV=8bf597e28faf84c5fad413bd3b1a4f2135f3fc2c      # atari800 7.2.1, Oct 2026
mkdir -p "$D/bin"

fetch() {   # fetch URL DIR REV
    if [ ! -d "$2/.git" ]; then
        git clone -q --filter=blob:none "$1" "$2"
    fi
    git -C "$2" fetch -q origin "$3" 2>/dev/null || true
    git -C "$2" checkout -q "$3"
}

if [ ! -x "$D/cc65/bin/ca65" ]; then
    echo "== cc65"
    fetch https://github.com/cc65/cc65.git "$D/cc65" "$CC65_REV"
    make -C "$D/cc65" -j4 bin >/dev/null
fi

if [ ! -f "$D/atari800/src/libatari800.a" ]; then
    echo "== atari800 (libatari800)"
    fetch https://github.com/atari800/atari800.git "$D/atari800" "$A800_REV"
    cd "$D/atari800"
    git checkout -q -- src/cpu.c
    patch -s -p1 < "$T/harness/atari800-pchist.patch"
    [ -x configure ] || ./autogen.sh >/dev/null 2>&1 || true
    ./configure -q --target=libatari800 >/dev/null
    # (its -Werror trips over a harmless ULONG redefinition with newer headers)
    make -j4 CFLAGS='-g -O2 -DNETSIO' CFLAGS_NOANSI='-g -O2 -DNETSIO' >/dev/null 2>&1 \
        || { echo "atari800 build failed: see $D/atari800"; exit 1; }
    cd "$T"
fi

echo "== harness"
gcc -O2 -o "$D/bin/harness" "$T/harness/harness.c" \
    -I "$D/atari800/src" -I "$D/atari800" -L "$D/atari800/src" -latari800 -lm -lz

python3 -c "import PIL" 2>/dev/null || echo "note: the tests need Pillow (pip install Pillow)"
echo "tools ready in $D"
echo "build with:  PATH=\"$D/cc65/bin:\$PATH\" sh build.sh   (or just tests/run_all.sh)"
