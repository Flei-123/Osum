#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
DRIVES=${DRIVES:-"ide ahci nvme"}
KARGS_EXTRA=${KARGS_EXTRA:-}
TMO=${TMO:-300}
OUT=${DISKFAULT_OUT:-}
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
[ -n "$OUT" ] && mkdir -p "$OUT"
KVM=(); [ -w /dev/kvm ] && KVM=(-accel kvm -cpu host)
LDREAL=$(readlink -f /lib/ld-musl-x86_64.so.1 2>/dev/null || true)
[ -r "$LDREAL" ] || LDREAL=/usr/lib/x86_64-linux-musl/libc.so
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1

if [ -n "${KERNEL:-}" ]; then
    KMB=$KERNEL
else
    KMB=$D/k.mb
    bash tools/build-kernel.sh "$KMB" --stufe 1 > "$D/k.log" 2>&1 || { echo "DISKFAULT: kernel build failed"; tail -8 "$D/k.log"; exit 1; }
fi

musl-gcc -O1 -o "$D/diskpg" tools/diskfault/diskpg.c || { echo "DISKFAULT: diskpg build failed"; exit 1; }
as --64 -o "$D/crt.o" kernel/user/crt.s
spec="/lib/ /bin/ /tmp/ /etc/ /var/ /dev/ /proc/ /d/"
for p in sh ls cat echo; do
    vendor/firn/bin/firnc1 "kernel/user/$p.fi" -o "$D/$p.o" > "$D/$p.log" 2>&1 || { echo "DISKFAULT: $p build failed"; exit 1; }
    ld -T kernel/user/user.ld --defsym=USER_ENTRY="_F1.u_start" -o "$D/$p.elf" "$D/crt.o" "$D/$p.o" 2>>"$D/$p.log" || exit 1
    strip --strip-all "$D/$p.elf" 2>/dev/null
    spec="$spec /bin/$p=$D/$p.elf"
done
head -c $((4096 * 4096)) /dev/urandom > "$D/data.bin"
for f in seq rnd rd prd; do spec="$spec /d/$f.dat=$D/data.bin"; done
spec="$spec /bin/diskpg=$D/diskpg /lib/ld-musl-x86_64.so.1=$LDREAL"
bash tools/mkfsfi/mkfs.sh build "$D/disk.img" 262144 --v3 --inodes=256 $spec > "$D/mkfs.txt" 2>&1 || { echo "DISKFAULT: mkfs failed"; tail -3 "$D/mkfs.txt"; exit 1; }

run_drive() {
    local drive=$1 kernel=$2 tag=$3 drv
    cp "$D/disk.img" "$D/live.img"
    case "$drive" in
        ide)  drv=(-drive "file=$D/live.img,format=raw,if=ide,index=0") ;;
        ahci) drv=(-device ahci,id=ahci -drive "file=$D/live.img,format=raw,if=none,id=d0" -device ide-hd,drive=d0,bus=ahci.0) ;;
        nvme) drv=(-drive "file=$D/live.img,format=raw,if=none,id=d0" -device nvme,drive=d0,serial=bench) ;;
    esac
    timeout "$TMO" qemu-system-x86_64 "${KVM[@]}" -smp 1 -kernel "$kernel" -m 512 \
        -append "osum vfs nokbd nosched noproc nofs $KARGS_EXTRA script=/bin/diskpg;exit" \
        -serial "file:$D/$tag.ser" -display none -no-reboot "${drv[@]}" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$D/$tag.ser" | tr -d '\r' > "$D/$tag.txt"
    echo "== $tag =="
    grep -a '^DP ' "$D/$tag.txt"
    [ -n "$OUT" ] && cp "$D/$tag.txt" "$OUT/$tag.txt"
}

for drive in $DRIVES; do run_drive "$drive" "$KMB" "$drive"; done

pass=0; fail=0
echo "== ahci budget =="
if python3 -I tools/diskfault/check.py "$D/ahci.txt"; then pass=$((pass+1)); else fail=$((fail+1)); fi

if [ -z "${NOMUTANT:-}" ] && [ -z "${KERNEL:-}" ]; then
    echo "== counter-probe: ahci limited to 32 KiB per command =="
    cp kernel/drv/blk/ahci/ahci_defs.fi "$D/ahci_defs.fi.keep"
    sed -i 's/^const PRDT_MAX: u64 = 32$/const PRDT_MAX: u64 = 8/' kernel/drv/blk/ahci/ahci_defs.fi
    bash tools/build-kernel.sh "$D/mutant.mb" --stufe 1 > "$D/mk.log" 2>&1
    cp "$D/ahci_defs.fi.keep" kernel/drv/blk/ahci/ahci_defs.fi
    run_drive ahci "$D/mutant.mb" mutant
    if python3 -I tools/diskfault/check.py "$D/mutant.txt"; then fail=$((fail+1)); echo "  FAIL  counter-probe passes"; else pass=$((pass+1)); echo "  OK    counter-probe is rejected"; fi
fi
echo "load: $(cut -d' ' -f1-3 /proc/loadavg)"
echo "DISKFAULT: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
