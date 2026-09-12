#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/design/knopfschuss.sh -- DIE FENSTERKNOEPFE BEI JUSTINS AUFLOESUNG.
#
#   bash tools/design/knopfschuss.sh [kern.mb] [ausgabe]
#
# Faehrt 3440x1440 mit einem Fenster (Einstellungen) hoch und zieht
# ueber den QEMU-Monitor einen Bildschirmabzug. Das Ergebnis ist das
# Bild, das der Kern WIRKLICH gemalt hat -- nicht ein Nachbau in
# Python. tools/design/knopfzoom.py schneidet daraus die drei Knoepfe
# heraus und vergroessert sie.
#
# WARUM EIN EIGENER LAEUFER: `capture.sh` fotografiert sieben feste
# Ansichten und braucht dafuer Minuten; hier geht es um EINE Ecke von
# 260x80 Bildpunkten, und die muss bei Justins Aufloesung entstehen --
# bei 1280x800 ist das Kreuz zehn Bildpunkte gross und der Fehler,
# um den es geht, unsichtbar.
set -uo pipefail
cd "$(dirname "$0")/../.."
KERN=${1:-/tmp/r2-k.mb}
W=${2:-/tmp/knopfschuss}
PLATTE=${PLATTE:-/tmp/aufn-3440/disk.img}
rm -rf "$W"; mkdir -p "$W"
[ -s "$KERN" ] || { echo "kein Kern: $KERN"; exit 1; }
[ -s "$PLATTE" ] || { echo "keine Platte: $PLATTE"; exit 1; }
cp "$PLATTE" "$W/disk.img"

qemu-system-x86_64 -kernel "$KERN" -m 2048 \
  -append "osum gfx disp fbres=3440x1440 wm wig desk wmshell wmdauer herz absturzhalt nopuls tz=120 lang=en usb hidgen modfs nosched noproc nofs wigapp=/bin/settings" \
  -serial "file:$W/serial.txt" -display none -no-reboot \
  -device "VGA,edid=on,xres=3440,yres=1440,vgamem_mb=128" \
  -drive "file=$W/disk.img,format=raw,if=ide,index=0" \
  -monitor "unix:$W/mon,server,nowait" > "$W/qemu.log" 2>&1 &
QP=$!

# Warten, bis der Fensterserver das Fenster gemalt hat.
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
n=$(grep -acE 'ABSTURZ|EXCEPTION' "$W/serial.txt" 2>/dev/null || echo 0)
echo "   $n"
ls -la "$W"/*.ppm 2>/dev/null || echo "   KEIN Abzug"
