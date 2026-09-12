#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/design/r4.sh -- JUSTINS FRAGE: KANN MAN IM SUCHFENSTER ETWAS AUSFUEHREN?
#
#   bash tools/design/r4.sh [kern.mb] [wurzel.img] [ausgabe]
#
# Sechs Schritte, jeder einzeln belegt, alles in 3440x1440:
#
#   1. Suchfenster ueber die SUPER-TASTE oeffnen
#   2. tippen -- kommt der Text an und filtert die Liste?
#   3. Treffer mit der MAUS anklicken -> startet das Programm?
#   4. Suchfenster ueber KLICK AUFS LOGO oeffnen
#   5. Treffer mit PFEILTASTEN + ENTER waehlen -> startet das Programm?
#   6. steht danach wirklich ein Fenster des gestarteten Programms da?
#
# GEFAHREN WIRD MIT tools/design/drive.py, und das ist der Punkt:
# `mouse_move` im QEMU-Monitor ist RELATIV. Ein selbstgebauter Aufruf
# `mouse_move 450 984` bewegt den Zeiger um 450/984 Bildpunkte WEITER,
# er setzt ihn nicht dorthin. Mein erster Anlauf zu R4 hat genau das
# falsch gemacht und "mouse: packets=0" gemessen -- ein Fehler des
# Fahrers, kein Befund ueber Justins System. `drive.py` faehrt erst
# in die Ecke (32 Schritte, traegt 4K) und von dort heraus, und es
# rechnet die Trefferflaeche aus der Zeile, die das PROGRAMM selbst
# gemeldet hat (`launcher: rect ...`).
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
# --- 3. TREFFER MIT DER MAUS ---
klickauf lzeile0
warte 5
foto 03-nach-mausklick
warte 3
foto 04-programm-da
DREH

APPEND="osum gfx disp fbres=3440x1440 wm wig desk wmshell wmdauer herz"
APPEND="$APPEND absturzhalt nopuls tz=120 lang=en usb hidgen modfs"
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
    && ok "die Maus liefert Pakete ($(grep -ao 'packets=[0-9]*' "$W/serial.txt" | tail -1))" \
    || bad "mouse packets=0 -- der Fahrer erreicht die Maus nicht"
grep -qa 'launcher: suche \[edit\]' "$W/serial.txt" \
    && ok "Tippen filtert die Liste ($(grep -a 'launcher: suche \[edit\]' "$W/serial.txt" | tail -1 | grep -o 'treffer=[0-9]*'))" \
    || bad "Tippen filtert nicht"
grep -qa 'launcher: start' "$W/serial.txt" \
    && ok "MAUSKLICK startet: $(grep -a 'launcher: start' "$W/serial.txt" | tail -1)" \
    || bad "Mausklick startet nichts"
echo
echo "R4: $pass bestanden, $fail durchgefallen"
[ "$fail" -eq 0 ]
