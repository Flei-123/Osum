#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/ota/plattformbild.sh -- RUNDE STORE-MOBIL: EIN BILD VOM SCHIRM.
#
# `tools/ota/plattformprobe.sh` misst, was `/bin/ota` unter QEMU AUSGIBT
# -- ueber die serielle Leitung, weil sich das vergleichen laesst. Diese
# Datei macht das, was man nicht vergleichen, aber ansehen kann: ein
# Bildschirmfoto DERSELBEN Maschine, waehrend `ota suchen` laeuft.
#
# Der Weg ist der aus Runde K15 (und `tools/speicher/run.sh`): QEMU hat
# auch bei `-display none` eine Bildflaeche, wenn man `-vga std` gibt,
# und ueber den Monitor an einem Unix-Socket schreibt `screendump` sie
# als PPM; `tools/gfx/ppm2png.py` macht ein PNG daraus.
#
#   bash tools/ota/plattformprobe.sh      # erst messen (baut $OUT)
#   bash tools/ota/plattformbild.sh       # dann das Bild
#
# $OUT (Vorgabe /tmp/ota-plattform) muss der Ausgabeordner eines Laufes
# von plattformprobe.sh sein: Abbild, Gegenstelle und Verzeichnis liegen
# dort schon. Ergebnis: $OUT/ota-plattform.png (und .ppm).
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
. tools/lib/qemu.sh
export OSUM_CPU=${OSUM_CPU:-Haswell}
OUT=${OUT:-/tmp/ota-plattform}
PORT=${OTA_PORT:-}
NAME=bild

for d in "$OUT/k.mb" "$OUT/quelle.img" "$OUT/quelle.crc" "$OUT/ziel.img"; do
    [ -e "$d" ] || { echo "BILD: $d fehlt -- erst plattformprobe.sh laufen lassen"; exit 1; }
done

# Die Gegenstelle: dieselbe wie in der Probe. Der Port steht in ota.conf.
if [ -z "$PORT" ]; then
    PORT=$(sed -n 's#^quelle=https://10\.0\.2\.2:\([0-9]*\).*#\1#p' "$OUT/ota.conf")
fi
[ -n "$PORT" ] || { echo "BILD: kein Port in $OUT/ota.conf"; exit 1; }

VERZ="$OUT/netzmix"
[ -d "$VERZ" ] || VERZ="$OUT/netz"
[ -d "$VERZ" ] || { echo "BILD: kein Verzeichnis unter $OUT/netzmix"; exit 1; }

echo "== die Gegenstelle (127.0.0.1:$PORT, Wurzel $VERZ)"
pkill -f "tools/ota/server.py .* $PORT" >/dev/null 2>&1
( setsid nohup python3 tools/ota/server.py --wurzel "$VERZ" --port "$PORT" \
    --cert "$OUT/certs/srv.pem" --key "$OUT/certs/srv.key" --log "$OUT/srv-bild.log" > "$OUT/srv-bild.out" 2>&1 & )
sleep 1.5

CRC=$(cat "$OUT/quelle.crc")
NETZ="nic nip=10.0.2.15/24 ngw=10.0.2.2 nsvc=0 nwait=0"
SOCK="$OUT/mon-$NAME.sock"
AUS="$OUT/$NAME.txt"
PPM="$OUT/ota-plattform.ppm"
PNG="$OUT/ota-plattform.png"
rm -f "$SOCK" "$AUS" "$PPM" "$PNG"
: > "$AUS"

echo "== die Maschine (QEMU, -vga std, Monitor an $SOCK)"
timeout 900 $QEMU_X86 -machine pc -cpu "$OSUM_CPU" -m "${MEM:-512}" \
    -kernel "$OUT/k.mb" -initrd "$OUT/quelle.img" \
    -append "osum vfs nokbd nosched noproc nofs noring3 modfs modcrc=$CRC $NETZ script=ota suchen;sleep 120" \
    -serial "file:$AUS" -display none -no-reboot \
    -vga std -monitor "unix:$SOCK,server,nowait" \
    -drive "file=$OUT/ziel.img,format=raw,if=ide,index=0" \
    -netdev user,id=otan0 -device e1000,netdev=otan0,mac=52:54:00:0a:0b:0c \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1 &
PID=$!

# Warten, bis die Liste WIRKLICH auf dem Schirm steht -- nicht blind
# schlafen. Die letzte Zeile, die `ota suchen` schreibt, ist die
# Zaehlung des Ausgeblendeten.
i=0
while [ $i -lt 2000 ]; do
    grep -qaF "ota: plattform" "$AUS" 2>/dev/null && break
    kill -0 "$PID" 2>/dev/null || break
    sleep 0.15
    i=$((i + 1))
done
sleep 1

python3 tools/gfx/screenshot.py "$SOCK" "$PPM" 25 > "$OUT/$NAME.shot" 2>&1
kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null
rm -f "$SOCK"
pkill -f "tools/ota/server.py .* $PORT" >/dev/null 2>&1

if [ -s "$PPM" ]; then
    python3 tools/gfx/ppm2png.py "$PPM" "$PNG" >/dev/null 2>&1
    echo "  Bild: $PNG ($(stat -c%s "$PNG" 2>/dev/null) Oktett)"
else
    echo "  KEIN Bild -- $OUT/$NAME.shot sagt warum"
fi
echo "  Serielle Leitung:"
sed -n 's/^/    /p' <(grep -a '^ota:' "$AUS" | head -12)
[ -s "$PNG" ]
