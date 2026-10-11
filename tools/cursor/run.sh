#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/cursor/run.sh -- THE POINTER SHAPES (W-CURSOR, 11.10.2026).
#
#   bash tools/cursor/run.sh [uiscale]      (run via /root/jarvis/bin/heavy)
#
# The drehbuch (tools/cursor/dreh.txt) moves the pointer over the desktop, the
# terminal grid, a title bar, two edges and two corners of the terminal window and
# the start menu, taking a picture at each spot. tools/cursor/check.py cuts the
# picture around the hot spot, renders all shapes from the SAME outlines the kernel
# uses (tools/wm/zeiger2.py) at the target size (24 px * scale), and demands that
# the best match is the expected shape (hot spot position included: the cut is
# placed by the shape's own hot spot). The serial lines `wm: form=N` must name the
# shapes too.
# COUNTER-PROOF: the same run with the kernel word `noshapes` (arrow everywhere)
# must FAIL several checks, or the checks measured nothing.
set -uo pipefail
cd "$(dirname "$0")/../.."
SCALE=${1:-1}
RES=1920x1080
[ "$SCALE" = 2 ] && RES=2560x1440
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
export DESIGNBUILD="$TMPD/build"
run() { # run <name> <extra kernel words>
    local name=$1; shift
    bash tools/design/eh6.sh "$TMPD/$name" res=$RES accel=kvm uiscale=$SCALE \
        drehbuch=tools/cursor/dreh.txt extra="$*" > "$TMPD/$name.log" 2>&1
    grep -a "FEHLGESCHLAGEN\|NICHT DA" "$TMPD/$name.log" | head -3
    if [ -n "${KEEP:-}" ]; then mkdir -p "$KEEP/$name"; cp "$TMPD/$name"/*.ppm "$TMPD/$name"/serial.txt "$TMPD/$name.log" "$KEEP/$name"/ 2>/dev/null; fi
}
echo "== shapes on =="
run fix
python3 tools/cursor/check.py "$TMPD/fix" "$TMPD/fix.log" "$TMPD/fix/serial.txt" "$SCALE" | tee "$TMPD/fix.txt"
f1=$(grep -c '^  FAIL' "$TMPD/fix.txt"); o1=$(grep -c '^  OK' "$TMPD/fix.txt")
echo "== counter-proof: noshapes (arrow everywhere) =="
run old noshapes
python3 tools/cursor/check.py "$TMPD/old" "$TMPD/old.log" "$TMPD/old/serial.txt" "$SCALE" | tee "$TMPD/old.txt"
f2=$(grep -c '^  FAIL' "$TMPD/old.txt")
echo "== result =="
[ "$f1" -eq 0 ] && [ "$o1" -ge 10 ] && echo "  OK    all $o1 checks pass with the shapes" || echo "  FAIL  $f1 checks failed with the shapes ($o1 ok)"
[ "$f2" -ge 4 ] && echo "  OK    without the shapes $f2 checks fail: they measure something" || echo "  FAIL  without the shapes only $f2 checks fail"
[ "$f1" -eq 0 ] && [ "$o1" -ge 10 ] && [ "$f2" -ge 4 ]
