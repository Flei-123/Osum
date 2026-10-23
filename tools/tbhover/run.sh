#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/tbhover/run.sh -- W-TBHOVER: HOVER, PRESSED AND ACTIVE STATE OF THE TASKBAR BUTTONS (Windows 11 look).
#
#   bash /root/jarvis/bin/heavy bash tools/tbhover/run.sh [s1|s2|old|all] [--old <worktree of a build without the fix>]
#
# One machine (tools/design/eh6.sh, KVM, Windows 11 bar: centred, no labels, 4 pins), the script tools/tbhover/dreh.txt moves the
# pointer onto an idle pin, away, onto start / chevron / clock, presses a pin, launches two programs, hovers a running pin.
# tools/tbhover/check.py compares the pictures: plate under the pointer (rounded: corner pixel untouched), plate gone again,
# pressed colour != hover colour, wide strip under the focused program, short one under a running one, none under an idle pin.
#   s1  = 1280x800 scale 1     s2 = 1920x1080 scale 2     old = scale 1 on the tree given by --old (COUNTER-PROOF: must FAIL)
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
MODE=${1:-all}
OLD=""
[ "${2:-}" = "--old" ] && OLD=${3:-}
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
PINS="explorer,settings,taskmgr,edit"
TBX="align=center;labels=never;height=48;clock_lines=2;clock_date=1;clock_year4=1;tray_chevron=1"
run_one() { # <tag> <tree> <res> <uiscale>
    local tag=$1 tree=$2 res=$3 sc=$4
    ( cd "$tree" && DESIGNBUILD="$TMPD/build-$tag" bash tools/design/eh6.sh "$TMPD/$tag" res=$res uiscale=$sc accel=kvm tafel=nein \
        pins="$PINS" tbextra="$TBX" drehbuch="$ROOT/tools/tbhover/dreh.txt" > "$TMPD/$tag.log" 2>&1 )
    [ -n "${TBHOVER_OUT:-}" ] && { mkdir -p "$TBHOVER_OUT/$tag"; cp "$TMPD/$tag"/*.ppm "$TMPD/$tag/serial.txt" "$TMPD/$tag.log" "$TBHOVER_OUT/$tag/" 2>/dev/null; }
    python3 tools/tbhover/check.py "$TMPD/$tag" "$sc" | tee "$TMPD/$tag.res"
}
rc=0
if [ "$MODE" = s1 ] || [ "$MODE" = all ]; then
    echo "== scale 1 (1280x800)"; run_one s1 "$ROOT" 1280x800 1
    [ "$(grep -c '^  FAIL' "$TMPD/s1.res")" -eq 0 ] || rc=1
fi
if [ "$MODE" = s2 ] || [ "$MODE" = all ]; then
    echo "== scale 2 (1920x1080)"; run_one s2 "$ROOT" 1920x1080 2
    [ "$(grep -c '^  FAIL' "$TMPD/s2.res")" -eq 0 ] || rc=1
fi
if [ "$MODE" = old ] || { [ "$MODE" = all ] && [ -n "$OLD" ]; }; then
    [ -n "$OLD" ] || { echo "old needs --old <tree>"; exit 2; }
    echo "== counter-proof: tree without the fix ($OLD)"; run_one old "$OLD" 1280x800 1
    f=$(grep -c '^  FAIL' "$TMPD/old.res")
    if [ "$f" -ge 4 ]; then echo "  OK    counter-proof: $f checks fail without the fix (they measure something)"
    else echo "  FAIL  counter-proof: only $f checks fail without the fix"; rc=1; fi
fi
echo "TBHOVER: rc=$rc"
exit $rc
