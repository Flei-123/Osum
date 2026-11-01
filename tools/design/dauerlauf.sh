#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
#   bash tools/design/dauerlauf.sh [anzahl] [smp]
#
#
#
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"

N=${1:-20}
SMP=${2:-4}
OUT=${DAUEROUT:-/tmp/d2-dauer}
mkdir -p "$OUT"
rm -f "$OUT/fehler.txt"

echo "== $N Laeufe, -smp $SMP, mit Bewegungen =="

bash tools/design/capture.sh "$OUT/bau" nurbau=ja shape=osum \
    res=1920x1080 > "$OUT/bau.log" 2>&1 || {
    echo "FEHLGESCHLAGEN: bauen"; tail -20 "$OUT/bau.log"; exit 1; }

BUILDD=${DESIGNBUILD:-/tmp/osum-designbuild-$(pwd | md5sum | cut -c1-12)}

ok=0
bad=0
for i in $(seq 1 "$N"); do
    d="$OUT/lauf$i"
    rm -rf "$d"
    mkdir -p "$d"
    cp "$OUT/bau/disk.img" "$d/disk.img"
    timeout 180 qemu-system-x86_64 \
        -kernel "$BUILDD/k0.mb" -m 512 -smp "$SMP" \
        -append "gfx fbres=1920x1080 wm desk wmhold wighalt=120 nokbd nosched noproc nofs" \
        -serial "file:$d/serial.txt" -display none -no-reboot \
        -device VGA,edid=on,xres=1920,yres=1080,vgamem_mb=32 \
        -drive "file=$d/disk.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        > "$d/qemu.log" 2>&1
    rc=$?
    panic=$(grep -acE 'PANIC|EXCEPTION|#PF|#GP|#DF' "$d/serial.txt" 2>/dev/null)
    fertig=$(grep -ac 'kernel: done' "$d/serial.txt" 2>/dev/null)
    if [ "$rc" = 21 ] && [ "$panic" = 0 ] && [ "$fertig" != 0 ]; then
        ok=$((ok + 1))
        printf '.'
    else
        bad=$((bad + 1))
        printf 'X'
        echo "lauf $i: rc=$rc panic=$panic fertig=$fertig" >> "$OUT/fehler.txt"
    fi
    rm -f "$d/disk.img"
done
echo
echo "== $ok of $N without panic, $bad failures =="
[ "$bad" = 0 ]
