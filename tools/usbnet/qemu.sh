#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/usbnet/qemu.sh -- gate for the USB CDC-ECM network driver (L-015).
#
#   bash tools/usbnet/qemu.sh
#
# MEASURES (QEMU `-device qemu-xhci -device usb-net`, user-mode net, NO PCI
# NIC at all -- the only way online is the USB function):
#   * xHCI enumerates the device, the ECM configuration is picked out of the
#     three QEMU offers (RNDIS / CDC / Subset), driver=ecm is printed
#   * the MAC comes from the string descriptor (== the -device mac=)
#   * the interface registers as a netdev card (netdev: c0=usbnet) and the
#     network stage comes up AFTER usb enumeration
#   * DHCP over the USB function: "dhcp: ack ip=10.0.2.15"
#   * ping the user-net gateway 10.0.2.2 over bulk IN/OUT
# NEGATIVE CONTROL (noecm): the same image without the usb-net device must
# NOT print any ecm line, and DHCP must get no lease.
set -uo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$HERE"
export FIRNLIB="$HERE/lib"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
command -v qemu-system-x86_64 >/dev/null || { echo "USBNET-QEMU: skipped, no qemu"; exit 0; }
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

run() { # name extra-qemu-args...
    XW=""; [ "$1" = nohub ] && XW="nohub"
    local name=$1; shift
    timeout 150 qemu-system-x86_64 -accel $ACC -kernel "$T/k.img" -m 256 \
        -append "osum nokbd nosched noproc nofs noring3 usb usbpoll nic nip=169.254.10.1/16 nsvc=0 nwait=0 $XW script=sh /t/s.sh;exit" \
        -serial "file:$T/$name.txt" -display none -no-reboot \
        -drive "file=$T/d.img,format=raw,if=ide,index=0" \
        -device qemu-xhci,id=x0 "$@" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
    tr -cd '\11\12\15\40-\176' < "$T/$name.txt" > "$T/$name.klar"
}

run main -netdev user,id=n0 -device usb-net,netdev=n0,mac=$MAC
M="$T/main.klar"
chk() { grep -aq -- "$2" "$M" && ok "$1" || { bad "$1 (missing: $2)"; }; }
chk "device bound to driver ecm"          'driver=ecm'
chk "MAC read from string descriptor"     "usb: ecm $MAC"
chk "netdev card is usbnet"               'netdev: c0=usbnet'
chk "network stage after USB came up"     'nic: queue='
chk "DHCP lease over USB"                 'dhcp: ack ip=10.0.2.15'
chk "ping reply over bulk pipes"          'octets from 10.0.2.2: icmp_seq=1'

# negative control: no usb-net device -> no ecm, no lease
run none -netdev user,id=n0
N="$T/none.klar"
grep -aq 'driver=ecm' "$N" && bad "noecm: ecm line without device" || ok "noecm: no ecm line without device"
grep -aq 'dhcp: ack ip=' "$N" && bad "noecm: lease without NIC" || ok "noecm: no lease without NIC"

run hub -netdev user,id=n0 -device usb-hub,bus=x0.0,port=1,id=hub0 -device usb-net,bus=x0.0,port=1.1,netdev=n0,mac=$MAC
H="$T/hub.klar"
grep -aq 'usb: hub p=' "$H" && ok "hub: hub driver enumerates the hub" || bad "hub: hub line missing"
grep -aq 'route=[1-9][0-9]* .*driver=ecm' "$H" && ok "hub: ecm behind the hub has a route string" || bad "hub: ecm behind hub missing"
grep -aq 'dhcp: ack ip=10.0.2.15' "$H" && ok "hub: DHCP lease through the hub" || bad "hub: no lease through the hub"
grep -aq 'octets from 10.0.2.2: icmp_seq=1' "$H" && ok "hub: ping through the hub" || bad "hub: no ping through the hub"

run nohub -netdev user,id=n0 -device usb-hub,bus=x0.0,port=1,id=hub0 -device usb-net,bus=x0.0,port=1.1,netdev=n0,mac=$MAC
NH="$T/nohub.klar"
grep -aq 'driver=ecm' "$NH" && bad "nohub: ecm found without hub driver" || ok "nohub: no ecm without hub driver"

echo "USBNET-QEMU: $pass ok, $fail fail"
if [ "$fail" -gt 0 ]; then
    cp "$M" /root/jarvis/data/tmp_usbnet/last-main.klar 2>/dev/null
    grep -a "usb\|netdev\|nic:\|dhcp\|ecm" "$M" | head -30
    exit 1
fi
exit 0
