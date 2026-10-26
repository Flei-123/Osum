#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$HERE"
export FIRNLIB="$HERE/lib"
T=${USBTETHER_WORK:-$(mktemp -d)}
[ -n "${USBTETHER_WORK:-}" ] || trap 'rm -rf "$T"' EXIT
mkdir -p "$T"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
command -v qemu-system-x86_64 >/dev/null || { echo "USBTETHER: skipped, no qemu"; exit 0; }
cleanup_pids() { for f in "$T"/*.pid; do [ -f "$f" ] && kill "$(cat "$f")" 2>/dev/null; done; pkill -P $$ 2>/dev/null; true; }
trap 'cleanup_pids; [ -n "${USBTETHER_WORK:-}" ] || rm -rf "$T"' EXIT
if [ ! -f "$T/k.img" ] || [ ! -f "$T/bin/dhcp.elf" ]; then
    bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
    bash tools/sync/build.sh "$T/bin" 0 sh sleep echo dhcp ping host cat > "$T/b.txt" 2>&1 || { tail "$T/b.txt"; exit 1; }
    ./tools/build-kernel.sh "$T/k.img" --stufe 0 > "$T/k.txt" 2>&1 || { tail "$T/k.txt"; exit 1; }
fi
printf 'echo ==START==\ndhcp\nping 192.168.42.129\nhost example.org\nsleep 2\necho ==END==\n' > "$T/s.sh"
printf 'echo ==START==\nsleep 1\ndhcp\nping 192.168.42.129\nhost example.org\nsleep 2\necho ==END==\n' > "$T/s_hot.sh"
printf 'echo ==START==\ndhcp\nping 192.168.42.129\nsleep 1\necho ==END==\n' > "$T/s_re.sh"
printf 'echo ==START==\nping 192.168.42.129\nping 192.168.42.129\nping 192.168.42.129\nping 192.168.42.129\ndhcp\nping 192.168.42.129\nsleep 1\necho ==END==\n' > "$T/s_late.sh"
printf 'echo ==START==\ndhcp\nping 192.168.42.129\nsleep 2\ncat /proc/usbnet\necho ==END==\n' > "$T/s_proc.sh"
printf 'echo ==START==\nsleep 3\ncat /proc/usbnet\ndhcp\necho ==END==\n' > "$T/s_procd.sh"
printf 'echo ==START==\nsleep 2\ncat /proc/usbsum\necho ==END==\n' > "$T/s_sum.sh"
printf 'echo ==START==\nsleep 12\ncat /proc/usbnet\ncat /proc/usbsum\necho ==END==\n' > "$T/s_hubhot.sh"
printf 'echo ==START==\nping 192.168.42.129\nsleep 1\nping 192.168.42.129\nsleep 1\nping 192.168.42.129\nsleep 1\nping 192.168.42.129\nsleep 1\ncat /proc/usbnet\necho ==END==\n' > "$T/s_intr.sh"
python3 tools/osum/mkfs.py build "$T/d.img" 8000 /bin/ /t/ /etc/ \
    /bin/sh="$T/bin/sh.elf" /bin/sleep="$T/bin/sleep.elf" /bin/echo="$T/bin/echo.elf" \
    /bin/dhcp="$T/bin/dhcp.elf" /bin/ping="$T/bin/ping.elf" /bin/host="$T/bin/host.elf" /bin/cat="$T/bin/cat.elf" /proc/ \
    /t/s.sh="$T/s.sh" /t/s_hot.sh="$T/s_hot.sh" /t/s_re.sh="$T/s_re.sh" /t/s_late.sh="$T/s_late.sh" /t/s_proc.sh="$T/s_proc.sh" /t/s_procd.sh="$T/s_procd.sh" /t/s_intr.sh="$T/s_intr.sh" /t/s_sum.sh="$T/s_sum.sh" /t/s_hubhot.sh="$T/s_hubhot.sh" > "$T/mkfs.txt" 2>&1 || { tail "$T/mkfs.txt"; exit 1; }
ACC=tcg; [ -w /dev/kvm ] && ACC=kvm
PORT=$((47000 + ($$ % 500) * 4))

helper() {
    local n=$1 p=$2
    qemu-system-x86_64 -M none -nodefaults -display none -pidfile "$T/$n.hpid" \
        -netdev user,id=u0,net=192.168.42.0/24,host=192.168.42.129,dhcpstart=192.168.42.100 \
        -netdev hubport,id=hp0,hubid=7,netdev=u0 \
        -netdev "dgram,id=s0,local.type=inet,local.host=127.0.0.1,local.port=$p,remote.type=inet,remote.host=127.0.0.1,remote.port=$((p+1))" \
        -netdev hubport,id=hp1,hubid=7,netdev=s0 >/dev/null 2>&1 &
    echo $! > "$T/$n.pid"
}

run() {
    local n=$1 prof=$2 mode=$3 script=$4 p=$PORT
    PORT=$((PORT+4))
    rm -f "$T/$n".* 
    local extra="" words="usb usbpoll"
    [ "$mode" = hot ] || [ "$mode" = replug ] && words="usb usbhold usbpoll"
    if [ "$mode" != none ]; then
        helper "$n" "$p"
        sleep 1
        local trig="--trigger $T/$n.trig"
        [ "$mode" = boot ] && : > "$T/$n.trig"
        python3 -I tools/usbredir/usbdev.py --sock "$T/$n.sock" --profile "$prof" --net-local $((p+1)) --net-remote "$p" \
            $trig --unplug "$T/$n.unplug" --log "$T/$n.gadget" --max-secs 200 ${GARGS:-} &
        echo $! > "$T/$n.gpid"
        extra="-chardev socket,id=r0,path=$T/$n.sock,server=on,wait=off -device usb-redir,chardev=r0${REDIR_BUS:+,bus=$REDIR_BUS}"
        [ -n "${BEHIND_HUB:-}" ] && extra="-device usb-hub,bus=x0.0,port=1,id=h0 -chardev socket,id=r0,path=$T/$n.sock,server=on,wait=off -device usb-redir,chardev=r0,bus=x0.0,port=1.2"
    fi
    timeout 170 qemu-system-x86_64 -accel $ACC -kernel "$T/k.img" -m 256 \
        -append "osum ${BASEW:-nokbd nosched noproc nofs noring3} $words ${XWORDS:-} nic nip=169.254.10.1/16 nsvc=0 nwait=0 script=sh /t/$script;exit" \
        -serial "file:$T/$n.txt" -display none -nic none -no-reboot -pidfile "$T/$n.qpid" -S \
        -monitor "unix:$T/$n.mon,server,nowait" \
        -drive "file=$T/d.img,format=raw,if=ide,index=0" \
        -device qemu-xhci,id=x0 ${XHCI2:-} $extra ${XQEMU:-} \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    local qp=$!
    bash tools/work/waitfor.sh -t 20 -i 1 file "$T/$n.mon" >/dev/null 2>&1
    if [ "$mode" = boot ]; then
        bash tools/work/waitfor.sh -t 20 -i 1 log "$T/$n.gadget" 'device_connect' >/dev/null 2>&1
        sleep 1
    fi
    python3 -I -c "import socket,sys,time;s=socket.socket(socket.AF_UNIX);s.connect(sys.argv[1]);time.sleep(0.3);s.sendall(b'cont\\n');time.sleep(0.5)" "$T/$n.mon"
    if [ "$mode" = hot ]; then
        bash tools/work/waitfor.sh -t 90 -i 1 log "$T/$n.txt" 'k17: hold' >/dev/null 2>&1
        : > "$T/$n.trig"
    elif [ "$mode" = replug ]; then
        bash tools/work/waitfor.sh -t 90 -i 1 log "$T/$n.txt" 'k17: hold' >/dev/null 2>&1
        : > "$T/$n.trig"
        bash tools/work/waitfor.sh -t 30 -i 1 log "$T/$n.gadget" "${REPLUG_WAIT:-set_alt_setting if=1 alt=1}" >/dev/null 2>&1
        sleep 2
        : > "$T/$n.unplug"
    fi
    bash tools/work/waitfor.sh -t ${QWAIT:-160} -i 2 pid "$qp" >/dev/null 2>&1
    kill "$qp" 2>/dev/null
    [ -f "$T/$n.hpid" ] && kill "$(cat "$T/$n.hpid")" 2>/dev/null
    [ -f "$T/$n.gpid" ] && kill "$(cat "$T/$n.gpid")" 2>/dev/null
    wait 2>/dev/null
    tr -cd '\11\12\15\40-\176' < "$T/$n.txt" > "$T/$n.klar"
}
chk() { grep -aq -- "$3" "$T/$1.klar" && ok "$1: $2" || bad "$1: $2 (missing: $3)"; }
nochk() { grep -aq -- "$3" "$T/$1.klar" && bad "$1: $2 (found: $3)" || ok "$1: $2"; }
panics() { grep -aiq 'panic\|exception\|#PF\|#GP\|#UD' "$T/$1.klar" && bad "$1: panic/exception in log" || ok "$1: no panic/exception"; }
net_ok() {
    chk "$1" "DHCP lease over the gadget" 'dhcp: ack ip=192.168.42.100'
    chk "$1" "net line with the address (also written to hwinv.txt)" 'net: up ip=192.168.42.100'
    chk "$1" "ping of the gateway through the gadget" 'octets from 192.168.42.129: icmp_seq=1'
    chk "$1" "script reached the end" '==END=='
    panics "$1"
}

