#!/usr/bin/env bash
# Kleine Probe: startet das Installationsfenster ueberhaupt, und was
# sagt es? `zeig` malt es und geht wieder -- kein Schreibzugriff.
#   bash tools/dual/probe.sh [args] [ausgabe]
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
ARGS=${1:-zeig}
OUT=${2:-/tmp/dual-probe}
. "$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)/tools/lib/sperre.sh" && osum_sperre "$OUT"   # A-024
BAU=${BAU:-/tmp/dual-img}
rm -rf "$OUT"; mkdir -p "$OUT"

# Eine fremde Platte als Ziel -- sonst gibt es nichts zu sehen.
bash tools/dual/fremdplatte.sh "$OUT/platte.img" 512 > "$OUT/bau.txt" 2>&1

APPEND="modfs osum vfs gfx wm wig wmhold wmdauer wighalt=900 nokbd nosched noproc nofs"
APPEND="$APPEND lang=de uiscale=1 wigapp=/bin/installer,$ARGS"

timeout "${LIMIT:-240}" $QEMU_X86 -m 512 \
  -kernel "$BAU/osum.mb" -initrd "$BAU/root.img" -append "$APPEND" \
  -serial "file:$OUT/ser.txt" -display none -no-reboot \
  -device VGA,edid=on,xres=1280,yres=800,vgamem_mb=32 \
  -drive "file=$OUT/platte.img,format=raw,if=ide,index=0" \
  -monitor "unix:$OUT/mon,server,nowait" > "$OUT/qemu.log" 2>&1 &
QP=$!
for i in $(seq 1 60); do [ -S "$OUT/mon" ] && break; sleep 1; done
# warten, bis das Programm etwas sagt
for i in $(seq 1 120); do
    grep -qa 'installer: ready\|installer: keine\|installer: NEBENNEIN\|installer: fertig\|installer: FEHLER' "$OUT/ser.txt" 2>/dev/null && break
    sleep 1
done
sleep 3
printf 'screendump %s/s.ppm\n' "$OUT" | socat - "UNIX-CONNECT:$OUT/mon" >/dev/null 2>&1
sleep 3
kill "$QP" 2>/dev/null; wait "$QP" 2>/dev/null

if [ -s "$OUT/s.ppm" ]; then
    python3 -c "
from PIL import Image
im = Image.open('$OUT/s.ppm'); im.save('$OUT/fenster.png'); print('Bild', im.size)
" 2>&1
fi
echo "== was der Installer gesagt hat =="
tr -d '\000' < "$OUT/ser.txt" 2>/dev/null | grep -a '^installer:' | head -30
echo "== letzte Zeilen der Leitung =="
tr -d '\000' < "$OUT/ser.txt" 2>/dev/null | tail -6
