#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
HERE="$PWD"
export FIRNLIB="$HERE/lib"
T=$(mktemp -d)
SRV=""
trap '[ -n "$SRV" ] && kill "$SRV" 2>/dev/null; if [ -n "${USBWLAN_KEEP:-}" ]; then mkdir -p "$USBWLAN_KEEP"; cp "$T"/*.klar "$USBWLAN_KEEP"/ 2>/dev/null; fi; rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
has() { grep -qaF -- "$2" "$1" && ok "$3" || bad "$3 -- '$2' missing"; }
hasnot() { grep -qaF -- "$2" "$1" && bad "$3 -- '$2' present" || ok "$3"; }
command -v qemu-system-x86_64 >/dev/null || { echo "USBWLAN: skipped, no qemu"; exit 0; }
ACC=tcg; [ -w /dev/kvm ] && ACC=kvm
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
USB_SNAPS=${USBWLAN_USB_SNAPS:-4}
WLAN_SNAPS=${USBWLAN_WLAN_SNAPS:-4}
BACK_SNAPS=${USBWLAN_BACK_SNAPS:-3}
SNAP_SEC=${USBWLAN_SNAP_SEC:-6}
GW=192.168.77.1
MAC=52:54:00:12:34:99

printf 'nameserver 192.168.1.1\nfallback 1.1.1.1\n' > "$T/resolv.old"
mkdir -p "$T/blobs" "$T/bin" "$T/www"
head -c 131072 /dev/zero | tr '\0' 'x' > "$T/www/big"
PORT=$(python3 -I -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1])')
(cd "$T/www" && exec python3 -I -m http.server "$PORT" --bind 127.0.0.1 >/dev/null 2>&1) &
SRV=$!
python3 -I tools/iwlfh/ref.py gen "$T/blobs" || { bad "reference generator"; exit 1; }
FWPATH=/lib/firmware/intel/iwlwifi/iwlwifi-8265-36.ucode
bash tools/sync/build.sh "$T/bin" 0 sh echo cat sleep ping host dhcp wget wlanctl netstat > "$T/b.txt" 2>&1 \
    && ok "programs build" || { bad "programs build"; tail "$T/b.txt"; echo "USBWLAN: $pass ok, $fail fail"; exit 1; }
./tools/build-kernel.sh "$T/k.img" --stufe 0 > "$T/k.txt" 2>&1 \
    && ok "kernel builds" || { bad "kernel build"; tail -30 "$T/k.txt"; echo "USBWLAN: $pass ok, $fail fail"; exit 1; }

snaps() { local i=0; while [ "$i" -lt "$1" ]; do echo "sleep $SNAP_SEC"; i=$((i+1)); done; }
{
    echo 'echo ==START=='
    snaps "$USB_SNAPS"
    echo 'dhcp dauer &'
    snaps 1
    echo "ping -c 2 $GW"
    echo "wget -q http://$GW:$PORT/big"
    echo 'cat /etc/resolv.conf'
    echo 'echo ==USB0=='
    echo 'cat /proc/wlan'
    echo 'netstat'
    echo 'echo ==USBSTATE=='
    echo 'wlanctl connect OrientFake orient-fake-pw1'
    snaps "$WLAN_SNAPS"
    echo 'echo ==WLAN0=='
    echo 'cat /proc/wlan'
    echo 'netstat'
    echo 'cat /etc/resolv.conf'
    echo 'echo ==WLANSTATE=='
    echo "ping -c 2 $GW"
    echo 'echo ==WPING=='
    echo "wget -q http://$GW/big"
    echo 'echo ==WWGET=='
    echo 'host store.fleitec.com'
    echo 'echo ==WHOST=='
    echo 'wlanctl forget'
    snaps "$BACK_SNAPS"
    echo 'echo ==BACK0=='
    echo 'cat /proc/wlan'
    echo 'netstat'
    echo 'cat /etc/resolv.conf'
    echo 'echo ==BACKSTATE=='
    echo "ping -c 2 $GW"
    echo 'echo ==BPING=='
    echo "wget -q http://$GW:$PORT/big"
    echo 'echo ==BWGET=='
    echo 'echo ==END=='
} > "$T/s.sh"

python3 tools/osum/mkfs.py build "$T/d.img" 20000 --v3 /bin/ /t/ /etc/ /proc/ /dev/ /lib/ /lib/firmware/ /lib/firmware/intel/ /lib/firmware/intel/iwlwifi/ \
    /bin/sh="$T/bin/sh.elf" /bin/echo="$T/bin/echo.elf" /bin/cat="$T/bin/cat.elf" /bin/sleep="$T/bin/sleep.elf" /bin/ping="$T/bin/ping.elf" /bin/host="$T/bin/host.elf" /bin/dhcp="$T/bin/dhcp.elf" /bin/wget="$T/bin/wget.elf" /bin/wlanctl="$T/bin/wlanctl.elf" /bin/netstat="$T/bin/netstat.elf" /etc/resolv.conf="$T/resolv.old" \
    "/t/s.sh=$T/s.sh" "$FWPATH=$T/blobs/v7.bin" > "$T/mkfs.txt" 2>&1 || { tail -3 "$T/mkfs.txt"; bad "image"; exit 1; }

run() {
    local n=$1 words=${2:-nethotwait nethotlate}
    timeout ${USBWLAN_TIMEOUT:-500} qemu-system-x86_64 -accel "$ACC" -smp 1 -kernel "${USBWLAN_KERNEL:-$T/k.img}" -m 512 \
        -append "osum vfs usb usbpoll iwlfhtest iwlfhbind nic nip=169.254.10.1/16 nsvc=0 nwait=0 $words script=sh /t/s.sh;exit" \
        -serial "file:$T/$n.txt" -display none -no-reboot \
        -drive "file=$T/d.img,format=raw,if=ide,index=0" \
        -device qemu-xhci,id=x0 \
        -netdev "user,id=n0,net=192.168.77.0/24,host=$GW,dhcpstart=192.168.77.15" -device usb-net,bus=x0.0,netdev=n0,mac=$MAC \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    local q=$!
    local i=0
    while kill -0 "$q" 2>/dev/null && [ "$i" -lt "${USBWLAN_TIMEOUT:-500}" ]; do
        grep -qaF '==END==' "$T/$n.txt" 2>/dev/null && break
        sleep 1
        i=$((i+1))
    done
    kill "$q" 2>/dev/null
    wait "$q" 2>/dev/null
    tr -cd '\11\12\15\40-\176' < "$T/$n.txt" > "$T/$n.klar"
}
run m
run o "nethotwait nethotlate nohotkeep"
section() { awk -v a="$2" -v b="$3" '$0 ~ a {f=1} $0 ~ b {f=0} f' "$1"; }
check() {
    local f=$1 tag=$2
    has "$f" '==END==' "$tag: system keeps running"
    section "$f" '==START==' '==USB0==' > "$T/$tag.usb"
    has "$T/$tag.usb" 'dhcp: ack ip=192.168.77.15' "$tag: DHCP lease over USB"
    has "$T/$tag.usb" 'wget: octets 131072' "$tag: wget over USB"
    section "$f" '==USBSTATE==' '==WLAN0==' > "$T/$tag.sw"
    has "$T/$tag.sw" 'nethot: uplink card=1 kind=wlan' "$tag: uplink switches to WLAN"
    section "$f" '==WLAN0==' '==WLANSTATE==' > "$T/$tag.w0"
    has "$T/$tag.w0" 'stack wired=1 uplink=1 kind=6 ip=192.168.77.50 gw=192.168.77.1' "$tag: WLAN lease active"
    section "$f" '==WLANSTATE==' '==WPING==' > "$T/$tag.wp"
    has "$T/$tag.wp" 'octets from 192.168.77.1' "$tag: ping over WLAN"
    section "$f" '==WPING==' '==WWGET==' > "$T/$tag.ww"
    has "$T/$tag.ww" 'status 200' "$tag: wget over WLAN"
    section "$f" '==WWGET==' '==WHOST==' > "$T/$tag.wh"
    has "$T/$tag.wh" '93.184.216.34' "$tag: host over WLAN"
    section "$f" '==WHOST==' '==BACK0==' > "$T/$tag.bk"
    has "$T/$tag.bk" 'nethot: uplink card=0 kind=usbnet' "$tag: uplink returns to USB"
    section "$f" '==BACK0==' '==BACKSTATE==' > "$T/$tag.b0"
}
check "$T/m.klar" keep
has "$T/keep.b0" 'ip=192.168.77.15 gw=192.168.77.1' "keep: USB keeps its DHCP lease after WLAN is dropped"
hasnot "$T/keep.b0" 'ip=169.254' "keep: no link-local address on USB"
section "$T/m.klar" '==BACKSTATE==' '==BPING==' > "$T/keep.bp"
has "$T/keep.bp" 'octets from 192.168.77.1' "keep: ping over USB after the switch back"
section "$T/m.klar" '==BPING==' '==BWGET==' > "$T/keep.bw"
has "$T/keep.bw" 'octets 131072' "keep: wget over USB after the switch back"
check "$T/o.klar" old
has "$T/old.b0" 'ip=169.254' "control nohotkeep: old behaviour leaves USB on link-local"
hasnot "$T/old.b0" 'gw=192.168.77.1' "control nohotkeep: old behaviour loses the gateway"
echo "USBWLAN: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
