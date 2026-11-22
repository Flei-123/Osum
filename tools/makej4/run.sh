#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/firnenv.sh
. tools/lib/smpwords.sh
export FIRNLIB="${FIRNLIB:-$(pwd)/lib}"
ROOT_DIR=${MAKEJ4_ROOT:-/root/fxhp/lm}
BOOTS=${BOOTS:-8}; ITERS=${ITERS:-3}; PAR=${PAR:-4}; SMP=${SMP:-4}; TMO=${TMO:-240}; MEM=${MEM:-3072}
OUT=${MAKEJ4_OUT:-$(mktemp -d)}; mkdir -p "$OUT"
[ -n "${MAKEJ4_KEEP:-}" ] || trap 'rm -rf "$OUT"' EXIT
KERNEL=${KERNEL:-}
if [ -z "$KERNEL" ]; then
    ./tools/build-kernel.sh "$OUT/k0.img" --stufe 0 --base 0x3000000 > "$OUT/kernel.log" 2>&1 || { echo "MAKEJ4: kernel build failed"; tail -5 "$OUT/kernel.log"; exit 1; }
    KERNEL=$OUT/k0.img
fi
grep -v '^/etc/inittab' "$ROOT_DIR/run/spec.txt" > "$OUT/spec.txt"
cp tools/makej4/guest.sh "$OUT/fx.sh"
printf '::sysinit:/bin/sh /etc/fx.sh\n::shutdown:/bin/true\n' > "$OUT/inittab"
ulimit -s 65536
mapfile -t SP < "$OUT/spec.txt"
bash tools/mkfsfi/mkfs.sh build "$OUT/disk.img" 2400000 --v3 --inodes=20000 "${SP[@]}" "/etc/fx.sh=$OUT/fx.sh@755" "/etc/inittab=$OUT/inittab" > "$OUT/mkfs.log" 2>&1 \
    || { echo "MAKEJ4: mkfs failed"; tail -5 "$OUT/mkfs.log"; exit 1; }
KARGS=$(smp_boot_words "$SMP" "osum vfs nokbd nosched noproc nofs iters=$ITERS")
ACC=(); [ -w /dev/kvm ] && ACC=(-accel kvm -cpu host)
boot_one() {
    local n=$1 d=$OUT/boot$1
    mkdir -p "$d"
    timeout "$TMO" qemu-system-x86_64 "${ACC[@]}" -smp "$SMP" -kernel "$KERNEL" -m "$MEM" -append "$KARGS" \
        -serial "file:$d/ser.txt" -display none -no-reboot \
        -device ahci,id=ahci -drive "file=$OUT/disk.img,format=raw,if=none,id=d0,snapshot=on" -device ide-hd,drive=d0,bus=ahci.0 \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$d/qemu.txt" 2>&1 &
    local q=$! i=0
    while kill -0 "$q" 2>/dev/null; do
        grep -qaF FX-END "$d/ser.txt" 2>/dev/null && break
        sleep 1; i=$((i + 1)); [ "$i" -ge "$TMO" ] && break
    done
    sleep 1; kill "$q" 2>/dev/null; wait "$q" 2>/dev/null
    tr -cd '\11\12\15\40-\176' < "$d/ser.txt" | tr -d '\r' > "$d/ser.clean"
}
n=1
while [ "$n" -le "$BOOTS" ]; do
    for _ in $(seq 1 "$PAR"); do
        [ "$n" -le "$BOOTS" ] || break
        boot_one "$n" &
        n=$((n + 1))
    done
    wait
done
ok=0; bad=0; hung=0
for n in $(seq 1 "$BOOTS"); do
    f=$OUT/boot$n/ser.clean
    if ! grep -qa 'MJ4-END' "$f"; then hung=$((hung + 1)); echo "HUNG  boot $n"; continue; fi
    good=$(grep -ac "^MJ4 [0-9]* rc=0 objs=8" "$f")
    if [ "$good" = "$ITERS" ]; then ok=$((ok + 1)); else bad=$((bad + 1)); echo "FAIL  boot $n: $(grep -a '^MJ4' "$f" | grep -av 'rc=0 objs=8' | head -2 | tr '\n' ' ')"; fi
done
echo "makej4: boots ok=$ok bad=$bad hung=$hung of $BOOTS (iters=$ITERS smp=$SMP)"
[ "$bad" = 0 ] && [ "$ok" -ge $((BOOTS - ${ALLOW_HUNG:-1})) ]
