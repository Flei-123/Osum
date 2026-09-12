#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/design/acceptance3440.sh -- DIE ABNAHME, IN JUSTINS AUFLOESUNG.
#
#   bash tools/design/acceptance3440.sh [kern.mb] [wurzel.img] [ausgabe]
#
# DAUERREGEL SEIT DEM 10.09.: jeder Pruefstandslauf faehrt 3440x1440.
# Ein Lauf in 1920x1080 zaehlt als NICHT GELAUFEN. Der Grund steht in
# kernel/fb.fi: 3440x1440x4 sind 18,9 MiB und passten nicht in acht
# Fensterplaetze zu 2 MiB. Der Kern starb VOR der Oberflaeche, und
# weil der Pruefstand kleiner fuhr, war monatelang alles gruen,
# waehrend Justin keine Taskleiste hatte.
#
# Diese Abnahme belegt vier Dinge, die vor jeder Auslieferung stimmen
# muessen:
#   1. kein Absturz
#   2. desktop, taskbar und launcher laufen
#   3. jarvisd startet VON SELBST (Bootwort `jarvis` im Haupteintrag)
#   4. und bringt einen sechsstelligen Kopplungscode auf den Schirm
set -uo pipefail
cd "$(dirname "$0")/../.."
KERN=${1:-/tmp/r3-k.mb}
WURZEL=${2:-/tmp/final-img/root.img}
W=${3:-/tmp/abnahme3440}
rm -rf "$W"; mkdir -p "$W"
[ -s "$KERN" ] || { echo "kein Kern: $KERN"; exit 1; }
[ -s "$WURZEL" ] || { echo "keine Wurzel: $WURZEL"; exit 1; }
cp "$WURZEL" "$W/disk.img"

pass=0; fail=0
ok(){ pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad(){ fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

# Die Befehlszeile des Sticks, minus modfs (die Wurzel kommt per -drive).
APPEND="osum gfx disp fbres=3440x1440 wm wig desk wmshell wmdauer tafel herz"
APPEND="$APPEND absturzhalt nopuls tz=120 lang=en usb hidgen modfs"
APPEND="$APPEND nic nip=169.254.10.1/16 nsvc=0 nwait=0 dhcp jarvis"
APPEND="$APPEND nosched noproc nofs"
echo "append: $APPEND"
echo

qemu-system-x86_64 -kernel "$KERN" -m 2048 -append "$APPEND" \
  -serial "file:$W/serial.txt" -display none -no-reboot \
  -device "VGA,edid=on,xres=3440,yres=1440,vgamem_mb=128" \
  -drive "file=$W/disk.img,format=raw,if=ide,index=0" \
  -netdev user,id=n0 -device e1000,netdev=n0 \
  -monitor "unix:$W/mon,server,nowait" > "$W/qemu.log" 2>&1 &
QP=$!
i=0
while [ $i -lt 700 ]; do
    grep -qa 'KOPPLUNGSCODE' "$W/serial.txt" 2>/dev/null && break
    kill -0 "$QP" 2>/dev/null || break
    sleep 0.3; i=$((i+1))
done
sleep 8
printf 'screendump %s/schirm.ppm\n' "$W" | socat - "UNIX-CONNECT:$W/mon" >/dev/null 2>&1
sleep 4
kill "$QP" 2>/dev/null; wait "$QP" 2>/dev/null

echo "== Bildspeicher =="
grep -a '^fb: 3440' "$W/serial.txt" | sed 's/^/   /'
echo "== Start =="
grep -a 'desk: start' "$W/serial.txt" | sed 's/^/   /'
echo "== jarvisd =="
grep -a 'jarvisd:' "$W/serial.txt" | head -6 | sed 's/^/   /'
echo

n=$(grep -acE "ABSTURZ|EXCEPTION" "$W/serial.txt" 2>/dev/null | head -1); n=${n:-0}
[ "$n" -eq 0 ] && ok "kein Absturz bei 3440x1440" || bad "$n Absturzzeilen"
grep -qa 'huge=10' "$W/serial.txt" \
    && ok "alle zehn Kacheln abgebildet (kein Streifenbetrieb)" \
    || bad "der Bildspeicher haengt nicht am Stueck"
for p in desktop taskbar launcher; do
    grep -qa "desk: start /bin/$p" "$W/serial.txt" \
        && ok "$p laeuft" || bad "$p laeuft NICHT"
done
grep -qa 'desk: start /bin/jarvisd' "$W/serial.txt" \
    && ok "jarvisd startet VON SELBST" || bad "jarvisd startet nicht"
HEX=$(grep -a 'KOPPLUNGSCODE' "$W/serial.txt" | tail -1 | awk '{print $NF}')
if [ -n "$HEX" ]; then
    CODE=$(python3 -c "import sys;print(bytes.fromhex(sys.argv[1]).decode())" "$HEX" 2>/dev/null)
    if [ "${#CODE}" -eq 6 ]; then
        ok "sechsstelliger Kopplungscode am Schirm: $CODE"
    else
        bad "Code hat ${#CODE} Stellen: $CODE"
    fi
else
    bad "kein Kopplungscode"
fi
[ -s "$W/schirm.ppm" ] && ok "Bildschirmabzug abgelegt ($W/schirm.ppm)" \
    || bad "kein Abzug"

echo
echo "ABNAHME 3440x1440: $pass bestanden, $fail durchgefallen"
[ "$fail" -eq 0 ]
