#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/tickfix/run.sh -- ROUND TICKFIX: the boot must not stand at "ticks: waiting".
#
#   bash tools/tickfix/run.sh
#   TICKFIX_KERNEL=<k.mb> TICKFIX_KERNEL_B=<mutant.mb> bash tools/tickfix/run.sh   (prebuilt)
#
# The boss's Tiger Lake laptop stopped at `ticks: waiting` for good: the wait
# loop slept in `hlt`, no timer interrupt ever came, and its time limit was
# only looked at after a wake-up. Cases (QEMU, serial file, no display):
#
#   A  `notick`        the timer is silenced right before the tick wait:
#                      the new kernel says "ticks: NO TIMER IRQ after 5 s,
#                      continuing" plus the `timer:` diagnosis line and
#                      goes on to `kernel: done`.
#   B  counter-probe   the same kernel built with the limits cut out of
#                      `ticks()` (sed mutation of kmain.fi, restored right
#                      after the build): no message, no `kernel: done`.
#   C  `nopit`         the calibration has no PIT: it must still end up with
#                      a clock (src != 1) and real ticks (spin ticks > 0).
#   D  `nopit nopm`    ... and with neither PIT nor PM timer (CPUID 0x15 or
#                      HPET, whichever the VM offers).
#   E  `nopit nopm nocpuid nohpet`  no calibration source at all: the APIC
#                      stays off and the PIC must still tick (the real
#                      Tiger Lake bug: a failed `apic.init` left LINT0
#                      masked and the PIC mute).
#   G  `lapicmute`       the APIC timer is silent: the PIT reroute rescues it.
#   F  plain boot      nothing changed for a healthy machine: src=1, ticks.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
. tools/lib/qemu.sh
TMPD=$(mktemp -d)
KSAVE="$TMPD/kmain.orig"
restore() { [ -f "$KSAVE" ] && { cp "$KSAVE" kernel/kmain.fi; rm -f "$KSAVE"; }; }
trap 'restore; rm -rf "$TMPD"' EXIT
pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

command -v qemu-system-x86_64 >/dev/null 2>&1 || { echo "TICKFIX: skipped, qemu missing"; exit 0; }

echo "== build =="
if [[ -n ${TICKFIX_KERNEL:-} && -f $TICKFIX_KERNEL ]]; then
    cp "$TICKFIX_KERNEL" "$TMPD/k.mb"
elif ! bash tools/build-kernel.sh "$TMPD/k.mb" > "$TMPD/b.log" 2>&1; then
    echo "build failed"; tail -20 "$TMPD/b.log"; exit 1
fi

# Counter-probe kernel: the limits of the tick wait cut out.
if [[ -n ${TICKFIX_KERNEL_B:-} && -f $TICKFIX_KERNEL_B ]]; then
    cp "$TICKFIX_KERNEL_B" "$TMPD/kb.mb"
else
    cp kernel/kmain.fi "$KSAVE"
    sed -i -e 's/limit_tsc != 0 \&\& apic.tsc() - t0 > limit_tsc {/false {/' \
           -e 's/passes >= TICKS_PASS_LIMIT {/false {/' kernel/kmain.fi
    cmp -s kernel/kmain.fi "$KSAVE" && bad "mutation did not change kmain.fi (limits not found)"
    bash tools/build-kernel.sh "$TMPD/kb.mb" > "$TMPD/bb.log" 2>&1 || { echo "mutant build failed"; tail -5 "$TMPD/bb.log"; }
    restore
fi

run() { # name kernel append limit [cpu]
    local name=$1 k=$2 app=$3 t=${4:-60} cpu=${5:-max}
    local t0
    t0=$(date +%s)
    timeout "$t" $QEMU_X86 -kernel "$TMPD/$k" -m 512 -cpu "$cpu" \
        -append "$app" -serial "file:$TMPD/$name.txt" -display none \
        -no-reboot -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        >/dev/null 2>&1
    echo $(( $(date +%s) - t0 )) > "$TMPD/$name.secs"
    return 0
}
has() { grep -aq -- "$2" "$TMPD/$1.txt" 2>/dev/null; }
clk() { grep -a "^timer: src=" "$TMPD/$1.txt" 2>/dev/null | head -1; }
spin() { grep -a "^spin: ticks=+" "$TMPD/$1.txt" 2>/dev/null | head -1 | sed 's/.*+//'; }

BASE="osum nosched noproc nofs"
MSG="ticks: NO TIMER IRQ after 5 s, continuing"

echo "== A: silenced timer, new kernel =="
run A k.mb "$BASE notick" 90
has A "$MSG" && ok "A: fallback message on the console" || bad "A: no fallback message"
has A "^timer: src=" && ok "A: diagnosis line present: $(clk A)" || bad "A: no diagnosis line"
has A "kernel: done" && ok "A: boot reaches kernel: done" || bad "A: boot did not finish"
s=$(cat "$TMPD/A.secs"); [ "$s" -le 40 ] && ok "A: whole run ${s}s" || bad "A: run took ${s}s"

echo "== B: counter-probe (limits cut out) =="
if [[ -f $TMPD/kb.mb ]]; then
    run B kb.mb "$BASE notick" 40
    has B "$MSG" && bad "B: mutant printed the message" || ok "B: no message without the limits"
    has B "kernel: done" && bad "B: mutant finished the boot" || ok "B: mutant hangs (no kernel: done)"
    has B "ticks: waiting" && ok "B: mutant stands at 'ticks: waiting'" || bad "B: mutant never reached the wait"
else
    bad "B: no mutant kernel"
fi

echo "== C..E: calibration fallbacks =="
run C k.mb "$BASE nopit" 90
c=$(clk C); echo "      $c"
has C "kernel: done" && ok "C: boot done" || bad "C: boot did not finish"
[[ $c == *"src=2"* || $c == *"src=3"* || $c == *"src=4"* ]] && ok "C: clock from a fallback source" || bad "C: no fallback source ($c)"
[ "$(spin C)" -gt 0 ] 2>/dev/null && ok "C: ticks arrive (spin +$(spin C))" || bad "C: no ticks"
has C "$MSG" && bad "C: 5 s message although a source worked" || ok "C: no hang message"

run D k.mb "$BASE nopit nopm" 90
c=$(clk D); echo "      $c"
has D "kernel: done" && ok "D: boot done" || bad "D: boot did not finish"
[[ $c == *"src=3"* || $c == *"src=4"* ]] && ok "D: clock from CPUID 0x15 / HPET" || bad "D: no CPUID/HPET source ($c)"
[ "$(spin D)" -gt 0 ] 2>/dev/null && ok "D: ticks arrive (spin +$(spin D))" || bad "D: no ticks"

run E k.mb "$BASE nopit nopm nocpuid nohpet" 90
c=$(clk E); echo "      $c"
has E "kernel: done" && ok "E: boot done without any clock source" || bad "E: boot did not finish"
has E "apic: not there" && ok "E: APIC stays off (nothing calibrated)" || bad "E: APIC unexpectedly on"
[ "$(spin E)" -gt 0 ] 2>/dev/null && ok "E: the PIC still ticks (LINT0 put back, spin +$(spin E))" || bad "E: PIC path mute after the failed calibration (the Tiger Lake bug)"
has E "$MSG" && bad "E: hang message although the PIC ticks" || ok "E: no hang message"

echo "== G: APIC timer silent, PIT rerouted through the IOAPIC =="
run G k.mb "$BASE lapicmute" 90
has G "no APIC timer IRQ, trying PIT via IOAPIC" && ok "G: reroute message" || bad "G: no reroute message"
has G "kernel: done" && ok "G: boot done" || bad "G: boot did not finish"
[ "$(spin G)" -gt 0 ] 2>/dev/null && ok "G: ticks arrive via the PIT (spin +$(spin G))" || bad "G: no ticks after the reroute"
has G "$MSG" && bad "G: hang message although the reroute worked" || ok "G: no hang message"

echo "== F: healthy boot unchanged =="
run F k.mb "$BASE" 90
has F "kernel: done" && ok "F: boot done" || bad "F: boot did not finish"
has F "$MSG" && bad "F: hang message on a healthy boot" || ok "F: no hang message"
[ "$(spin F)" -gt 0 ] 2>/dev/null && ok "F: ticks arrive (spin +$(spin F))" || bad "F: no ticks"
has F "apic: " && ok "F: APIC line present" || bad "F: no APIC line"

echo "TICKFIX: $pass ok, $fail fail"
[ "$fail" -eq 0 ]
