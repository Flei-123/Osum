#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/termmax/run.sh -- W-TERM1: maximise, restore, title double click, edge drag and snap must resize the terminal, never end its shell.
#   [OLDREF=<ref>] bash /root/jarvis/bin/heavy bash tools/termmax/run.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/firnenv.sh
ROOT=$(pwd)
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"; [ -n "${OLDWT:-}" ] && git worktree remove --force "$OLDWT" 2>/dev/null' EXIT
run() {
    (cd "$2" && DESIGNBUILD="$TMPD/build-$1" bash tools/design/eh6.sh "$TMPD/$1" accel=kvm moreprogs=term drehbuch="$ROOT/tools/termmax/script.txt" > "$TMPD/$1.log" 2>&1)
    grep -a "FEHLGESCHLAGEN\|NICHT DA" "$TMPD/$1.log" | head -3
    [ -n "${KEEP:-}" ] && { mkdir -p "$KEEP/$1"; cp "$TMPD/$1"/serial.txt "$TMPD/$1"/*.ppm "$KEEP/$1"/ 2>/dev/null; }
}
run new "$ROOT"
python3 tools/termmax/check.py "$TMPD/new/serial.txt" | tee "$TMPD/new.txt"
f1=$(grep -c '^  FAIL' "$TMPD/new.txt")
OLDREF=${OLDREF:-}
if [ -n "$OLDREF" ]; then
    echo "== counter-proof: the same drehbuch on $OLDREF =="
    OLDWT="$TMPD/oldtree"
    git worktree add --detach "$OLDWT" "$OLDREF" > /dev/null 2>&1
    firnenv_prepare_old_tree "$OLDWT"
    run old "$OLDWT"
    python3 tools/termmax/check.py "$TMPD/old/serial.txt" | tee "$TMPD/old.txt"
    f2=$(grep -c '^  FAIL' "$TMPD/old.txt")
    grep -q 'FAIL  no terminal row says' "$TMPD/old.txt" && echo "  OK    the old tree ends the shell (sh: bye): the gate sees the bug" || { echo "  FAIL  the old tree does not show the bug"; f2=0; }
fi
echo "== result =="
[ "$f1" -eq 0 ] && echo "  OK    all checks pass" || echo "  FAIL  $f1 failed"
[ "$f1" -eq 0 ] && { [ -z "$OLDREF" ] || [ "${f2:-0}" -ge 1 ]; }
