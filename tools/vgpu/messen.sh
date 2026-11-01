#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh
SEK=${1:-8}
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

K=${VGPU_KERNEL:-$TMPD/k.mb}
if [ -z "${VGPU_KERNEL:-}" ]; then
    bash tools/build-kernel.sh "$K" >"$TMPD/build.log" 2>&1 \
        || { echo "Bau fehlgeschlagen"; tail -20 "$TMPD/build.log"; exit 1; }
fi

python3 tools/osum/mkfs.py build "$TMPD/disk.img" 4096 /lib/ \
    /lib/mono.ttf=assets/osum-mono.ttf /lib/sans.ttf=assets/osum-sans.ttf \
    > "$TMPD/mkfs.txt" 2>&1 || { echo "mkfs fehlgeschlagen"; cat "$TMPD/mkfs.txt"; exit 1; }

GRUND="nokbd noproc nofs"
APP="gfx wm wig desk wmhold wiglong vsync mausflut=60 wighalt=$SEK $GRUND"

lauf() { # name qemu-grafikargumente...
    local name=$1; shift
    cp -f "$TMPD/disk.img" "$TMPD/live-$name.img"
    timeout 180 $QEMU_X86 -kernel "$K" -m 256 \
        -append "$APP $VGPU_EXTRA" \
        -serial "file:$TMPD/$name.txt" -display none -no-reboot \
        "$@" -global VGA.edid=off \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    echo "--- $name ---"
    grep -a '^gpu:' "$TMPD/$name.txt" | tail -1
    grep -a '^wm: vsync=' "$TMPD/$name.txt" | tail -1 \
        | grep -oE 'comp=[0-9]+|pres=[0-9]+|frames=[0-9]+' | tr '\n' ' '
    echo
    grep -a '^vgpu:' "$TMPD/$name.txt" | tail -5
    cp -f "$TMPD/$name.txt" "/tmp/vgpu-$name.txt" 2>/dev/null || true
}

VGPU_EXTRA=${VGPU_EXTRA:-}
echo "== measurement over $SEK seconds, pointer stream 60 Hz =="
lauf vga  -vga std
lauf vgpu -vga std -device virtio-gpu-pci

echo
echo "The full recordings are under /tmp/vgpu-*.txt"
