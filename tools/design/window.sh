#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
#   bash tools/design/window.sh
#
#
#
#
set -uo pipefail
cd "$(dirname "$0")/../.."

W=${1:-/tmp/fenstermess}
BUILDD=${DESIGNBUILD:-/tmp/osum-designbuild-$(pwd | md5sum | cut -c1-12)}

SW=3440
SH=1440

echo "== bauen =="
bash vendor/firn/fetch-firnc.sh > "$BUILDD/fetch.log" 2>&1 || {
    echo "FEHLGESCHLAGEN: fetch-firnc.sh"; tail -5 "$BUILDD/fetch.log"; exit 1; }
./tools/build-kernel.sh "$BUILDD/k0.mb" > "$BUILDD/k.log" 2>&1 \
    || { echo "FAIL: the kernel does not build"; tail -25 "$BUILDD/k.log"; exit 1; }
echo "kernel $(stat -c%s "$BUILDD/k0.mb") Oktette"

WURZEL=${WURZEL:-}
if [ -z "$WURZEL" ]; then
    WURZEL=$(ls -t /tmp/*/disk.img 2>/dev/null | head -1 || true)
fi
if [ ! -s "$WURZEL" ]; then
    echo "FEHLGESCHLAGEN: keine Wurzelplatte gefunden"
    echo "  einmal 'bash tools/design/capture.sh' laufen lassen,"
    echo "  or set WURZEL=/path/to/disk.img"
    exit 1
fi
echo "platte $WURZEL ($(stat -c%s "$WURZEL") Oktette)"

rm -rf "$W"; mkdir -p "$W"
cp "$WURZEL" "$W/disk.img"

# ------------------------------------------------------ 2. Drehbuch
cp tools/design/window.txt "$W/drehbuch.txt"

APPEND="osum gfx disp fbres=${SW}x${SH} wm wig desk wmshell wmdauer herz"
APPEND="$APPEND crashhalt nopuls tz=120 lang=en usb hidgen modfs"
APPEND="$APPEND nosched noproc nofs"

qemu-system-x86_64 -kernel "$BUILDD/k0.mb" -m 2048 -append "$APPEND" \
  -serial "file:$W/serial.txt" -display none -no-reboot \
  -device "VGA,edid=on,xres=$SW,yres=$SH,vgamem_mb=128" \
  -drive "file=$W/disk.img,format=raw,if=ide,index=0" \
  -monitor "unix:$W/mon,server,nowait" > "$W/qemu.log" 2>&1 &
QP=$!
sleep 3
python3 tools/design/drive.py "$W/mon" "$W/serial.txt" "$W" \
    "$W/drehbuch.txt" > "$W/fahren.log" 2>&1 || true
kill "$QP" 2>/dev/null; wait "$QP" 2>/dev/null

echo
echo "== der Fahrer =="
sed 's/^/   /' "$W/fahren.log" | tail -25

echo
echo "== what the window manager itself reported =="
grep -aE 'wm: (work|fen|ebene|voll)' "$W/serial.txt" | tail -30 | sed 's/^/   /'

echo
python3 tools/design/fenstermess.py "$W" "$SW" "$SH"
