#!/usr/bin/env bash
# tools/viewer/dbg.sh -- EIN Bild, EIN Lauf, schnell. Nur zum Iterieren.
#   bash tools/viewer/dbg.sh <hostdatei> [weitere argumente fuer imgtest]
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh >/dev/null 2>&1
export FIRNLIB="$(pwd)/lib"
D=${DBGD:-/root/vw/dbg}
mkdir -p "$D"
BILD=$1; shift
NAME=$(basename "$BILD")
REF=""
[ -f "$BILD.rgba" ] && REF="/r/$NAME.rgba"

[ -f "$D/k.mb" ] && [ "${SKIPK:-0}" = 1 ] || bash tools/build-kernel.sh "$D/k.mb" >/dev/null || exit 1
[ -f "$D/crt.o" ] || as --64 -o "$D/crt.o" kernel/user/crt.s
for p in sh echo imgtest; do
    vendor/firn/bin/firnc "kernel/user/$p.fi" -o "$D/$p.o" > "$D/$p.err" 2>&1 || {
        echo "== $p uebersetzt nicht"; head -20 "$D/$p.err"; exit 1; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY=_F0.u_start -o "$D/$p.elf" \
        "$D/crt.o" "$D/$p.o" || exit 1
done
SPEC="/bin/sh=$D/sh.elf /bin/echo=$D/echo.elf /bin/imgtest=$D/imgtest.elf"
DATA="/b/$NAME=$BILD"
[ -n "$REF" ] && DATA="$DATA /r/$NAME.rgba=$BILD.rgba"
python3 tools/osum/mkfs.py build "$D/d.img" 32768 --inodes=64 /bin/ /b/ /r/ /aus/ \
    $SPEC $DATA > "$D/mkfs.log" 2>&1 || { tail -3 "$D/mkfs.log"; exit 1; }
cp "$D/d.img" "$D/live.img"
timeout 300 $QEMU_X86 -kernel "$D/k.mb" -m 512 \
    -append "osum nokbd nosched noproc nofs script=imgtest /b/$NAME $REF $*;exit" \
    -serial "file:$D/out.txt" -display none -no-reboot \
    -drive "file=$D/live.img,format=raw,if=ide,index=0" \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
echo "QEMU rc=$?"
grep -a 'IMG\|fault\|panic\|imgtest:' "$D/out.txt" | head -20
