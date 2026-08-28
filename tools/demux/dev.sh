#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/demux/dev.sh -- der kurze Weg waehrend der Arbeit: uebersetzen,
# ein Abbild bauen, EINEN Befehl in Osum laufen lassen, die Ausgabe zeigen.
#
#   bash tools/demux/dev.sh "<befehl in osum>" [weitere programme]
#
# Die Abnahme ist tools/demux/run.sh. Dieses Skript ist zum Arbeiten.
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh

CMD=${1:?Befehl fehlt}
shift
PROGS="sh demuxt $*"
MEDIA=${OSUM_MEDIA:-/tmp/demux-media}
W=${OSUM_DEVWORK:-/tmp/demux-work}
mkdir -p "$W"
export FIRNLIB="$(pwd)/lib"
FIRNC=vendor/firn/bin/firnc

[ -f "$W/crt.o" ] || as --64 -o "$W/crt.o" kernel/user/crt.s || exit 1
if [ ! -f "$W/k.mb" ] || [ kernel -nt "$W/k.mb" ]; then
    bash tools/build-kernel.sh "$W/k.mb" >/dev/null || exit 1
fi

for p in $PROGS; do
    $FIRNC "kernel/user/$p.fi" -o "$W/$p.o" || exit 1
    ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" \
        -o "$W/$p.elf" "$W/crt.o" "$W/$p.o" || exit 1
    strip --strip-all "$W/$p.elf"
done

SPEC="/bin/"
for p in $PROGS; do SPEC="$SPEC /bin/$p=$W/$p.elf"; done
SPEC="$SPEC /w/ /m/"
for f in "$MEDIA"/*; do
    case "$f" in *.raw) continue ;; esac
    SPEC="$SPEC /m/$(basename "$f")=$f"
done
python3 tools/osum/mkfs.py build "$W/disk.img" 32768 $SPEC >"$W/mkfs.log" 2>&1 \
    || { echo "mkfs fehlgeschlagen"; tail -5 "$W/mkfs.log"; exit 1; }

timeout 180 $QEMU_X86 -kernel "$W/k.mb" -m 512 \
    -append "osum nokbd nosched noproc nofs noring3 script=$CMD;exit" \
    -serial "file:$W/out.txt" -display none -no-reboot \
    -drive "file=$W/disk.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
echo "qemu exit: $?"
cat "$W/out.txt"
