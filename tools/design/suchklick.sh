#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/design/suchklick.sh -- R4, ZWEITER ANLAUF: WO GEHT DER KLICK VERLOREN?
#
# Der erste Lauf zeigte: tippen filtert (7 -> 3 Treffer), aber ein
# Klick auf die Trefferzeile startet nichts. Die Vermutung
# "Doppelklick noetig" ist WIDERLEGT -- launcher.fi:786 ruft
# `wlib.list_einklick(ls, true)`.
#
# Dieser Laeufer sucht die Stelle, an der es haengt, indem er die Maus
# STUFENWEISE benutzt und nach jedem Schritt fragt, was das System
# gemeldet hat:
#
#   a) Maus auf die Zeile bewegen        -> faerbt sich die Zeile?
#   b) einfacher Klick                   -> Auswahl? Start?
#   c) Doppelklick                       -> Start?
#   d) Pfeiltaste ab + Enter             -> Start?
#
# Jeder Schritt bekommt einen eigenen Abzug, damit sich hinterher
# sagen laesst, WELCHER der vier Wege funktioniert und welcher nicht.
# Alles in 3440x1440.
set -uo pipefail
cd "$(dirname "$0")/../.."
KERN=${1:-/tmp/final-img/osum.mb}
WURZEL=${2:-/tmp/final-img/root.img}
W=${3:-/tmp/suchklick}
rm -rf "$W"; mkdir -p "$W"
cp "$WURZEL" "$W/disk.img"

mon(){ printf '%s\n' "$1" | socat - "UNIX-CONNECT:$W/mon" >/dev/null 2>&1; sleep "${2:-1}"; }
schuss(){ mon "screendump $W/$1.ppm" 2; }

APPEND="osum gfx disp fbres=3440x1440 wm wig desk wmshell wmdauer herz"
APPEND="$APPEND absturzhalt nopuls tz=120 lang=en usb hidgen modfs"
APPEND="$APPEND nosched noproc nofs"

qemu-system-x86_64 -kernel "$KERN" -m 2048 -append "$APPEND" \
  -serial "file:$W/serial.txt" -display none -no-reboot \
  -device "VGA,edid=on,xres=3440,yres=1440,vgamem_mb=128" \
  -drive "file=$W/disk.img,format=raw,if=ide,index=0" \
  -monitor "unix:$W/mon,server,nowait" > "$W/qemu.log" 2>&1 &
QP=$!
i=0
while [ $i -lt 400 ]; do
    grep -qa 'launcher: ready' "$W/serial.txt" 2>/dev/null && break
    kill -0 "$QP" 2>/dev/null || break
    sleep 0.5; i=$((i+1))
done
sleep 8

mon "sendkey meta_l" 3
for k in e d i t; do mon "sendkey $k" 0.5; done
sleep 2
schuss 10-getippt
echo "--- nach dem Tippen ---"
grep -a 'launcher: suche' "$W/serial.txt" | tail -1

# Die erste Trefferzeile: Fenster y=792 + Liste y=164 + halbe Zeile 28
Y=984
X=450

echo "--- a) nur bewegen ---"
mon "mouse_move $X $Y" 2
schuss 11-hover

echo "--- b) einfacher Klick ---"
mon "mouse_button 1" 1
mon "mouse_button 0" 3
schuss 12-einklick

echo "--- c) Doppelklick ---"
mon "mouse_button 1" 0.1
mon "mouse_button 0" 0.1
mon "mouse_button 1" 0.1
mon "mouse_button 0" 3
schuss 13-doppelklick

echo "--- d) Pfeil ab + Enter ---"
mon "sendkey down" 1
mon "sendkey ret" 3
schuss 14-enter

sleep 3
schuss 15-ende
kill "$QP" 2>/dev/null; wait "$QP" 2>/dev/null

echo
echo "== Startversuche =="
grep -aE 'launcher: (start|exec|zu)|desk: start|SYS_EXEC|editor' "$W/serial.txt" | tail -12
echo "== Fenster, die der wm kennt =="
grep -aE 'wm: (fenster|neu|fokus)' "$W/serial.txt" | tail -8
