#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/termsel/run.sh -- r1014: THE TERMINAL WINDOW HAS A BLINKING CURSOR, MOUSE SELECTION, COPY AND PASTE.
#
#   bash /root/jarvis/bin/heavy bash tools/termsel/run.sh
#
# One boot of the stick's machine (tools/design/eh6.sh, KVM), drehbuch tools/termsel/dreh.txt: three echo lines, ten pictures
# (blink), a mouse drag over a row, Ctrl+Shift+C, Ctrl+Shift+V, right click, Ctrl+C with a selection. tools/termsel/check.py reads the
# serial witnesses (`wm: tcur`, `wm: tcopy`, `wm: tpaste`, `wm: termzeile`) and the pixels of the pictures.
# COUNTER-PROOF: the same run on the tree WITHOUT the change (git worktree of the base ref in $OLDREF, default origin/main
# of the commit before this work) must FAIL the checks, otherwise they measured nothing.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"; [ -n "${OLDWT:-}" ] && git worktree remove --force "$OLDWT" 2>/dev/null' EXIT
export DESIGNBUILD="$TMPD/build"
bash tools/design/eh6.sh "$TMPD/new" accel=kvm drehbuch="$ROOT/tools/termsel/dreh.txt" > "$TMPD/run.log" 2>&1
grep -a "FEHLGESCHLAGEN\|NICHT DA\|KEIN RECHTECK" "$TMPD/run.log" | head -5
python3 tools/termsel/check.py "$TMPD/new" | tee "$TMPD/new.txt"
f1=$(grep -c '^  FAIL' "$TMPD/new.txt"); o1=$(grep -c '^  OK' "$TMPD/new.txt")
mkdir -p docs/shots/termsel
for n in b00 s1-selected p1-pasted; do
    [ -s "$TMPD/new/$n.ppm" ] && python3 tools/design/ppm2png.py "$TMPD/new/$n.ppm" "docs/shots/termsel/$n.png" > /dev/null 2>&1
done
OLDREF=${OLDREF:-}
if [ -n "$OLDREF" ]; then
    echo "== counter-proof: the same drehbuch on $OLDREF =="
    OLDWT="$TMPD/oldtree"
    git worktree add --detach "$OLDWT" "$OLDREF" > /dev/null 2>&1
    (cd "$OLDWT" && DESIGNBUILD="$TMPD/oldbuild" bash tools/design/eh6.sh "$TMPD/old" accel=kvm drehbuch="$ROOT/tools/termsel/dreh.txt" > "$TMPD/run2.log" 2>&1)
    python3 tools/termsel/check.py "$TMPD/old" | tee "$TMPD/old.txt"
    f2=$(grep -c '^  FAIL' "$TMPD/old.txt")
    [ "$f2" -ge 8 ] && echo "  OK    the old tree fails $f2 checks: they measure something" || echo "  FAIL  the old tree fails only $f2 checks"
fi
echo "== result =="
[ "$f1" -eq 0 ] && [ "$o1" -ge 14 ] && echo "  OK    all $o1 checks pass" || echo "  FAIL  $f1 failed ($o1 ok)"
[ "$f1" -eq 0 ] && [ "$o1" -ge 14 ] && { [ -z "$OLDREF" ] || [ "${f2:-0}" -ge 8 ]; }
