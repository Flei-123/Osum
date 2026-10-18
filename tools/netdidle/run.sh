#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/netdidle/run.sh -- THE NETWORK TASK MUST NOT EAT THE IDLE DESKTOP (W-U, 17.10.2026).
#
#   bash tools/netdidle/run.sh
#
# Boss, VirtualBox VM (image z11, bridged NIC): the taskbar's CPU widget showed
# 45-50 % with no window open. `ps` there: pid 3 `netd` had 104 000 ticks, always
# runnable, ~70 % of a core; the widget was right. `netd_body` spun
# 4000 turns of the run queue after EVERY frame -- with a dozen ready tasks a
# turn is a round of all of them, so 4000 turns are far longer than a tick, and a
# few ARP/mDNS frames a second kept it hot. QEMU's user network is silent, which
# is why tools/menualive (9.5 %) never saw it.
# Fix: the spin is bounded to HOT_US = 1500 us after the last frame/kick.
#
# This run: the eh6 machine with an e1000 on a `-netdev socket,udp=` link that carries
# broadcast frames (tools/netdidle/flood.py, 40 per second) and two `ps` 30 s apart:
#   1. netd (pid = index from `nic: netd=N` + 1) uses < 15 % of the core;
#   2. the widget's method (everything but the idle task) < 15 %;
#   3. COUNTER-PROOF, kernel word `netdhot` (the old rule): netd is high again.
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"; kill $(jobs -p) 2>/dev/null' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
export DESIGNBUILD="$TMPD/build"
FPS=${FPS:-40}

run() { # run <name> <extra kernel words>
    local name=$1; shift
    local qp=$((20000 + RANDOM % 20000)) hp=$((40000 + RANDOM % 20000))
    python3 tools/netdidle/flood.py "$qp" "$FPS" 150 "$hp" > "$TMPD/$name.flood" 2>&1 &
    local fp=$!
    EH_NETDEV="-netdev socket,id=n0,udp=127.0.0.1:$hp,localaddr=127.0.0.1:$qp -device e1000,netdev=n0,mac=52:54:00:aa:bb:cc" \
    bash tools/design/eh6.sh "$TMPD/$name" res=1280x800 accel=kvm netz=ja \
        drehbuch=tools/netdidle/dreh.txt extra="$*" > "$TMPD/$name.log" 2>&1
    kill $fp 2>/dev/null
    grep -a "FEHLGESCHLAGEN\|NICHT DA" "$TMPD/$name.log" | head -3
}

measure() { # measure <name> -> prints "netd busy"
    local D="$TMPD/$1"
    # `nic: netd=N` is the scheduler's task INDEX; `ps` lists pid = index + 1
    NIDX=$(grep -a 'nic: netd=' "$D/serial.txt" | sed -n 's/.*nic: netd=\([0-9]*\).*/\1/p' | head -1)
    NPID=$(( ${NIDX:-2} + 1 ))
    [ -n "${KEEP:-}" ] && { mkdir -p "$KEEP"; cp "$D/serial.txt" "$KEEP/$1.serial.txt"; }
    python3 tools/menualive/check.py cpu "$D/serial.txt" "pid:${NPID}" | tee "$TMPD/$1.netd" | sed 's/^/        /'
    python3 tools/menualive/check.py cpu "$D/serial.txt" notkind:idle | tee "$TMPD/$1.busy" | sed 's/^/        /'
}
pct() { sed -n 's/.*share=\([-0-9.]*\).*/\1/p' "$1" | head -1; }

echo "== fix on =="
run fix
measure fix
# eh6 runs with `noproc`, so the netd pid comes from the kernel's own line `nic: netd=N`
grep -aq 'nic: netd=[0-9]' "$TMPD/fix/serial.txt" && ok "netd pid known from 'nic: netd=N'" || bad "no 'nic: netd=N' line (netd not started?)"
n=$(pct "$TMPD/fix.netd"); b=$(pct "$TMPD/fix.busy")
awk -v s="${n:--1}" 'BEGIN{exit !(s >= 0 && s < 15)}' && ok "netd uses ${n} % of the core under $FPS frames/s (limit 15 %)" || bad "netd uses ${n:-?} % (limit 15 %)"
awk -v s="${b:--1}" 'BEGIN{exit !(s >= 0 && s < 15)}' && ok "widget method: the core is ${b} % busy (limit 15 %)" || bad "widget method: ${b:-?} % busy (limit 15 %)"

echo "== counter-proof: netdhot (old rule) =="
run ctl netdhot
measure ctl
n2=$(pct "$TMPD/ctl.netd")
awk -v s="${n2:--1}" 'BEGIN{exit !(s >= 30)}' && ok "with netdhot netd is hot again (${n2} %): the check measures something" || bad "with netdhot netd uses only ${n2:-?} % -- the check is blind"

echo
echo "NETDIDLE: $pass passed, $fail failed"
[ "$fail" = 0 ]
