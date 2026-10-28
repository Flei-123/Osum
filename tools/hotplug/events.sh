#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/hotplug/events.sh -- gate for the unified device-event ring (uevent): add/remove series per class.
#
#   /root/jarvis/bin/heavy bash tools/hotplug/events.sh [KERNEL_IMG] [OLD_KERNEL_IMG]
#
# CASES (QEMU qemu-xhci, monitor device_add / device_del inside the usbhold window):
#   stick: usb-storage, add then remove        -> class=block   events 1,2
#   nic:   usb-net, add, remove, add again     -> class=net-eth events 1,2,3
# EACH CASE expects: serial 'uevent:' lines with strictly increasing seq, right action/class/bus,
#   ids as vvvv:pppp, and the guest reads the same lines back from /proc/uevent.
# COUNTER-PROOF (optional 2nd argument): an older kernel prints no 'uevent:' line at all.
set -uo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$HERE"
export FIRNLIB="$HERE/lib"
T=${UEV_DIR:-$(mktemp -d)}; mkdir -p "$T"; [ -n "${UEV_DIR:-}" ] || trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
command -v qemu-system-x86_64 >/dev/null || { echo "UEVENTS: skipped, no qemu"; exit 0; }
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
bash tools/sync/build.sh "$T/bin" 0 sh sleep echo cat > "$T/b.txt" 2>&1 || { tail "$T/b.txt"; exit 1; }
KIMG="${1:-}"
if [ -z "$KIMG" ]; then
    ./tools/build-kernel.sh "$T/k.img" --stufe 0 > "$T/k.txt" 2>&1 || { tail "$T/k.txt"; exit 1; }
    KIMG="$T/k.img"
fi
OLDIMG="${2:-}"
printf 'echo ==START==\nsleep 14\ncat /proc/usbsum\ncat /proc/uevent\necho ==ALIVE==\n' > "$T/s.sh"
python3 tools/osum/mkfs.py build "$T/d.img" 8000 /bin/ /t/ /etc/ /proc/ \
    /bin/sh="$T/bin/sh.elf" /bin/sleep="$T/bin/sleep.elf" /bin/echo="$T/bin/echo.elf" \
    /bin/cat="$T/bin/cat.elf" /t/s.sh="$T/s.sh" > "$T/mkfs.txt" 2>&1 || { tail "$T/mkfs.txt"; exit 1; }
dd if=/dev/zero of="$T/stick.img" bs=1M count=8 status=none
ACC=tcg; [ -w /dev/kvm ] && ACC=kvm
MAC=52:54:00:12:34:99

run_case() { # name kernel
    local name=$1 img=$2
    timeout 170 qemu-system-x86_64 -accel $ACC -kernel "$img" -m 256 \
        -append "osum vfs nokbd nosched noproc noring3 usb usbhold usbpoll nic rndisonly nip=169.254.10.1/16 nsvc=0 nwait=0 script=sh /t/s.sh;exit" \
        -serial "file:$T/$name.txt" -display none -no-reboot \
        -monitor "unix:$T/$name.mon,server,nowait" -pidfile "$T/$name.pid" \
        -drive "file=$T/d.img,format=raw,if=ide,index=0" \
        -device qemu-xhci,id=x0 -netdev user,id=n0 \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    python3 -I tools/hotplug/monitor.py "$T/$name.mon" "$T/$name.txt" "$T/$name.plan" > "$T/$name.mon.txt" 2>&1
    local mrc=$?
    for i in $(seq 1 45); do grep -aq '==ALIVE==' "$T/$name.txt" && break; sleep 2; done
    [ -f "$T/$name.pid" ] && kill "$(cat "$T/$name.pid")" 2>/dev/null; wait 2>/dev/null
    tr -cd '\11\12\15\40-\176' < "$T/$name.txt" > "$T/$name.klar"
    return $mrc
}

printf 'aufzeile k17: hold\nstecke stk1 %s\naufzeile uevent: 1 add\nziehe stk1\naufzeile uevent: 2 remove\naufzeile k17: free\n' "$T/stick.img" > "$T/stick.plan"
printf 'aufzeile k17: hold\nmonitor device_add usb-net,id=devn1,netdev=n0,mac=%s\naufzeile uevent: 1 add\nziehe n1\naufzeile uevent: 2 remove\nmonitor device_add usb-net,id=devn2,netdev=n0,mac=%s\naufzeile uevent: 3 add\naufzeile k17: free\n' "$MAC" "$MAC" > "$T/nic.plan"

expect_line() { # file regex text
    grep -aEq "$2" "$1" && ok "$3" || bad "$3 (no match: $2)"
}
SEQ='uevent: [0-9]+ (add|remove) class=[a-z-]+ bus=usb ids=[0-9a-f]{4}:[0-9a-f]{4} path=[0-9a-f]{8} arg=[0-9]+ tick=[0-9]+'

run_case stick "$KIMG"; H="$T/stick.klar"
[ "$(grep -aEc "^$SEQ" "$H")" -ge 2 ] && ok "stick: serial event lines well-formed" || bad "stick: event lines malformed or missing"
expect_line "$H" '^uevent: 1 add class=block bus=usb ids=[0-9a-f]{4}:[0-9a-f]{4}' "stick: event 1 is add class=block"
expect_line "$H" '^uevent: 2 remove class=block bus=usb ids=[0-9a-f]{4}:[0-9a-f]{4}' "stick: event 2 is remove class=block"
expect_line "$H" '^uevent total=2$' "stick: /proc/uevent shows total=2"
[ "$(grep -aEc '^uevent: [12] (add|remove) class=block' "$H")" -ge 4 ] && ok "stick: /proc/uevent repeats both lines" || bad "stick: /proc/uevent lines missing"
grep -aq 'wechsel: ' "$H" && ok "stick: media table still saw it" || bad "stick: no wechsel line"
grep -aiq 'panic\|exception\|#PF\|#GP\|#UD' "$H" && bad "stick: panic/exception" || ok "stick: no panic/exception"

run_case nic "$KIMG"; H="$T/nic.klar"
expect_line "$H" '^uevent: 1 add class=net-eth bus=usb ids=[0-9a-f]{4}:[0-9a-f]{4}' "nic: event 1 is add class=net-eth"
expect_line "$H" '^uevent: 2 remove class=net-eth bus=usb' "nic: event 2 is remove class=net-eth"
expect_line "$H" '^uevent: 3 add class=net-eth bus=usb' "nic: event 3 is add class=net-eth after replug"
expect_line "$H" '^uevent total=3$' "nic: /proc/uevent shows total=3"
a=$(grep -aE '^uevent: [123] ' "$H" | sed -n '1p' | grep -ao 'ids=[0-9a-f:]*'); b=$(grep -aE '^uevent: 3 add' "$H" | head -1 | grep -ao 'ids=[0-9a-f:]*')
[ -n "$a" ] && [ "$a" = "$b" ] && ok "nic: same ids on add and re-add ($a)" || bad "nic: ids differ ($a vs $b)"
[ "$(grep -ac 'usbnet: detached' "$H")" = 1 ] && ok "nic: usbnet detached once (old path intact)" || bad "nic: detached count $(grep -ac 'usbnet: detached' "$H")"
grep -aiq 'panic\|exception\|#PF\|#GP\|#UD' "$H" && bad "nic: panic/exception" || ok "nic: no panic/exception"

if [ -n "$OLDIMG" ]; then
    run_case oldnic "$OLDIMG" || true
    grep -aq '^uevent' "$T/oldnic.klar" && bad "counter-proof: old kernel printed uevent lines" || ok "counter-proof: old kernel prints no uevent line"
fi

echo "UEVENTS: $pass ok, $fail fail"
[ "$fail" -gt 0 ] && exit 1
exit 0
