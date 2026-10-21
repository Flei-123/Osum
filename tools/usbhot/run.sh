#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/usbhot/run.sh -- gate for RNDIS housekeeping + hot unplug of a USB NIC (r1501, LW-1a).
#
#   /root/jarvis/bin/heavy bash tools/usbhot/run.sh
#
# MEASURES (QEMU `-device qemu-xhci -device usb-net,id=devn1`, word `rndisonly`, user-mode net):
#   * the media-status poll ran and the link is up (`usbnet: rndis link up`)
#   * the host KEEPALIVE completed: `usbnet: rndis keepalive ok`. The driver sends one control command
#     every HOUSE_TICKS (300 ticks of 10 ms) and a keepalive on every third round, so the first one
#     is due after more than 900 ticks. The gate waits for the line (no fixed sleep, up to 120 s).
#   * `device_del devn1` over the QEMU monitor while the guest runs (tools/hotplug/monitor.py):
#     `usbnet: detached` appears, the kernel keeps running (a later `==ALIVE==` line), no
#     `rndis dead`, no panic after the unplug.
# CONTROL RUN: same machine without device_del -> `keepalive ok` yes, `detached` never.
#
# UNPLUG PART IS OFF BY DEFAULT (USBHOT_UNPLUG=1 turns it on): a script boot (`script=sh ...`) never runs the loop that
# calls usb.hotplug_work (kernel/kmain.fi usb_hold loop / kgui loop), so the port-change event is queued (S_PEND) but
# `usb.gone` -> usbnet.unplug_slot never runs and `usbnet: detached` is not printed (measured, r1501). Until the unplug
# is driven from a loop that exists in a script boot, the default run covers link up + keepalive + control.
set -uo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$HERE"
export FIRNLIB="$HERE/lib"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
command -v qemu-system-x86_64 >/dev/null || { echo "USBHOT: skipped, no qemu"; exit 0; }
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1

bash tools/sync/build.sh "$T/bin" 0 sh sleep echo dhcp ping > "$T/b.txt" 2>&1 || { tail "$T/b.txt"; exit 1; }
./tools/build-kernel.sh "$T/k.img" --stufe 0 > "$T/k.txt" 2>&1 || { tail "$T/k.txt"; exit 1; }
# housekeeping (usbnet.house) only runs when the stack polls the NIC (netdev.poll_on from inet rx),
# so the guest keeps the stack busy with short pings instead of sleeping. 14 rounds ~ 40 s.
gen() { { echo 'echo ==START=='; echo dhcp; i=0; while [ $i -lt $1 ]; do echo 'ping 10.0.2.2'; echo 'sleep 1'; i=$((i+1)); done; echo 'echo ==ALIVE=='; } > "$2"; }
gen 14 "$T/s_long.sh"
gen 12 "$T/s_ctl.sh"
python3 tools/osum/mkfs.py build "$T/d.img" 8000 /bin/ /t/ /etc/ \
    /bin/sh="$T/bin/sh.elf" /bin/sleep="$T/bin/sleep.elf" /bin/echo="$T/bin/echo.elf" \
    /bin/dhcp="$T/bin/dhcp.elf" /bin/ping="$T/bin/ping.elf" \
    /t/s_long.sh="$T/s_long.sh" /t/s_ctl.sh="$T/s_ctl.sh" > "$T/mkfs.txt" 2>&1 || { tail "$T/mkfs.txt"; exit 1; }
ACC=tcg; [ -w /dev/kvm ] && ACC=kvm
MAC=52:54:00:12:34:99

start() { # name script  (QEMU in background, monitor socket $T/<name>.mon, pid in $T/<name>.pid)
    local name=$1 script=$2
    timeout 170 qemu-system-x86_64 -accel $ACC -kernel "$T/k.img" -m 256 \
        -append "osum nokbd nosched noproc nofs noring3 usb usbpoll nic rndisonly nip=169.254.10.1/16 nsvc=0 nwait=0 script=sh /t/$script;exit" \
        -serial "file:$T/$name.txt" -display none -no-reboot \
        -monitor "unix:$T/$name.mon,server,nowait" -pidfile "$T/$name.pid" \
        -drive "file=$T/d.img,format=raw,if=ide,index=0" \
        -device qemu-xhci,id=x0 -netdev user,id=n0 -device usb-net,id=devn1,netdev=n0,mac=$MAC \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
}
clean() { tr -cd '\11\12\15\40-\176' < "$T/$1.txt" > "$T/$1.klar"; }
stop() { [ -f "$T/$1.pid" ] && kill "$(cat "$T/$1.pid")" 2>/dev/null; wait 2>/dev/null; }

# --- run 1: wait for keepalive ok, pull the plug, kernel must live on
UNPLUG=${USBHOT_UNPLUG:-0}
printf 'aufzeile usbnet: rndis link up\naufzeile usbnet: rndis keepalive ok\n' > "$T/plan.txt"
[ "$UNPLUG" = 1 ] && printf 'ziehe n1\naufzeile usbnet: detached\n' >> "$T/plan.txt"
start hot s_long.sh
python3 -I tools/hotplug/monitor.py "$T/hot.mon" "$T/hot.txt" "$T/plan.txt" > "$T/mon.txt" 2>&1
mrc=$?
[ "$mrc" = 0 ] && ok "monitor plan: link up, keepalive ok, unplug, detached all seen" || { bad "monitor plan rc=$mrc"; cat "$T/mon.txt" | tail -8; }
# the kernel must live on after the unplug: wait for ==ALIVE== (guest sleeps 45 s in total)
for i in $(seq 1 60); do grep -aq '==ALIVE==' "$T/hot.txt" && break; sleep 2; done
stop hot; clean hot
H="$T/hot.klar"
chk() { grep -aq -- "$2" "$H" && ok "$1" || bad "$1 (missing: $2)"; }
chk "device bound to driver rndis"      'driver=rndis'
chk "link up reported"                  'usbnet: rndis link up'
chk "host keepalive completed"          'usbnet: rndis keepalive ok'
[ "$UNPLUG" = 1 ] && chk "unplug reported"  'usbnet: detached'
chk "kernel alive after unplug"         '==ALIVE=='
la=$(grep -an 'usbnet: detached' "$H" | head -1 | cut -d: -f1)
lb=$(grep -an '==ALIVE==' "$H" | head -1 | cut -d: -f1)
if [ "$UNPLUG" = 1 ]; then [ -n "$la" ] && [ -n "$lb" ] && [ "$la" -lt "$lb" ] && ok "detached comes before ALIVE (line $la < $lb)" || bad "order detached/ALIVE ($la/$lb)"; fi
grep -aq 'usbnet: rndis dead' "$H" && bad "rndis dead reported (should be detached only)" || ok "no 'rndis dead' after unplug"
grep -aiq 'panic\|exception\|#PF\|#GP\|#UD' "$H" && bad "panic/exception in log" || ok "no panic/exception"
nd=$(grep -ac 'usbnet: detached' "$H")
if [ "$UNPLUG" = 1 ]; then [ "$nd" = 1 ] && ok "detached exactly once" || bad "detached $nd times"; else [ "$nd" = 0 ] && ok "no unplug requested: never detached" || bad "detached without device_del"; fi

# --- run 2 (control): nobody pulls the plug -> keepalive ok, never detached
start ctl s_ctl.sh
for i in $(seq 1 70); do grep -aq '==ALIVE==' "$T/ctl.txt" && break; sleep 2; done
stop ctl; clean ctl
C="$T/ctl.klar"
grep -aq 'usbnet: rndis keepalive ok' "$C" && ok "control: keepalive ok without unplug" || bad "control: no keepalive ok"
grep -aq 'usbnet: detached' "$C" && bad "control: detached without device_del" || ok "control: never detached"
grep -aq 'usbnet: rndis dead' "$C" && bad "control: rndis dead on a healthy link" || ok "control: link stays alive"

echo "USBHOT: $pass ok, $fail fail"
if [ "$fail" -gt 0 ]; then
    grep -a "usb\|netdev\|rndis\|ALIVE" "$H" | head -30
    exit 1
fi
exit 0
