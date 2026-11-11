#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/nethot/run.sh -- USB NIC hot plug as a network card + uplink switch/fallback (QEMU, monitor device_add/del).
# Cases: attach (e1000 at boot, usb-net added -> uplink usb, lease 10.0.5.15), fallback (add+del -> uplink e1000,
# lease 10.0.2.15), usbonly (no PCI NIC). Control: attach on origin/main must fail. NETHOT_OLD=0 skips it.
set -uo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$HERE"
export FIRNLIB="$HERE/lib"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
command -v qemu-system-x86_64 >/dev/null || { echo "NETHOT: skipped, no qemu"; exit 0; }
. tools/lib/firnenv.sh
bash tools/sync/build.sh "$T/bin" 0 sh sleep echo dhcp ping cat > "$T/b.txt" 2>&1 || { tail "$T/b.txt"; exit 1; }
KNEW="${NETHOT_KERNEL:-}"
if [ -z "$KNEW" ]; then
    ./tools/build-kernel.sh "$T/k.img" --stufe 0 > "$T/k.txt" 2>&1 || { tail "$T/k.txt"; exit 1; }
    KNEW="$T/k.img"
fi
mkscript() { printf 'echo ==START==\ndhcp\nping %s\necho ==PINGDONE==\ncat /proc/net/dev\necho ==ALIVE==\n' "$2" > "$T/$1.sh"; }
mkscript s_usb 10.0.5.2
mkscript s_eth 10.0.2.2
bash tools/mkfsfi/mkfs.sh build "$T/d.img" 8000 /bin/ /t/ /etc/ /proc/ /dev/ \
    /bin/sh="$T/bin/sh.elf" /bin/sleep="$T/bin/sleep.elf" /bin/echo="$T/bin/echo.elf" \
    /bin/dhcp="$T/bin/dhcp.elf" /bin/ping="$T/bin/ping.elf" /bin/cat="$T/bin/cat.elf" \
    /t/s_usb.sh="$T/s_usb.sh" /t/s_eth.sh="$T/s_eth.sh" > "$T/mkfs.txt" 2>&1 || { tail "$T/mkfs.txt"; exit 1; }
ACC=tcg; [ -w /dev/kvm ] && ACC=kvm
ADD="monitor device_add usb-net,id=devu1,bus=x0.0,netdev=n1,mac=52:54:00:12:34:99"

run() { # name kernel script pci(1|0) plan
    local name=$1 kimg=$2 script=$3 pci=$4 plan=$5 eth=""
    [ "$pci" = 1 ] && eth="-netdev user,id=n0,net=10.0.2.0/24 -device e1000,netdev=n0"
    timeout 200 qemu-system-x86_64 -accel $ACC -kernel "$kimg" -m 256 -nodefaults \
        -append "osum vfs nokbd nosched noring3 usb usbhold usbpoll nic rndisonly nip=169.254.10.1/16 nsvc=0 nwait=0 script=sh /t/$script;exit" \
        -serial "file:$T/$name.txt" -display none -no-reboot \
        -monitor "unix:$T/$name.mon,server,nowait" -pidfile "$T/$name.pid" \
        -drive "file=$T/d.img,format=raw,if=ide,index=0" \
        $eth -device qemu-xhci,id=x0 -netdev user,id=n1,net=10.0.5.0/24 \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    python3 -I tools/hotplug/monitor.py "$T/$name.mon" "$T/$name.txt" "$plan" > "$T/$name.mon.txt" 2>&1
    echo $? > "$T/$name.mrc"
    for i in $(seq 1 45); do grep -aq '==ALIVE==' "$T/$name.txt" && break; sleep 2; done
    [ -f "$T/$name.pid" ] && kill "$(cat "$T/$name.pid")" 2>/dev/null; wait 2>/dev/null
    tr -cd '\11\12\15\40-\176' < "$T/$name.txt" > "$T/$name.klar"
    [ -n "${NETHOT_KEEP:-}" ] && cp "$T/$name.klar" "$NETHOT_KEEP/$name.klar"
}
plan_ok() { [ "$(cat "$T/$1.mrc")" = 0 ] && ok "$1: monitor plan" || { bad "$1: monitor plan rc=$(cat "$T/$1.mrc")"; grep -a "NOT SEEN" "$T/$1.mon.txt"; tail -1 "$T/$1.mon.txt"; }; }
common() {
    grep -aq '==ALIVE==' "$T/$1.klar" && ok "$1: script reached the end" || bad "$1: script did not finish"
    grep -aiq 'panic\|exception\|#PF\|#GP\|#UD' "$T/$1.klar" && bad "$1: panic/exception" || ok "$1: no panic/exception"
}
printf 'aufzeile k17: hold\n%s\naufzeile nethot: uplink card=1 kind=usbnet\naufzeile k17: free\n' "$ADD" > "$T/p_attach"
printf 'aufzeile k17: hold\n%s\naufzeile nethot: uplink card=1 kind=usbnet\nmonitor device_del devu1\naufzeile usbnet: detached\naufzeile nethot: uplink card=0 kind=e1000\naufzeile k17: free\n' "$ADD" > "$T/p_fallback"
printf 'aufzeile k17: hold\n%s\naufzeile nethot: usbnet attached\naufzeile k17: free\n' "$ADD" > "$T/p_usbonly"

echo "== attach =="
run attach "$KNEW" s_usb.sh 1 "$T/p_attach"; H="$T/attach.klar"; plan_ok attach
grep -aq 'nethot: usbnet attached card=1 kind=usbnet' "$H" && ok "attach: usbnet registered as card 1" || bad "attach: usbnet not registered"
grep -aq 'dhcp: ack ip=10.0.5.15' "$H" && ok "attach: lease from the USB network" || bad "attach: no USB lease"
grep -aq 'dhcp: ack ip=10.0.2.15' "$H" && bad "attach: lease from the e1000 network" || ok "attach: no e1000 lease"
grep -aq '[1-9][0-9]* received' "$H" && ok "attach: ping 10.0.5.2 answered" || bad "attach: no ping replies"
grep -aq 'eth0: *[0-9]' "$H" && grep -aq 'usb0: *[1-9]' "$H" && ok "attach: /proc/net/dev lists eth0 + usb0" || bad "attach: /proc/net/dev misses eth0/usb0"
common attach
echo "== fallback =="
run fallback "$KNEW" s_eth.sh 1 "$T/p_fallback"; H="$T/fallback.klar"; plan_ok fallback
grep -aq 'nethot: usbnet detached' "$H" && ok "fallback: card removed" || bad "fallback: no detach"
grep -aq 'dhcp: ack ip=10.0.2.15' "$H" && ok "fallback: lease from e1000" || bad "fallback: no e1000 lease"
grep -aq '[1-9][0-9]* received' "$H" && ok "fallback: ping 10.0.2.2 answered" || bad "fallback: no ping replies"
grep -aq 'eth0: *[1-9]' "$H" && ! grep -aq 'usb0:' "$H" && ok "fallback: /proc/net/dev lists eth0, usb0 gone" || bad "fallback: /proc/net/dev wrong (eth0 missing or usb0 listed)"
common fallback
echo "== usbonly =="
run usbonly "$KNEW" s_usb.sh 0 "$T/p_usbonly"; H="$T/usbonly.klar"; plan_ok usbonly
grep -aq 'dhcp: ack ip=10.0.5.15' "$H" && ok "usbonly: USB lease" || bad "usbonly: no lease"
grep -aq '[1-9][0-9]* received' "$H" && ok "usbonly: ping answered" || bad "usbonly: no ping replies"
common usbonly
if [ "${NETHOT_OLD:-1}" = 1 ]; then
    echo "== control: origin/main =="
    mkdir -p "$T/old"; git archive "${NETHOT_BASE:-97b7e6b71}" | tar -x -C "$T/old"
    firnenv_prepare_old_tree "$T/old"
    if (cd "$T/old" && FIRNLIB="$T/old/lib" ./tools/build-kernel.sh "$T/old.img" --stufe 0 > "$T/old.txt" 2>&1); then
        run ctl "$T/old.img" s_usb.sh 1 "$T/p_attach"; H="$T/ctl.klar"
        grep -aq 'dhcp: ack ip=10.0.5.15' "$H" && bad "control: old kernel leased from USB" || ok "control: old kernel gets no USB lease"
    else bad "control: old kernel did not build"; fi
fi
echo "NETHOT: $pass ok, $fail fail"
[ "$fail" -gt 0 ] && exit 1
exit 0
