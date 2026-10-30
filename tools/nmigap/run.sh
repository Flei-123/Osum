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
jumps() { grep -ac 'usb: seq jump' "$TMPD/$1/serial.txt"; }
ringpeak() { grep -aoE ' rp=[0-9]+' "$TMPD/$1/serial.txt" | tail -n1 | cut -d= -f2; }

echo "== NMI every $PERIOD cycles, NMI on IST2 =="
boot ist "nmiperiod=$PERIOD nmiguard ${NMIGAP_WORDS:-}"
n=$(faults ist); s=$(starts ist)
[ "$n" -eq 0 ] && ok "no exception under the NMI storm" || {
    bad "$n exception lines under the NMI storm"
    grep -aE -m3 -A2 '\*\*\* EXCEPTION' "$TMPD/ist/serial.txt" | sed 's/^/        /'
}
[ "$s" -ge "$CYCLES" ] && ok "explorer started $s of $CYCLES times" || bad "explorer started $s of $CYCLES times"
j=$(jumps ist)
[ "$j" -eq 0 ] && ok "no usb seq jump (every completion delivered)" || {
    bad "$j usb seq jump lines"
    grep -a -m2 'usb: seq jump' "$TMPD/ist/serial.txt" | sed 's/^/        /'
}
grep -aq 'nmi: frame guard on, fix=' "$TMPD/ist/serial.txt" && ok "nmi frame guard armed" || bad "nmi frame guard line missing"
c=$(grep -ac 'nmi: frame changed' "$TMPD/ist/serial.txt")
[ "$c" -eq 0 ] && ok "no nmi return frame changed under the storm" || {
    bad "$c nmi return frames changed"
    grep -a -m2 'nmi: frame changed' "$TMPD/ist/serial.txt" | sed 's/^/        /'
}
echo "  info  faults inside nmi: $(grep -ac 'nmi: fault inside nmi' "$TMPD/ist/serial.txt") printed"
rp=$(ringpeak ist)
[ -n "$rp" ] && [ "$rp" -le 1 ] && ok "at most one transfer queued per hid endpoint (rp=$rp)" || bad "hid ring peak rp=${rp:-missing}, want 1"

echo "== planted #GP inside every 64th nmi after a spin (nmigpplant): the exception returns without iretq =="
boot plant "nmiperiod=$PERIOD nmiguard nmigpplant" short
f=$(grep -ac 'nmi: fault inside nmi' "$TMPD/plant/serial.txt")
[ "$f" -gt 0 ] && ok "planted faults taken inside nmi ($f printed)" || bad "no planted fault inside nmi"
n=$(faults plant); c=$(grep -ac 'nmi: frame changed' "$TMPD/plant/serial.txt")
[ "$n" -eq 0 ] && [ "$c" -eq 0 ] && ok "no exception, no nmi frame change with planted faults" || bad "$n exception lines, $c frame changes with planted faults"
s=$(starts plant)
[ "$s" -ge 2 ] && ok "explorer started $s of 2 times with planted faults" || bad "explorer started $s of 2 times with planted faults"

echo "== counter-proof: nonmifix (planted #GP returns with iretq, nmis unblocked inside the nmi) =="
boot plant0 "nmiperiod=$PERIOD nmiguard nmigpplant nonmifix" short
n=$(faults plant0); c=$(grep -ac 'nmi: frame changed' "$TMPD/plant0/serial.txt")
[ $((n + c)) -gt 0 ] && ok "iretq inside the nmi breaks the nmi frame ($n exception lines, $c frame changes)" || bad "nonmifix survived; the plant does not reach nesting"

echo "== counter-proof: usbstack (silence watchdog stacks a block on a live ring, the old refill) =="
boot stack "nmiperiod=$PERIOD usbstack" short
rp=$(ringpeak stack)
[ -n "$rp" ] && [ "$rp" -ge 2 ] && ok "the old refill stacks blocks (rp=$rp)" || bad "usbstack ring peak rp=${rp:-missing}, want >= 2"

echo "== counter-proof: nmiflat (NMI on the interrupted rsp, the old entry) =="
boot flat "nmiperiod=$PERIOD nmiflat" short
grep -aq 'hang: nmi on the interrupted rsp' "$TMPD/flat/serial.txt" \
    && ok "nmiflat took effect" || bad "nmiflat line missing"
n=$(faults flat)
[ "$n" -gt 0 ] && ok "the old entry faults ($n exception lines)" || bad "the old entry survived; the storm does not reach the gap"
grep -aE -m1 -A2 '\*\*\* EXCEPTION' "$TMPD/flat/serial.txt" | sed 's/^/        /'

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
