#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
HERE="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$HERE"
. tools/lib/firnenv.sh
export FIRNLIB="$HERE/lib"
T=${SOCKMAX_WORK:-$(mktemp -d)}
mkdir -p "$T"
OLD_REF=${SOCKMAX_OLD_REF:-2424cb43b}
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
command -v qemu-system-x86_64 >/dev/null || { echo "SOCKMAX: skipped, no qemu"; exit 0; }
OLD_TREE="$T/oldtree"
cleanup() {
    for f in "$T"/*.pid; do [ -f "$f" ] && kill "$(cat "$f")" 2>/dev/null; done
    [ -d "$OLD_TREE" ] && git worktree remove --force "$OLD_TREE" >/dev/null 2>&1
    [ -n "${SOCKMAX_WORK:-}" ] || rm -rf "$T"
}
trap cleanup EXIT
if [ ! -f "$T/kernel-new.img" ] || [ ! -f "$T/bin/sh.elf" ]; then
    bash tools/sync/build.sh "$T/bin" 0 sh sleep echo > "$T/b.txt" 2>&1 || { tail "$T/b.txt"; exit 1; }
    "$FIRNC" -c --profile=app -o "$T/socktest.o" kernel/app/socktest.fi > "$T/app.txt" 2>&1 || { tail "$T/app.txt"; exit 1; }
    ld -T kernel/user/user.ld -o "$T/bin/socktest.elf" "$T/socktest.o" >> "$T/app.txt" 2>&1 || { tail "$T/app.txt"; exit 1; }
    ./tools/build-kernel.sh "$T/kernel-new.img" --stufe 0 > "$T/k.txt" 2>&1 || { tail "$T/k.txt"; exit 1; }
fi
if [ ! -f "$T/kernel-old.img" ]; then
    if [ -n "${SOCKMAX_OLD_KERNEL:-}" ]; then cp "$SOCKMAX_OLD_KERNEL" "$T/kernel-old.img"
    else
        git worktree add --detach "$OLD_TREE" "$OLD_REF" > /dev/null 2>&1 || { echo "SOCKMAX: cannot check out $OLD_REF"; exit 1; }
        (cd "$OLD_TREE" && ./tools/build-kernel.sh "$T/kernel-old.img" --stufe 0 > "$T/kold.txt" 2>&1) || { tail "$T/kold.txt"; exit 1; }
    fi
fi
printf 'echo ==START==\nsocktest stat\nsocktest fill\nsocktest killloop 5\nsocktest stat\necho ==END==\n' > "$T/s_all.sh"
bash tools/mkfsfi/mkfs.sh build "$T/d.img" 8000 /bin/ /t/ /etc/ /var/ /var/log/ \
    /bin/sh="$T/bin/sh.elf" /bin/sleep="$T/bin/sleep.elf" /bin/echo="$T/bin/echo.elf" \
    /bin/socktest="$T/bin/socktest.elf" /bin/jarvisd="$T/bin/socktest.elf" /proc/ \
    /t/s_all.sh="$T/s_all.sh" > "$T/mkfs.txt" 2>&1 || { tail "$T/mkfs.txt"; exit 1; }
ACC=tcg; [ -w /dev/kvm ] && ACC=kvm
PORT=$((49000 + ($$ % 500) * 4))

run() {
    local n=$1 kernel=$2 p=$PORT
    PORT=$((PORT+4))
    rm -f "$T/$n".*
    python3 -I tools/pinggw/peer.py --local "$((p+1))" --remote "$p" --log "$T/$n.peer" --secs 170 &
    echo $! > "$T/$n.ppid"
    sleep 1
    timeout 160 qemu-system-x86_64 -accel $ACC -kernel "$kernel" -m 256 \
        -append "osum nokbd nosched vfs usb usbpoll nic nip=169.254.10.1/16 nsvc=0 nwait=0 script=sh /t/s_all.sh;exit" \
        -serial "file:$T/$n.txt" -display none -no-reboot -pidfile "$T/$n.pid" \
        -netdev "dgram,id=n0,local.type=inet,local.host=127.0.0.1,local.port=$p,remote.type=inet,remote.host=127.0.0.1,remote.port=$((p+1))" \
        -device virtio-net-pci,netdev=n0,mac=52:54:00:aa:bb:cc \
        -drive "file=$T/d.img,format=raw,if=ide,index=0,snapshot=on" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    local qp=$!
    bash tools/work/waitfor.sh -t 150 -i 2 pid "$qp" >/dev/null 2>&1
    kill "$qp" 2>/dev/null
    kill "$(cat "$T/$n.ppid")" 2>/dev/null
    wait 2>/dev/null
    tr -cd '\11\12\15\40-\176' < "$T/$n.txt" > "$T/$n.klar"
}
val() { grep -a "^$2 " "$T/$1.klar" | tail -n 1 | awk '{print $2}'; }
vals() { grep -a "^$2 " "$T/$1.klar" | awk '{print $2}' | tr '\n' ' '; }
want() { [ "$(val "$1" "$3")" = "$4" ] && ok "$1: $2" || bad "$1: $2 ($3=$(val "$1" "$3"), want $4)"; }
atleast() { local v; v=$(val "$1" "$3"); [ -n "$v" ] && [ "$v" -ge "$4" ] 2>/dev/null && ok "$1: $2" || bad "$1: $2 ($3=${v:-none}, want >= $4)"; }
panics() { grep -aiq 'panic\|exception\|#PF\|#GP\|#UD' "$T/$1.klar" && bad "$1: panic/exception in log" || ok "$1: no panic/exception"; }

run new "$T/kernel-new.img"
grep -aq '==END==' "$T/new.klar" && ok "new: script ran to the end" || bad "new: script did not finish"
atleast new "table is large (max)" max 128
atleast new "table filled by four programs" fill_used 120
want new "ordinary program is refused with ENFILE" probe_errno 23
want new "bridge (jarvisd) still gets a socket" probe_ok 1
want new "bridge probe exit code 0" bridge_probe_code 0
want new "ordinary probe exit code 1" normal_probe_code 1
atleast new "refusals are counted" fill_refused_total 1
want new "table drained after kill" drained_used 0
want new "ordinary probe works again after drain" after_probe_code 0
want new "kill loop leaks no slot" killloop_after 0
atleast new "kill loop really used slots" killloop_peak 31
panics new

run old "$T/kernel-old.img"
grep -aq '==END==' "$T/old.klar" && ok "old: script ran to the end" || bad "old: script did not finish"
[ "$(vals old probe_errno | wc -w)" -ge 2 ] && ok "old: counter-proof, the bridge probe is refused too (ENFILE)" || bad "old: counter-proof, bridge probe was not refused ($(vals old probe_errno))"
echo "SOCKMAX: $pass passed, $fail failed"
[ "$fail" = 0 ]
