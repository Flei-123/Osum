#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$HERE"
export FIRNLIB="$HERE/lib"
T=${NETCHECK_WORK:-$(mktemp -d)}
mkdir -p "$T"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
command -v qemu-system-x86_64 >/dev/null || { echo "NETCHECK: skipped, no qemu"; exit 0; }
CASES="${*:-ok nogw nodns noinet flap quiet}"
trap 'for f in "$T"/*.pid; do [ -f "$f" ] && kill "$(cat "$f")" 2>/dev/null; done; [ -n "${NETCHECK_WORK:-}" ] || rm -rf "$T"' EXIT
if [ ! -f "$T/k.img" ] || [ ! -f "$T/bin/sh.elf" ]; then
    bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
    bash tools/sync/build.sh "$T/bin" 0 sh sleep echo dhcp cat > "$T/b.txt" 2>&1 || { tail "$T/b.txt"; exit 1; }
    vendor/firn/bin/firnc -c --profile=app -o "$T/netcheck.o" kernel/app/netcheck.fi > "$T/app.txt" 2>&1 || { tail "$T/app.txt"; exit 1; }
    ld -T kernel/user/user.ld -o "$T/bin/netcheck.elf" "$T/netcheck.o" >> "$T/app.txt" 2>&1 || { tail "$T/app.txt"; exit 1; }
    ./tools/build-kernel.sh "$T/k.img" --stufe 0 > "$T/k.txt" 2>&1 || { tail "$T/k.txt"; exit 1; }
fi
printf 'echo ==START==\ndhcp\nnetcheck -c 8 -i 1 -b 1\nnetcheck get\ncat /var/log/net.log\necho ==END==\n' > "$T/s_loop.sh"
printf 'echo ==START==\ndhcp\nnetcheck -c 1 -i 1 -b 1\nnetcheck get\necho ==END==\n' > "$T/s_once.sh"
printf 'echo ==START==\ndhcp\nnetcheck get\necho ==END==\n' > "$T/s_none.sh"
bash tools/mkfsfi/mkfs.sh build "$T/d.img" 8000 /bin/ /t/ /etc/ /var/ /var/log/ \
    /bin/sh="$T/bin/sh.elf" /bin/sleep="$T/bin/sleep.elf" /bin/echo="$T/bin/echo.elf" \
    /bin/dhcp="$T/bin/dhcp.elf" /bin/netcheck="$T/bin/netcheck.elf" /bin/cat="$T/bin/cat.elf" /proc/ \
    /t/s_loop.sh="$T/s_loop.sh" /t/s_once.sh="$T/s_once.sh" /t/s_none.sh="$T/s_none.sh" > "$T/mkfs.txt" 2>&1 || { tail "$T/mkfs.txt"; exit 1; }
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
        run ok s_loop.sh "nip=169.254.10.1/16" ""
        chk ok "stage ok" 'health 1'
        chk ok "no heals" 'heals 0'
        chk ok "stage logged" 'netcheck stage=1'
        nochk ok "no heal logged" 'netcheck heal='
        panics ok
        ;;
    nogw)
        run nogw s_loop.sh "nip=169.254.10.1/16" "--no-echo"
        chk nogw "stage no gateway" 'health 2'
        chk nogw "heal ladder ran" 'heals [1-9]'
        chk nogw "rung above 1" 'rung [2-4]'
        chk nogw "heal logged" 'netcheck heal='
        pchk nogw "arp flushed, gateway asked again" 'ARP-GW-ASK'
        panics nogw
        ;;
    nodns)
        run nodns s_loop.sh "nip=169.254.10.1/16" "--no-dns"
        chk nodns "stage no dns" 'health 3'
        panics nodns
        ;;
    noinet)
        run noinet s_loop.sh "nip=169.254.10.1/16" "--no-inet"
        chk noinet "stage no internet" 'health 4'
        panics noinet
        ;;
    flap)
        run flap s_once.sh "nip=169.254.10.1/16" "--no-echo"
        chk flap "single bad round is not published" 'health 0'
        chk flap "no heal after one round" 'heals 0'
        panics flap
        ;;
    quiet)
        run quiet s_none.sh "nip=169.254.10.1/16" ""
        chk quiet "unknown without the daemon" 'health 0'
        panics quiet
        ;;
    esac
done
echo "NETCHECK: $pass passed, $fail failed"
[ "$fail" = 0 ]
