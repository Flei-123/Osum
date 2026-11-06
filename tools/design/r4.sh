#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
#   bash tools/design/r4.sh [kern.mb] [wurzel.img] [ausgabe]
#
#
#
set -uo pipefail
cd "$(dirname "$0")/../.."
KERN=${1:-/tmp/final-img/osum.mb}
WURZEL=${2:-/tmp/final-img/root.img}
W=${3:-/tmp/r4}
rm -rf "$W"; mkdir -p "$W"
cp "$WURZEL" "$W/disk.img"

cat > "$W/drehbuch.txt" <<'DREH'
warteauf launcher: ready || 120
warte 6
foto 00-schreibtisch
# --- 1. SUPER-TASTE ---
taste meta_l
warte 3
foto 01-super-auf
# --- 2. TIPPEN ---
taste e
taste d
taste i
taste t
warte 3
foto 02-getippt
klickauf lzeile0
warte 5
foto 03-nach-mausklick
warte 3
foto 04-programm-da
DREH

APPEND="osum gfx disp fbres=3440x1440 wm wig desk wmshell wmdauer herz"
APPEND="$APPEND crashhalt nopuls tz=120 lang=en usb hidgen modfs"
APPEND="$APPEND nosched noproc nofs"

qemu-system-x86_64 -kernel "$KERN" -m 2048 -append "$APPEND" \
  -serial "file:$W/serial.txt" -display none -no-reboot \
  -device "VGA,edid=on,xres=3440,yres=1440,vgamem_mb=128" \
  -drive "file=$W/disk.img,format=raw,if=ide,index=0" \
  -monitor "unix:$W/mon,server,nowait" > "$W/qemu.log" 2>&1 &
QP=$!
sleep 3
python3 tools/design/drive.py "$W/mon" "$W/serial.txt" "$W" \
    "$W/drehbuch.txt" > "$W/fahren.log" 2>&1 || true
kill "$QP" 2>/dev/null; wait "$QP" 2>/dev/null

echo "== der Fahrer =="
sed 's/^/   /' "$W/fahren.log" | tail -20
echo
echo "== Maus wirklich angekommen? =="
grep -a 'mouse:' "$W/serial.txt" | tail -2 | sed 's/^/   /'
echo "== Suche =="
grep -a 'launcher: suche' "$W/serial.txt" | tail -3 | sed 's/^/   /'
echo "== Start =="
grep -aE 'launcher: (start|zugemacht)' "$W/serial.txt" | sed 's/^/   /'

pass=0; fail=0
ok(){ pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad(){ fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
echo
grep -qa 'launcher: ready' "$W/serial.txt" && ok "Starter laeuft" || bad "Starter fehlt"
grep -qa 'mouse: id=.*packets=[1-9]' "$W/serial.txt" \
    && ok "the mouse delivers packets ($(grep -ao 'packets=[0-9]*' "$W/serial.txt" | tail -1))" \
    || bad "mouse packets=0 -- the driver does not reach the mouse"
grep -qa 'launcher: suche \[edit\]' "$W/serial.txt" \
    && ok "typing filters the list ($(grep -a 'launcher: suche \[edit\]' "$W/serial.txt" | tail -1 | grep -o 'treffer=[0-9]*'))" \
    || bad "Tippen filtert nicht"
grep -qa 'launcher: start' "$W/serial.txt" \
    && ok "MAUSKLICK startet: $(grep -a 'launcher: start' "$W/serial.txt" | tail -1)" \
    || bad "Mausklick startet nichts"
echo
echo "R4: $pass bestanden, $fail durchgefallen"
[ "$fail" -eq 0 ]
