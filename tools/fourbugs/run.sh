#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/fourbugs/run.sh -- THE FOUR WINDOW BUGS OF THE DELL (04.10.2026).
#
#   bash tools/fourbugs/run.sh [uiscale]
#
# Justin's Dell: (2) the title sits closer to the top edge than the bottom
# edge, (3) a window pushed a little over the screen edge jumps back at once,
# (4) the resize cursor shows only at the right and bottom edge. Run on the
# stick's machine (tools/design/eh6.sh). Checks (tools/fourbugs/check.py):
#   cursor shapes at 8 edge/corner points + inside; resize through all 8
#   grips; windows may stick out right/bottom/left but keep a handle; the
#   title text gaps above/below agree within 1 px.
# COUNTER-PROOF: the same run with the kernel word `nowinfix` (old behaviour)
# must FAIL several of those checks, or the checks measured nothing.
set -uo pipefail
cd "$(dirname "$0")/../.."
SCALE=${1:-1}
RES=1920x1080
[ "$SCALE" = 2 ] && RES=2560x1440
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
export DESIGNBUILD="$TMPD/build"
pass=0; fail=0
run() { # run <name> <extra kernel words>
    local name=$1; shift
    bash tools/design/eh6.sh "$TMPD/$name" res=$RES accel=kvm uiscale=$SCALE \
        drehbuch=tools/fourbugs/dreh.txt extra="$*" > "$TMPD/$name.log" 2>&1
    grep -a "FEHLGESCHLAGEN\|NICHT DA" "$TMPD/$name.log" | head -3
    if [ -n "${KEEP:-}" ]; then mkdir -p "$KEEP/$name"; cp "$TMPD/$name"/*.ppm "$TMPD/$name"/serial.txt "$KEEP/$name"/ 2>/dev/null; fi
}
echo "== fixes on =="
run fix
python3 tools/fourbugs/check.py "$TMPD/fix/serial.txt" "$TMPD/fix" "$SCALE" | tee "$TMPD/fix.txt"
f1=$(grep -c '^  FAIL' "$TMPD/fix.txt"); o1=$(grep -c '^  OK' "$TMPD/fix.txt")
echo "== counter-proof: old behaviour (nowinfix) =="
run old nowinfix
python3 tools/fourbugs/check.py "$TMPD/old/serial.txt" "$TMPD/old" "$SCALE" | tee "$TMPD/old.txt"
f2=$(grep -c '^  FAIL' "$TMPD/old.txt")
echo "== result =="
[ "$f1" -eq 0 ] && [ "$o1" -ge 20 ] && echo "  OK    all $o1 checks pass with the fixes" || echo "  FAIL  $f1 checks failed with the fixes ($o1 ok)"
[ "$f2" -ge 6 ] && echo "  OK    the old behaviour fails $f2 checks: they measure something" || echo "  FAIL  the old behaviour fails only $f2 checks"
[ "$f1" -eq 0 ] && [ "$o1" -ge 20 ] && [ "$f2" -ge 6 ]
