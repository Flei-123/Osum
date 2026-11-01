#!/usr/bin/env bash
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
[ "${LADEN_WARTE:-0}" != 0 ] && sleep "${LADEN_WARTE}"
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
