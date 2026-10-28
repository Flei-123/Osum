#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
export FIRNLIB=$PWD/lib
OUT=${1:?output dir}
SMP=${SMP:-4}
MB=${MB:-8}
SZ=${SZ:-65536}
N=${N:-4}
MEM=${MEM:-8192}
HIGH_GIB=${HIGH_GIB:-150}
mkdir -p "$OUT"
KERNEL=${KERNEL:-$OUT/k.mb}
[ -f "$KERNEL" ] || bash tools/build-kernel.sh "$KERNEL" > "$OUT/build.txt" 2>&1 || { tail -5 "$OUT/build.txt"; exit 1; }
as --64 -o "$OUT/crt.o" kernel/user/crt.s
SPEC="/bin/ /tmp/ /dev/ /proc/"
for p in sh ls echo rm df wbench sleep; do
    vendor/firn/bin/firnc kernel/user/$p.fi -o "$OUT/$p.o" 2> "$OUT/e$p" || { head "$OUT/e$p"; exit 1; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F0.u_start" -o "$OUT/$p.elf" "$OUT/crt.o" "$OUT/$p.o"
    SPEC="$SPEC /bin/$p=$OUT/$p.elf"
done
python3 tools/osum/mkfs.py build "$OUT/d.img" 600000 --v3 --inodes=256 $SPEC > "$OUT/mk.txt" 2>&1 || { tail -3 "$OUT/mk.txt"; exit 1; }
START=$((HIGH_GIB * 2048 * 1024))
SECT=$(( $(stat -c %s "$OUT/d.img") / 512 ))
rm -f "$OUT/hi.img"
dd if=/dev/null of="$OUT/hi.img" bs=512 seek=$((START + SECT + 6144)) count=0 status=none
sgdisk -o "$OUT/hi.img" > /dev/null 2>&1
sgdisk -n 1:$START:$((START + SECT - 1)) -t 1:4F53554D-4F46-5301-8E75-6D6F72694F53 -c 1:OSUM "$OUT/hi.img" > /dev/null 2>&1 || { echo "WBPAR: sgdisk failed"; exit 1; }
dd if="$OUT/d.img" of="$OUT/hi.img" bs=512 seek=$START conv=notrunc,sparse status=none
S=""
for i in $(seq 1 "$N"); do S="$S wbench /f$i $MB $SZ &;"; done
timeout ${TMO:-300} qemu-system-x86_64 -accel kvm -cpu host -smp "$SMP" -kernel "$KERNEL" -m "$MEM" -append "osum vfs nokbd script=$S sleep 40;df;ls /;exit" \
    -serial "file:$OUT/s.txt" -display none -no-reboot -device ahci,id=ahci -drive "file=$OUT/hi.img,format=raw,if=none,id=d0" -device ide-hd,drive=d0,bus=ahci.0 \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
rm -f "$OUT/hi.img"
done_n=$(tr -d '\000' < "$OUT/s.txt" | grep -ac "wbench: total_ticks")
pass=0
[ "$done_n" = "$N" ] && pass=1
tr -d '\000' < "$OUT/s.txt" | grep -a "EXCEPTION\|PANIC\|panic" | head -3
if [ "$pass" = 1 ]; then echo "WBPAR: $N parallel writers finished (smp $SMP, mem $MEM MiB, partition at $HIGH_GIB GiB)"; exit 0; fi
echo "WBPAR: only $done_n of $N writers finished"
exit 1
