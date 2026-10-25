#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$HERE"
export FIRNLIB="$HERE/lib"
T=${NETTEST_WORK:-$(mktemp -d)}
mkdir -p "$T"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
command -v qemu-system-x86_64 >/dev/null || { echo "NETTEST: skipped, no qemu"; exit 0; }
CASES="${*:-ok nodns nogw nolease}"
trap 'for f in "$T"/*.pid; do [ -f "$f" ] && kill "$(cat "$f")" 2>/dev/null; done; [ -n "${NETTEST_WORK:-}" ] || rm -rf "$T"' EXIT
if [ ! -f "$T/k.img" ] || [ ! -f "$T/bin/sh.elf" ]; then
    bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
    bash tools/sync/build.sh "$T/bin" 0 sh sleep echo dhcp cat > "$T/b.txt" 2>&1 || { tail "$T/b.txt"; exit 1; }
    vendor/firn/bin/firnc -c --profile=app -o "$T/nettest.o" kernel/app/nettest.fi > "$T/app.txt" 2>&1 || { tail "$T/app.txt"; exit 1; }
    ld -T kernel/user/user.ld -o "$T/bin/nettest.elf" "$T/nettest.o" >> "$T/app.txt" 2>&1 || { tail "$T/app.txt"; exit 1; }
    ./tools/build-kernel.sh "$T/k.img" --stufe 0 > "$T/k.txt" 2>&1 || { tail "$T/k.txt"; exit 1; }
fi
printf 'echo ==START==\ndhcp\nnettest -n nettest.test\ncat /proc/usbnet\necho ==END==\n' > "$T/s_dhcp.sh"
printf 'echo ==START==\nnettest -n nettest.test\necho ==END==\n' > "$T/s_static.sh"
python3 tools/osum/mkfs.py build "$T/d.img" 8000 /bin/ /t/ /etc/ \
    /bin/sh="$T/bin/sh.elf" /bin/sleep="$T/bin/sleep.elf" /bin/echo="$T/bin/echo.elf" \
    /bin/dhcp="$T/bin/dhcp.elf" /bin/nettest="$T/bin/nettest.elf" /bin/cat="$T/bin/cat.elf" /proc/ \
    /t/s_dhcp.sh="$T/s_dhcp.sh" /t/s_static.sh="$T/s_static.sh" > "$T/mkfs.txt" 2>&1 || { tail "$T/mkfs.txt"; exit 1; }
ACC=tcg; [ -w /dev/kvm ] && ACC=kvm
PORT=$((49000 + ($$ % 500) * 4))

run() {
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
        -drive "file=$T/d.img,format=raw,if=ide,index=0,snapshot=on" \
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
panics() { grep -aiq 'panic\|exception\|#PF\|#GP\|#UD' "$T/$1.klar" && bad "$1: panic/exception in log" || ok "$1: no panic/exception"; }

for c in $CASES; do
    case "$c" in
    ok)
        run ok s_dhcp.sh "nip=169.254.10.1/16" ""
        chk ok "link line" 'OK   link '
        chk ok "ip line" 'OK   ip       192.168.1.50 mask 255.255.255.0'
        chk ok "gateway line with mac" 'OK   gateway  192.168.1.1 mac=52:54:00:11:22:33'
        chk ok "dns line from kernel" 'OK   dns      kernel 192.168.1.1'
        chk ok "ping gateway" 'OK   ping-gw  192.168.1.1 '
        chk ok "ping off-link" 'OK   ping-net 1.1.1.1 '
        chk ok "resolve" 'OK   resolve  nettest.test -> 203.0.113.80'
        chk ok "tls refused connection reported" 'FAIL tls      https://nettest.test tcp connect failed'
        chk ok "summary" 'nettest: 7/8 OK'
        chk ok "proc dns line" '^dns: 192.168.1.1'
        pchk ok "dns query reached the peer" 'DNS-QUERY'
        pchk ok "tcp syn to the resolved address" 'TCP-SYN dst=203.0.113.80 port=443'
        panics ok
        ;;
    nodns)
        run nodns s_dhcp.sh "nip=169.254.10.1/16" "--no-dns"
        chk nodns "resolve fails" 'FAIL resolve  nettest.test no answer'
        chk nodns "tls skipped" 'FAIL tls      https://nettest.test skipped, no address'
        chk nodns "ping still ok" 'OK   ping-gw '
        nochk nodns "no resolve success" 'OK   resolve'
        panics nodns
        ;;
    nogw)
        run nogw s_dhcp.sh "nip=169.254.10.1/16" "--no-echo"
        chk nogw "ping gateway fails" 'FAIL ping-gw  192.168.1.1 no answer'
        chk nogw "ping off-link fails" 'FAIL ping-net 1.1.1.1 no answer'
        chk nogw "resolve still ok" 'OK   resolve '
        panics nogw
        ;;
    nolease)
        run nolease s_static.sh "nip=169.254.10.1/16" ""
        chk nolease "link-local address fails" 'FAIL ip       169.254.10.1'
        chk nolease "no dns" 'FAIL dns      no nameserver'
        nochk nolease "no ok summary" 'nettest: 8/8'
        panics nolease
        ;;
    esac
done
echo "NETTEST: $pass passed, $fail failed"
[ "$fail" = 0 ]
