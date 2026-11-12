#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$HERE"
. tools/lib/firnenv.sh
export FIRNLIB="$HERE/lib"
T=${UPHEALTH_WORK:-$(mktemp -d)}
mkdir -p "$T"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
command -v qemu-system-x86_64 >/dev/null || { echo "UPHEALTH: skipped, no qemu"; exit 0; }
CASES="${*:-stay fallback control}"
trap 'for f in "$T"/*.pid; do [ -f "$f" ] && kill "$(cat "$f")" 2>/dev/null; done; [ -n "${UPHEALTH_WORK:-}" ] || rm -rf "$T"' EXIT
if [ ! -f "$T/k.img" ] || [ ! -f "$T/bin/sh.elf" ]; then
    bash tools/sync/build.sh "$T/bin" 0 sh sleep echo dhcp cat > "$T/b.txt" 2>&1 || { tail "$T/b.txt"; exit 1; }
    "$FIRNC" -c --profile=app -o "$T/netcheck.o" kernel/app/netcheck.fi > "$T/app.txt" 2>&1 || { tail "$T/app.txt"; exit 1; }
    ld -T kernel/user/user.ld -o "$T/bin/netcheck.elf" "$T/netcheck.o" >> "$T/app.txt" 2>&1 || { tail "$T/app.txt"; exit 1; }
    ./tools/build-kernel.sh "$T/k.img" --stufe 0 > "$T/k.txt" 2>&1 || { tail "$T/k.txt"; exit 1; }
fi
printf 'echo ==START==\ndhcp\nnetcheck -c 14 -i 1 -b 1\nnetcheck get\ncat /proc/net/connectivity\necho ==END==\n' > "$T/s_loop.sh"
bash tools/mkfsfi/mkfs.sh build "$T/d.img" 8000 /bin/ /t/ /etc/ /var/ /var/log/ \
    /bin/sh="$T/bin/sh.elf" /bin/sleep="$T/bin/sleep.elf" /bin/echo="$T/bin/echo.elf" \
    /bin/dhcp="$T/bin/dhcp.elf" /bin/netcheck="$T/bin/netcheck.elf" /bin/cat="$T/bin/cat.elf" /proc/ \
    /t/s_loop.sh="$T/s_loop.sh" > "$T/mkfs.txt" 2>&1 || { tail "$T/mkfs.txt"; exit 1; }
ACC=tcg; [ -w /dev/kvm ] && ACC=kvm
PORT=$((49000 + ($$ % 500) * 8))

run() {
    local n=$1 words=$2 args0=$3 args1=$4 p=$PORT
    PORT=$((PORT+8))
    rm -f "$T/$n".*
    python3 -I tools/pinggw/peer.py --local "$((p+1))" --remote "$p" --log "$T/$n.peer0" --secs 150 $args0 &
    echo $! > "$T/$n.ppid0"
    python3 -I tools/pinggw/peer.py --local "$((p+3))" --remote "$((p+2))" --log "$T/$n.peer1" --secs 150 $args1 &
    echo $! > "$T/$n.ppid1"
    sleep 1
    timeout 140 qemu-system-x86_64 -accel $ACC -kernel "$T/k.img" -m 256 \
        -append "osum nokbd nosched vfs usb usbhold usbpoll nic nip=169.254.10.1/16 nsvc=0 nwait=0 $words script=sh /t/s_loop.sh;exit" \
        -serial "file:$T/$n.txt" -display none -no-reboot -pidfile "$T/$n.pid" \
        -netdev "dgram,id=n0,local.type=inet,local.host=127.0.0.1,local.port=$p,remote.type=inet,remote.host=127.0.0.1,remote.port=$((p+1))" \
        -device virtio-net-pci,netdev=n0,mac=52:54:00:aa:bb:cc \
        -netdev "dgram,id=n1,local.type=inet,local.host=127.0.0.1,local.port=$((p+2)),remote.type=inet,remote.host=127.0.0.1,remote.port=$((p+3))" \
        -device qemu-xhci,id=x0 -device usb-net,bus=x0.0,netdev=n1,mac=52:54:00:aa:bb:dd \
        -drive "file=$T/d.img,format=raw,if=ide,index=0,snapshot=on" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    local qp=$!
    bash tools/work/waitfor.sh -t 130 -i 2 pid "$qp" >/dev/null 2>&1
    kill "$qp" 2>/dev/null
    kill "$(cat "$T/$n.ppid0")" "$(cat "$T/$n.ppid1")" 2>/dev/null
    wait 2>/dev/null
    tr -cd '\11\12\15\40-\176' < "$T/$n.txt" > "$T/$n.klar"
}
chk() { grep -aq -- "$3" "$T/$1.klar" && ok "$1: $2" || bad "$1: $2 (missing: $3)"; }
nochk() { grep -aq -- "$3" "$T/$1.klar" && bad "$1: $2 (found: $3)" || ok "$1: $2"; }
panics() { grep -aiq 'panic\|exception\|#PF\|#GP\|#UD' "$T/$1.klar" && bad "$1: panic/exception in log" || ok "$1: no panic/exception"; }

for c in $CASES; do
    case "$c" in
    stay)
        run stay "" "--no-inet" ""
        chk stay "script finished" '==END=='
        chk stay "USB network attached" 'nethot: usbnet attached'
        chk stay "USB uplink has internet" 'health 1'
        chk stay "status file: USB online and default" 'usb0 online default'
        nochk stay "no switch away from a healthy uplink" 'eth0 [a-z-]* default'
        panics stay
        ;;
    fallback)
        run fallback "" "" "--no-inet"
        chk fallback "script finished" '==END=='
        chk fallback "USB network attached" 'nethot: usbnet attached'
        chk fallback "LAN has internet" 'health 1'
        chk fallback "status file: USB local-only" 'usb0 local-only'
        chk fallback "status file: LAN online and default" 'eth0 online default'
        panics fallback
        ;;
    control)
        run control "nouphealth" "" "--no-inet"
        chk control "script finished" '==END=='
        chk control "USB network attached" 'nethot: usbnet attached'
        nochk control "old logic never leaves the dead uplink" 'eth0 [a-z-]* default'
        chk control "status file: USB local-only and still default" 'usb0 local-only default'
        chk control "old logic stays without internet" 'health 4'
        panics control
        ;;
    esac
done
echo "UPHEALTH: $pass passed, $fail failed"
[ "$fail" = 0 ]
