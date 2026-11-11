#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/speedcmp/osum.sh <outdir> <speedbench-binary> -- boots speedbench RUNS times under Osum (QEMU/KVM), writes <outdir>/osum-<n>.txt
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
. tools/speedcmp/common.sh
OUT=${1:?outdir}; BENCH=${2:?bench binary}
mkdir -p "$OUT"
export FIRNLIB="$ROOT/lib"
bash vendor/firn/fetch-firnc.sh >/dev/null || { echo "osum: fetch-firnc failed" >&2; exit 1; }
LIBC=$(resolve_musl_libc) || { echo "osum: no musl libc.so" >&2; exit 1; }
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT

if [ -n "${SPEED_KERNEL:-}" ]; then
    cp "$SPEED_KERNEL" "$W/k.mb"
else
    bash tools/build-kernel.sh "$W/k.mb" --stufe 1 > "$W/kernel.log" 2>&1 || { tail -8 "$W/kernel.log" >&2; exit 1; }
    [ -n "${SPEED_KERNEL_OUT:-}" ] && cp "$W/k.mb" "$SPEED_KERNEL_OUT"
fi

as --64 -o "$W/crt.o" kernel/user/crt.s || exit 1
SPEC="/lib/ /bin/ /tmp/ /etc/ /dev/ /proc/ /run/"
for p in sh ls cat echo; do
    vendor/firn/bin/firnc1 "kernel/user/$p.fi" -o "$W/$p.o" > "$W/$p.log" 2>&1 || { head -5 "$W/$p.log" >&2; exit 1; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F1.u_start" -o "$W/$p.elf" "$W/crt.o" "$W/$p.o" 2>> "$W/$p.log" || exit 1
    strip --strip-all "$W/$p.elf" 2>/dev/null
    SPEC="$SPEC /bin/$p=$W/$p.elf"
done
printf 'root:x:0:0:root:/root:/bin/sh\n' > "$W/passwd"
SPEC="$SPEC /lib/ld-musl-x86_64.so.1=$LIBC /bin/speedbench=$BENCH /etc/passwd=$W/passwd"
bash tools/mkfsfi/mkfs.sh build "$W/disk.img" 98304 --v3 --inodes=1024 $SPEC > "$W/mkfs.txt" 2>&1 || { tail -5 "$W/mkfs.txt" >&2; exit 1; }

OSUM_DRIVE=${OSUM_DRIVE:-ahci}
for i in $(seq 1 "$SPEED_RUNS"); do
    cp "$W/disk.img" "$W/live.img"
    drive_args "$OSUM_DRIVE" "$W/live.img" || exit 1
    timeout "$SPEED_BOOT_TIMEOUT" qemu-system-x86_64 "${SPEED_KVM[@]}" -smp "$SPEED_SMP" -m "$SPEED_MEM" -kernel "$W/k.mb" \
        -append "osum vfs nokbd ${SPEED_OSUM_WORDS-nosched noproc nofs} script=/bin/speedbench;exit" -serial "file:$OUT/osum-$i.raw" -display none -no-reboot \
        "${DRIVE_ARGS[@]}" -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
    echo "osum run $i rc=$?" >&2
    grep -a '^S ' "$OUT/osum-$i.raw" | tr -d '\r' > "$OUT/osum-$i.txt"
    rm -f "$W/live.img"
done
