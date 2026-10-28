#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/usbhot/replug.sh -- gate for USB NIC replug: unplug, plug again, new DHCP lease, ping (r2185).
#
#   /root/jarvis/bin/heavy bash tools/usbhot/replug.sh [KERNEL_IMG]
#
# CASES (QEMU qemu-xhci + usb-net, monitor device_del / device_add inside the usbhold window):
#   root: NIC on a root port.
#   hub:  NIC behind a usb-hub (hub child removal must be noticed by the hub port rescan).
# EACH CASE expects: detached once, rebound (second driver=rndis line), fresh dhcp ack, ping replies, no panic.
set -uo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$HERE"
export FIRNLIB="$HERE/lib"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
command -v qemu-system-x86_64 >/dev/null || { echo "USBREPLUG: skipped, no qemu"; exit 0; }
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
bash tools/sync/build.sh "$T/bin" 0 sh sleep echo dhcp ping > "$T/b.txt" 2>&1 || { tail "$T/b.txt"; exit 1; }
KIMG="${1:-}"
if [ -z "$KIMG" ]; then
    ./tools/build-kernel.sh "$T/k.img" --stufe 0 > "$T/k.txt" 2>&1 || { tail "$T/k.txt"; exit 1; }
    KIMG="$T/k.img"
fi
printf 'echo ==START==\ndhcp\nping 10.0.2.2\necho ==PINGDONE==\nsleep 1\necho ==ALIVE==\n' > "$T/s.sh"
python3 tools/osum/mkfs.py build "$T/d.img" 8000 /bin/ /t/ /etc/ \
    /bin/sh="$T/bin/sh.elf" /bin/sleep="$T/bin/sleep.elf" /bin/echo="$T/bin/echo.elf" \
    /bin/dhcp="$T/bin/dhcp.elf" /bin/ping="$T/bin/ping.elf" /t/s.sh="$T/s.sh" > "$T/mkfs.txt" 2>&1 || { tail "$T/mkfs.txt"; exit 1; }
ACC=tcg; [ -w /dev/kvm ] && ACC=kvm
MAC=52:54:00:12:34:99

run_case() { # name topology(root|hub)
    local name=$1 topo=$2 bus="" addbus="" hub=""
    if [ "$topo" = hub ]; then
        hub="-device usb-hub,id=hub1,bus=x0.0,port=1"
        bus=",bus=x0.0,port=1.2"
    fi
    printf 'aufzeile k17: hold\nziehe n1\naufzeile usbnet: detached\nmonitor device_add usb-net,id=devn2%s,netdev=n0,mac=%s\naufzeile k17: free\n' "$bus" "$MAC" > "$T/$name.plan"
    timeout 170 qemu-system-x86_64 -accel $ACC -kernel "$KIMG" -m 256 \
        -append "osum nokbd nosched noproc nofs noring3 usb usbhold usbpoll nic rndisonly nip=169.254.10.1/16 nsvc=0 nwait=0 script=sh /t/s.sh;exit" \
        -serial "file:$T/$name.txt" -display none -no-reboot \
        -monitor "unix:$T/$name.mon,server,nowait" -pidfile "$T/$name.pid" \
        -drive "file=$T/d.img,format=raw,if=ide,index=0" \
        -device qemu-xhci,id=x0 $hub -netdev user,id=n0 -device "usb-net,id=devn1$bus,netdev=n0,mac=$MAC" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    python3 -I tools/hotplug/monitor.py "$T/$name.mon" "$T/$name.txt" "$T/$name.plan" > "$T/$name.mon.txt" 2>&1
    local mrc=$?
    [ "$mrc" = 0 ] && ok "$name: monitor plan (hold, unplug, detached, replug, free)" || { bad "$name: monitor plan rc=$mrc"; tail -4 "$T/$name.mon.txt"; }
    for i in $(seq 1 45); do grep -aq '==ALIVE==' "$T/$name.txt" && break; sleep 2; done
    [ -f "$T/$name.pid" ] && kill "$(cat "$T/$name.pid")" 2>/dev/null; wait 2>/dev/null
    tr -cd '\11\12\15\40-\176' < "$T/$name.txt" > "$T/$name.klar"
    local H="$T/$name.klar"
    [ "$(grep -ac 'usbnet: detached' "$H")" = 1 ] && ok "$name: detached exactly once" || bad "$name: detached count $(grep -ac 'usbnet: detached' "$H")"
    [ "$(grep -ac 'usb: port=.*driver=rndis' "$H")" -ge 2 ] && ok "$name: rebound to rndis after replug" || bad "$name: no second rndis bind"
    grep -aq 'second adapter ignored' "$H" && bad "$name: replugged NIC rejected as second adapter" || ok "$name: replugged NIC not rejected"
    grep -aq 'dhcp: ack ip=10.0.2.15' "$H" && ok "$name: fresh dhcp ack after replug" || bad "$name: no dhcp ack"
    grep -aq '[1-9][0-9]* received' "$H" && ok "$name: ping replies over the replugged NIC" || bad "$name: no ping replies"
    grep -aq '==ALIVE==' "$H" && ok "$name: script reached the end" || bad "$name: script did not finish"
    grep -aq 'usbnet: rndis dead' "$H" && bad "$name: rndis dead reported" || ok "$name: no rndis dead"
    grep -aiq 'panic\|exception\|#PF\|#GP\|#UD' "$H" && bad "$name: panic/exception" || ok "$name: no panic/exception"
}

run_case root root
run_case hub hub

echo "USBREPLUG: $pass ok, $fail fail"
[ "$fail" -gt 0 ] && exit 1
exit 0
