#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
CASES="${*:-delayed immediate once}"
LINK_DELAY_S=${LINKDELAY_S:-14}
LEASE=10.0.2.15
LEASE_LIMIT_S=${LINKDELAY_LIMIT_S:-40}
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
D=$(mktemp -d)
QPID=""
cleanup() { [ -n "$QPID" ] && kill "$QPID" 2>/dev/null; rm -rf "$D"; }
trap cleanup EXIT
: "${OSUM_QEMU_ACCEL:=tcg}"
[ -e /dev/kvm ] && [ "$OSUM_QEMU_ACCEL" = tcg ] && OSUM_QEMU_ACCEL=kvm
. tools/lib/firnenv.sh

mkdir -p "$D/bin"
bash tools/sync/build.sh "$D/bin" 0 sh sleep echo dhcp ping cat > "$D/b.txt" 2>&1 || { tail "$D/b.txt"; exit 1; }
./tools/build-kernel.sh "$D/k.img" --stufe 0 > "$D/k.txt" 2>&1 || { tail "$D/k.txt"; exit 1; }
printf 'echo ==START==\ndhcp dauer t1=12 &\nsleep 900\n' > "$D/s_dauer.sh"
printf 'echo ==START==\ndhcp einmal\nsleep 900\n' > "$D/s_once.sh"
for s in dauer once; do
    bash tools/mkfsfi/mkfs.sh build "$D/d_$s.img" 8000 /bin/ /t/ /etc/ /proc/ \
        /bin/sh="$D/bin/sh.elf" /bin/sleep="$D/bin/sleep.elf" /bin/echo="$D/bin/echo.elf" \
        /bin/dhcp="$D/bin/dhcp.elf" /bin/ping="$D/bin/ping.elf" /bin/cat="$D/bin/cat.elf" \
        "/t/s.sh=$D/s_$s.sh" > "$D/mkfs_$s.txt" 2>&1 || { tail "$D/mkfs_$s.txt"; exit 1; }
done

monitor() { printf '%s\n' "$2" | socat - "UNIX-CONNECT:$D/$1.mon" >/dev/null 2>&1; }

lease_seen() { tr -cd '\11\12\15\40-\176' < "$D/$1.txt" | grep -ac "dhcp: ack ip=$LEASE"; }

run_case() {
    local n=$1 image=$2 delay=$3
    cp "$D/d_$image.img" "$D/disk-$n.img"
    : > "$D/$n.txt"
    timeout 200 qemu-system-x86_64 -accel "$OSUM_QEMU_ACCEL" -smp 1 -kernel "$D/k.img" -m 512 -S \
        -append "osum nokbd nosched noproc nofs noring3 nethotwait nic nip=169.254.10.1/16 nsvc=0 nwait=0 script=sh /t/s.sh;exit" \
        -serial "file:$D/$n.txt" -display none -no-reboot \
        -drive "file=$D/disk-$n.img,format=raw,if=ide,index=0" \
        -netdev user,id=pn0 -device e1000,netdev=pn0,id=nic0,mac=52:54:00:aa:bb:01 \
        -monitor "unix:$D/$n.mon,server,nowait" >/dev/null 2>&1 &
    QPID=$!
    local t=0
    while [ ! -S "$D/$n.mon" ] && [ $t -lt 50 ]; do sleep 0.2; t=$((t + 1)); done
    [ "$delay" -gt 0 ] && monitor "$n" "set_link nic0 off"
    monitor "$n" "cont"
    local t0 up_at=0
    t0=$(date +%s)
    while [ $(( $(date +%s) - t0 )) -lt $((delay + LEASE_LIMIT_S)) ]; do
        if [ "$delay" -gt 0 ] && [ $up_at -eq 0 ] && [ $(( $(date +%s) - t0 )) -ge "$delay" ]; then
            monitor "$n" "set_link nic0 on"
            up_at=$(date +%s)
        fi
        [ "$(lease_seen "$n")" -ge 1 ] && break
        sleep 0.5
    done
    local got
    got=$(lease_seen "$n")
    kill "$QPID" 2>/dev/null; wait "$QPID" 2>/dev/null; QPID=""
    echo "        $n: delay=${delay}s lease_lines=$got"
    return $([ "$got" -ge 1 ] && echo 0 || echo 1)
}

for c in $CASES; do
    case "$c" in
    immediate) run_case immediate dauer 0 && ok "immediate link: lease" || bad "immediate link: no lease" ;;
    delayed) run_case delayed dauer "$LINK_DELAY_S" && ok "link up after ${LINK_DELAY_S}s: lease within ${LEASE_LIMIT_S}s of link-up" \
        || bad "link up after ${LINK_DELAY_S}s: no lease within ${LEASE_LIMIT_S}s" ;;
    once) run_case once once "$LINK_DELAY_S" && bad "one-shot client got a lease although the link came late (control)" \
        || ok "one-shot client stays without lease when link comes late (control)" ;;
    *) bad "unknown case $c" ;;
    esac
done
echo "LINKDELAY: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
