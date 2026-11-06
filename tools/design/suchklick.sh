#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
#
#
#
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
APPEND="$APPEND crashhalt nopuls tz=120 lang=en usb hidgen modfs"
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
echo "--- after typing ---"
grep -a 'launcher: suche' "$W/serial.txt" | tail -1

Y=984
X=450

echo "--- a) move only ---"
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
echo "== windows the wm knows =="
grep -aE 'wm: (fenster|neu|fokus)' "$W/serial.txt" | tail -8
