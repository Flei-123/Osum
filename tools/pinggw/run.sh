#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/pinggw/run.sh -- gate "pinggw": ping to an off-link address goes to the gateway MAC.
#
#   /root/jarvis/bin/heavy bash tools/pinggw/run.sh [case...]      (default: all cases)
#
# Peer (tools/pinggw/peer.py) = home router on 192.168.1.0/24: DHCP (mask/router/dns), ARP only for 192.168.1.1,
# ICMP echo reply for ANY destination when the frame is addressed to the gateway MAC.
#   dhcp      lease -> ping 1.1.1.1 and 8.8.8.8 answered via the gateway; /proc/usbnet shows mask, gw mac, route, arp
#   storm     unanswered ARP target, ping -c 12: ARP requests on the wire stay <= 30 (counter-proof stormopen: noarpgap word, > 100)
#   blocksend blocking ICMP socket to an unanswered target: sendto gives up after ~3 s, ARP <= 12 (counter-proof blocksendopen: noarpgap, > 100)
#   wrongmask static mask /0 (negative control) -> 1.1.1.1 looks on-link, ARP asked directly, no answer, loss reported
set -uo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$HERE"
export FIRNLIB="$HERE/lib"
T=${PINGGW_WORK:-$(mktemp -d)}
mkdir -p "$T"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
command -v qemu-system-x86_64 >/dev/null || { echo "PINGGW: skipped, no qemu"; exit 0; }
CASES="${*:-dhcp wrongmask nogw storm stormopen blocksend blocksendopen}"
trap 'for f in "$T"/*.pid; do [ -f "$f" ] && kill "$(cat "$f")" 2>/dev/null; done; [ -n "${PINGGW_WORK:-}" ] || rm -rf "$T"' EXIT
if [ ! -f "$T/k.img" ] || [ ! -f "$T/bin/ping.elf" ]; then
    bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
    bash tools/sync/build.sh "$T/bin" 0 sh sleep echo dhcp ping cat > "$T/b.txt" 2>&1 || { tail "$T/b.txt"; exit 1; }
    ./tools/build-kernel.sh "$T/k.img" --stufe 0 > "$T/k.txt" 2>&1 || { tail "$T/k.txt"; exit 1; }
fi
printf 'echo ==START==\ndhcp\nping -c 2 1.1.1.1\nping -c 2 8.8.8.8\nsleep 1\ncat /proc/usbnet\necho ==END==\n' > "$T/s_dhcp.sh"
printf 'echo ==START==\nping -c 2 1.1.1.1\nsleep 1\ncat /proc/usbnet\necho ==END==\n' > "$T/s_static.sh"
printf 'echo ==START==\nping -c 12 1.1.1.1\ncat /proc/usbnet\necho ==END==\n' > "$T/s_storm.sh"
printf 'echo ==START==\nping -b -c 1 1.1.1.1\necho ==MID==\ncat /proc/usbnet\necho ==END==\n' > "$T/s_block.sh"
python3 tools/osum/mkfs.py build "$T/d.img" 8000 /bin/ /t/ /etc/ \
    /bin/sh="$T/bin/sh.elf" /bin/sleep="$T/bin/sleep.elf" /bin/echo="$T/bin/echo.elf" \
    /bin/dhcp="$T/bin/dhcp.elf" /bin/ping="$T/bin/ping.elf" /bin/cat="$T/bin/cat.elf" /proc/ \
    /t/s_dhcp.sh="$T/s_dhcp.sh" /t/s_static.sh="$T/s_static.sh" /t/s_storm.sh="$T/s_storm.sh" /t/s_block.sh="$T/s_block.sh" > "$T/mkfs.txt" 2>&1 || { tail "$T/mkfs.txt"; exit 1; }
ACC=tcg; [ -w /dev/kvm ] && ACC=kvm
PORT=$((48000 + ($$ % 500) * 4))

run() { # name script nipword peer-args
    local n=$1 script=$2 nip=$3 pargs=$4 p=$PORT
    PORT=$((PORT+4))
    rm -f "$T/$n".*
    python3 -I tools/pinggw/peer.py --local "$((p+1))" --remote "$p" --log "$T/$n.peer" --secs 150 $pargs &
    echo $! > "$T/$n.ppid"
    sleep 1
    timeout 140 qemu-system-x86_64 -accel $ACC -kernel "$T/k.img" -m 256 \
        -append "osum nokbd nosched vfs usb usbpoll nic $nip nsvc=0 nwait=0 script=sh /t/$script;exit" \
        -serial "file:$T/$n.txt" -display none -no-reboot -pidfile "$T/$n.pid" \
        -netdev "dgram,id=n0,local.type=inet,local.host=127.0.0.1,local.port=$p,remote.type=inet,remote.host=127.0.0.1,remote.port=$((p+1))" \
        -device virtio-net-pci,netdev=n0,mac=52:54:00:aa:bb:cc \
        -drive "file=$T/d.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    local qp=$!
    bash tools/work/waitfor.sh -t 130 -i 2 pid "$qp" >/dev/null 2>&1
    kill "$qp" 2>/dev/null
    kill "$(cat "$T/$n.ppid")" 2>/dev/null
    wait 2>/dev/null
    tr -cd '\11\12\15\40-\176' < "$T/$n.txt" > "$T/$n.klar"
}
chk() { grep -aq -- "$3" "$T/$1.klar" && ok "$1: $2" || bad "$1: $2 (missing: $3)"; }
nochk() { grep -aq -- "$3" "$T/$1.klar" && bad "$1: $2 (found: $3)" || ok "$1: $2"; }
pchk() { grep -aq -- "$3" "$T/$1.peer" && ok "$1: $2" || bad "$1: $2 (peer log missing: $3)"; }
pnochk() { grep -aq -- "$3" "$T/$1.peer" && bad "$1: $2 (peer log has: $3)" || ok "$1: $2"; }
txk() { grep -a '^txk:' "$T/$1.klar" | head -1 | sed -n "s/.*$2=\\([0-9][0-9]*\\).*/\\1/p"; }
atmost() { local v; v=$(txk "$1" "$2"); [ -n "$v" ] && [ "$v" -le "$3" ] && ok "$1: $4 ($2=$v <= $3)" || bad "$1: $4 ($2=${v:-none}, wanted <= $3)"; }
atleast() { local v; v=$(txk "$1" "$2"); [ -n "$v" ] && [ "$v" -ge "$3" ] && ok "$1: $4 ($2=$v >= $3)" || bad "$1: $4 ($2=${v:-none}, wanted >= $3)"; }
panics() { grep -aiq 'panic\|exception\|#PF\|#GP\|#UD' "$T/$1.klar" && bad "$1: panic/exception in log" || ok "$1: no panic/exception"; }

for c in $CASES; do
    case "$c" in
    dhcp)
        run dhcp s_dhcp.sh "nip=169.254.10.1/16" ""
        chk dhcp "lease" 'dhcp: ack ip=192.168.1.50'
        chk dhcp "echo reply from 1.1.1.1" 'octets from 1.1.1.1: icmp_seq=1'
        chk dhcp "echo reply from 8.8.8.8" 'octets from 8.8.8.8: icmp_seq=1'
        pchk dhcp "echo for 1.1.1.1 addressed to the gateway MAC" 'ECHO dst=1.1.1.1 via_gw=1'
        pnochk dhcp "no direct ARP for 1.1.1.1" 'ARP-OTHER-ASK 1.1.1.1'
        pnochk dhcp "no direct ARP for 8.8.8.8" 'ARP-OTHER-ASK 8.8.8.8'
        chk dhcp "proc: mask and gateway mac" 'net: mask=255.255.255.0 gwmac=52:54:00:11:22:33'
        chk dhcp "proc: route 1.1.1.1 via gateway" 'route: 1.1.1.1 next=gw hop=192.168.1.1 mac=52:54:00:11:22:33'
        chk dhcp "proc: route 8.8.8.8 via gateway" 'route: 8.8.8.8 next=gw hop=192.168.1.1 mac=52:54:00:11:22:33'
        chk dhcp "proc: arp entry of the gateway" 'arp: 192.168.1.1 52:54:00:11:22:33'
        nochk dhcp "arp table holds no off-link entry (1.1.1.1)" 'arp: 1.1.1.1 '
        chk dhcp "statistics" '0% packet loss'
        chk dhcp "script reached the end" '==END=='
        panics dhcp
        ;;
    wrongmask)
        run wrongmask s_static.sh "nip=192.168.1.50/0 ngw=192.168.1.1" ""
        pchk wrongmask "wrong mask: ARP asked directly for 1.1.1.1" 'ARP-OTHER-ASK 1.1.1.1'
        nochk wrongmask "wrong mask: no echo reply" 'octets from 1.1.1.1'
        chk wrongmask "wrong mask: timeout reported" 'ping: no answer for 1'
        chk wrongmask "wrong mask: 100% loss reported" '100% packet loss'
        chk wrongmask "proc shows the wrong mask" 'net: mask=0.0.0.0'
        chk wrongmask "proc: route 1.1.1.1 direct" 'route: 1.1.1.1 next=direct hop=1.1.1.1 mac=pending'
        chk wrongmask "script reached the end" '==END=='
        panics wrongmask
        ;;
    nogw)
        run nogw s_dhcp.sh "nip=169.254.10.1/16" "--no-echo"
        chk nogw "lease" 'dhcp: ack ip=192.168.1.50'
        pchk nogw "echo for 1.1.1.1 reached the gateway" 'ECHO dst=1.1.1.1 via_gw=1'
        chk nogw "timeout line per packet" 'ping: no answer for 2'
        chk nogw "100% loss reported" '100% packet loss'
        chk nogw "second target ends too" 'PING 8.8.8.8'
        chk nogw "script reached the end" '==END=='
        panics nogw
        ;;
    storm)
        run storm s_storm.sh "nip=192.168.1.50/0 ngw=192.168.1.1" ""
        chk storm "ping ran to the end" '100% packet loss'
        atmost storm arp 30 "ARP requests on the wire are rate limited"
        atleast storm arpgated 1 "excess ARP requests were held back"
        chk storm "script reached the end" '==END=='
        panics storm
        ;;
    stormopen)
        run stormopen s_storm.sh "nip=192.168.1.50/0 ngw=192.168.1.1 noarpgap" ""
        atleast stormopen arp 100 "counter-proof: without the gap the storm shows"
        chk stormopen "script reached the end" '==END=='
        ;;
    blocksend)
        run blocksend s_block.sh "nip=192.168.1.50/0 ngw=192.168.1.1" ""
        chk blocksend "blocking ping returned" '==MID=='
        chk blocksend "no answer reported" 'ping: no answer for 1'
        atmost blocksend arp 12 "ARP requests of a blocking send are rate limited"
        chk blocksend "script reached the end" '==END=='
        panics blocksend
        ;;
    blocksendopen)
        run blocksendopen s_block.sh "nip=192.168.1.50/0 ngw=192.168.1.1 noarpgap" ""
        atleast blocksendopen arp 100 "counter-proof: blocking send floods without the gap"
        ;;
    esac
done
echo "PINGGW: $pass passed, $fail failed"
[ "$fail" = 0 ]
