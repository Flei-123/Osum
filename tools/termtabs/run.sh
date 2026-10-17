#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/termtabs/run.sh -- r1014: TERMINAL TABS (Ctrl+Shift+T / '+', Ctrl+Tab, click on a tab, 'x', Ctrl+Shift+W).
#
#   OLDREF=<ref without the tabs> bash /root/jarvis/bin/heavy bash tools/termtabs/run.sh
#
# One boot of the stick's machine (tools/design/eh6.sh, KVM, with /bin/term built: moreprogs=term), drehbuch tools/termtabs/dreh.txt.
# tools/termtabs/check.py reads the serial witnesses (`tt: new|switch|close win= grp= tabs=`, `wm: tab shell started:`) and the pixels of
# the title strip. COUNTER-PROOF: the same drehbuch on the tree WITHOUT the change (OLDREF) must FAIL at least 8 checks.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"; [ -n "${OLDWT:-}" ] && git worktree remove --force "$OLDWT" 2>/dev/null' EXIT
export DESIGNBUILD="$TMPD/build"
bash tools/design/eh6.sh "$TMPD/new" accel=kvm moreprogs=term drehbuch="$ROOT/tools/termtabs/dreh.txt" > "$TMPD/run.log" 2>&1
grep -a "FEHLGESCHLAGEN\|NICHT DA\|KEIN RECHTECK" "$TMPD/run.log" | head -5
python3 tools/termtabs/check.py "$TMPD/new" | tee "$TMPD/new.txt"
f1=$(grep -c '^  FAIL' "$TMPD/new.txt"); o1=$(grep -c '^  OK' "$TMPD/new.txt")
mkdir -p docs/shots/termtabs
for n in t0-single t1-two t4-three; do
    [ -s "$TMPD/new/$n.ppm" ] && python3 tools/design/ppm2png.py "$TMPD/new/$n.ppm" "docs/shots/termtabs/$n.png" > /dev/null 2>&1
done
OLDREF=${OLDREF:-}
if [ -n "$OLDREF" ]; then
    echo "== counter-proof: the same drehbuch on $OLDREF =="
    OLDWT="$TMPD/oldtree"
    git worktree add --detach "$OLDWT" "$OLDREF" > /dev/null 2>&1
    (cd "$OLDWT" && DESIGNBUILD="$TMPD/oldbuild" bash tools/design/eh6.sh "$TMPD/old" accel=kvm moreprogs=term drehbuch="$ROOT/tools/termtabs/dreh.txt" > "$TMPD/run2.log" 2>&1)
    python3 tools/termtabs/check.py "$TMPD/old" | tee "$TMPD/old.txt"
    f2=$(grep -c '^  FAIL' "$TMPD/old.txt")
    [ "$f2" -ge 8 ] && echo "  OK    the old tree fails $f2 checks: they measure something" || echo "  FAIL  the old tree fails only $f2 checks"
fi
echo "== result =="
[ "$f1" -eq 0 ] && [ "$o1" -ge 14 ] && echo "  OK    all $o1 checks pass" || echo "  FAIL  $f1 failed ($o1 ok)"
[ "$f1" -eq 0 ] && [ "$o1" -ge 14 ] && { [ -z "$OLDREF" ] || [ "${f2:-0}" -ge 8 ]; }
