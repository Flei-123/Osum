#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
HERE="$PWD"
export FIRNLIB="$HERE/lib"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' present" || ok "$3"; }
command -v qemu-system-x86_64 >/dev/null || { echo "WLANAUTO: skipped, no qemu"; exit 0; }
ACC=tcg; [ -w /dev/kvm ] && ACC=kvm
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
SNAPS=${WLANAUTO_SNAPS:-8}
SNAP_SEC=${WLANAUTO_SNAP_SEC:-8}

mkdir -p "$T/blobs" "$T/bin"
python3 -I tools/iwlfh/ref.py gen "$T/blobs" || { bad "reference generator"; exit 1; }
FWPATH=/lib/firmware/intel/iwlwifi/iwlwifi-8265-36.ucode
bash tools/sync/build.sh "$T/bin" 0 sh echo cat sleep > "$T/b.txt" 2>&1 \
    && ok "programs build" || { bad "programs build"; tail "$T/b.txt"; echo "WLANAUTO: $pass ok, $fail fail"; exit 1; }
./tools/build-kernel.sh "$T/k.img" --stufe 0 > "$T/k.txt" 2>&1 \
    && ok "kernel builds" || { bad "kernel build"; tail -30 "$T/k.txt"; echo "WLANAUTO: $pass ok, $fail fail"; exit 1; }
{
    echo 'echo ==START=='
    i=0
    while [ "$i" -lt "$SNAPS" ]; do
        echo "sleep $SNAP_SEC"
        echo "echo ==SNAP $i =="
        echo 'cat /proc/wlan'
        i=$((i+1))
    done
    echo 'echo ==END=='
} > "$T/s.sh"

image() { # name [conf-file]
    local n=$1 conf=${2:-}
    local extra=()
    [ -n "$conf" ] && extra=("/etc/wlan.conf=$conf")
    python3 tools/osum/mkfs.py build "$T/$n.img" 20000 --v3 /bin/ /t/ /etc/ /proc/ /lib/ /lib/firmware/ /lib/firmware/intel/ /lib/firmware/intel/iwlwifi/ \
        /bin/sh="$T/bin/sh.elf" /bin/echo="$T/bin/echo.elf" /bin/cat="$T/bin/cat.elf" /bin/sleep="$T/bin/sleep.elf" \
        "/t/s.sh=$T/s.sh" "$FWPATH=$T/blobs/v7.bin" "${extra[@]}" > "$T/$n.mkfs" 2>&1 \
        || { tail -3 "$T/$n.mkfs"; return 1; }
}
run() { # name words
    local n=$1 words=$2
    timeout 400 qemu-system-x86_64 -accel "$ACC" -smp 1 -kernel "$T/k.img" -m 512 \
        -append "osum vfs $words script=sh /t/s.sh;exit" \
        -serial "file:$T/$n.txt" -display none -no-reboot \
        -drive "file=$T/$n.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$T/$n.txt" > "$T/$n.klar"
}

printf 'ssid OrientFake\npsk orient-fake-pw1\n' > "$T/good.conf"
printf 'ssid OrientFake\npsk wrong-password-9\n' > "$T/wrong.conf"
image a || { bad "image a"; exit 1; }
image b "$T/wrong.conf" || { bad "image b"; exit 1; }
image c "$T/good.conf" || { bad "image c"; exit 1; }

echo "-- A: no /etc/wlan.conf: scan lines, no join"
run a "iwlfhtest iwlfhbind"
A="$T/a.klar"
has "$A" 'phase=ready' "driver ready"
has "$A" 'driver=bound' "fake transport bound by wlan_auto"
has "$A" 'net OrientFake ' "scan line: OrientFake"
has "$A" 'net CafeOpen ' "scan line: CafeOpen"
has "$A" 'net Neighbor5 ' "scan line: Neighbor5"
has "$A" 'auto=no-conf' "autostart state no-conf"
hasnot "$A" 'fakeap: m1' "no handshake attempted"
hasnot "$A" 'ip=192.' "no lease"
has "$A" '==END==' "system keeps running"

echo "-- B: wrong password: MIC check fails in the fake AP, retry, never up"
run b "iwlfhtest iwlfhbind"
B="$T/b.klar"
has "$B" 'fakeap: m2 badmic' "fake AP rejects message 2 (bad MIC)"
hasnot "$B" 'fakeap: m4 ok' "handshake never completes"
hasnot "$B" 'auto=up' "never up"
hasnot "$B" 'ip=192.' "no lease"
grep -aE 'auto=retry rc=-[0-9]+ tries=[1-9]' "$B" >/dev/null && ok "state retry with error code and tries counter" || bad "retry state missing"
has "$B" '==END==' "system keeps running"

echo "-- C: correct password: join, WPA2 4-way, DHCP, lease .50"
run c "iwlfhtest iwlfhbind"
C="$T/c.klar"
has "$C" 'fakeap: m2 ok' "fake AP verified message 2 MIC"
has "$C" 'fakeap: m4 ok' "4-way handshake completed (message 4 verified)"
has "$C" 'auto=up rc=0' "autostart state up"
has "$C" 'ip=192.168.77.50 mask=255.255.255.0 gw=192.168.77.1' "lease 192.168.77.50 / 255.255.255.0 / gw .1"
hasnot "$C" 'fakeap: m2 badmic' "no MIC failure"
has "$C" '==END==' "system keeps running"
has "$C" 'fakefw: scan ok v7 slots=52 nchan=35' "W-WLAN17: scan request is v7 with 52 channel slots (from the blob TLVs), 35 channels used"
hasnot "$C" 'fakefw: scan bad' "W-WLAN17: the fake firmware format check never fails"

printf 'echo ==START==\nsleep 6\ncat /proc/wlan\necho ==END==\n' > "$T/s.sh"
for ctl in "d iwloldscan 'bad length' a" "e iwloldslot 'bad length' a" "f iwloldssid 'ssid bitmap missing' c"; do
    eval set -- $ctl
    echo "-- $1: counter-proof $2 (old driver behaviour must be refused by the fake firmware)"
    image "$1" "$( [ "$4" = c ] && echo "$T/good.conf" )" || { bad "image $1"; continue; }
    run "$1" "iwlfhtest iwlfhbind $2"
    has "$T/$1.klar" "fakefw: scan bad $3" "$2: fake firmware names the format error"
    hasnot "$T/$1.klar" 'fakefw: scan ok' "$2: no scan accepted"
    hasnot "$T/$1.klar" 'net OrientFake ' "$2: no network found (fake AP stays silent)"
done

echo "WLANAUTO: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
