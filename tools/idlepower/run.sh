#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/idlepower/run.sh -- AN IDLE DESKTOP MUST LET EVERY CORE SLEEP (w-idle-power, 21.11.2026).
#
#   [IDLEPOWER_SMP=8] bash tools/idlepower/run.sh
#
# Surface Laptop 4 (8 CPUs) drained 60 % -> 6 % while idle. QEMU cannot show real C-states, but it shows a core that
# does not execute HLT / MWAIT: the host thread of such a vCPU burns a whole host core.
#   1. idle desktop, N vCPUs: the average host CPU share per vCPU thread stays under 12 % (measured 4-6 %);
#   2. the kernel prints no `idle: awake cpu` line (a core awake >= 60 % of a 10 s window, reported after 60 s uptime);
#   COUNTER-PROOF: the same kernel with the boot word `idlespin` (idle loops poll instead of sleeping): the average share
#   per vCPU is at least 40 % and the kernel prints `idle: awake cpu` lines.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
SMP=${IDLEPOWER_SMP:-8}
OUTD=${IDLEPOWER_KEEP:-$(mktemp -d)}
mkdir -p "$OUTD"
trap '[ -n "${IDLEPOWER_KEEP:-}" ] || rm -rf "$OUTD"; kill $(jobs -p) 2>/dev/null' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
BUILD=$OUTD/build

run_case() { # <name> [extra words]
    local n=$1 o=$OUTD/$1
    mkdir -p "$o"
    python3 -I "$ROOT/tools/idlepower/sample.py" "$o" "$o/o/serial.txt" 25 30 > "$o/threads.txt" 2>&1 &
    local sp=$!
    EH_SMP=$SMP DESIGNBUILD=$BUILD bash tools/design/eh6.sh "$o/o" res=1280x800 accel=kvm \
        drehbuch="$ROOT/tools/idlepower/script.txt" ${2:+extra="$2"} > "$o/eh.log" 2>&1
    wait "$sp" 2>/dev/null
}
avg_share() { awk -v n="$SMP" '{ s += $3 } END { printf "%.1f", (NR ? s / n : -1) }' "$1"; }
awake_lines() { grep -a -c '^idle: awake cpu' "$1" 2>/dev/null || true; }

run_case normal ""
run_case spin "idlespin"
for c in normal spin; do
    [ -s "$OUTD/$c/threads.txt" ] || { bad "$c: no thread samples"; tail -5 "$OUTD/$c/eh.log"; }
done
A=$(avg_share "$OUTD/normal/threads.txt"); B=$(avg_share "$OUTD/spin/threads.txt")
LA=$(awake_lines "$OUTD/normal/o/serial.txt"); LB=$(awake_lines "$OUTD/spin/o/serial.txt")
echo "  INFO  idle desktop, $SMP vCPUs: host share per vCPU ${A} % (idlespin: ${B} %), awake lines ${LA:-0} (idlespin: ${LB:-0})"
awk -v a="$A" 'BEGIN { exit !(a >= 0 && a < 12) }' && ok "idle desktop: ${A} % per vCPU < 12 %" || bad "idle desktop: ${A} % per vCPU (budget 12 %)"
[ "${LA:-0}" -eq 0 ] && ok "no core stays awake in the idle window" || bad "${LA} awake lines on the idle desktop"
awk -v b="$B" 'BEGIN { exit !(b >= 40) }' && ok "counter-proof: idlespin burns ${B} % per vCPU" || bad "counter-proof: idlespin only ${B} % per vCPU"
[ "${LB:-0}" -ge 1 ] && ok "counter-proof: idlespin is reported by the kernel (${LB} lines)" || bad "counter-proof: idlespin printed no awake line"
echo
echo "IDLEPOWER: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
