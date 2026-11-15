#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
WD=${WD:-/root/fxhp}
BBDYN=${BBDYN:-/root/bbdyn/busybox}
DEBIAN_LIBC=${DEBIAN_LIBC:-/usr/lib/x86_64-linux-musl/libc.so}
ASSET=assets/musl/ld-musl-x86_64.so.1
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
pass=0; fail=0
if [ -z "${KERNEL:-}" ]; then
    ./tools/build-kernel.sh "$OUT/k0.mb" --stufe 0 > "$OUT/kernel.log" 2>&1 || { tail -5 "$OUT/kernel.log"; exit 1; }
    KERNEL=$OUT/k0.mb
fi
ok() { echo "  OK    $*"; pass=$((pass+1)); }
bad() { echo "  FAIL  $*"; fail=$((fail+1)); }

guest() {
    EXTRA="/lib/swap-musl.so=$1@755 /lib/busybox=$BBDYN@755" KERNEL="$KERNEL" BLOCKS=1000000 TMO=300 \
        bash tools/linuxapps/run.sh "$WD" tools/muslrelr/guest-swap.sh "$OUT/$2" > "$OUT/$2.log" 2>&1
}

guest "$ASSET" asset &
guest "$DEBIAN_LIBC" debian &
wait

grep -qa "MUSLRELR rc=0" "$OUT/asset/ser.clean" && ok "firefox starts on the shipped musl" || bad "firefox does not start on the shipped musl"
grep -qa "MUSLRELR busybox ok" "$OUT/asset/ser.clean" && ok "Debian-built busybox runs on the shipped musl" || bad "busybox fails on the shipped musl"
! grep -qa "user fault" "$OUT/asset/ser.clean" && ok "no user fault on the shipped musl" || bad "user fault on the shipped musl"
grep -qa "cr2=0x2390  rip=0x2390" "$OUT/debian/ser.clean" && ok "counter-proof: musl 1.2.3 jumps to the unrelocated init_array entry" || bad "counter-proof: musl 1.2.3 did not reproduce the fault"
strings -a "$ASSET" | grep -q '^\.relr\.dyn$' && ok "shipped musl knows DT_RELR" || bad "shipped musl lacks DT_RELR"
grep -q 'assets/musl/ld-musl-x86_64.so.1' tools/usbimg/build.sh && grep -q 'assets/musl/ld-musl-x86_64.so.1' tools/ota/overlay-assets.txt && ok "image build and OTA overlay ship the same musl" || bad "image build or OTA overlay does not use the shipped musl"
echo "muslrelr: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
