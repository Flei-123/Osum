#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/pidkill.sh
ROOT=$(pwd)
. tools/lib/qemu.sh
export OSUM_CPU=${OSUM_CPU:-Haswell}
OUT=${OUT:-/tmp/ota-plattform}
PORT=${OTA_PORT:-}
NAME=bild

for d in "$OUT/k.mb" "$OUT/quelle.img" "$OUT/quelle.crc" "$OUT/ziel.img"; do
    [ -e "$d" ] || { echo "BILD: $d fehlt -- erst plattformprobe.sh laufen lassen"; exit 1; }
done

if [ -z "$PORT" ]; then
    PORT=$(sed -n 's#^\(source\|quelle\)=https://10\.0\.2\.2:\([0-9]*\).*#\2#p' "$OUT/ota.conf")
fi
[ -n "$PORT" ] || { echo "IMAGE: no port in $OUT/ota.conf"; exit 1; }

VERZ="$OUT/netzmix"
[ -d "$VERZ" ] || VERZ="$OUT/netz"
[ -d "$VERZ" ] || { echo "IMAGE: no directory under $OUT/netzmix"; exit 1; }

echo "== the peer (127.0.0.1:$PORT, root $VERZ)"
( setsid nohup python3 tools/ota/server.py --wurzel "$VERZ" --port "$PORT" \
    --cert "$OUT/certs/srv.pem" --key "$OUT/certs/srv.key" --log "$OUT/srv-bild.log" > "$OUT/srv-bild.out" 2>&1 & echo $! > "$OUT/srv-bild.pid" )
SRV_PID=$(cat "$OUT/srv-bild.pid")
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
    -append "osum vfs nokbd nosched noproc nofs noring3 modfs modcrc=$CRC $NETZ script=ota search;sleep 120" \
    -serial "file:$AUS" -display none -no-reboot \
    -vga std -monitor "unix:$SOCK,server,nowait" \
    -drive "file=$OUT/ziel.img,format=raw,if=ide,index=0" \
    -netdev user,id=otan0 -device e1000,netdev=otan0,mac=52:54:00:0a:0b:0c \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1 &
PID=$!

i=0
while [ $i -lt 2000 ]; do
    grep -qaF "ota: platform" "$AUS" 2>/dev/null && break
    kill -0 "$PID" 2>/dev/null || break
    sleep 0.15
    i=$((i + 1))
done
sleep 1

python3 tools/gfx/screenshot.py "$SOCK" "$PPM" 25 > "$OUT/$NAME.shot" 2>&1
osum_kill_tree "$PID"; wait "$PID" 2>/dev/null
rm -f "$SOCK"
osum_kill_tree "$SRV_PID"

if [ -s "$PPM" ]; then
    python3 tools/gfx/ppm2png.py "$PPM" "$PNG" >/dev/null 2>&1
    echo "  Bild: $PNG ($(stat -c%s "$PNG" 2>/dev/null) Oktett)"
else
    echo "  NO image -- $OUT/$NAME.shot says why"
fi
echo "  Serielle Leitung:"
sed -n 's/^/    /p' <(grep -a '^ota:' "$AUS" | head -12)
[ -s "$PNG" ]
