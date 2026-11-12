#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
STONES=${STONES:-/root/stones}
TMO=${TMO:-240}
SMP=${SMP:-1}
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
KVM=(); [ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)
LDREAL=$(readlink -f /lib/ld-musl-x86_64.so.1 2>/dev/null || true)
[ -r "$LDREAL" ] || LDREAL=/usr/lib/x86_64-linux-musl/libc.so
[ -r "$STONES/strace" ] || { echo "PTRACECOMPAT: $STONES/strace missing (tools/ptracecompat/build-strace.sh), skipped"; exit 0; }
. tools/lib/firnenv.sh
firnenv_need_firnc1
. tools/unterbau/devstones.sh

if [ -n "${KERNEL:-}" ]; then
    KMB=$KERNEL
else
    KMB=$D/k.mb
    bash tools/build-kernel.sh "$KMB" --stufe 1 > "$D/k.log" 2>&1 || { echo "PTRACECOMPAT: kernel build failed"; tail -8 "$D/k.log"; exit 1; }
fi

spec_progs=""
for src in tools/ptracecompat/*.c; do
    n=$(basename "$src" .c)
    musl-gcc -O1 -pthread -o "$D/$n" "$src" || { echo "PTRACECOMPAT: $n build failed"; exit 1; }
    spec_progs="$spec_progs /bin/$n=$D/$n"
done
musl-gcc -O1 -static -o "$D/true_static" tools/ptracecompat/true.c || { echo "PTRACECOMPAT: true_static build failed"; exit 1; }
musl-gcc -O1 -static-pie -fPIE -o "$D/true_spie" tools/ptracecompat/true.c || { echo "PTRACECOMPAT: true_spie build failed"; exit 1; }
spec_progs="$spec_progs /bin/true_static=$D/true_static /bin/true_spie=$D/true_spie"
as --64 -o "$D/crt.o" kernel/user/crt.s
spec="/lib/ /bin/ /tmp/ /etc/ /var/ /dev/ /proc/"
for p in sh ls cat echo; do
    "$FIRNC1" "kernel/user/$p.fi" -o "$D/$p.o" > "$D/$p.log" 2>&1 || { echo "PTRACECOMPAT: $p build failed"; exit 1; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F1.u_start" -o "$D/$p.elf" "$D/crt.o" "$D/$p.o" 2>>"$D/$p.log" || exit 1
    strip --strip-all "$D/$p.elf" 2>/dev/null
    spec="$spec /bin/$p=$D/$p.elf"
done
spec="$spec$spec_progs /lib/ld-musl-x86_64.so.1=$LDREAL /bin/strace=$STONES/strace"
bash tools/mkfsfi/mkfs.sh build "$D/disk.img" 98304 --v3 --inodes=256 $spec > "$D/mkfs.txt" 2>&1 || { echo "PTRACECOMPAT: mkfs failed"; tail -3 "$D/mkfs.txt"; exit 1; }

run_guest() {
    local tag=$1 script=$2
    cp "$D/disk.img" "$D/live.img"
    timeout "$TMO" qemu-system-x86_64 "${KVM[@]}" -smp "$SMP" -kernel "$KMB" -m 512 \
        -append "osum vfs nokbd nosched noproc nofs ${KARGS:-} script=$script;exit" \
        -serial "file:$D/$tag.ser" -display none -no-reboot -drive "file=$D/live.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$D/$tag.ser" | tr -d '\r' > "$D/$tag.txt"
}

run_guest main "${SCRIPT:-/bin/ptprobe}"
[ -n "${SHOW:-}" ] && awk "/sh: ready/{f=1} f" "$D/main.txt" | head -n "$SHOW" | cut -c1-200
pass=$(grep -c '^PC .* PASS' "$D/main.txt"); fail=$(grep -c '^PC .* \(FAIL\|GAP\)' "$D/main.txt")
grep '^PC ' "$D/main.txt" | grep -v ' PASS'
echo "PTRACECOMPAT: $pass passed, $fail failed"
[ "$fail" -eq 0 ] && [ "$pass" -gt 0 ]
