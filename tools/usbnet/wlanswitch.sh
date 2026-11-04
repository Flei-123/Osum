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
LATE_SNAPS=${USBWLAN_LATE_SNAPS:-5}
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

bash tools/mkfsfi/mkfs.sh build "$T/d.img" 20000 --v3 /bin/ /t/ /etc/ /proc/ /dev/ /lib/ /lib/firmware/ /lib/firmware/intel/ /lib/firmware/intel/iwlwifi/ \
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
section() { awk -v a="$2" -v b="$3" '$0 ~ a {f=1} $0 ~ b {f=0} f' "$1"; }
if [ "${USBWLAN_LATE_ONLY:-0}" != 1 ]; then
run m
run o "nethotwait nethotlate wlanfirst nohotkeep"
run d "nethotwait nethotlate iwlfhdrop"
fi
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
if [ "${USBWLAN_LATE_ONLY:-0}" != 1 ]; then
has "$T/m.klar" '==END==' "keep: system keeps running"
section "$T/m.klar" '==START==' '==USB0==' > "$T/keep.usb"
has "$T/keep.usb" 'dhcp: ack ip=192.168.77.15' "keep: DHCP lease over USB"
has "$T/keep.usb" 'wget: octets 131072' "keep: wget over USB"
section "$T/m.klar" '==USBSTATE==' '==WLAN0==' > "$T/keep.sw"
hasnot "$T/keep.sw" 'nethot: uplink card=1 kind=wlan' "keep: WLAN does not take the uplink while USB is alive"
section "$T/m.klar" '==WLAN0==' '==WLANSTATE==' > "$T/keep.w0"
has "$T/keep.w0" 'stack wired=1 uplink=0 kind=5 ip=192.168.77.15 gw=192.168.77.1' "keep: WLAN joined as standby, stack stays on USB"
section "$T/m.klar" '==WLANSTATE==' '==WPING==' > "$T/keep.wp"
has "$T/keep.wp" 'octets from 192.168.77.1' "keep: ping over USB while WLAN is joined"
section "$T/m.klar" '==WPING==' '==WWGET==' > "$T/keep.ww"
has "$T/keep.ww" 'octets 131072' "keep: wget over USB while WLAN is joined"
section "$T/m.klar" '==WWGET==' '==WHOST==' > "$T/keep.wh"
has "$T/keep.wh" '93.184.216.34' "keep: host over USB while WLAN is joined"
section "$T/m.klar" '==WHOST==' '==BACK0==' > "$T/keep.bk"
hasnot "$T/keep.bk" 'nethot: uplink' "keep: forgetting the WLAN does not touch the uplink"
section "$T/m.klar" '==BACK0==' '==BACKSTATE==' > "$T/keep.b0"
has "$T/keep.b0" 'ip=192.168.77.15 gw=192.168.77.1' "keep: USB keeps its DHCP lease after WLAN is dropped"
hasnot "$T/keep.b0" 'ip=169.254' "keep: no link-local address on USB"
section "$T/m.klar" '==BACKSTATE==' '==BPING==' > "$T/keep.bp"
has "$T/keep.bp" 'octets from 192.168.77.1' "keep: ping over USB after the WLAN is dropped"
section "$T/m.klar" '==BPING==' '==BWGET==' > "$T/keep.bw"
has "$T/keep.bw" 'octets 131072' "keep: wget over USB after the WLAN is dropped"
has "$T/d.klar" '==END==' "deaf: system keeps running"
section "$T/d.klar" '==WLANSTATE==' '==WPING==' > "$T/deaf.wp"
has "$T/deaf.wp" 'octets from 192.168.77.1' "deaf: ping over USB while the WLAN access point is deaf"
section "$T/d.klar" '==WPING==' '==WWGET==' > "$T/deaf.ww"
has "$T/deaf.ww" 'octets 131072' "deaf: wget over USB while the WLAN access point is deaf"
section "$T/d.klar" '==WWGET==' '==WHOST==' > "$T/deaf.wh"
has "$T/deaf.wh" '93.184.216.34' "deaf: host over USB while the WLAN access point is deaf"
hasnot "$T/d.klar" 'nethot: uplink card=1 kind=wlan' "deaf: the deaf WLAN never becomes the uplink"
check "$T/o.klar" old
has "$T/old.b0" 'ip=169.254' "control wlanfirst+nohotkeep: old behaviour leaves USB on link-local"
hasnot "$T/old.b0" 'gw=192.168.77.1' "control wlanfirst+nohotkeep: old behaviour loses the gateway"
fi
if [ "${USBWLAN_LATE:-1}" = 1 ]; then
    echo "== dongle plugged after WLAN =="
    {
        echo 'echo ==START=='
        echo 'wlanctl connect OrientFake orient-fake-pw1'
        snaps "$WLAN_SNAPS"
        echo 'dhcp dauer &'
        snaps 1
        echo 'cat /proc/wlan'
        echo 'echo ==LATE0=='
        snaps "$LATE_SNAPS"
        echo 'cat /proc/wlan'
        echo 'cat /etc/resolv.conf'
        echo 'echo ==LATE1=='
        echo 'ping -c 2 10.0.5.2'
        echo 'echo ==LPING=='
        echo 'echo ==UNPLUG=='
        snaps "$BACK_SNAPS"
        echo 'cat /proc/wlan'
        echo 'echo ==LBACK0=='
        echo "ping -c 2 $GW"
        echo 'echo ==LBPING=='
        echo "wget -q http://$GW/big"
        echo 'echo ==LBWGET=='
        echo 'host store.fleitec.com'
        echo 'echo ==LBHOST=='
        echo 'echo ==END=='
    } > "$T/late.sh"
    bash tools/mkfsfi/mkfs.sh build "$T/dl.img" 20000 --v3 /bin/ /t/ /etc/ /proc/ /dev/ /lib/ /lib/firmware/ /lib/firmware/intel/ /lib/firmware/intel/iwlwifi/ \
        /bin/sh="$T/bin/sh.elf" /bin/echo="$T/bin/echo.elf" /bin/cat="$T/bin/cat.elf" /bin/sleep="$T/bin/sleep.elf" /bin/ping="$T/bin/ping.elf" /bin/host="$T/bin/host.elf" /bin/dhcp="$T/bin/dhcp.elf" /bin/wget="$T/bin/wget.elf" /bin/wlanctl="$T/bin/wlanctl.elf" /bin/netstat="$T/bin/netstat.elf" \
        "/t/s.sh=$T/late.sh" "$FWPATH=$T/blobs/v7.bin" > "$T/mkfs2.txt" 2>&1 || { tail -3 "$T/mkfs2.txt"; bad "late image"; }
    printf 'aufzeile k17: hold\naufzeile ==LATE0==\nmonitor device_add usb-net,id=devu1,bus=x0.0,netdev=n1,mac=%s\naufzeile nethot: usbnet attached\naufzeile ==UNPLUG==\nmonitor device_del devu1\naufzeile k17: free\n' "$MAC" > "$T/p_late"
    timeout ${USBWLAN_TIMEOUT:-500} qemu-system-x86_64 -accel "$ACC" -smp 1 -kernel "${USBWLAN_KERNEL:-$T/k.img}" -m 512 \
        -append "osum vfs usb usbhold usbpoll iwlfhtest iwlfhbind nic nip=169.254.10.1/16 nsvc=0 nwait=0 nethotwait nethotlate script=sh /t/s.sh;exit" \
        -serial "file:$T/l.txt" -display none -no-reboot \
        -monitor "unix:$T/l.mon,server,nowait" -pidfile "$T/l.pid" \
        -drive "file=$T/dl.img,format=raw,if=ide,index=0" \
        -device qemu-xhci,id=x0 -netdev "user,id=n1,net=10.0.5.0/24" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    python3 -I tools/hotplug/monitor.py "$T/l.mon" "$T/l.txt" "$T/p_late" > "$T/l.mon.txt" 2>&1
    echo $? > "$T/l.mrc"
    for i in $(seq 1 120); do grep -qaF '==END==' "$T/l.txt" 2>/dev/null && break; sleep 2; done
    [ -f "$T/l.pid" ] && kill "$(cat "$T/l.pid")" 2>/dev/null
    tr -cd '\11\12\15\40-\176' < "$T/l.txt" > "$T/l.klar"
    [ -n "${USBWLAN_KEEP:-}" ] && cp "$T/l.klar" "$USBWLAN_KEEP"/ 2>/dev/null
    has "$T/l.klar" '==END==' "late: system keeps running"
    has "$T/l.klar" 'nethot: usbnet attached' "late: dongle registered"
    section "$T/l.klar" '==START==' '==LATE0==' > "$T/late.w0"
    has "$T/late.w0" 'ip=192.168.77.50 gw=192.168.77.1' "late: WLAN lease before the dongle"
    section "$T/l.klar" '==LATE0==' '==LATE1==' > "$T/late.w1"
    has "$T/late.w1" 'nethot: uplink card=1 kind=usbnet' "late: uplink switches to the dongle"
    has "$T/late.w1" 'ip=10.0.5.15' "late: dongle gets its own DHCP lease"
    section "$T/l.klar" '==LATE1==' '==LPING==' > "$T/late.pg"
    has "$T/late.pg" 'octets from 10.0.5.2' "late: ping over the dongle"
    section "$T/l.klar" '==UNPLUG==' '==LBACK0==' > "$T/late.bk"
    has "$T/late.bk" 'nethot: uplink card=0 kind=wlan' "late: uplink returns to WLAN after unplug"
    has "$T/late.bk" 'ip=192.168.77.50 gw=192.168.77.1' "late: WLAN lease is back after unplug"
    hasnot "$T/late.bk" 'ip=169.254' "late: no link-local address after unplug"
    section "$T/l.klar" '==LBACK0==' '==LBPING==' > "$T/late.bp"
    has "$T/late.bp" 'octets from 192.168.77.1' "late: ping over WLAN after unplug"
    section "$T/l.klar" '==LBPING==' '==LBWGET==' > "$T/late.bw"
    has "$T/late.bw" 'status 200' "late: wget over WLAN after unplug"
    section "$T/l.klar" '==LBWGET==' '==LBHOST==' > "$T/late.bh"
    has "$T/late.bh" '93.184.216.34' "late: host over WLAN after unplug"
fi
echo "USBWLAN: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
