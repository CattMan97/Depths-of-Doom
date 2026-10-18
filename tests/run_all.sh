#!/bin/sh
# Build the cartridge and run every check.  Prints each check's PASS/FAIL
# lines and a summary; exits non-zero if anything failed.
#   tests/run_all.sh            everything (about 5 minutes)
#   tests/run_all.sh items      just the named checks (tests/checks/NAME.py)
T="$(cd "$(dirname "$0")" && pwd)"
[ -x "$T/.tools/bin/harness" ] || { echo "run tests/setup.sh first"; exit 2; }
export PATH="$T/.tools/cc65/bin:$PATH"
echo "== build"
sh "$T/../build.sh" || exit 1
python3 -c "import sys; sys.path.insert(0, '$T/lib'); import dod; dod.build_variant('frozen', 'E_SPEED=0', 'BENCH')" || exit 1
if [ $# -gt 0 ]; then names="$*"; else names=$(cd "$T/checks" && ls *.py | sed 's/\.py$//'); fi
failed=""
for n in $names; do
    echo "== $n"
    python3 -u "$T/checks/$n.py" || failed="$failed $n"
done
echo
if [ -z "$failed" ]; then echo "ALL CHECKS PASSED"; else echo "FAILED:$failed"; exit 1; fi
