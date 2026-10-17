#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/rotinput/run.sh -- INPUT FOLLOWS THE OUTPUT (W-K): the desktop is rotated 0/90/180/270 and a click through an ABSOLUTE
# tablet (QMP) at the PANEL position of the Start button must hit the Start button that is drawn there.
#   bash tools/rotinput/run.sh [outdir]
# Per rotation one desktop boot (`deskrot90|180|270`, none for 0), `uitrace=yes` so the taskbar reports its geometry in logical
# pixels and what a click hit. Oracle: tools/rotinput/drive.py maps the logical button centre to the panel with the rotation of
# fb.present. COUNTER-PROBE: the tree before the fix (ROTINPUT_BASE = the commit that only added the boot words) clicks in the
# wrong place at 90/180/270 (the tablet position is not turned back) and misses the button.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
OUT=${1:-$(mktemp -d)}
mkdir -p "$OUT"
BASE_COMMIT=${ROTINPUT_BASE:-$(git log --format=%H --grep="^rotinput: boot words" -1)}
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "ROTINPUT: skipped, no qemu"; exit 0; }
PROGS="desktop taskbar launcher settings theme explorer sh echo ls cat"

run_tree() { # tree out rot
    mkdir -p "$2"
    local word=""
    [ "$3" != 0 ] && word="deskrot$3"
    ( cd "$1" && bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
      ALLTAGBUILD="$2.build" bash tools/alltag/build.sh "$2" kbd=no warten=1 \
        extra="modfs osum wmshell wmdauer usb hidgen $word" hold=no uitrace=yes waitfor="taskbar: start x=" progs="$PROGS" \
        qemu="-device qemu-xhci -device usb-tablet -device usb-mouse -qmp unix:$2/qmp.sock,server,nowait" \
        hook="python3 $ROOT/tools/rotinput/drive.py $2/qmp.sock \$SOCK $2/serial.txt $2 $3" ) > "$2.log" 2>&1
}
fact() { sed -n "s/^$2=//p" "$1/scenes.txt" 2>/dev/null | tail -1; }

echo "== 1. new tree =="
for R in 0 90 180 270; do
    run_tree "$ROOT" "$OUT/new$R" "$R" || true
    N="$OUT/new$R"
    if [ ! -s "$N/scenes.txt" ] || [ "$(fact $N desktop)" != 1 ]; then bad "rot $R: no desktop / driver wrote nothing"; tail -5 "$N.log"; continue; fi
    [ "$(fact $N click_in_start)" = 1 ] && ok "rot $R: the tablet click at panel $(fact $N panel_target) landed in the Start rectangle (local $(fact $N click_local), start $(fact $N start))" \
        || bad "rot $R: click local '$(fact $N click_local)' outside start '$(fact $N start)' (panel target $(fact $N panel_target))"
    [ "$(fact $N rel_ok)" = 1 ] && ok "rot $R: a relative mouse pushed toward the physical corner $(fact $N rel_push) ends at the bar's logical corner (click local $(fact $N rel_click_local))" \
        || bad "rot $R: relative mouse push $(fact $N rel_push) -> click local '$(fact $N rel_click_local)' (want the end of the bar)"
    [ "$(fact $N menu_open)" = 1 ] && ok "rot $R: the start menu opened" || bad "rot $R: the start menu did not open"
    [ -s "$N/before.ppm" ] && [ -s "$N/after.ppm" ] && python3 - "$N/before.ppm" "$N/after.ppm" <<'PY' && ok "rot $R: the picture changed after the click (menu drawn)" || bad "rot $R: before/after pictures are equal"
import sys
def ppm(p):
    d=open(p,'rb').read(); parts=d.split(b"\n",3); return parts[3]
a,b=ppm(sys.argv[1]),ppm(sys.argv[2])
n=sum(1 for i in range(0,min(len(a),len(b)),3) if a[i:i+3]!=b[i:i+3])
sys.exit(0 if n>=5000 else 1)
PY
done

echo
echo "== 2. COUNTER-PROBE: tree with the boot words but without the fix =="
if [ -n "$BASE_COMMIT" ] && git rev-parse -q --verify "$BASE_COMMIT^{commit}" >/dev/null 2>&1; then
    BT="$OUT/basetree"
    git worktree add -q --detach "$BT" "$BASE_COMMIT" 2>/dev/null
    for R in 90 180 270; do
        run_tree "$BT" "$OUT/old$R" "$R" || true
        O="$OUT/old$R"
        [ -s "$O/scenes.txt" ] && [ "$(fact $O desktop)" = 1 ] || { bad "old rot $R: no desktop"; continue; }
        [ "$(fact $O click_in_start)" = 0 ] && ok "old rot $R: the same click MISSES the Start button (local $(fact $O click_local))" || bad "old rot $R: the click still hit the button"
        [ "$(fact $O rel_ok)" = 0 ] && ok "old rot $R: the relative push ends elsewhere (click local $(fact $O rel_click_local))" || bad "old rot $R: relative push still correct"
    done
    git worktree remove --force "$BT" >/dev/null 2>&1
else
    echo "  (skipped: base commit '$BASE_COMMIT' not in this clone)"
fi
echo
echo "== ROTINPUT: $pass green, $fail red =="
[ "$fail" -eq 0 ]
