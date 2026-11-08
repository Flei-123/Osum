#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD" "$TMPD-build"' EXIT
export DESIGNBUILD="$TMPD-build"
SCRIPT="$(pwd)/tools/tabstrip/inactive.txt"
bash tools/design/audit.sh "$TMPD/live" accel=kvm uitrace=yes halt=300 drehbuch="$SCRIPT" > "$TMPD/live.log" 2>&1
python3 -I tools/tabstrip/inactive.py "$TMPD/live" | tee "$TMPD/live.txt"
live_fail=$(grep -c '^  FAIL' "$TMPD/live.txt")
echo "== counter-proof: explorer built with the old strip label colour =="
cp -a kernel/user "$TMPD/mut"
python3 - "$TMPD/mut/fuiscene/fsdraw.fi" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
new = "strip_text_color())"
assert new in s
open(p, "w", encoding="utf-8").write(s.replace(new, "style.color_token(style.TOK_TEXT_ON_ACCENT))"))
PY
vendor/firn/bin/firnc -c "$TMPD/mut/explorer.fi" -o "$TMPD/explorer.o" > "$TMPD/mut.log" 2>&1 || { tail -20 "$TMPD/mut.log"; exit 1; }
CRT=""
grep -qa '^profile app' "$TMPD/mut/explorer.fi" || { as --64 -o "$TMPD/crt.o" kernel/user/crt.s && CRT="$TMPD/crt.o"; }
ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" -o "$TMPD/explorer.elf" $CRT "$TMPD/explorer.o" 2> "$TMPD/ld.err" || { cat "$TMPD/ld.err"; exit 1; }
strip --strip-all "$TMPD/explorer.elf"
DESIGNBUILD="$TMPD-build" AUDIT_MKFS_EXTRA="/bin/explorer=$TMPD/explorer.elf" \
    bash tools/design/audit.sh "$TMPD/old" accel=kvm uitrace=yes halt=300 drehbuch="$SCRIPT" > "$TMPD/old.log" 2>&1
python3 -I tools/tabstrip/inactive.py "$TMPD/old" | tee "$TMPD/old.txt"
old_fail=$(grep -c '^  FAIL' "$TMPD/old.txt")
echo "== result =="
[ "$live_fail" -eq 0 ] && echo "  OK    the plus button is visible on an inactive strip" || echo "  FAIL  the plus button is not visible ($live_fail failed)"
[ "$old_fail" -ge 1 ] && echo "  OK    with the old label colour the check fails: it measures something" || echo "  FAIL  the old label colour passed the check"
[ "$live_fail" -eq 0 ] && [ "$old_fail" -ge 1 ]
