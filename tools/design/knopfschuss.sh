#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
#   bash tools/design/knopfschuss.sh [kern.mb] [ausgabe]
#
#
set -uo pipefail
cd "$(dirname "$0")/../.."
KERN=${1:-/tmp/r2-k.mb}
W=${2:-/tmp/knopfschuss}
PLATTE=${PLATTE:-/tmp/aufn-3440/disk.img}
rm -rf "$W"; mkdir -p "$W"
[ -s "$KERN" ] || { echo "kein Kern: $KERN"; exit 1; }
[ -s "$PLATTE" ] || { echo "no disk: $PLATTE"; exit 1; }
cp "$PLATTE" "$W/disk.img"

qemu-system-x86_64 -kernel "$KERN" -m 2048 \
  -append "osum gfx disp fbres=3440x1440 wm wig desk wmshell wmdauer herz crashhalt nopuls tz=120 lang=en usb hidgen modfs nosched noproc nofs wigapp=/bin/settings" \
  -serial "file:$W/serial.txt" -display none -no-reboot \
  -device "VGA,edid=on,xres=3440,yres=1440,vgamem_mb=128" \
  -drive "file=$W/disk.img,format=raw,if=ide,index=0" \
  -monitor "unix:$W/mon,server,nowait" > "$W/qemu.log" 2>&1 &
QP=$!

i=0
while [ $i -lt 300 ]; do
    grep -qa 'settings: ready\|wm: fenster\|desk: start /bin/settings' \
        "$W/serial.txt" 2>/dev/null && break
    kill -0 "$QP" 2>/dev/null || break
    sleep 0.5; i=$((i+1))
done
sleep 12

printf 'screendump %s/schirm.ppm\n' "$W" | socat - "UNIX-CONNECT:$W/mon" >/dev/null 2>&1
sleep 5
kill "$QP" 2>/dev/null; wait "$QP" 2>/dev/null

echo "== Start =="
grep -a 'desk: start' "$W/serial.txt" | sed 's/^/   /'
echo "== Abstuerze =="
n=$(grep -acE 'CRASH|EXCEPTION' "$W/serial.txt" 2>/dev/null || echo 0)
echo "   $n"
ls -la "$W"/*.ppm 2>/dev/null || echo "   KEIN Abzug"
