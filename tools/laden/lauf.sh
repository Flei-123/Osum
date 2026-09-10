#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/laden/lauf.sh -- EIN Lauf auf der Arbeitsplatte, mit Bild.
#
#   bash tools/laden/lauf.sh <name> "<kernelzeile>" [limit] [marke] [monitordatei]
#
# Die Platte ist $OUT/lauf.img und wird NICHT zurueckgesetzt: die Runde
# misst eine FOLGE -- vorher, installieren, nachher --, und dafuer muss
# der Lauf davor auf der Platte stehengeblieben sein. Wer von vorn
# anfangen will, kopiert $OUT/platte/disk.img selbst darueber.
#
# ZWEI ARTEN, EIN BILD ZU BEKOMMEN, und beide gibt es schon:
#
#   `fb: hold`  Der Kern spiegelt die Konsole auf den Schirm und haelt
#               am Ende rund vier Sekunden still (Runde K7, `fbhold`).
#               So wird aus einer SHELL-Ausgabe ein Bild. Danach
#               beendet er sich selbst -- hier wird NICHT abgeschossen.
#   `wm: hold`  Der Fensterserver haelt (`wmhold`). Der Lauf endet
#               nicht von selbst, also wird nach dem Foto abgeschossen.
#
# Welche der beiden gemeint ist, sagt die Marke; ob abgeschossen wird,
# entscheidet $LADEN_KILL (Vorgabe: nur bei `wm:`).
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
OUT=${OUT:-/tmp/laden}
NAME=${1:?usage: lauf.sh <name> "<kernelzeile>" [limit] [marke] [monitor]}
ZEILE=${2:-}
LIMIT=${3:-300}
MARKE=${4:-}
MON=${5:-}
MEM=${MEM:-1024}
XRES=${LADEN_XRES:-1280}
YRES=${LADEN_YRES:-1024}
# `-cpu host` unter KVM. Der Grund steht in docs/OTA.md: Firns
# Bibliothek nimmt ihren AVX2-Weg, sobald CPUID ihn anbietet, und seit
# der Runde AVX schaltet Osum XSAVE/XCR0 fuer Ring 3 frei. Wer das
# Gegenteil messen will, haengt `nofpu` an die Kernelzeile.
ACC=(-cpu qemu64)
if [ "$OSUM_QEMU_ACCEL" = kvm ]; then ACC=(-cpu host); fi

case "$MARKE" in
    wm:*) KILL=${LADEN_KILL:-ja} ;;
    *)    KILL=${LADEN_KILL:-nein} ;;
esac

sock="$OUT/mon-$NAME.sock"
rm -f "$sock" "$OUT/$NAME.txt" "$OUT/$NAME.ppm" "$OUT/$NAME.png"
: > "$OUT/$NAME.txt"

timeout "$LIMIT" $QEMU_X86 "${ACC[@]}" -m "$MEM" \
    -kernel "$OUT/k.mb" -append "$ZEILE" \
    -serial "file:$OUT/$NAME.txt" -display none -no-reboot \
    -device "VGA,edid=on,xres=$XRES,yres=$YRES,vgamem_mb=32" \
    -monitor "unix:$sock,server,nowait" \
    -drive "file=${LADEN_PLATTE:-$OUT/lauf.img},format=raw,if=ide,index=0" \
    -netdev user,id=n0 -device e1000,netdev=n0,mac=52:54:00:0a:0b:0c \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$OUT/$NAME.qemu" 2>&1 &
pid=$!

if [ -n "$MARKE" ]; then
    i=0
    while [ $i -lt 8000 ]; do
        grep -qaE "$MARKE" "$OUT/$NAME.txt" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.15; i=$((i + 1))
    done
fi
# NACH DER MARKE NOCH WARTEN. Eine Marke sagt, dass eine Stufe
# BEGONNEN hat -- `desk: start` steht in der seriellen Leitung, bevor
# der erste Bildpunkt des Schreibtischs auf dem Schirm ist. Wer sofort
# fotografiert, bekommt ein leeres Bild; gemessen: 1280x1024 mit ZWEI
# Farben.
[ "${LADEN_WARTE:-0}" != 0 ] && sleep "${LADEN_WARTE}"
# EIN BILD VOR DEM EINGRIFF. Der Nachweis "das Programm kam aus dem
# Laden" braucht ZWEI Aufnahmen derselben Maschine: den Starter mit der
# Liste, und danach dasselbe Bild mit dem gestarteten Fenster darin.
# Zwei Laeufe waeren zwei Maschinen.
if [ "${LADEN_VORSHOT:-nein}" = ja ]; then
    python3 tools/gfx/screenshot.py "$sock" "$OUT/$NAME-vor.ppm" 25 \
        > "$OUT/$NAME-vor.shot" 2>&1
    if [ -s "$OUT/$NAME-vor.ppm" ]; then
        python3 -c "import sys;from PIL import Image;Image.open(sys.argv[1]+'.ppm').convert('RGB').save(sys.argv[1]+'.png')" \
            "$OUT/$NAME-vor" 2>/dev/null
    fi
fi
if [ -n "$MON" ] && [ -s "$MON" ]; then
    python3 tools/wm/monitor.py "$sock" "$MON" "${LADEN_TIPPAUSE:-0.10}" > "$OUT/$NAME.monlog" 2>&1
fi
# DIE ZWEITE MARKE, und sie ist der Grund, warum die Bilder dieser
# Runde ueberhaupt etwas zeigen: das Terminalfenster haengt an der
# KONSOLE, und auf dieselbe Konsole schreiben Kern, Schreibtisch und
# Taskleiste weiter. Wer nach einem festen `warte 220` fotografiert,
# bekommt nicht die Antwort des Befehls, sondern das, was seither
# nachgerueckt ist -- gemessen: das Bild zeigte die Zeilen der
# Taskleiste. $LADEN_MARKE2 wartet auf die LETZTE Zeile der Antwort
# und loest sofort danach aus.
if [ -n "${LADEN_MARKE2:-}" ]; then
    i=0
    while [ $i -lt 8000 ]; do
        grep -qaE "$LADEN_MARKE2" "$OUT/$NAME.txt" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.15; i=$((i + 1))
    done
fi
python3 tools/gfx/screenshot.py "$sock" "$OUT/$NAME.ppm" 25 > "$OUT/$NAME.shot" 2>&1
[ "$KILL" = ja ] && kill "$pid" 2>/dev/null
wait "$pid"; rc=$?
rm -f "$sock"
echo "$rc" > "$OUT/$NAME.rc"
if [ -s "$OUT/$NAME.ppm" ]; then
    python3 - "$OUT/$NAME" <<'PY' 2>/dev/null
import sys
from PIL import Image
b = sys.argv[1]
im = Image.open(b + ".ppm").convert("RGB")
im.save(b + ".png")
print("   bild      %s.png  %dx%d, %d Farben"
      % (b, im.size[0], im.size[1], len(im.getcolors(maxcolors=1 << 24) or [])))
PY
fi
echo "   $NAME  rc=$rc  $(wc -c < "$OUT/$NAME.txt") Oktette seriell"
exit 0
