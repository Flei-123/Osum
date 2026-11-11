#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
HERE="$PWD"
export FIRNLIB="$HERE/lib"
T=$(mktemp -d)
SRV=""
trap '[ -n "$SRV" ] && kill "$SRV" 2>/dev/null; if [ -n "${WLANGUARD_KEEP:-}" ]; then mkdir -p "$WLANGUARD_KEEP"; cp "$T"/*.klar "$WLANGUARD_KEEP"/ 2>/dev/null; fi; rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' present" || ok "$3"; }
command -v qemu-system-x86_64 >/dev/null || { echo "WLANGUARD: skipped, no qemu"; exit 0; }
ACC=tcg; [ -w /dev/kvm ] && ACC=kvm
. tools/lib/firnenv.sh
SNAP_SEC=${WLANGUARD_SNAP_SEC:-2}
USB_SNAPS=${WLANGUARD_USB_SNAPS:-10}
WATCH_SNAPS=${WLANGUARD_WATCH_SNAPS:-16}
GW=192.168.77.1
MAC=52:54:00:12:34:99
FWPATH=/lib/firmware/intel/iwlwifi/iwlwifi-8265-36.ucode

printf 'nameserver 192.168.1.1\nfallback 1.1.1.1\n' > "$T/resolv.old"
mkdir -p "$T/blobs" "$T/bin" "$T/www"
head -c 131072 /dev/zero | tr '\0' 'x' > "$T/www/big"
PORT=$(python3 -I -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])')
(cd "$T/www" && exec python3 -I -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1) &
SRV=$!
python3 -I tools/iwlfh/ref.py gen "$T/blobs" || { bad "reference generator"; exit 1; }
bash tools/sync/build.sh "$T/bin" 0 sh echo cat sleep ping dhcp wget wlanctl netstat > "$T/b.txt" 2>&1 \
    && ok "programs build" || { bad "programs build"; tail "$T/b.txt"; echo "WLANGUARD: $pass passed, $fail failed"; exit 1; }
./tools/build-kernel.sh "$T/k.img" --stufe 0 > "$T/k.txt" 2>&1 \
    && ok "kernel builds" || { bad "kernel build"; tail -30 "$T/k.txt"; echo "WLANGUARD: $pass passed, $fail failed"; exit 1; }

snaps() { local i=0; while [ "$i" -lt "$1" ]; do echo "sleep $SNAP_SEC"; i=$((i+1)); done; }
{
    echo 'echo ==START=='
    echo 'dhcp dauer &'
    snaps "$USB_SNAPS"
    echo 'wlanctl connect OrientFake orient-fake-pw1'
    echo 'echo ==T0=='
    i=1
    while [ "$i" -le "$WATCH_SNAPS" ]; do
        snaps 1
        echo "echo ==T$i=="
        i=$((i+1))
    done
    echo 'echo ==NET0=='
    echo 'cat /proc/wlan'
    echo 'netstat'
    echo 'echo ==PING0=='
    echo "ping -c 2 $GW"
    echo 'echo ==WGET0=='
    echo "wget -q http://$GW:$PORT/big"
    echo 'echo ==END=='
} > "$T/s.sh"

IMG_FILES=(/bin/sh="$T/bin/sh.elf" /bin/echo="$T/bin/echo.elf" /bin/cat="$T/bin/cat.elf" /bin/sleep="$T/bin/sleep.elf" /bin/ping="$T/bin/ping.elf" /bin/dhcp="$T/bin/dhcp.elf" /bin/wget="$T/bin/wget.elf" /bin/wlanctl="$T/bin/wlanctl.elf" /bin/netstat="$T/bin/netstat.elf" /etc/resolv.conf="$T/resolv.old" "/t/s.sh=$T/s.sh" "$FWPATH=$T/blobs/v7.bin")
bash tools/mkfsfi/mkfs.sh build "$T/d.img" 20000 --v3 /bin/ /t/ /etc/ /proc/ /dev/ /lib/ /lib/firmware/ /lib/firmware/intel/ /lib/firmware/intel/iwlwifi/ "${IMG_FILES[@]}" > "$T/mkfs.txt" 2>&1 \
    || { tail -3 "$T/mkfs.txt"; bad "image"; exit 1; }

run() {
    local n=$1 words=$2
    timeout ${WLANGUARD_TIMEOUT:-600} qemu-system-x86_64 -accel "$ACC" -smp 1 -kernel "${WLANGUARD_KERNEL:-$T/k.img}" -m 512 \
        -append "osum vfs usb usbpoll iwlfhtest iwlfhbind nic nip=169.254.10.1/16 nsvc=0 nwait=0 nethotwait nethotlate $words script=sh /t/s.sh;exit" \
        -serial "file:$T/$n.txt" -display none -no-reboot \
        -drive "file=$T/d.img,format=raw,if=ide,index=0" \
        -device qemu-xhci,id=x0 \
        -netdev "user,id=n0,net=192.168.77.0/24,host=$GW,dhcpstart=192.168.77.15" -device usb-net,bus=x0.0,netdev=n0,mac=$MAC \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    local q=$!
    local i=0
    while kill -0 "$q" 2>/dev/null && [ "$i" -lt "${WLANGUARD_TIMEOUT:-600}" ]; do
        grep -qaF '==END==' "$T/$n.txt" 2>/dev/null && break
        sleep 1
        i=$((i+1))
    done
    kill "$q" 2>/dev/null
    wait "$q" 2>/dev/null
    tr -cd '\11\12\15\40-\176' < "$T/$n.txt" > "$T/$n.klar"
}
section() { awk -v a="$2" -v b="$3" '$0 ~ a {f=1} $0 ~ b {f=0} f' "$1"; }
first_mark_with() {
    local f=$1 pat=$2 last=$3 i=1
    while [ "$i" -le "$last" ]; do
        if section "$f" "==T$((i-1))==" "==T${i}==" | grep -qaF -- "$pat"; then echo "$i"; return; fi
        i=$((i+1))
    done
    echo 0
}

run g "wlanfirst fakenogw"
run h "wlanfirst"
run n "wlanfirst fakenogw wfnoguard"

echo "== WLAN joined, gateway silent, guard on =="
has "$T/g.klar" '==END==' "guard: system keeps running"
has "$T/g.klar" 'nethot: uplink card=1 kind=wlan' "guard: wlanfirst takes the uplink first"
has "$T/g.klar" 'wlanfirst: probation' "guard: probation starts"
has "$T/g.klar" 'wlanfirst: fallback why=1' "guard: fallback because the gateway never answers"
hasnot "$T/g.klar" 'wlanfirst: proven' "guard: the silent gateway is never proven"
SW=$(first_mark_with "$T/g.klar" 'nethot: uplink card=1 kind=wlan' "$WATCH_SNAPS")
FB=$(first_mark_with "$T/g.klar" 'wlanfirst: fallback why=1' "$WATCH_SNAPS")
echo "  info  switch to WLAN in slot $SW, fallback in slot $FB (slot = ${SNAP_SEC} s)"
[ "$FB" -gt 0 ] && [ "$FB" -le "$(( SW + 7 ))" ] && ok "guard: fallback within 14 s of the switch" || bad "guard: fallback within 14 s of the switch (slots $SW/$FB)"
section "$T/g.klar" '==T0==' '==NET0==' > "$T/g.watch"
has "$T/g.watch" 'nethot: uplink card=0 kind=usbnet' "guard: uplink returns to USB"
hasnot "$T/g.watch" 'ip=169.254' "guard: USB never falls back to a link-local address"
section "$T/g.klar" '==NET0==' '==PING0==' > "$T/g.net"
has "$T/g.net" 'stack wired=1 uplink=0 kind=5 ip=192.168.77.15 gw=192.168.77.1' "guard: stack is back on USB with its lease and gateway"
section "$T/g.klar" '==PING0==' '==WGET0==' > "$T/g.ping"
has "$T/g.ping" 'octets from 192.168.77.1' "guard: ping over USB after the fallback"
section "$T/g.klar" '==WGET0==' '==END==' > "$T/g.wget"
has "$T/g.wget" 'octets 131072' "guard: wget over USB after the fallback"

echo "== healthy WLAN, guard on =="
has "$T/h.klar" '==END==' "healthy: system keeps running"
has "$T/h.klar" 'nethot: uplink card=1 kind=wlan' "healthy: wlanfirst takes the uplink"
has "$T/h.klar" 'wlanfirst: proven' "healthy: the gateway answers over WLAN, WLAN is proven"
hasnot "$T/h.klar" 'wlanfirst: fallback' "healthy: no fallback"
section "$T/h.klar" '==T0==' '==NET0==' > "$T/h.watch"
hasnot "$T/h.watch" 'nethot: uplink card=0' "healthy: uplink stays on WLAN"
section "$T/h.klar" '==NET0==' '==PING0==' > "$T/h.net"
has "$T/h.net" 'stack wired=1 uplink=1 kind=6 ip=192.168.77.50 gw=192.168.77.1' "healthy: WLAN lease active"
section "$T/h.klar" '==PING0==' '==WGET0==' > "$T/h.ping"
has "$T/h.ping" 'octets from 192.168.77.1' "healthy: ping over WLAN"

echo "== gateway silent, guard off (counter-proof) =="
has "$T/n.klar" '==END==' "control: system keeps running"
has "$T/n.klar" 'nethot: uplink card=1 kind=wlan' "control: wlanfirst takes the uplink"
hasnot "$T/n.klar" 'wlanfirst: probation' "control: no probation without the guard"
hasnot "$T/n.klar" 'wlanfirst: fallback' "control: no fallback without the guard"
section "$T/n.klar" '==T0==' '==NET0==' > "$T/n.watch"
hasnot "$T/n.watch" 'nethot: uplink card=0' "control: the dead WLAN keeps the uplink for the whole watch"
section "$T/n.klar" '==NET0==' '==PING0==' > "$T/n.net"
has "$T/n.net" 'stack wired=1 uplink=1 kind=6' "control: stack stays on the WLAN"
section "$T/n.klar" '==PING0==' '==WGET0==' > "$T/n.ping"
hasnot "$T/n.ping" 'octets from 192.168.77.1' "control: no ping gets through"
echo "WLANGUARD: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
