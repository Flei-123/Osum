#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
CYCLES=${NMIGAP_CYCLES:-8}
PERIOD=${NMIGAP_PERIOD:-200000}
if [ -n "${NMIGAP_OUT:-}" ]; then
    TMPD=$NMIGAP_OUT; mkdir -p "$TMPD"
else
    TMPD=$(mktemp -d)
    trap 'rm -rf "$TMPD"' EXIT
fi
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
export DESIGNBUILD="$TMPD/build"
export EH_SMP=${EH_SMP:-4}
python3 tools/drift/gen.py "$CYCLES" 0 > "$TMPD/script.txt"
python3 tools/drift/gen.py 2 0 > "$TMPD/short.txt"

boot() {
    bash tools/design/eh6.sh "$TMPD/$1" res=1920x1080 accel=kvm drehbuch="$TMPD/${3:-script}.txt" extra="$2" > "$TMPD/$1.log" 2>&1
}
faults() { grep -acE 'panic|\*\*\* EXCEPTION|\*\*\* fault' "$TMPD/$1/serial.txt"; }
starts() { grep -acE '^launcher: start /apps/explorer' "$TMPD/$1/serial.txt"; }

echo "== NMI every $PERIOD cycles, NMI on IST2 =="
boot ist "nmiperiod=$PERIOD"
n=$(faults ist); s=$(starts ist)
[ "$n" -eq 0 ] && ok "no exception under the NMI storm" || {
    bad "$n exception lines under the NMI storm"
    grep -aE -m3 -A2 '\*\*\* EXCEPTION' "$TMPD/ist/serial.txt" | sed 's/^/        /'
}
[ "$s" -ge "$CYCLES" ] && ok "explorer started $s of $CYCLES times" || bad "explorer started $s of $CYCLES times"

echo "== counter-proof: nmiflat (NMI on the interrupted rsp, the old entry) =="
boot flat "nmiperiod=$PERIOD nmiflat" short
grep -aq 'hang: nmi on the interrupted rsp' "$TMPD/flat/serial.txt" \
    && ok "nmiflat took effect" || bad "nmiflat line missing"
n=$(faults flat)
[ "$n" -gt 0 ] && ok "the old entry faults ($n exception lines)" || bad "the old entry survived; the storm does not reach the gap"
grep -aE -m1 -A2 '\*\*\* EXCEPTION' "$TMPD/flat/serial.txt" | sed 's/^/        /'

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
