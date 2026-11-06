#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
#   bash tools/design/suchabnahme.sh [kern.mb] [wurzel.img] [ausgabe]
#
#
#
#
set -uo pipefail
cd "$(dirname "$0")/../.."
KERN=${1:-/tmp/r3-k.mb}
WURZEL=${2:-/tmp/final-img/root.img}
W=${3:-/tmp/suchabnahme}
rm -rf "$W"; mkdir -p "$W"
[ -s "$KERN" ] || { echo "kein Kern: $KERN"; exit 1; }
[ -s "$WURZEL" ] || { echo "no root: $WURZEL"; exit 1; }
cp "$WURZEL" "$W/disk.img"

pass=0; fail=0
ok(){ pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad(){ fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
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
    grep -qa 'launcher: ready\|taskbar: state' "$W/serial.txt" 2>/dev/null && break
    kill -0 "$QP" 2>/dev/null || break
    sleep 0.5; i=$((i+1))
done
sleep 10
schuss 00-schreibtisch

# --- 1. SUPER-TASTE ---------------------------------------------------
: > "$W/marke1"
mon "sendkey meta_l" 3
schuss 01-super
S1=$(grep -ac 'launcher: sichtbar\|launcher: auf\|starter: auf' "$W/serial.txt" 2>/dev/null | head -1)

# --- 3. TIPPEN --------------------------------------------------------
for k in e d i t; do mon "sendkey $k" 0.4; done
sleep 2
schuss 02-getippt

mon "mouse_move 450 1010" 1
mon "mouse_button 1" 1
mon "mouse_button 0" 3
schuss 03-maus-geklickt

sleep 3
schuss 04-nach-klick

mon "sendkey esc" 2
mon "mouse_move 44 1400" 1
mon "mouse_button 1" 1
mon "mouse_button 0" 3
schuss 05-logo-geklickt

# --- 6. PFEILTASTEN + ENTER -------------------------------------------
for k in e d i t; do mon "sendkey $k" 0.4; done
sleep 2
mon "sendkey down" 1
mon "sendkey ret" 3
schuss 06-tasten-enter
sleep 3
schuss 07-ende

kill "$QP" 2>/dev/null; wait "$QP" 2>/dev/null

echo
echo "== was die serielle Leitung sagt =="
grep -aE 'launcher:|taskbar: (state|btn)|desk: start|editor|edit:' "$W/serial.txt" \
    | tail -24 | sed 's/^/   /'
echo

n=$(grep -acE "CRASH|EXCEPTION" "$W/serial.txt" 2>/dev/null | head -1); n=${n:-0}
[ "$n" -eq 0 ] && ok "kein Absturz" || bad "$n Absturzzeilen"
grep -qa 'desk: start /bin/launcher' "$W/serial.txt" \
    && ok "der Starter laeuft ueberhaupt" || bad "kein Starter"
grep -qa 'launcher: apps=' "$W/serial.txt" \
    && ok "the launcher found programs ($(grep -ao 'apps=[0-9]*' "$W/serial.txt" | tail -1))" \
    || bad "the launcher knows no programs"
# Getippt?
grep -qa 'launcher: suche\|launcher: filter\|launcher: name' "$W/serial.txt" \
    && ok "the launcher reacted to input" || bad "no reaction to input"
# Gestartet?
if grep -qa 'launcher: starten\|launcher: exec\|SYS_EXEC' "$W/serial.txt"; then
    ok "a hit was EXECUTED"
else
    bad "no hit was executed"
fi
ls "$W"/*.ppm >/dev/null 2>&1 && ok "$(ls "$W"/*.ppm | wc -l) Abzuege abgelegt" || bad "keine Abzuege"

echo
echo "SUCHABNAHME: $pass bestanden, $fail durchgefallen"
[ "$fail" -eq 0 ]
