#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
HERE="$PWD"
export FIRNLIB="$HERE/lib"
T=$(mktemp -d)
trap 'if [ -n "${WLANFLAP_KEEP:-}" ]; then rm -rf "$WLANFLAP_KEEP"; mkdir -p "$WLANFLAP_KEEP"; cp "$T"/*.klar "$WLANFLAP_KEEP"/ 2>/dev/null; fi; rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' present" || ok "$3"; }
command -v qemu-system-x86_64 >/dev/null || { echo "WLANFLAP: skipped, no qemu"; exit 0; }
ACC=tcg; [ -w /dev/kvm ] && ACC=kvm
. tools/lib/firnenv.sh
SNAPS=${WLANFLAP_SNAPS:-7}
SNAP_SEC=${WLANFLAP_SNAP_SEC:-6}
FLAP_SNAPS=${WLANFLAP_FLAP_SNAPS:-3}

mkdir -p "$T/blobs" "$T/bin"
python3 -I tools/iwlfh/ref.py gen "$T/blobs" || { bad "reference generator"; exit 1; }
FWPATH=/lib/firmware/intel/iwlwifi/iwlwifi-8265-36.ucode
bash tools/sync/build.sh "$T/bin" 0 sh echo cat sleep ping host dhcp burn wget wlanctl > "$T/b.txt" 2>&1 \
    && ok "programs build" || { bad "programs build"; tail "$T/b.txt"; echo "WLANFLAP: $pass ok, $fail fail"; exit 1; }
./tools/build-kernel.sh "$T/k.img" --stufe 0 > "$T/k.txt" 2>&1 \
    && ok "kernel builds" || { bad "kernel build"; tail -30 "$T/k.txt"; echo "WLANFLAP: $pass ok, $fail fail"; exit 1; }

{
    echo 'echo ==START=='
    i=0
    while [ "$i" -lt "$SNAPS" ]; do echo "sleep $SNAP_SEC"; i=$((i+1)); done
    echo 'echo ==UP=='
    echo 'cat /proc/wlan'
    echo 'dhcp'
    echo 'wget -q http://192.168.77.1/big'
    echo 'echo ==WGET0=='
    echo 'host store.fleitec.com'
    echo 'echo ==HOST0=='
    echo 'wget -q http://192.168.77.1/hold &'
    echo 'sleep 4'
    echo 'netstat'
    echo 'echo ==HELD=='
    echo 'wlanctl connect OrientFake orient-fake-pw1'
    i=0
    while [ "$i" -lt "$FLAP_SNAPS" ]; do echo "sleep $SNAP_SEC"; i=$((i+1)); done
    echo 'echo ==AFTERFLAP=='
    echo 'cat /proc/wlan'
    echo 'netstat'
    echo 'echo ==NETSTAT2=='
    echo 'ping -c 2 192.168.77.1'
    echo 'echo ==PING1=='
    echo 'wget -q http://192.168.77.1/big'
    echo 'echo ==WGET1=='
    echo 'dhcp'
    echo 'host store.fleitec.com'
    echo 'echo ==HOST1=='
    echo 'wget -q http://192.168.77.1/big'
    echo 'echo ==WGET2=='
    echo 'cat /proc/wlan'
    echo 'echo ==END=='
} > "$T/s.sh"

image() {
    local n=$1 conf=${2:-}
    local extra=()
    [ -n "$conf" ] && extra=("/etc/wlan.conf=$conf")
    bash tools/mkfsfi/mkfs.sh build "$T/$n.img" 20000 --v3 /bin/ /t/ /etc/ /proc/ /lib/ /lib/firmware/ /lib/firmware/intel/ /lib/firmware/intel/iwlwifi/ \
        /bin/sh="$T/bin/sh.elf" /bin/echo="$T/bin/echo.elf" /bin/cat="$T/bin/cat.elf" /bin/sleep="$T/bin/sleep.elf" /bin/ping="$T/bin/ping.elf" /bin/host="$T/bin/host.elf" /bin/dhcp="$T/bin/dhcp.elf" /bin/burn="$T/bin/burn.elf" /bin/wget="$T/bin/wget.elf" /bin/wlanctl="$T/bin/wlanctl.elf" /etc/resolv.conf="$T/resolv.old" \
        "/t/s.sh=$T/s.sh" "$FWPATH=$T/blobs/v7.bin" "${extra[@]}" > "$T/$n.mkfs" 2>&1 \
        || { tail -3 "$T/$n.mkfs"; return 1; }
}
run() {
    local n=$1 words=$2 nics=${3:--nic none}
    timeout ${WLANDNS_TIMEOUT:-400} qemu-system-x86_64 -accel "$ACC" -smp 1 -kernel "${WLANDNS_KERNEL:-$T/k.img}" -m 512 \
        -append "osum vfs $words script=sh /t/s.sh;exit" \
        -serial "file:$T/$n.txt" -display none -no-reboot $nics \
        -drive "file=$T/$n.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$T/$n.txt" > "$T/$n.klar"
}
printf 'nameserver 192.168.1.1\nfallback 1.1.1.1\n' > "$T/resolv.old"
printf 'ssid OrientFake\npsk orient-fake-pw1\n' > "$T/good.conf"
for n in c e; do image $n "$T/good.conf" || { bad "image $n"; exit 1; }; done
ETH="-netdev user,id=n0,net=10.0.2.0/24 -device e1000,netdev=n0"

section() { awk -v a="$2" -v b="$3" '$0 ~ a {f=1} $0 ~ b {f=0} f' "$1"; }

check_flap() {
    local f=$1 tag=$2
    has "$f" '==END==' "$tag: system keeps running"
    section "$f" '==UP==' '==WGET0==' | grep -aq 'octets\|status 200' || true
    section "$f" '==UP==' '==WGET0==' > "$T/$tag.w0"
    has "$T/$tag.w0" 'status 200' "$tag: wget before the flap"
    section "$f" '==WGET0==' '==HOST0==' | grep -aq '93.184.216.34' && ok "$tag: host before the flap" || bad "$tag: host before the flap"
    section "$f" '==AFTERFLAP==' '==PING1==' > "$T/$tag.p"
    has "$T/$tag.p" 'octets from 192.168.77.1' "$tag: ping after the flap"
    section "$f" '==PING1==' '==WGET1==' > "$T/$tag.w1"
    has "$T/$tag.w1" 'status 200' "$tag: new TCP connection after the flap"
    has "$T/$tag.w1" 'octets 131072' "$tag: whole body after the flap"
    section "$f" '==WGET1==' '==HOST1==' | grep -aq '93.184.216.34' && ok "$tag: host after the flap" || bad "$tag: host after the flap"
    section "$f" '==HOST1==' '==WGET2==' > "$T/$tag.w2"
    has "$T/$tag.w2" 'status 200' "$tag: wget after host after the flap"
}

echo "-- A: rejoin while idle: new connections and DNS afterwards"
run c "iwlfhtest iwlfhbind nic"
check_flap "$T/c.klar" rejoin

echo "-- B: AP goes deaf after the lease: probe, loss, reconnect, then the same traffic"
run e "iwlfhtest iwlfhbind iwlfhdrop nic"
check_flap "$T/e.klar" drop
has "$T/e.klar" 'wlan: link lost 1' "drop: the loss is detected"

echo "WLANFLAP: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
