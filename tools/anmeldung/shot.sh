#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/anmeldung/shot.sh -- EIN FOTO AUS EINEM LAUF, mit Tastendruecken.
#
#   bash tools/anmeldung/shot.sh <bauverz> <ausgabe.png> [taste ...]
#
# Der Weg ist woertlich der aus tools/usbimg/shot-qs2.sh und
# /root/gbwork/qsshot.sh: DAUERBETRIEB (`wmshell wmdauer herz`), nicht
# `wmhold` -- mit `wmhold` ist die Schleife der Leiste vorbei, und eine
# Taste, die danach kommt, steht als letzte Zeile im Bericht und wirkt
# nicht mehr.
#
# Die Tasten gehen ueber den QEMU-Monitor (`sendkey`), mit einer Pause
# dazwischen -- dieselbe Mechanik, mit der die Runde ALLTAG den
# Sperrbildschirm gemessen hat. `@N` wartet N Zehntelsekunden,
# `#foto:name` macht ein Zwischenbild <ausgabe>-name.png.
#
# ENV:
#   APPEND_EXTRA   zusaetzliche Woerter auf der Kernelzeile
#   SEKUNDEN       Gesamtlaufzeit (Vorgabe 45)
#   VORLAUF        Wartezeit vor der ersten Taste (Vorgabe 12)
set -uo pipefail
cd "$(dirname "$0")/../.."

BUILD=${1:?bauverzeichnis fehlt}
OUT=${2:?ausgabe.png fehlt}
shift 2

[ -f "$BUILD/osum.mb" ] || { echo "== $BUILD/osum.mb fehlt" >&2; exit 1; }
[ -f "$BUILD/root.img" ] || { echo "== $BUILD/root.img fehlt" >&2; exit 1; }

SEKUNDEN=${SEKUNDEN:-45}
VORLAUF=${VORLAUF:-12}
EXTRA=${APPEND_EXTRA:-}

W=$(mktemp -d)
QP=""
trap 'kill $QP 2>/dev/null; rm -rf "$W"' EXIT

# EIGENE KOPIE DER PLATTE: zwei Laeufe duerfen sich nicht um die
# Schreibsperre streiten ("Failed to get write lock").
cp "$BUILD/root.img" "$W/disk.img"

KVM=(-accel tcg)
[ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)

APPEND="gfx fbres=1280x800 wm wig desk wmshell wmdauer herz"
APPEND="$APPEND nosched noproc nofs lang=de uiscale=1 $EXTRA"

timeout $((SEKUNDEN + 40)) qemu-system-x86_64 "${KVM[@]}" -m 512 \
    -kernel "$BUILD/osum.mb" -append "$APPEND" \
    -serial "file:$W/serial.txt" -display none -no-reboot \
    -device VGA,edid=on,xres=1280,yres=800,vgamem_mb=32 \
    -monitor "unix:$W/mon,server,nowait" \
    -drive "file=$W/disk.img,format=raw,if=ide,index=0" &
QP=$!

mon() {
    printf '%s\n' "$1" | timeout 10 socat - "unix-connect:$W/mon" >/dev/null 2>&1
}

wandeln() {
    python3 - "$1" "$2" <<'PY' 2>/dev/null
import sys
from PIL import Image
Image.open(sys.argv[1]).save(sys.argv[2])
PY
}

sleep "$VORLAUF"

for t in "$@"; do
    case "$t" in
        @*)
            python3 -c "import time,sys; time.sleep(float(sys.argv[1])/10)" "${t#@}"
            ;;
        '#foto:'*)
            nm=${t#\#foto:}
            mon "screendump $W/z-$nm.ppm"
            sleep 1
            [ -f "$W/z-$nm.ppm" ] && wandeln "$W/z-$nm.ppm" "${OUT%.png}-$nm.png"
            ;;
        *)
            mon "sendkey $t"
            python3 -c "import time; time.sleep(0.35)"
            ;;
    esac
done

sleep 3
mon "screendump $W/ende.ppm"
sleep 2
[ -f "$W/ende.ppm" ] && wandeln "$W/ende.ppm" "$OUT"

cp "$W/serial.txt" "${OUT%.png}.txt" 2>/dev/null

kill $QP 2>/dev/null
wait $QP 2>/dev/null

echo "== Bild:    $OUT"
echo "== Bericht: ${OUT%.png}.txt ($(wc -l < "${OUT%.png}.txt" 2>/dev/null || echo 0) Zeilen)"
