#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
export BOOT_KERNEL_COPY=1   # r1223: QEMU -kernel/-initrd has no boot medium; the installer needs /boot/osum.mb in the root
. tools/lib/qemu.sh

IMGDIR=${1:?bauverzeichnis fehlt}
OUT=${2:?ausgabe.png fehlt}
ARGS=${3:-}
ZIEL=${4:-}

[ -f "$IMGDIR/osum.mb" ] || { echo "== $IMGDIR/osum.mb fehlt" >&2; exit 1; }
[ -f "$IMGDIR/root.img" ] || { echo "== $IMGDIR/root.img fehlt" >&2; exit 1; }

W=$(mktemp -d)
QP=""
trap 'kill $QP 2>/dev/null; rm -rf "$W"' EXIT

PLATTE=()
if [ -n "$ZIEL" ]; then
    cp "$ZIEL" "$W/ziel.img"
    PLATTE=(-drive "file=$W/ziel.img,format=raw,if=ide,index=0")
fi

APPEND="modfs osum vfs gfx wm wig desk wmshell wmdauer herz nostart"
APPEND="$APPEND nosched noproc nofs lang=de uiscale=1"
if [ -n "$ARGS" ]; then
    APPEND="$APPEND wigapp=/bin/installer,$ARGS"
else
    APPEND="$APPEND wigapp=/bin/installer"
fi

timeout 300 $QEMU_X86 -m 512 \
    -kernel "$IMGDIR/osum.mb" -initrd "$IMGDIR/root.img" \
    -append "$APPEND" \
    -serial "file:$W/serial.txt" -display none -no-reboot \
    -device VGA,edid=on,xres=1280,yres=800,vgamem_mb=32 \
    -monitor "unix:$W/mon,server,nowait" \
    "${PLATTE[@]}" > "$W/qemu.log" 2>&1 &
QP=$!

mon() { printf '%s\n' "$1" | socat - "UNIX-CONNECT:$W/mon" >/dev/null 2>&1; sleep "${2:-1}"; }

i=0
while [ $i -lt 400 ]; do
    grep -qa 'w=640 h=440' "$W/serial.txt" 2>/dev/null && break
    kill -0 "$QP" 2>/dev/null || break
    sleep 0.5; i=$((i + 1))
done
sleep 6

mon "screendump $W/s.ppm" 4
kill "$QP" 2>/dev/null; wait "$QP" 2>/dev/null

mkdir -p "$(dirname "$OUT")"
cp "$W/serial.txt" "${OUT%.png}.txt" 2>/dev/null
if [ -s "$W/s.ppm" ]; then
    python3 -c "
from PIL import Image
Image.open('$W/s.ppm').save('$OUT')
print('  $OUT')
"
else
    echo "== no image was produced" >&2
    tail -5 "$W/qemu.log" >&2
    exit 1
fi
grep -aE '^installer:|w=640 h=440' "$W/serial.txt" | tail -6 | sed 's/^/      /'
