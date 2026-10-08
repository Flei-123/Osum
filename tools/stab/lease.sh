#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/stab/lease.sh -- DHCP lease renewal (kernel/user/dhcp.fi, renew_loop).
#
#   bash tools/stab/lease.sh [seconds]
#
# QEMU's user network hands out a lease and answers REQUESTs. `dhcp dauer t1=12`
# (T1 shortened to 12 s for the test, the real one is lease/2) must
#   * get the lease                              "dhcp: ack ip="
#   * renew it again and again, unicast          "dhcp: lease renewed" >= 3 times
#   * NOT touch the address while doing so       exactly one "dhcp: gesetzt ip="
# STAB_TREE=<worktree> builds the guest from another tree: the counter-proof is
# the tree before the change -- it has no renewal at all (0 renewals).
set -uo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
TREE=${STAB_TREE:-$HERE}
SECS=${1:-70}
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
cd "$TREE"
export FIRNLIB="$TREE/lib"
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
bash tools/sync/build.sh "$T/bin" 0 sh sleep echo dhcp > "$T/b.txt" 2>&1 || { tail "$T/b.txt"; exit 1; }
./tools/build-kernel.sh "$T/k.img" --stufe 0 > "$T/k.txt" 2>&1 || { tail "$T/k.txt"; exit 1; }
printf 'echo ==START==\ndhcp dauer t1=12 &\nsleep %s\necho ==END==\n' "$SECS" > "$T/s.sh"
python3 tools/osum/mkfs.py build "$T/d.img" 8000 /bin/ /t/ /etc/ \
    /bin/sh="$T/bin/sh.elf" /bin/sleep="$T/bin/sleep.elf" /bin/echo="$T/bin/echo.elf" /bin/dhcp="$T/bin/dhcp.elf" \
    /t/s.sh="$T/s.sh" > "$T/mkfs.txt" 2>&1 || { tail "$T/mkfs.txt"; exit 1; }
ACC=tcg; [ -w /dev/kvm ] && ACC=kvm
timeout $((SECS + 120)) qemu-system-x86_64 -accel $ACC -kernel "$T/k.img" -m 256 \
    -append "osum nokbd nosched noproc nofs noring3 nic nip=169.254.10.1/16 nsvc=0 nwait=0 script=sh /t/s.sh;exit" \
    -serial "file:$T/s.txt" -display none -no-reboot \
    -drive "file=$T/d.img,format=raw,if=ide,index=0" \
    -netdev user,id=n0 -device e1000,netdev=n0,mac=52:54:00:aa:bb:cc \
    -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
tr -cd '\11\12\15\40-\176' < "$T/s.txt" > "$T/s.klar"
acks=$(grep -ac "dhcp: ack ip=" "$T/s.klar")
ren=$(grep -ac "dhcp: lease renewed" "$T/s.klar")
sets=$(grep -ac "dhcp: gesetzt ip=" "$T/s.klar")
lost=$(grep -ac "dhcp: lease lost" "$T/s.klar")
echo "STABLEASE: acks=$acks renewals=$ren address_sets=$sets lease_lost=$lost (window ${SECS} s, t1=12 s)"
[ -n "${STAB_KEEP:-}" ] && cp "$T/s.klar" "$STAB_KEEP"
[ "$acks" -ge 1 ] && [ "$ren" -ge 3 ] && [ "$sets" -eq 1 ] && [ "$lost" -eq 0 ]
