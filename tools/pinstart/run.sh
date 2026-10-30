#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/pinstart/run.sh -- every start menu entry opens a window, with the registry icon (Boss 30.10.2026, HP: old icons, dead clicks).
#
#   bash tools/pinstart/run.sh
#
# Image: eh6 machine + store-style packages (16x16 symbol, bare program as start) zip, top, netview, calc, edit, trash
# next to the editor/trashbin bundles. Main run ships /usr/share/appreg (tools/appreg/build.py); counter-proof ships none.
#   1. each of zip, top, netview (console) and calc (window) found in the menu by a keyword, Enter: the picture changes (a window)
#   2. console entries log `appreg: console wrap id=<id>`; registry symbols are used (`appreg: symbol from registry`), no letter tile
#   3. edit/trash are dropped as duplicates of editor/trashbin (`appreg: duplicate dropped`)
#   4. the menu rows differ from the counter-proof run (registry icon instead of the 16x16 package symbol)
#   COUNTER-PROOF: no registry -> no wrap line, console entries open nothing, no registry symbol lines, nothing dropped.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
TMPD=$(mktemp -d)
KEEP=${PINSTART_KEEP:-}
save_shots() { [ -n "$KEEP" ] || return 0; mkdir -p "$KEEP"; for n in reg ctl; do mkdir -p "$KEEP/$n"; cp "$TMPD/$n"/*.ppm "$KEEP/$n/" 2>/dev/null; cp "$TMPD/$n/serial.txt" "$KEEP/$n/" 2>/dev/null; done; }
trap 'save_shots; rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
export DESIGNBUILD="$TMPD/build"
IDS=zip,top,netview,calc,edit,trash
export PINSTART_BIN_calc=calc
python3 -I tools/pinstart/mkapps.py "$TMPD/apps" "$IDS" || { echo "mkapps failed"; exit 1; }
python3 -I tools/appreg/build.py "$ROOT" "$TMPD/reg" > "$TMPD/reg.log" 2>&1 || { cat "$TMPD/reg.log"; exit 1; }

cat > "$TMPD/dreh.txt" <<'EOT'
warteauf 'launcher: ready' || 120
warte 6
foto 00-base
taste meta_l
warte 6
tippe zip
warte 3
foto 01-menu-zip
taste ret
warte 8
foto 02-zip
taste meta_l
warte 6
tippe prozesse
warte 3
foto 03-menu-top
taste ret
warte 8
foto 04-top
taste meta_l
warte 6
tippe netview
warte 3
foto 05-menu-netview
taste ret
warte 8
foto 06-netview
taste meta_l
warte 6
tippe taschenrechner
warte 3
foto 07-menu-calc
taste ret
warte 8
foto 08-calc
EOT

run() { # <name> <registry dir or empty>
    local name=$1
    EH_APPREG_DIR=$2 APPS_DIR="$TMPD/apps" bash tools/design/eh6.sh "$TMPD/$name" res=1920x1080 accel=kvm \
        moreprogs="term zip top calc nedit trashbin" drehbuch="$TMPD/dreh.txt" > "$TMPD/$name.log" 2>&1
    grep -a "FEHLGESCHLAGEN\|NICHT DA" "$TMPD/$name.log" | head -3
}

echo "== registry shipped =="
run reg "$TMPD/reg"
D="$TMPD/reg"
[ -s "$D/08-calc.ppm" ] && ok "the run took all pictures" || bad "pictures are missing: $(tail -3 "$TMPD/reg.log" | tr '\n' ' ')"
prev=00-base
for step in 02-zip 04-top 06-netview 08-calc; do
    n=$(python3 -I tools/pinstart/check.py "$D/$prev.ppm" "$D/$step.ppm" 0 0 1920 1030 2>/dev/null)
    [ "${n:-0}" -gt 3000 ] && ok "$step: a window opened ($n pixels changed)" || bad "$step: no window opened (${n:-0} pixels changed)"
    prev=$step
done
for id in zip top netview; do
    grep -aq "appreg: console wrap id=$id" "$D/serial.txt" && ok "$id: console program wrapped into a terminal window" || bad "$id: no console wrap line"
done
for id in zip top netview calc; do
    grep -aq "appreg: symbol from registry id=$id" "$D/serial.txt" && ok "$id: icon comes from the registry" || bad "$id: no registry symbol line"
done
n=$(grep -ac "appreg: letter tile" "$D/serial.txt")
[ "$n" -eq 0 ] && ok "no letter tile among the entries" || bad "$n letter tiles"
for id in edit trash; do
    grep -aq "appreg: duplicate dropped id=$id" "$D/serial.txt" && ok "$id: duplicate of the image bundle dropped" || bad "$id: duplicate still listed"
done

echo "== counter-proof: no registry =="
run ctl ""
C="$TMPD/ctl"
grep -aq "appreg: console wrap" "$C/serial.txt" && bad "counter-proof: wrap line without a registry" || ok "counter-proof: no wrap line"
grep -aq "appreg: symbol from registry" "$C/serial.txt" && bad "counter-proof: registry symbol without a registry" || ok "counter-proof: no registry symbol"
grep -aq "appreg: duplicate dropped" "$C/serial.txt" && bad "counter-proof: duplicate dropped without a registry" || ok "counter-proof: both duplicates stay"
n=$(python3 -I tools/pinstart/check.py "$C/00-base.ppm" "$C/02-zip.ppm" 0 0 1920 1030 2>/dev/null)
[ "${n:-0}" -lt 3000 ] && ok "counter-proof: zip opens nothing (the dead click, $n pixels)" || bad "counter-proof: zip opened a window anyway ($n pixels)"
for pair in 01-menu-zip 03-menu-top 05-menu-netview 07-menu-calc; do
    n=$(python3 -I tools/pinstart/check.py "$D/$pair.ppm" "$C/$pair.ppm" 8 580 450 1035 2>/dev/null)
    [ "${n:-0}" -gt 200 ] && ok "$pair: menu row icon differs from the 16x16 package symbol ($n pixels)" || bad "$pair: menu looks like the old icon (${n:-0} pixels)"
done
echo "PINSTART: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
