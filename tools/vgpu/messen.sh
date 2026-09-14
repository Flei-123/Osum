#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/vgpu/messen.sh -- DIE WAAGE DER RUNDE VIRTIOGPU.
#
# EIN Schreibtischlauf, zwei Betriebsarten, DIESELBE Rechnung:
#
#   vga     der heutige Weg -- Kopie in den Rahmenpuffer der Firmware
#   vgpu    der neue Weg    -- virtio-gpu, nur geaenderte Rechtecke
#
# Gemessen wird an einem BEWEGTEN Bild: `mausflut=60` erzeugt einen
# echten Zeigerstrom aus dem Kern (60 Pakete je Sekunde), und die Uhr
# in der Leiste tickt ohnehin. Ein stehendes Bild waere die falsche
# Messung -- dort ist jede Zahl klein, weil sich nichts aendert.
#
#   bash tools/vgpu/messen.sh [sekunden]
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

# DAS ABBILD MIT DEN SCHRIFTEN -- ohne sie gibt es keine Fenster, und
# ohne Fenster misst dieser Lauf einen leeren Schirm.
python3 tools/osum/mkfs.py build "$TMPD/disk.img" 4096 /lib/ \
    /lib/mono.ttf=assets/osum-mono.ttf /lib/sans.ttf=assets/osum-sans.ttf \
    > "$TMPD/mkfs.txt" 2>&1 || { echo "mkfs fehlgeschlagen"; cat "$TMPD/mkfs.txt"; exit 1; }

GRUND="nokbd nosched noproc nofs"
# mausflut=60 -- ein Zeigerstrom mit echter Rate. wighalt haelt den
# Schreibtisch die Messdauer offen, damit die Uhr wirklich tickt.
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
echo "== Messung ueber $SEK Sekunden, Zeigerstrom 60 Hz =="
lauf vga  -vga std
lauf vgpu -vga std -device virtio-gpu-pci

echo
echo "Die vollen Mitschnitte liegen unter /tmp/vgpu-*.txt"
