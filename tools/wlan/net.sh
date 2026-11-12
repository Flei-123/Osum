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
. tools/lib/firnenv.sh
SNAPS=${WLANNET_SNAPS:-8}
SNAP_SEC=${WLANNET_SNAP_SEC:-6}

mkdir -p "$T/blobs" "$T/bin"
python3 -I tools/iwlfh/ref.py gen "$T/blobs" || { bad "reference generator"; exit 1; }
FWPATH=/lib/firmware/intel/iwlwifi/iwlwifi-8265-36.ucode
bash tools/sync/build.sh "$T/bin" 0 sh echo cat sleep ping burn > "$T/b.txt" 2>&1 \
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
{
    echo 'echo ==START=='
    i=0
    while [ "$i" -lt "$SNAPS" ]; do echo "sleep $SNAP_SEC"; i=$((i+1)); done
    echo 'echo ==WAITED=='
    echo 'ping -c 1 192.168.77.1'
    echo 'cat /proc/wlan'
    echo 'echo ==BEFORE=='
    echo 'burn 1500 &'
    echo 'burn 1500 &'
    echo 'ping -c 1 -s 150 192.168.77.1'
    echo 'echo ==BURST=='
    echo 'sleep 4'
    echo 'cat /proc/wlan'
    echo 'echo ==AFTER=='
    echo 'ping -c 1 -s 150 192.168.77.1'
    echo 'sleep 4'
    echo 'cat /proc/wlan'
    echo 'echo ==END=='
} > "$T/sg.sh"

image() {
    local n=$1 conf=${2:-} script=${3:-s.sh}
    local extra=()
    [ -n "$conf" ] && extra=("/etc/wlan.conf=$conf")
    bash tools/mkfsfi/mkfs.sh build "$T/$n.img" 20000 --v3 /bin/ /t/ /etc/ /proc/ /lib/ /lib/firmware/ /lib/firmware/intel/ /lib/firmware/intel/iwlwifi/ \
        /bin/sh="$T/bin/sh.elf" /bin/echo="$T/bin/echo.elf" /bin/cat="$T/bin/cat.elf" /bin/sleep="$T/bin/sleep.elf" /bin/ping="$T/bin/ping.elf" /bin/burn="$T/bin/burn.elf" \
        "/t/s.sh=$T/$script" "$FWPATH=$T/blobs/v7.bin" "${extra[@]}" > "$T/$n.mkfs" 2>&1 \
        || { tail -3 "$T/$n.mkfs"; return 1; }
}
run() {
    local n=$1 words=$2 nics=${3:--nic none}
    timeout 400 qemu-system-x86_64 -accel "$ACC" -smp 1 -kernel "$T/k.img" -m 512 \
        -append "osum vfs $words script=sh /t/s.sh;exit" \
        -serial "file:$T/$n.txt" -display none -no-reboot $nics \
        -drive "file=$T/$n.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$T/$n.txt" > "$T/$n.klar"
}

printf 'ssid OrientFake\npsk orient-fake-pw1\n' > "$T/good.conf"
image g "$T/good.conf" sg.sh || { bad "image g"; exit 1; }
for n in c e f; do image $n "$T/good.conf" || { bad "image $n"; exit 1; }; done
image d || { bad "image d"; exit 1; }

echo "-- C: wlan0 up on the fake AP: ARP + ICMP echo through the stack"
run c "iwlfhtest iwlfhbind nic"
C="$T/c.klar"
has "$C" 'fakeap: m4 ok' "link up (handshake done)"
has "$C" 'auto=up rc=0' "autostart up"
has "$C" 'fakeap: arp' "ARP request for the gateway reached the AP"
has "$C" 'fakeap: echo' "AP mirrors the ARP broadcast (group key) in the same burst as the reply"
has "$C" 'fakeap: icmp' "ICMP echo reached the AP"
awk '/==WAITED==/{f=1} /==PING1==/{f=0} f' "$C" > "$T/p1.txt"
grep -aqE 'octets from 192\.168\.77\.1' "$T/p1.txt" && ok "ping gateway answered" || { bad "ping gateway not answered"; head -12 "$T/p1.txt"; }
has "$C" 'stack wired=1 uplink=0' "/proc/wlan stack line: wired, uplink card 0"
awk '/==PING1==/{f=1} f' "$C" | grep -aqE 'stack wired=1 .* gwmac=[0-9a-f]{2}:' && ok "/proc/wlan stack line: gateway MAC learned" || bad "/proc/wlan stack line: no gateway MAC"
grep -aqE 'stack wired=1 .* drop=[0-9]+ echo=[0-9]+ .*dns=' "$C" && ok "/proc/wlan stack line: drop/echo/dns fields" || bad "/proc/wlan stack line: drop/echo/dns fields missing"
awk '/==PING1==/{f=1} f' "$C" | grep -aqE 'wire arp tx=[0-9]+ rxrq=[0-9]+ rxrp=[0-9]+ .* icmp tx=3 rxrep=3 rxoth=[0-9]+ stk icmp=3 echo=3 .* err conv=0 send=0 last=0' && ok "/proc/wlan wire line: ARP answered, 3 echo requests, 3 echo replies, no send errors" || { bad "/proc/wlan wire line wrong"; awk '/==PING1==/{f=1} f' "$C" | grep -a 'wire arp' | head -2; }
has "$C" '==END==' "system keeps running"

ETH="-netdev user,id=n0,net=10.0.2.0/24 -device e1000,netdev=n0"
echo "-- E: e1000 + wlan0: the WLAN link becomes the uplink, ping goes over WLAN"
run e "iwlfhtest iwlfhbind nic wlanfirst" "$ETH"
E="$T/e.klar"
has "$E" 'auto=up rc=0' "two cards: autostart up"
has "$E" 'stack wired=1 uplink=1' "two cards: uplink is the WLAN card"
awk '/==WAITED==/{f=1} /==PING1==/{f=0} f' "$E" > "$T/p2.txt"
grep -aqE 'octets from 192\.168\.77\.1' "$T/p2.txt" && ok "two cards: ping over WLAN answered" || { bad "two cards: ping over WLAN not answered"; head -12 "$T/p2.txt"; }
has "$E" '==END==' "two cards: system keeps running"

echo "-- F: control noupprefer: uplink stays on the e1000, ping over WLAN fails"
run f "iwlfhtest iwlfhbind nic noupprefer" "$ETH"
F="$T/f.klar"
has "$F" 'auto=up rc=0' "control: autostart up"
has "$F" 'stack wired=1 uplink=0' "control: uplink stays on the e1000"
awk '/==WAITED==/{f=1} /==PING1==/{f=0} f' "$F" > "$T/p3.txt"
grep -aqE 'octets from 192\.168\.77\.1' "$T/p3.txt" && bad "control: ping answered without uplink_prefer" || ok "control: no ping reply without uplink_prefer"

echo "-- G: burst of 24 echo replies in one go: the stack receive ring must not drop frames"
run g "iwlfhtest iwlfhbind nic"
G="$T/g.klar"
has "$G" 'auto=up rc=0' "burst: autostart up" 
awk '/==WAITED==/{f=1} /==BEFORE==/{f=0} f' "$G" > "$T/g0.txt"
awk '/==BEFORE==/{f=1} /==BURST==/{f=0} f' "$G" > "$T/g1.txt"
awk '/==BURST==/{f=1} /==AFTER==/{f=0} f' "$G" > "$T/g2.txt"
awk '/==AFTER==/{f=1} /==END==/{f=0} f' "$G" > "$T/g3.txt"
field() { grep -aoE "$2=[0-9]+" "$1" | head -1 | cut -d= -f2; }
R0=$(field "$T/g0.txt" rx); D0=$(field "$T/g0.txt" drop)
R1=$(field "$T/g2.txt" rx); D1=$(field "$T/g2.txt" drop)
R2=$(field "$T/g3.txt" rx); D2=$(field "$T/g3.txt" drop)
echo "  rx/drop: warmup ${R0:-?}/${D0:-?} after burst 1 ${R1:-?}/${D1:-?} after burst 2 ${R2:-?}/${D2:-?}"
[ -n "$R0" ] && [ -n "$R1" ] && [ $((R1 - R0)) -ge 24 ] && ok "burst 1: all 24 replies reached the stack" || bad "burst 1: fewer than 24 replies reached the stack"
[ -n "$D1" ] && [ "$D1" -eq "${D0:-0}" ] && ok "burst 1: no frame dropped by the receive ring" || bad "burst 1: receive ring dropped frames"
[ -n "$R2" ] && [ -n "$R1" ] && [ $((R2 - R1)) -ge 24 ] && ok "burst 2: all 24 replies reached the stack" || bad "burst 2: fewer than 24 replies reached the stack"
[ -n "$D2" ] && [ "$D2" -eq "${D0:-0}" ] && ok "burst 2: no frame dropped by the receive ring" || bad "burst 2: receive ring dropped frames"
has "$G" 'fakeap: icmp' "burst: AP saw the echo request"
has "$G" '==END==' "burst: system keeps running"

echo "-- D: no conf: no stack on wlan0, ping cannot succeed"
run d "iwlfhtest iwlfhbind nic"
D="$T/d.klar"
hasnot "$D" 'fakeap: arp' "no ARP without a link"
hasnot "$D" 'octets from' "no ping reply"
has "$D" '==END==' "system keeps running"

echo "WLANNET: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
