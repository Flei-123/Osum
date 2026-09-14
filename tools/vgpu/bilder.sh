#!/usr/bin/env bash
# tools/vgpu/bilder.sh -- ZWEI BILDER, DIE GLEICH AUSSEHEN MUESSEN.
#
# Derselbe Kern, dieselbe Kommandozeile, einmal mit und einmal ohne
# Grafiktreiber -- und danach `pruef/bildpruef.py` auf beide. Sieht das
# Ergebnis verschieden aus, ist der Treiber falsch, egal wie gut seine
# Zahlen sind.
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh >/dev/null 2>&1
VGPU_DEV=${VGPU_DEV:-vg}
K=${VGPU_KERNEL:?VGPU_KERNEL setzen}
AUS=${1:-/tmp/vgpu-bilder}
mkdir -p "$AUS"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
python3 tools/osum/mkfs.py build "$T/d.img" 4096 /lib/ \
    /lib/mono.ttf=assets/osum-mono.ttf /lib/sans.ttf=assets/osum-sans.ttf >/dev/null 2>&1
for modus in alt neu; do
    W=""; [ "$modus" = alt ] && W="novgpu"
    cp -f "$T/d.img" "$T/l.img"
    S="$T/mon-$modus.sock"
    timeout 120 $QEMU_X86 -kernel "$K" -m 256 \
        -append "gfx wm wig desk wmhold wiglong vsync wighalt=6 nokbd noproc nofs $W" \
        -serial "file:$T/$modus.txt" -display none -no-reboot \
        -vga std -device virtio-gpu-pci,id=vg -global VGA.edid=off \
        -monitor "unix:$S,server,nowait" \
        -drive "file=$T/l.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    pid=$!
    i=0
    while [ $i -lt 600 ]; do
        grep -qaE '^wm: hold' "$T/$modus.txt" 2>/dev/null && break
        kill -0 $pid 2>/dev/null || break
        sleep 0.15; i=$((i+1))
    done
    sleep 1
    # DAS FOTO MUSS VOM RICHTIGEN GERAET KOMMEN.
    #
    # `screendump` ohne Geraetenamen nimmt das ERSTE Anzeigegeraet, und
    # das ist die VGA-Karte, die QEMU immer dazustellt. Mit Treiber
    # steht das Bild aber auf der virtio-gpu -- die VGA-Flaeche bleibt
    # schwarz. Ein Foto davon zeigt nicht "der Treiber malt nicht",
    # sondern "hier wird das falsche Geraet fotografiert", und der
    # Unterschied ist der zwischen einem Fehler und einer Fehlmessung.
    DEV=""
    [ "$modus" = neu ] && DEV="$VGPU_DEV"
    python3 tools/vgpu/schuss.py "$S" "$AUS/$modus.ppm" 25 $DEV >/dev/null 2>&1
    wait $pid 2>/dev/null
    echo "$modus: $(grep -a '^vgpu:' "$T/$modus.txt"|tail -1)"
done
