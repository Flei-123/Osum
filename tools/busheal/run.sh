#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -u
cd "$(dirname "$0")/../.."
. tools/lib/firnenv.sh
TMPD=$(mktemp -d)
. tools/lib/summary.sh; summary_begin BUSHEAL
trap 'summary_guard; rm -rf "$TMPD"; summary_exit_status || exit 1' EXIT
trap 'exit 1' HUP INT TERM
pass=0; fail=0
ok()  { echo "  OK   $*"; pass=$((pass + 1)); }
bad() { echo "  FAIL $*"; fail=$((fail + 1)); }
QEMU=${QEMU:-qemu-system-x86_64}
export FIRNLIB="$PWD/lib"
KERNEL=${BUSHEAL_KERNEL:-$TMPD/k.mb}
if [ ! -f "$KERNEL" ]; then
    bash tools/build-kernel.sh "$KERNEL" --stufe 0 > "$TMPD/k.log" 2>&1 \
        || { bad "kernel does not build"; tail -8 "$TMPD/k.log"; summary_emit "$pass" "$fail" 0; exit 1; }
fi

run_case() {
    local name=$1 smp=$2 extra=$3 limit=$4
    local out="$TMPD/$name.txt"
    : > "$out"
    local t0=$SECONDS
    timeout "$limit" $QEMU -kernel "$KERNEL" -m 512 -smp "$smp" \
        -append "nokbd nosched noproc nofs $extra" \
        -serial "file:$out" -display none -no-reboot -vga std \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > "$TMPD/$name.qemu" 2>&1 &
    local pid=$! i=0
    while [ $i -lt $((limit * 5)) ]; do
        grep -qa '^bus: done\|^panic:\|^\*\*\* EXCEPTION' "$out" 2>/dev/null && break
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.2; i=$((i + 1))
    done
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    echo $((SECONDS - t0)) > "$TMPD/$name.secs"
}
field() { grep -a "^$2" "$1" 2>/dev/null | tail -1 | sed "s/^$2//"; }

echo "== 1. clean run, 4 cores: nothing is taken over =="
run_case clean 4 "busbench bus r3alle" 200
A="$TMPD/clean.txt"
[ "$(field "$A" 'busa: run=')" = 100 ] && ok "100 rounds" || bad "rounds: '$(field "$A" 'busa: run=')'"
[ "$(field "$A" 'bus: stolen=')" = 0 ] && ok "no lock taken over without a leak" || bad "stolen=$(field "$A" 'bus: stolen=')"
grep -qa 'orphan lock' "$A" && bad "orphan message without a leak" || ok "no orphan message"

echo
echo "== 2. leaked lock (busleak), healing on =="
run_case heal 4 "busbench bus busleak r3alle" 200
H="$TMPD/heal.txt"
[ "$(field "$H" 'busa: run=')" = 100 ] && ok "100 rounds despite the leak" || bad "rounds: '$(field "$H" 'busa: run=')'"
st=$(field "$H" 'bus: stolen=')
[ "${st:-0}" -ge 1 ] 2>/dev/null && ok "lock taken over ($st x)" || bad "stolen='$st'"
grep -a 'orphan lock' "$H" | head -2 | sed 's/^/        /'
grep -qa '^bus: lock stuck' "$H" && bad "lock reported stuck" || ok "never stuck"
hs=$(cat "$TMPD/heal.secs"); echo "        heal wall time: ${hs}s"

echo
echo "== 3. counter-check: leak with healing off (nobusheal) =="
run_case old 4 "busbench bus busleak nobusheal r3alle" 200
O="$TMPD/old.txt"
os=$(cat "$TMPD/old.secs"); echo "        no-heal wall time: ${os}s"
stuck=$(grep -ac '^bus: lock stuck' "$O" || true)
if [ "${stuck:-0}" -ge 1 ] || [ "$(field "$O" 'busa: run=')" != 100 ]; then
    ok "old behaviour is red: stuck messages=$stuck, rounds='$(field "$O" 'busa: run=')'"
else
    bad "leak without healing went unnoticed"
fi
[ "$(field "$O" 'bus: stolen=')" = 0 ] && ok "nothing taken over with nobusheal" || bad "stolen with nobusheal"
[ "$hs" -lt "$os" ] 2>/dev/null && ok "healing is faster (${hs}s vs ${os}s)" || bad "heal ${hs}s not faster than ${os}s"

echo
echo "== 4. source checks =="
grep -q 'L_BUS' kernel/sync/atomic.fi && ok "bus lock is in the lock registry" || bad "L_BUS missing"
grep -qw 'S_LOCK' kernel/bus/bus.fi && bad "raw bus lock word still used" || ok "no raw lock word"
summary_emit "$pass" "$fail" 0
echo "$pass ok, $fail fail"
[ "$fail" = 0 ]
