#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$HERE"
export FIRNLIB="$HERE/lib"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
command -v qemu-system-x86_64 >/dev/null || { echo "USBEVENTS: skipped, no qemu"; exit 0; }
bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
bash tools/sync/build.sh "$T/bin" 0 sh sleep echo > "$T/b.txt" 2>&1 || { tail "$T/b.txt"; exit 1; }
KIMG="${1:-}"
if [ -z "$KIMG" ]; then
    ./tools/build-kernel.sh "$T/k.img" --stufe 0 > "$T/k.txt" 2>&1 || { tail "$T/k.txt"; exit 1; }
    KIMG="$T/k.img"
fi
printf 'echo ==START==\nsleep 1\necho ==ALIVE==\n' > "$T/s.sh"
bash tools/mkfsfi/mkfs.sh build "$T/d.img" 8000 /bin/ /t/ /etc/ \
    /bin/sh="$T/bin/sh.elf" /bin/sleep="$T/bin/sleep.elf" /bin/echo="$T/bin/echo.elf" /t/s.sh="$T/s.sh" > "$T/mkfs.txt" 2>&1 || { tail "$T/mkfs.txt"; exit 1; }
ACC=tcg; [ -w /dev/kvm ] && ACC=kvm
MAC=52:54:00:12:34:99

run_case() { # name extra-words plan(yes|no)
    local name=$1 words=$2 plan=$3
    timeout 170 qemu-system-x86_64 -accel $ACC -kernel "$KIMG" -m 256 \
        -append "osum nokbd nosched noproc nofs noring3 usb usbhold usbpoll nic rndisonly nip=169.254.10.1/16 nsvc=0 nwait=0 $words script=sh /t/s.sh;exit" \
        -serial "file:$T/$name.txt" -display none -no-reboot \
        -monitor "unix:$T/$name.mon,server,nowait" -pidfile "$T/$name.pid" \
        -drive "file=$T/d.img,format=raw,if=ide,index=0" \
        -device qemu-xhci,id=x0 -netdev user,id=n0 -device "usb-net,id=devn1,netdev=n0,mac=$MAC" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$T/$name.qerr" 2>&1 &
    if [ "$plan" = yes ]; then
        printf 'aufzeile k17: hold\nwarte 2\nziehe n1\nwarte 1\nmonitor device_add usb-net,id=devn2,netdev=n0,mac=%s\nwarte 3\nmonitor device_del devn2\nwarte 1\nmonitor device_add usb-net,id=devn3,netdev=n0,mac=%s\naufzeile k17: free\n' "$MAC" "$MAC" > "$T/$name.plan"
        python3 -I tools/hotplug/monitor.py "$T/$name.mon" "$T/$name.txt" "$T/$name.plan" > "$T/$name.mon.txt" 2>&1 || { bad "$name: monitor plan"; tail -3 "$T/$name.mon.txt"; }
    fi
    for i in $(seq 1 60); do grep -aq '==ALIVE==' "$T/$name.txt" && break; sleep 2; done
    [ -f "$T/$name.pid" ] && kill "$(cat "$T/$name.pid")" 2>/dev/null; wait 2>/dev/null
    [ -f "$T/$name.txt" ] || { bad "$name: no serial file"; head -c 300 "$T/$name.qerr"; }
    tr -cd '\11\12\15\40-\176' < "$T/$name.txt" > "$T/$name.klar" 2>/dev/null
}
cnt() { grep -ac "$2" "$T/$1.klar"; }

if [ "${USBEVENTS_SKIP_CYCLE:-0}" != 1 ]; then run_case cycle "" yes; fi
H=cycle
[ "$(cnt $H 'usb: ev PSC-IRQ')" -ge 2 ] && ok "cycle: PSC-IRQ lines" || bad "cycle: PSC-IRQ lines $(cnt $H 'usb: ev PSC-IRQ')"
[ "$(cnt $H 'usb: ev PSC-POLL')" -ge 2 ] && ok "cycle: PSC-POLL lines" || bad "cycle: PSC-POLL lines"
[ "$(cnt $H 'usb: ev ATTACH-BEGIN')" -ge 3 ] && ok "cycle: ATTACH-BEGIN x3" || bad "cycle: ATTACH-BEGIN $(cnt $H 'usb: ev ATTACH-BEGIN')"
[ "$(cnt $H 'usb: ev ATTACH-OK')" -ge 3 ] && ok "cycle: ATTACH-OK x3" || bad "cycle: ATTACH-OK $(cnt $H 'usb: ev ATTACH-OK')"
[ "$(cnt $H 'usb: ev DETACH')" -ge 2 ] && ok "cycle: DETACH x2" || bad "cycle: DETACH $(cnt $H 'usb: ev DETACH')"
[ "$(cnt $H 'usb: ev CTRL-LOST')" = 0 ] && ok "cycle: no false controller loss" || bad "cycle: false CTRL-LOST"
grep -aq '==ALIVE==' "$T/$H.klar" && ok "cycle: script reached the end" || bad "cycle: script did not finish"

for mode in usbloss usblossff; do
    run_case $mode "$mode" no
    H=$mode
    [ "$(cnt $H 'usb: ev CTRL-LOST')" -ge 1 ] && ok "$mode: CTRL-LOST logged" || bad "$mode: no CTRL-LOST"
    [ "$(cnt $H 'usb: ev CTRL-RESUME.*a=0x0*1....$')" -ge 1 ] && ok "$mode: CTRL-RESUME ok" || bad "$mode: no successful CTRL-RESUME"
    [ "$(cnt $H 'usb: port=.*driver=rndis')" -ge 2 ] && ok "$mode: device bound again after resume" || bad "$mode: no rebind"
    grep -aq '==ALIVE==' "$T/$H.klar" && ok "$mode: script reached the end" || bad "$mode: script did not finish"
done

run_case noevr "nousbevr usbloss" no
[ "$(cnt noevr 'usb: ev ')" = 0 ] && ok "noevr: no ring lines (negative control)" || bad "noevr: ring lines present"
grep -aq '==ALIVE==' "$T/noevr.klar" && ok "noevr: script reached the end" || bad "noevr: script did not finish"

run_case nowatch "nousbwatch usbloss" no
[ "$(cnt nowatch 'usb: ev CTRL-LOST')" = 0 ] && ok "nowatch: no CTRL-LOST (negative control)" || bad "nowatch: CTRL-LOST present"
[ "$(cnt nowatch 'usb: port=.*driver=rndis')" -ge 2 ] && bad "nowatch: device rebound without watcher" || ok "nowatch: no rebind without watcher"

for c in cycle usbloss usblossff noevr nowatch; do
    [ -f "$T/$c.klar" ] || continue
    grep -aiq 'panic\|exception\|#PF\|#GP\|#UD' "$T/$c.klar" && bad "$c: panic/exception" || ok "$c: no panic/exception"
done

echo "USBEVENTS: $pass ok, $fail fail"
[ "$fail" -gt 0 ] && exit 1
exit 0
