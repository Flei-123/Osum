#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
HERE="$PWD"
export FIRNLIB="$HERE/lib"
T=$(mktemp -d)
trap 'if [ -n "${WLANNET_KEEP:-}" ]; then rm -rf "$WLANNET_KEEP"; mkdir -p "$WLANNET_KEEP"; cp "$T"/*.klar "$WLANNET_KEEP"/ 2>/dev/null; fi; rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' present" || ok "$3"; }
command -v qemu-system-x86_64 >/dev/null || { echo "WLANNET: skipped, no qemu"; exit 0; }
ACC=tcg; [ -w /dev/kvm ] && ACC=kvm
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
SNAPS=${WLANNET_SNAPS:-8}
SNAP_SEC=${WLANNET_SNAP_SEC:-6}

mkdir -p "$T/blobs" "$T/bin"
python3 -I tools/iwlfh/ref.py gen "$T/blobs" || { bad "reference generator"; exit 1; }
FWPATH=/lib/firmware/intel/iwlwifi/iwlwifi-8265-36.ucode
bash tools/sync/build.sh "$T/bin" 0 sh echo cat sleep ping > "$T/b.txt" 2>&1 \
    && ok "programs build" || { bad "programs build"; tail "$T/b.txt"; echo "WLANNET: $pass ok, $fail fail"; exit 1; }
./tools/build-kernel.sh "$T/k.img" --stufe 0 > "$T/k.txt" 2>&1 \
    && ok "kernel builds" || { bad "kernel build"; tail -30 "$T/k.txt"; echo "WLANNET: $pass ok, $fail fail"; exit 1; }
make_script() { # target
    {
        echo 'echo ==START=='
        i=0
        while [ "$i" -lt "$SNAPS" ]; do
            echo "sleep $SNAP_SEC"
            i=$((i+1))
        done
        echo 'echo ==WAITED=='
        echo 'cat /proc/wlan'
        echo "ping -c 3 $1"
        echo 'echo ==PING1=='
        echo 'cat /proc/wlan'
        echo 'echo ==END=='
    } > "$T/s.sh"
}
make_script 192.168.77.1

image() {
    local n=$1 conf=${2:-}
    local extra=()
    [ -n "$conf" ] && extra=("/etc/wlan.conf=$conf")
    python3 tools/osum/mkfs.py build "$T/$n.img" 20000 --v3 /bin/ /t/ /etc/ /proc/ /lib/ /lib/firmware/ /lib/firmware/intel/ /lib/firmware/intel/iwlwifi/ \
        /bin/sh="$T/bin/sh.elf" /bin/echo="$T/bin/echo.elf" /bin/cat="$T/bin/cat.elf" /bin/sleep="$T/bin/sleep.elf" /bin/ping="$T/bin/ping.elf" \
        "/t/s.sh=$T/s.sh" "$FWPATH=$T/blobs/two.bin" "${extra[@]}" > "$T/$n.mkfs" 2>&1 \
        || { tail -3 "$T/$n.mkfs"; return 1; }
}
run() {
    local n=$1 words=$2
    timeout 400 qemu-system-x86_64 -accel "$ACC" -smp 1 -kernel "$T/k.img" -m 512 \
        -append "osum vfs $words script=sh /t/s.sh;exit" \
        -serial "file:$T/$n.txt" -display none -no-reboot -nic none \
        -drive "file=$T/$n.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$T/$n.txt" > "$T/$n.klar"
}

printf 'ssid OrientFake\npsk orient-fake-pw1\n' > "$T/good.conf"
image c "$T/good.conf" || { bad "image c"; exit 1; }
image d || { bad "image d"; exit 1; }

echo "-- C: wlan0 up on the fake AP: ARP + ICMP echo through the stack"
run c "iwlfhtest iwlfhbind nic"
C="$T/c.klar"
has "$C" 'fakeap: m4 ok' "link up (handshake done)"
has "$C" 'auto=up rc=0' "autostart up"
has "$C" 'fakeap: arp' "ARP request for the gateway reached the AP"
has "$C" 'fakeap: icmp' "ICMP echo reached the AP"
awk '/==WAITED==/{f=1} /==PING1==/{f=0} f' "$C" > "$T/p1.txt"
grep -aqE 'octets from 192\.168\.77\.1' "$T/p1.txt" && ok "ping gateway answered" || { bad "ping gateway not answered"; head -12 "$T/p1.txt"; }
has "$C" '==END==' "system keeps running"

echo "-- D: no conf: no stack on wlan0, ping cannot succeed"
run d "iwlfhtest iwlfhbind nic"
D="$T/d.klar"
hasnot "$D" 'fakeap: arp' "no ARP without a link"
hasnot "$D" 'octets from' "no ping reply"
has "$D" '==END==' "system keeps running"

echo "WLANNET: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
