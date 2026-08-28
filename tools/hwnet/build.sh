#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/hwnet/build.sh -- kernel image + disk image for round HWNET.
#
#   tools/hwnet/build.sh <workdir> [stage]
#
# stage 0 = firnc0 (the Rust compiler), 1 = firnc1 (the one written in
# Firn). Both have to build the same thing; ./test.sh measures that, and
# this file exists so that the round's runner does not have to repeat
# the twenty lines.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
W=${1:?workdir}
S=${2:-0}
mkdir -p "$W"

export FIRNLIB="$ROOT/lib"
FIRNC=${FIRNC:-vendor/firn/bin/firnc}
FC1=${FIRNC1:-vendor/firn/bin/firnc1}
LDSCRIPT=kernel/kernel.ld
ULD=kernel/user/user.ld
PROGS=${HWNET_PROGS:-"sh ls cat echo ping wget dhcp"}
BLOCKS=${HWNET_BLOCKS:-8192}

if [ "$S" = 0 ]; then CC="$FIRNC"; else CC="$FC1"; fi

for f in boot isr switch smp hv; do
    as --64 -o "$W/$f.o" "kernel/arch/x86_64/$f.s" || exit 1
done
as --64 -o "$W/crt.o" kernel/user/crt.s || exit 1

"$CC" kernel/kmain.fi -o "$W/k.o" > "$W/build.log" 2>&1 || {
    echo "kmain.fi does not compile"; head -20 "$W/build.log"; exit 1; }
"$CC" kernel/uprog.fi -o "$W/u.o" >> "$W/build.log" 2>&1 || {
    echo "uprog.fi does not compile"; tail -20 "$W/build.log"; exit 1; }
ld -n -T "$LDSCRIPT" \
    --defsym=KERNEL_MAIN="_F$S.kernel_main" \
    --defsym=KERNEL_TRAP="_F$S.trap__entry" \
    --defsym=KERNEL_SYSCALL="_F$S.sys__entry" \
    --defsym=KERNEL_TASK_MAIN="_F$S.tasks__main" \
    --defsym=KERNEL_USER_START="_F$S.proc__user_start" \
    --defsym=KERNEL_AP_MAIN="_F$S.smp__ap_main" \
    --defsym=USER_MAIN="_F$S.u_enter" \
    -o "$W/k.elf" "$W/boot.o" "$W/isr.o" "$W/switch.o" "$W/smp.o" \
    "$W/hv.o" "$W/k.o" "$W/u.o" 2>"$W/ld.err" || {
    echo "ld failed"; head -10 "$W/ld.err"; exit 1; }
objcopy -O elf32-i386 "$W/k.elf" "$W/k.mb" || exit 1

SPEC="/bin/"
for p in $PROGS; do
    "$CC" "kernel/user/$p.fi" -o "$W/$p.o" >> "$W/build.log" 2>&1 || {
        echo "$p.fi does not compile"; tail -10 "$W/build.log"; exit 1; }
    ld -T "$ULD" --defsym=USER_ENTRY="_F$S.u_start" \
        -o "$W/$p.elf" "$W/crt.o" "$W/$p.o" 2>/dev/null || {
        echo "ld failed on $p"; exit 1; }
    strip --strip-all "$W/$p.elf"
    SPEC="$SPEC /bin/$p=$W/$p.elf"
done
python3 tools/osum/mkfs.py build "$W/disk.img" $BLOCKS $SPEC > "$W/mkfs.txt" 2>&1 \
    || { echo "mkfs failed"; tail -5 "$W/mkfs.txt"; exit 1; }
echo "hwnet/build: $W/k.mb + $W/disk.img (stage $S, $(echo $PROGS | wc -w) programs)"
