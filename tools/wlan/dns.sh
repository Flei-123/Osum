#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
HERE="$PWD"
export FIRNLIB="$HERE/lib"
T=$(mktemp -d)
trap 'if [ -n "${WLANDNS_KEEP:-}" ]; then rm -rf "$WLANDNS_KEEP"; mkdir -p "$WLANDNS_KEEP"; cp "$T"/*.klar "$WLANDNS_KEEP"/ 2>/dev/null; fi; rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' present" || ok "$3"; }
command -v qemu-system-x86_64 >/dev/null || { echo "WLANDNS: skipped, no qemu"; exit 0; }
ACC=tcg; [ -w /dev/kvm ] && ACC=kvm
. tools/lib/firnenv.sh
SNAPS=${WLANDNS_SNAPS:-8}
SNAP_SEC=${WLANDNS_SNAP_SEC:-6}

mkdir -p "$T/blobs" "$T/bin"
python3 -I tools/iwlfh/ref.py gen "$T/blobs" || { bad "reference generator"; exit 1; }
FWPATH=/lib/firmware/intel/iwlwifi/iwlwifi-8265-36.ucode
bash tools/sync/build.sh "$T/bin" 0 sh echo cat sleep ping host dhcp burn wget > "$T/b.txt" 2>&1 \
    && ok "programs build" || { bad "programs build"; tail "$T/b.txt"; echo "WLANDNS: $pass ok, $fail fail"; exit 1; }
./tools/build-kernel.sh "$T/k.img" --stufe 0 > "$T/k.txt" 2>&1 \
    && ok "kernel builds" || { bad "kernel build"; tail -30 "$T/k.txt"; echo "WLANDNS: $pass ok, $fail fail"; exit 1; }

{
    echo 'echo ==START=='
    i=0
    while [ "$i" -lt "$SNAPS" ]; do echo "sleep $SNAP_SEC"; i=$((i+1)); done
    echo 'echo ==WAITED=='
    echo 'cat /proc/wlan'
    echo 'dhcp'
    echo 'cat /etc/resolv.conf'
    echo 'host -v store.fleitec.com'
    echo 'echo ==HOST1=='
    echo 'host store.fleitec.com'
    echo 'echo ==HOST2=='
    echo 'host -t aaaa store.fleitec.com'
    echo 'echo ==HOST3=='
    echo 'host -v -s 192.168.77.99 silent.example'
    echo 'echo ==SILENT1=='
    echo 'host -v -s 1.1.1.1 silent.example'
    echo 'echo ==SILENT2=='
    echo 'burn 2500 &'
    echo 'host store.fleitec.com'
    echo 'echo ==LOADED=='
    echo 'wget -q http://192.168.77.1/big'
    echo 'echo ==WGET1=='
    echo 'host store.fleitec.com'
    echo 'echo ==AFTERWGET=='
    echo 'ping -c 2 192.168.77.1'
    echo 'cat /proc/wlan'
    echo 'echo ==END=='
} > "$T/s.sh"

image() {
    local n=$1 conf=${2:-}
    local extra=()
    [ -n "$conf" ] && extra=("/etc/wlan.conf=$conf")
    bash tools/mkfsfi/mkfs.sh build "$T/$n.img" 20000 --v3 /bin/ /t/ /etc/ /proc/ /lib/ /lib/firmware/ /lib/firmware/intel/ /lib/firmware/intel/iwlwifi/ \
        /bin/sh="$T/bin/sh.elf" /bin/echo="$T/bin/echo.elf" /bin/cat="$T/bin/cat.elf" /bin/sleep="$T/bin/sleep.elf" /bin/ping="$T/bin/ping.elf" /bin/host="$T/bin/host.elf" /bin/dhcp="$T/bin/dhcp.elf" /bin/burn="$T/bin/burn.elf" /bin/wget="$T/bin/wget.elf" /etc/resolv.conf="$T/resolv.old" \
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

check_host() {
    local f=$1 tag=$2
    awk '/==WAITED==/{f=1} /==HOST1==/{f=0} f' "$f" > "$T/$tag.h1"
    awk '/==HOST1==/{f=1} /==HOST2==/{f=0} f' "$f" > "$T/$tag.h2"
    awk '/==HOST2==/{f=1} /==HOST3==/{f=0} f' "$f" > "$T/$tag.h3"
    has "$T/$tag.h1" 'nameserver 192.168.77.1' "$tag: resolv.conf names the AP"
    has "$T/$tag.h1" '93.184.216.34' "$tag: host -v resolves the A record"
    has "$T/$tag.h2" '93.184.216.34' "$tag: host resolves again"
    hasnot "$T/$tag.h3" '93.184.216.34' "$tag: AAAA query gets no A answer"
    has "$f" '==SILENT1==' "$tag: unanswered on-link query ends"
    has "$f" '==SILENT2==' "$tag: unanswered off-link query ends"
    awk '/==SILENT1==/{f=1} /==SILENT2==/{f=0} f' "$f" > "$T/$tag.s2"
    awk '/==HOST3==/{f=1} /==SILENT1==/{f=0} f' "$f" > "$T/$tag.s1"
    hasnot "$T/$tag.s1" '93.184.216.34' "$tag: control: unanswered on-link query yields no address"
    hasnot "$T/$tag.s2" '93.184.216.34' "$tag: control: unanswered off-link query yields no address"
    awk '/==SILENT2==/{f=1} /==LOADED==/{f=0} f' "$f" | grep -aq '93.184.216.34' && ok "$tag: host resolves under CPU load" || bad "$tag: host under load failed"
    awk '/==LOADED==/{f=1} /==WGET1==/{f=0} f' "$f" > "$T/$tag.w"
    has "$T/$tag.w" 'octets 131072' "$tag: wget over WLAN gets the whole 128 KiB body"
    has "$T/$tag.w" 'status 200' "$tag: wget over WLAN status 200"
    awk '/==WGET1==/{f=1} /==AFTERWGET==/{f=0} f' "$f" | grep -aq '93.184.216.34' && ok "$tag: host resolves after the download" || bad "$tag: host after download failed"
    has "$f" 'fakeap: tcp' "$tag: TCP SYN reached the AP"
    has "$f" 'fakeap: dns' "$tag: DNS query reached the AP"
    has "$f" 'octets from 192.168.77.1' "$tag: ping after DNS works"
    has "$f" '==END==' "$tag: system keeps running"
}

echo "-- A: WLAN only: host resolves through the AP"
run c "iwlfhtest iwlfhbind nic"
check_host "$T/c.klar" wlan
has "$T/c.klar" 'dns=192.168.77.1' "wlan: stack line names the WLAN DNS"

echo "-- B: e1000 + WLAN with wlanfirst: uplink switch to WLAN, host resolves through the AP"
run e "iwlfhtest iwlfhbind nic wlanfirst" "$ETH"
check_host "$T/e.klar" both
has "$T/e.klar" 'stack wired=1 uplink=1' "both: uplink is the WLAN card"

echo "WLANDNS: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
