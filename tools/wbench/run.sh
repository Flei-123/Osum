#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB=$PWD/lib
OUT=${1:?output dir}
MB=${MB:-48}
SIZES=${SIZES:-"4096 65536"}
BLOCKS=${BLOCKS:-600000}
mkdir -p "$OUT"
KERNEL=${KERNEL:-$OUT/k.mb}
[ -f "$KERNEL" ] || bash tools/build-kernel.sh "$KERNEL" > "$OUT/build.txt" 2>&1 || { tail -5 "$OUT/build.txt"; exit 1; }
as --64 -o "$OUT/crt.o" kernel/user/crt.s
SPEC="/bin/ /tmp/ /dev/ /proc/"
for p in sh ls echo rm df wbench; do
    vendor/firn/bin/firnc kernel/user/$p.fi -o "$OUT/$p.o" 2> "$OUT/e$p" || { head "$OUT/e$p"; exit 1; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" -o "$OUT/$p.elf" "$OUT/crt.o" "$OUT/$p.o"
    SPEC="$SPEC /bin/$p=$OUT/$p.elf"
done
python3 tools/osum/mkfs.py build "$OUT/d.img" "$BLOCKS" --v3 --inodes=256 ${MKOPT:-} $SPEC > "$OUT/mk.txt" 2>&1 || { tail -3 "$OUT/mk.txt"; exit 1; }
DRV=(-drive "file=$OUT/live.img,format=raw,if=ide,index=0")
[ "${DRIVE:-ahci}" = ahci ] && DRV=(-device ahci,id=ahci -drive "file=$OUT/live.img,format=raw,if=none,id=d0" -device ide-hd,drive=d0,bus=ahci.0)
for sz in $SIZES; do
    cp --sparse=always "$OUT/d.img" "$OUT/live.img"
    timeout 900 qemu-system-x86_64 -accel kvm -cpu host -kernel "$KERNEL" -m 512 -append "osum vfs nokbd script=wbench /big $MB $sz;exit" \
        -serial "file:$OUT/s$sz.txt" -display none -no-reboot "${DRV[@]}" -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
    t=$(tr -d '\000' < "$OUT/s$sz.txt" | grep -a "wbench: total_ticks" | sed 's/.*= //')
    echo "WBENCH: chunk=$sz mb=$MB ticks=${t:-none} (10 ms each)"
done
