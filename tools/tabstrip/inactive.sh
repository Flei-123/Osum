#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD" "$TMPD-build" "$TMPD-mut"' EXIT
export DESIGNBUILD="$TMPD-build"
DIR="$(pwd)/tools/tabstrip"
live_fail=0
for scale in 1 2; do
    if [ "$scale" = 1 ]; then ARGS="res=1280x800 uiscale=1"; SCRIPT="$DIR/inactive.txt"; else ARGS="res=1920x1080 uiscale=2"; SCRIPT="$DIR/inactive2.txt"; fi
    bash tools/design/audit.sh "$TMPD/live$scale" accel=kvm uitrace=yes halt=300 $ARGS drehbuch="$SCRIPT" > "$TMPD/live$scale.log" 2>&1
    echo "== scale $scale =="
    python3 -I tools/tabstrip/inactive.py "$TMPD/live$scale" | tee "$TMPD/live$scale.txt"
    live_fail=$((live_fail + $(grep -c '^  FAIL' "$TMPD/live$scale.txt")))
done
echo "== counter-proof: explorer built with the old plus glyph colour =="
cp -a kernel/user "$TMPD/mut"
python3 - "$TMPD/mut/fuiscene/fsdraw.fi" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
old = "col = theme_rgb(wlibc.C_TITLEBAR_OFF_TEXT)"
assert old in s
open(p, "w", encoding="utf-8").write(s.replace(old, "col = (*t).text_on_accent"))
PY
vendor/firn/bin/firnc -c "$TMPD/mut/explorer.fi" -o "$TMPD/explorer.o" > "$TMPD/mut.log" 2>&1 || { tail -20 "$TMPD/mut.log"; exit 1; }
CRT=""
grep -qa '^profile app' "$TMPD/mut/explorer.fi" || { as --64 -o "$TMPD/crt.o" kernel/user/crt.s && CRT="$TMPD/crt.o"; }
ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" -o "$TMPD/explorer.elf" $CRT "$TMPD/explorer.o" 2> "$TMPD/ld.err" || { cat "$TMPD/ld.err"; exit 1; }
strip --strip-all "$TMPD/explorer.elf"
cp -a "$TMPD-build" "$TMPD-mut"
cp "$TMPD/explorer.elf" "$TMPD-mut/explorer.elf"
DESIGNBUILD="$TMPD-mut" bash tools/design/audit.sh "$TMPD/old" accel=kvm uitrace=yes halt=300 drehbuch="$DIR/inactive.txt" > "$TMPD/old.log" 2>&1
python3 -I tools/tabstrip/inactive.py "$TMPD/old" | tee "$TMPD/old.txt"
old_fail=$(grep -c '^  FAIL' "$TMPD/old.txt")
echo "== result =="
[ "$live_fail" -eq 0 ] && echo "  OK    the plus button is visible on an inactive strip at scale 1 and 2" || echo "  FAIL  the plus button is not visible ($live_fail failed)"
[ "$old_fail" -ge 1 ] && echo "  OK    with the old glyph colour the check fails: it measures something" || echo "  FAIL  the old glyph colour passed the check"
[ "$live_fail" -eq 0 ] && [ "$old_fail" -ge 1 ]
