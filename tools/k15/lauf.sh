#!/usr/bin/env bash
# tools/k15/lauf.sh -- EINEN Lauf machen, ein Foto holen, zum Iterieren.
#
#   bash tools/k15/lauf.sh <name> "<kommandozeile>" [monitordatei]
#
# Legt unter $OUT ab: <name>.txt (die serielle Leitung) und <name>.ppm.
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${OUT:-/tmp/k15}
NAME=${1:-w}
ZEILE=${2:-"gfx wm wig wmhold wiglong nokbd nosched noproc nofs"}
MON=${3:-}
MARKE=${MARKE:-"^wm: hold"}
sock="$OUT/mon-$NAME.sock"
rm -f "$sock" "$OUT/$NAME.txt" "$OUT/$NAME.ppm"
cp -f "$OUT/disk.img" "$OUT/live-$NAME.img"
timeout 240 qemu-system-x86_64 -kernel "$OUT/k.mb" -m 256 -append "$ZEILE" \
    -serial "file:$OUT/$NAME.txt" -display none -no-reboot -vga std \
    -monitor "unix:$sock,server,nowait" \
    -drive "file=$OUT/live-$NAME.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
pid=$!
i=0
while [ $i -lt 1200 ]; do
    grep -qaE "$MARKE" "$OUT/$NAME.txt" 2>/dev/null && break
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.15
    i=$((i + 1))
done
if [ -n "$MON" ]; then
    python3 tools/wm/monitor.py "$sock" "$MON" > "$OUT/$NAME.monlog" 2>&1
fi
python3 tools/gfx/schuss.py "$sock" "$OUT/$NAME.ppm" 25 > "$OUT/$NAME.shot" 2>&1
wait "$pid"
rc=$?
rm -f "$sock"
echo "rc=$rc  $(wc -c < "$OUT/$NAME.txt") Oktette seriell"
exit 0
