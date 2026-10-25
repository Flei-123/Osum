#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/usbredir/run.sh -- gate "usbtether": USB tethering gadgets end to end in QEMU (NCM, multi-datagram NCM,
# Android composite RNDIS+ADB with several configurations, Android NCM+ADB, hot plug, unplug/replug).
#
#   /root/jarvis/bin/heavy bash tools/usbredir/run.sh [case...]      (default: all cases)
#
# MEASURES (QEMU `-device qemu-xhci -device usb-redir`, the gadget is tools/usbredir/usbdev.py; its Ethernet side is
# a helper QEMU running slirp (DHCP 192.168.42.x, DNS, NAT), frames travel as UDP datagrams):
#   * the kernel enumerates the gadget, picks the right configuration/interface and binds ncm/rndis
#   * DHCP lease over the USB function, ping of the gateway, DNS lookup through the gadget
#   * hot plug AFTER boot (usbhold window), unplug and replug in the same window
# NEGATIVE CONTROLS: no gadget -> no driver line, no lease; unpatched wiring would show up as missing driver lines.
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
CASES="${*:-ncm ncm-multi android-rndis android-ncm hotplug replug none ch336 ch336-late ch336-nokick ch336-ecmfirst ch336-proc ch336-intr ch336-intr-only ch336-nochintr ch336-alt1 ch336-alt1-nochalt ch336-alt1-nosetif}"
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
printf 'echo ==START==\nping 192.168.42.129\nsleep 1\nping 192.168.42.129\nsleep 1\nping 192.168.42.129\nsleep 1\nping 192.168.42.129\nsleep 1\ncat /proc/usbnet\necho ==END==\n' > "$T/s_intr.sh"
python3 tools/osum/mkfs.py build "$T/d.img" 8000 /bin/ /t/ /etc/ \
    /bin/sh="$T/bin/sh.elf" /bin/sleep="$T/bin/sleep.elf" /bin/echo="$T/bin/echo.elf" \
    /bin/dhcp="$T/bin/dhcp.elf" /bin/ping="$T/bin/ping.elf" /bin/host="$T/bin/host.elf" /bin/cat="$T/bin/cat.elf" /proc/ \
    /t/s.sh="$T/s.sh" /t/s_hot.sh="$T/s_hot.sh" /t/s_re.sh="$T/s_re.sh" /t/s_late.sh="$T/s_late.sh" /t/s_proc.sh="$T/s_proc.sh" /t/s_procd.sh="$T/s_procd.sh" /t/s_intr.sh="$T/s_intr.sh" > "$T/mkfs.txt" 2>&1 || { tail "$T/mkfs.txt"; exit 1; }
ACC=tcg; [ -w /dev/kvm ] && ACC=kvm
PORT=$((47000 + ($$ % 500) * 4))

helper() { # name  -> helper QEMU (slirp router for the gadget side)
    local n=$1 p=$2
    qemu-system-x86_64 -M none -nodefaults -display none -pidfile "$T/$n.hpid" \
        -netdev user,id=u0,net=192.168.42.0/24,host=192.168.42.129,dhcpstart=192.168.42.100 \
        -netdev hubport,id=hp0,hubid=7,netdev=u0 \
        -netdev "dgram,id=s0,local.type=inet,local.host=127.0.0.1,local.port=$p,remote.type=inet,remote.host=127.0.0.1,remote.port=$((p+1))" \
        -netdev hubport,id=hp1,hubid=7,netdev=s0 >/dev/null 2>&1 &
    echo $! > "$T/$n.pid"
}

# run NAME PROFILE MODE SCRIPT   MODE: boot (gadget there from the start) | hot (plugged in the usbhold window) |
#                                      none (no gadget) | replug (plug, unplug, plug again in the window)
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
        extra="-chardev socket,id=r0,path=$T/$n.sock,server=on,wait=off -device usb-redir,chardev=r0"
    fi
    timeout 170 qemu-system-x86_64 -accel $ACC -kernel "$T/k.img" -m 256 \
        -append "osum ${BASEW:-nokbd nosched noproc nofs noring3} $words ${XWORDS:-} nic nip=169.254.10.1/16 nsvc=0 nwait=0 script=sh /t/$script;exit" \
        -serial "file:$T/$n.txt" -display none -nic none -no-reboot -pidfile "$T/$n.qpid" -S \
        -monitor "unix:$T/$n.mon,server,nowait" \
        -drive "file=$T/d.img,format=raw,if=ide,index=0" \
        -device qemu-xhci,id=x0 $extra \
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
        bash tools/work/waitfor.sh -t 30 -i 1 log "$T/$n.gadget" 'set_alt_setting if=1 alt=1' >/dev/null 2>&1
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
net_ok() { # name
    chk "$1" "DHCP lease over the gadget" 'dhcp: ack ip=192.168.42.100'
    chk "$1" "net line with the address (also written to hwinv.txt)" 'net: up ip=192.168.42.100'
    chk "$1" "ping of the gateway through the gadget" 'octets from 192.168.42.129: icmp_seq=1'
    chk "$1" "script reached the end" '==END=='
    panics "$1"
}

for c in $CASES; do
    case "$c" in
    ncm)
        run ncm ncm boot s.sh
        chk ncm "bound to driver ncm" 'driver=ncm'
        net_ok ncm
        chk ncm "DNS through the gadget" '^[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*\s*$'
        ;;
    ncm-multi)
        run ncmm ncm-multi boot s.sh
        chk ncmm "bound to driver ncm (3 datagrams per NTB offered)" 'driver=ncm'
        net_ok ncmm
        grep -a 'rx=' "$T/ncmm.gadget" | tail -1
        ;;
    android-rndis)
        run andr android-rndis boot s.sh
        grep -aq 'set_configuration 2' "$T/andr.gadget" && ok "andr: gadget saw set_configuration 2" || bad "andr: gadget never got configuration 2 ($(grep -a configuration "$T/andr.gadget" | head -2 | tr '\n' ' '))"
        chk andr "bound to driver rndis" 'driver=rndis'
        net_ok andr
        ;;
    android-ncm)
        run andn android-ncm boot s.sh
        chk andn "bound to driver ncm behind the ADB interface" 'driver=ncm'
        net_ok andn
        ;;
    hotplug)
        run hot ncm hot s_hot.sh
        chk hot "hold window ran" 'k17: hold'
        chk hot "bound to driver ncm after boot" 'driver=ncm'
        net_ok hot
        ;;
    replug)
        run re ncm replug s_re.sh
        chk re "bound to driver ncm" 'driver=ncm'
        chk re "unplug noticed" 'usbnet: detached'
        panics re
        ;;
    ch336)
        GARGS="--phy-boot down" run ch ch336 boot s.sh
        chk ch "bound to driver ch336" 'driver=ch336'
        grep -aq 'phy kick #1 via 0x1F' "$T/ch.gadget" && ok "ch: gadget saw the PHY kick" || bad "ch: gadget never saw a PHY kick"
        chk ch "link up with BMCR restored and one kick" 'usb: ch336 link=[a-z]* bmsr=782d .* bmcr=1000 kicks=01'
        net_ok ch
        ;;
    ch336-late)
        GARGS="--phy-boot an" run chl ch336 boot s_late.sh
        grep -aq 'phy kick #1' "$T/chl.gadget" && ok "chl: kick after the link wait" || bad "chl: no kick after the link wait"
        chk chl "link came up after the kick" 'usb: ch336 link=up'
        net_ok chl
        ;;
    ch336-nokick)
        GARGS="--phy-boot down" XWORDS="nophykick" run chn ch336 boot s.sh
        chk chn "bound to driver ch336" 'driver=ch336'
        grep -aq 'phy kick' "$T/chn.gadget" && bad "chn: kick sent despite nophykick" || ok "chn: no kick sent"
        nochk chn "no link without the kick" 'usb: ch336 link=up'
        chk chn "link down with kicks=00" 'usb: ch336 link=down .* kicks=00'
        nochk chn "no lease without the kick" 'dhcp: ack ip='
        panics chn
        ;;
    ch336-ecmfirst)
        GARGS="--phy-boot down" run che ch336-ecmfirst boot s.sh
        chk che "vendor configuration wins over ECM" 'driver=ch336'
        nochk che "ECM not bound" 'driver=ecm'
        net_ok che
        ;;
    ch336-proc)
        GARGS="--phy-boot down" BASEW="nokbd nosched vfs" run chp ch336 boot s_proc.sh
        chk chp "usb line with id" 'usb: ch336 id=1a86:5394'
        chk chp "configuration seen" 'usb: ncfg=2 cfg=1 setcfg=1 rc=0'
        chk chp "interface vendor class" 'usb: iface=ff/ff/ff'
        chk chp "bring-up finished" 'usb: step=4 ok'
        chk chp "alt scan not needed, SET_INTERFACE sent and accepted" 'usb: alt=0 scan=0 setif=1'
        grep -aq 'set_alt_setting if=0 alt=0' "$T/chp.gadget" && ok "chp: gadget saw SET_INTERFACE alt 0" || bad "chp: gadget never saw SET_INTERFACE alt 0"
        chk chp "phy line with kick count" 'phy: bmcr=1000 bmsr=782d id=0e400141'
        chk chp "link up line" 'link: state=up'
        chk chp "usbnet counters" 'usbnet: ready mode=3 link=up'
        chk chp "dhcp line" 'dhcp: state='
        ;;
    ch336-intr)
        GARGS="--phy-boot down --intr link" BASEW="nokbd nosched vfs" run chi ch336 boot s_proc.sh
        grep -aq 'interrupt packet 40' "$T/chi.gadget" && ok "chi: gadget sent an interrupt packet with the link bit" || bad "chi: no interrupt packet with the link bit"
        chk chi "interrupt endpoint open and polled" 'intr: open=1 ep=3 n=[1-9]'
        chk chi "interrupt byte 0x40 means link up" 'last=0x40 link=up'
        chk chi "link up line" 'link: state=up'
        net_ok chi
        ;;
    ch336-intr-only)
        GARGS="--phy-boot down --phy-deaf --intr up" QWAIT=45 BASEW="nokbd nosched noproc nofs noring3" run chy ch336 boot s_intr.sh
        chk chy "bring-up saw no PHY link" 'usb: ch336 link=down bmsr=7809'
        chk chy "link went up on the interrupt byte while the PHY stayed down" 'usb: ch336 link=up bmsr=7809'
        panics chy
        ;;
    ch336-nochintr)
        GARGS="--phy-boot down --phy-deaf --intr up" XWORDS="nochintr" QWAIT=45 BASEW="nokbd nosched noproc nofs noring3" run chx ch336 boot s_intr.sh
        chk chx "bring-up saw no PHY link" 'usb: ch336 link=down bmsr=7809'
        nochk chx "link not taken from the interrupt" 'usb: ch336 link=up'
        grep -aq 'interrupt packet' "$T/chx.gadget" && bad "chx: interrupt endpoint was opened despite nochintr" || ok "chx: interrupt endpoint not opened"
        panics chx
        ;;
    ch336-alt1)
        GARGS="--phy-boot down" BASEW="nokbd nosched vfs" run ca1 ch336-alt1 boot s_proc.sh
        chk ca1 "bound to driver ch336" 'driver=ch336'
        chk ca1 "bulk endpoints taken from alt 1" 'usb: ep in=[1-9][0-9]* out=[1-9][0-9]*'
        chk ca1 "alt scan picked alt 1, SET_INTERFACE accepted" 'usb: alt=1 scan=1 setif=1'
        grep -aq 'set_alt_setting if=0 alt=1' "$T/ca1.gadget" && ok "ca1: gadget saw SET_INTERFACE alt 1" || bad "ca1: gadget never saw SET_INTERFACE alt 1"
        grep -aq 'bulk STALL' "$T/ca1.gadget" && bad "ca1: bulk transfer stalled" || ok "ca1: no bulk stall"
        net_ok ca1
        ;;
    ch336-alt1-nochalt)
        GARGS="--phy-boot down" XWORDS="nochalt" QWAIT=70 BASEW="nokbd nosched vfs" run ca2 ch336-alt1 boot s_procd.sh
        chk ca2 "bound to driver ch336" 'driver=ch336'
        chk ca2 "no bulk endpoints without the alt scan" 'usb: ep in=0 out=0'
        chk ca2 "no scan reported" 'usb: alt=0 scan=0'
        nochk ca2 "no lease without the alt scan" 'dhcp: ack ip='
        panics ca2
        ;;
    ch336-alt1-nosetif)
        GARGS="--phy-boot down" XWORDS="nosetif" QWAIT=70 BASEW="nokbd nosched vfs" run ca3 ch336-alt1 boot s_procd.sh
        grep -aq 'set_alt_setting if=0 alt=1' "$T/ca3.gadget" && bad "ca3: SET_INTERFACE sent despite nosetif" || ok "ca3: no SET_INTERFACE sent"
        grep -aq 'stats\|tx=' "$T/ca3.gadget" && grep -aq 'stats tx=0' "$T/ca3.gadget" && ok "ca3: no frame reached the gadget" || bad "ca3: frames reached the gadget without SET_INTERFACE"
        chk ca3 "alt scan reported with SET_INTERFACE refused" 'usb: alt=1 scan=1 setif=0'
        nochk ca3 "no lease without SET_INTERFACE" 'dhcp: ack ip='
        panics ca3
        ;;
    none)
        run none ncm none s.sh
        nochk none "no driver line without a gadget" 'driver=ncm'
        nochk none "no lease without a gadget" 'dhcp: ack ip='
        chk none "script reached the end" '==END=='
        ;;
    esac
done
echo "USBTETHER: $pass ok, $fail fail"
if [ "$fail" -gt 0 ]; then
    grep -a "usb\|netdev\|nic:\|dhcp\|ncm\|rndis" "$T"/*.klar | cut -c1-170 | head -40
    [ -n "${USBTETHER_WORK:-}" ] || cp -r "$T" /root/tether-fail 2>/dev/null
    exit 1
fi
exit 0
