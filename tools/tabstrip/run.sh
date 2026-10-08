#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/tabstrip/run.sh -- r454: THE TABS IN THE TITLE BAR of the file manager (docs/COMPOSITOR.md, "Tabs in the title bar").
#
#   bash /root/jarvis/bin/heavy bash tools/tabstrip/run.sh [<belege directory>]
#
# One machine (tools/design/audit.sh, KVM), the drehbuch tools/tabstrip/dreh.txt: open the file manager, a second tab, click each
# tab, drag from a tab (the window must stay), drag from the empty part of the strip (it must move by the pointer's way), double
# click (maximise, restore), the three caption buttons over the strip. tools/tabstrip/check.py reads the serial log and the pictures.
# COUNTER-PROOF: the same run with the kernel word `nostrip` (the server refuses the strip) must FAIL the checks of the strip,
# otherwise they measured nothing.
set -uo pipefail
cd "$(dirname "$0")/../.."
BEL=${1:-}
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD" "$TMPD-build"' EXIT
export DESIGNBUILD="$TMPD-build"
bash tools/design/audit.sh "$TMPD/o" accel=kvm uitrace=yes halt=420 drehbuch="$(pwd)/tools/tabstrip/dreh.txt" > "$TMPD/run.log" 2>&1
grep -a "FEHLGESCHLAGEN\|NICHT DA\|KEIN RECHTECK\|KEINE" "$TMPD/run.log" | head -5
python3 tools/tabstrip/check.py "$TMPD/o" ${BEL:+"$BEL"} | tee "$TMPD/fix.txt"
f1=$(grep -c '^  FAIL' "$TMPD/fix.txt"); o1=$(grep -c '^  OK' "$TMPD/fix.txt")
echo "== counter-proof: the server refuses the strip (kernel word nostrip) =="
bash tools/design/audit.sh "$TMPD/n" accel=kvm uitrace=yes halt=420 extra=nostrip drehbuch="$(pwd)/tools/tabstrip/dreh.txt" > "$TMPD/run2.log" 2>&1
python3 tools/tabstrip/check.py "$TMPD/n" | tee "$TMPD/old.txt"
f2=$(grep -c '^  FAIL' "$TMPD/old.txt")
echo "== result =="
[ "$f1" -eq 0 ] && [ "$o1" -ge 20 ] && echo "  OK    all $o1 checks pass" || echo "  FAIL  $f1 failed ($o1 ok)"
[ "$f2" -ge 6 ] && echo "  OK    without the strip $f2 checks fail: they measure something" || echo "  FAIL  without the strip only $f2 checks fail"
[ "$f1" -eq 0 ] && [ "$o1" -ge 20 ] && [ "$f2" -ge 6 ]
