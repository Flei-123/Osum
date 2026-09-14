#!/usr/bin/env bash
# tools/vgpu/paar.sh -- EIN PAAR LAEUFE: alter Weg gegen neuen, auf
# DERSELBEN Maschine, mit DEMSELBEN Kern und DERSELBEN Kommandozeile.
# Der einzige Unterschied ist das Wort `novgpu`.
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh >/dev/null 2>&1
SEK=${1:-4}
EXTRA=${2:-}
K=${VGPU_KERNEL:?VGPU_KERNEL setzen}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
python3 tools/osum/mkfs.py build "$T/d.img" 4096 /lib/ \
    /lib/mono.ttf=assets/osum-mono.ttf /lib/sans.ttf=assets/osum-sans.ttf >/dev/null 2>&1
APP="gfx wm wig desk wmhold wiglong vsync $EXTRA wighalt=$SEK nokbd noproc nofs"
for modus in alt neu; do
    W=""; [ "$modus" = alt ] && W="novgpu"
    cp -f "$T/d.img" "$T/l.img"
    timeout 200 $QEMU_X86 -kernel "$K" -m 256 \
        -append "$APP $W" -serial "file:$T/$modus.txt" -display none -no-reboot \
        -vga std -device virtio-gpu-pci -global VGA.edid=off \
        -drive "file=$T/l.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    printf '%-4s ' "$modus"
    grep -a '^gpu:' "$T/$modus.txt" | tail -1
    grep -a '^vgpu:' "$T/$modus.txt" | tail -1 | sed 's/^/       /'
    cp -f "$T/$modus.txt" "/tmp/paar-$modus.txt"
done
