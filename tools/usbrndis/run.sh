#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/usbrndis/run.sh -- gate for the USB RNDIS network driver (r811).
#
#   bash tools/usbrndis/run.sh
#
# MEASURES (QEMU `-device qemu-xhci -device usb-net`, user-mode net, NO PCI NIC at all):
#   * word `rndisonly`: the RNDIS configuration of usb-net is bound (driver=rndis), ECM is refused
#   * RNDIS bring-up on the control pipe: INITIALIZE, permanent MAC (== -device mac=), packet filter
#   * DHCP lease and ping over bulk IN/OUT behind the 44 byte PACKET_MSG header
# CONTROL RUNS:
#   * without the word the same device is bound to ECM (ECM preferred, RNDIS never taken)
#   * without usb-net no rndis line and no lease
set -uo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$HERE"
export FIRNLIB="$HERE/lib"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
command -v qemu-system-x86_64 >/dev/null || { echo "USBRNDIS: skipped, no qemu"; exit 0; }
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1

bash tools/sync/build.sh "$T/bin" 0 sh sleep echo dhcp ping > "$T/b.txt" 2>&1 || { tail "$T/b.txt"; exit 1; }
./tools/build-kernel.sh "$T/k.img" --stufe 0 > "$T/k.txt" 2>&1 || { tail "$T/k.txt"; exit 1; }
printf 'echo ==START==\ndhcp\nping 10.0.2.2\nsleep 2\necho ==END==\n' > "$T/s.sh"
python3 tools/osum/mkfs.py build "$T/d.img" 8000 /bin/ /t/ /etc/ \
    /bin/sh="$T/bin/sh.elf" /bin/sleep="$T/bin/sleep.elf" /bin/echo="$T/bin/echo.elf" \
    /bin/dhcp="$T/bin/dhcp.elf" /bin/ping="$T/bin/ping.elf" \
    /t/s.sh="$T/s.sh" > "$T/mkfs.txt" 2>&1 || { tail "$T/mkfs.txt"; exit 1; }
ACC=tcg; [ -w /dev/kvm ] && ACC=kvm
MAC=52:54:00:12:34:99

run() { # name extra-kernel-words extra-qemu-args...
    local name=$1 words=$2; shift 2
    timeout 150 qemu-system-x86_64 -accel $ACC -kernel "$T/k.img" -m 256 \
        -append "osum nokbd nosched noproc nofs noring3 usb usbpoll nic $words nip=169.254.10.1/16 nsvc=0 nwait=0 script=sh /t/s.sh;exit" \
        -serial "file:$T/$name.txt" -display none -no-reboot \
        -drive "file=$T/d.img,format=raw,if=ide,index=0" \
        -device qemu-xhci,id=x0 "$@" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$T/$name.txt" > "$T/$name.klar"
}

run rndis "rndisonly" -netdev user,id=n0 -device usb-net,netdev=n0,mac=$MAC
M="$T/rndis.klar"
chk() { grep -aq -- "$2" "$M" && ok "$1" || { bad "$1 (missing: $2)"; }; }
chk "device bound to driver rndis"        'driver=rndis'
chk "MAC read by OID query"               "usb: rndis $MAC"
chk "netdev card is usbnet"               'netdev: c0=usbnet'
chk "DHCP lease over RNDIS"               'dhcp: ack ip=10.0.2.15'
chk "ping reply over bulk pipes"          'octets from 10.0.2.2: icmp_seq=1'
grep -aq 'driver=ecm' "$M" && bad "forced rndis: ecm line present" || ok "forced rndis: no ecm line"
grep -aq 'usb: rndis failed' "$M" && bad "rndis bring-up reported failure" || ok "rndis bring-up without failure"

# control: no word -> ECM is preferred, RNDIS is never taken
run ecm "" -netdev user,id=n0 -device usb-net,netdev=n0,mac=$MAC
E="$T/ecm.klar"
grep -aq 'driver=ecm' "$E" && ok "default: ECM preferred" || bad "default: no ecm line"
grep -aq 'driver=rndis' "$E" && bad "default: rndis taken although ECM exists" || ok "default: rndis not taken"
grep -aq 'dhcp: ack ip=10.0.2.15' "$E" && ok "default: DHCP lease over ECM" || bad "default: no lease over ECM"

# negative control: no usb-net device -> no rndis, no lease
run none "rndisonly" -netdev user,id=n0
N="$T/none.klar"
grep -aq 'driver=rndis' "$N" && bad "none: rndis line without device" || ok "none: no rndis line without device"
grep -aq 'dhcp: ack ip=' "$N" && bad "none: lease without NIC" || ok "none: no lease without NIC"

echo "USBRNDIS: $pass ok, $fail fail"
if [ "$fail" -gt 0 ]; then
    grep -a "usb\|netdev\|nic:\|dhcp\|rndis\|ecm" "$M" | head -30
    exit 1
fi
exit 0
