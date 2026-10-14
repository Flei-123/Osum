#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/toctousmp/run.sh -- r721 / K-07: SMP races of the user-space copy paths + memfd seals, with counter-checks.
#
#   bash tools/toctousmp/run.sh [<cores>]
#
# Runs the unterbau tests t_seal and t_toctousmp at <cores> (default 4) cores with `smpfrueh`:
#   fix      every check must PASS (seal rules; no mixed octets in the socket bounce buffer; no write into a freed frame)
#   counter  same kernel with the words `noscratch nommlock` (locks skipped): scratch_no_mixing must FAIL, otherwise the test
#            measures nothing. mm_no_stale_write is reported but only warns (the window is a few microseconds wide).
# Use /root/jarvis/bin/heavy for the call.
set -uo pipefail
cd "$(dirname "$0")/../.."
CORES=${1:-4}
T=${TOCTOUSMP_DIR:-$(mktemp -d)}; mkdir -p "$T"
[ -n "${TOCTOUSMP_KEEP:-}" ] || trap 'rm -rf "$T"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
verdict() { awk -v n="$2" '$1 == n {print $2; f=1; exit} END {if (!f) print "MISSING"}' "$1"; }

echo "== fix: $CORES cores =="
ONLY="t_seal t_toctousmp" SMP=$CORES KARGS="smpfrueh" TMO=300 UB_OUT="$T/fix" KEEP=1 UB_RESULT="$T/fix.res" \
    bash tools/unterbau/run.sh > "$T/fix.log" 2>&1
for n in $(awk '/^(seal|toctousmp)\./ {print $1}' "$T/fix.res" | sort -u); do
    v=$(verdict "$T/fix.res" "$n")
    if [ "$v" = PASS ]; then ok "$n"; else bad "$n $v"; fi
done
for n in seal.mmap_rw_after_seal_refused seal.seal_write_busy_with_rw_mapping toctousmp.scratch_no_mixing toctousmp.mm_no_stale_write; do
    [ "$(verdict "$T/fix.res" "$n")" = MISSING ] && bad "$n missing"
done
grep -a "^T toctousmp\.\(scratch\|mm\)" "$T/fix/new-t_toctousmp.ser" 2>/dev/null | sed 's/^/        /' | head -8

echo "== counter: noscratch nommlock =="
if [ -r "$T/fix/k-new.mb" ]; then
    ONLY="t_toctousmp" SMP=$CORES KARGS="smpfrueh noscratch nommlock" TMO=300 KERNEL="$T/fix/k-new.mb" UB_OUT="$T/ctl" KEEP=1 UB_RESULT="$T/ctl.res" \
        bash tools/unterbau/run.sh > "$T/ctl.log" 2>&1
    grep -a "^T toctousmp\.\(scratch\|mm\)" "$T/ctl/new-t_toctousmp.ser" 2>/dev/null | sed 's/^/        /' | head -8
    [ "$(verdict "$T/ctl.res" toctousmp.scratch_no_mixing)" = FAIL ] && ok "counter: scratch lock off -> octets mix" || bad "counter: scratch race not shown"
    [ "$(verdict "$T/ctl.res" toctousmp.mm_no_stale_write)" = FAIL ] && ok "counter: MM lock off -> stale write shown" || echo "  WARN  counter: stale write not shown (narrow window)"
else
    bad "no kernel image from the fix run"
fi
echo "TOCTOUSMP: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
