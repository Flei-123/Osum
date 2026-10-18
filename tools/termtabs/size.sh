#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/termtabs/size.sh -- W-X2: all tabs of a terminal group follow a size change (maximise / restore of the shown tab).
#   [OLDREF=<ref>] bash /root/jarvis/bin/heavy bash tools/termtabs/size.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"; [ -n "${OLDWT:-}" ] && git worktree remove --force "$OLDWT" 2>/dev/null' EXIT
run() { # run <name> <worktree>
    (cd "$2" && DESIGNBUILD="$TMPD/build-$1" bash tools/design/eh6.sh "$TMPD/$1" accel=kvm moreprogs=term drehbuch="$ROOT/tools/termtabs/size.txt" > "$TMPD/$1.log" 2>&1)
    grep -a "FEHLGESCHLAGEN\|NICHT DA" "$TMPD/$1.log" | head -3
    [ -n "${KEEP:-}" ] && { mkdir -p "$KEEP/$1"; cp "$TMPD/$1"/serial.txt "$TMPD/$1"/*.ppm "$KEEP/$1"/ 2>/dev/null; }
}
run new "$ROOT"
python3 tools/termtabs/size.py "$TMPD/new" | tee "$TMPD/new.txt"
f1=$(grep -c '^  FAIL' "$TMPD/new.txt")
OLDREF=${OLDREF:-}
if [ -n "$OLDREF" ]; then
    echo "== counter-proof: the same drehbuch on $OLDREF =="
    OLDWT="$TMPD/oldtree"
    git worktree add --detach "$OLDWT" "$OLDREF" > /dev/null 2>&1
    run old "$OLDWT"
    python3 tools/termtabs/size.py "$TMPD/old" | tee "$TMPD/old.txt"
    f2=$(grep -c '^  FAIL' "$TMPD/old.txt")
    [ "$f2" -ge 1 ] && echo "  OK    the old tree fails $f2 checks: they measure something" || echo "  FAIL  the old tree passes"
fi
echo "== result =="
[ "$f1" -eq 0 ] && echo "  OK    all checks pass" || echo "  FAIL  $f1 failed"
[ "$f1" -eq 0 ] && { [ -z "$OLDREF" ] || [ "${f2:-0}" -ge 1 ]; }
