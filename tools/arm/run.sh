#!/usr/bin/env bash
# tools/arm/run.sh -- THE ABNAHME OF THE AArch64 SIDE (round ARM).
#
# What is checked is what the machine SAYS, not what the source claims. The
# image built here is a kernel that reports each of its own steps with a
# number attached, and every number below is compared against something
# that was measured somewhere else:
#
#   1. THE MACHINE DESCRIBES ITSELF. `tools/arm/dtb.py` reads the device
#      tree QEMU dumps for `-M virt` and every address in
#      `kernel/arch/aarch64/virt.inc` is held against it. When a future
#      QEMU moves the GIC, this fails here instead of failing mysteriously
#      at run time.
#   2. IT BOOTS AND SAYS SO. The first octet on the PL011 arrives before
#      the MMU, the GIC or the timer exist -- so if it appears, the image
#      was loaded, `_start` ran, the stack was set and .bss was cleared.
#   3. THE VECTOR TABLE CATCHES A DELIBERATE EXCEPTION. `svc #0`, entry 4
#      of sixteen, ESR class 0x15, and the `eret` comes back.
#   4. TRANSLATION IS ON AND DOES SOMETHING. SCTLR_EL1.M read back out of
#      the processor; a 4 KiB page mapped by hand through three levels and
#      read back through its physical address; the same octet reached
#      through TTBR0 and through TTBR1.
#   5. THE TIMER FIRES THROUGH THE GIC. CNTFRQ_EL0 against the device tree,
#      and a hundred interrupts counted -- not a flag, a count.
#   6. TWO TASKS SHARE ONE PROCESSOR. `arch_switch` twenty times; the
#      pattern ABAB... is the proof, because a switch that half works
#      prints ABBB or stops.
#   7. VIRTIO IS MEMORY HERE, NOT A BUS. Thirty-two fixed slots, and the
#      count of devices changes when devices are attached.
#
# AND THE COUNTER-CHECKS, because a property without one is a claim:
#   nomm     without `mmu_init` the page proof MUST NOT come out right
#   noaf     the access flag left clear MUST give a data abort
#   notimer  without INTID 27 enabled the tick count MUST NOT be reached
#   noeoi    acknowledged but never finished: exactly ONE tick, then silence
#   novirtio without devices attached the device count MUST be 0
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

need() {
    command -v "$1" >/dev/null || { echo "missing: $1"; exit 1; }
}
need qemu-system-aarch64
need aarch64-linux-gnu-gcc
need aarch64-linux-gnu-ld

QEMU="qemu-system-aarch64 -M virt -cpu cortex-a53 -m 128 -nographic -kernel"

# lauf <image> <seconds> [extra qemu args...] -> writes $TMPD/out
lauf() {
    local img=$1 limit=$2; shift 2
    timeout "$limit" $QEMU "$img" "$@" >"$TMPD/out" 2>"$TMPD/err"
    return $?
}

feld() { # feld <key> -> the rest of the line after "osum-arm: <key>="
    sed -n "s/^osum-arm: $1=//p" "$TMPD/out" | tail -1
}

echo "== 1. the machine describes itself: dtb vs kernel/arch/aarch64/virt.inc =="
qemu-system-aarch64 -machine virt,dumpdtb="$TMPD/virt.dtb" -cpu cortex-a53 \
    -nographic >/dev/null 2>&1
if [ -s "$TMPD/virt.dtb" ]; then
    ok "QEMU dumped its device tree"
else
    bad "no device tree came out of QEMU"
fi
python3 tools/arm/dtb.py "$TMPD/virt.dtb" --facts > "$TMPD/facts" 2>"$TMPD/dtberr" \
    && ok "tools/arm/dtb.py read it ($(wc -l < "$TMPD/facts") facts)" \
    || { bad "tools/arm/dtb.py failed"; sed 's/^/        /' "$TMPD/dtberr"; }

INC=kernel/arch/aarch64/virt.inc
while read -r key hex dec; do
    want=$(sed -n "s/^[[:space:]]*\.set[[:space:]]\+$key,[[:space:]]*\([0-9a-fA-Fx]\+\).*/\1/p" "$INC" | head -1)
    [ -n "$want" ] || continue
    got=$((dec))
    if [ "$((want))" -eq "$got" ]; then
        ok "$key = $hex, and virt.inc says the same"
    else
        bad "$key: the machine says $hex, virt.inc says $want"
    fi
done < "$TMPD/facts"

echo "== 2. the image builds, and it boots =="
bash tools/arm/build.sh "$TMPD/osum-a64.elf" >"$TMPD/build.log" 2>&1 \
    && ok "tools/arm/build.sh: $(tail -1 "$TMPD/build.log")" \
    || { bad "the build failed"; sed 's/^/        /' "$TMPD/build.log"; exit 1; }

# The ELF has to be for the right machine and start where virt.ld says.
mach=$(readelf -h "$TMPD/osum-a64.elf" | sed -n 's/^  Machine: *//p')
[ "$mach" = "AArch64" ] && ok "ELF machine: AArch64" || bad "ELF machine '$mach'"
entry=$(readelf -h "$TMPD/osum-a64.elf" | sed -n 's/^  Entry point address: *//p')
[ "$((entry))" -eq "$((0x40080000))" ] \
    && ok "entry point $entry, which is where virt.ld puts it" \
    || bad "entry point $entry, expected 0x40080000"

lauf "$TMPD/osum-a64.elf" 30
rc=$?
[ $rc -eq 0 ] && ok "QEMU ended by itself (PSCI SYSTEM_OFF), exit $rc" \
              || bad "QEMU did not end by itself (exit $rc)"

grep -q '^osum-arm: hello$' "$TMPD/out" \
    && ok "the first line arrived on the PL011, before the MMU and the GIC" \
    || { bad "nothing arrived on the PL011"; sed 's/^/        /' "$TMPD/out" | head -5; }

echo "== 3. the exception level and the vector table =="
[ "$(feld el)" = "1" ] && ok "the kernel runs at EL1" || bad "EL is '$(feld el)', expected 1"

svc=$(feld svc)
[ "${svc%% *}" = "1" ] \
    && ok "the deliberate svc #0 was caught and returned from" \
    || bad "svc: '$svc'"
[ "$(echo "$svc" | awk '{print $2}')" = "0000000000000015" ] \
    && ok "ESR_EL1 class 0x15 -- the hardware named the cause, not the entry" \
    || bad "ESR class: '$(echo "$svc" | awk '{print $2}')', expected 0x15"

echo "== 4. translation =="
[ "$(feld mmu)" = "1" ] \
    && ok "SCTLR_EL1.M is set, read back out of the processor" \
    || bad "mmu: '$(feld mmu)'"

page=$(feld page)
[ "$(echo "$page" | awk '{print $3}')" = "1" ] \
    && ok "a page mapped by hand at $(echo "$page" | awk '{print $1}') through three levels, written and read back" \
    || bad "the page proof came out '$page'"
[ "$(echo "$page" | awk '{print $2}')" = "00badc0de0ddba11" ] \
    && ok "and the value that came back is the one that went in" \
    || bad "the value read back was '$(echo "$page" | awk '{print $2}')'"

t1=$(feld ttbr1)
[ "$(echo "$t1" | awk '{print $2}')" = "1" ] \
    && ok "the same octet through TTBR0 and through TTBR1 ($(echo "$t1" | awk '{print $1}'))" \
    || bad "the TTBR1 proof came out '$t1'"

echo "== 5. the timer, through the GIC =="
freq=$(feld freq)
# 62500000 Hz is what `-M virt` reports; it is not in the device tree, it is
# in CNTFRQ_EL0, so the only place to read it is the running machine. Pinning
# the value here means a QEMU that changes it fails HERE and not inside
# whatever depends on the tick rate later.
[ "$freq" = "62500000" ] \
    && ok "CNTFRQ_EL0 = $freq Hz, stated by the machine and not calibrated" \
    || bad "CNTFRQ_EL0 = '$freq', expected 62500000"
[ "$(feld ticks)" = "100" ] \
    && ok "100 virtual timer interrupts arrived through the GIC (INTID 27)" \
    || bad "ticks: '$(feld ticks)'"

echo "== 6. two tasks on one processor =="
sw=$(feld switch)
[ "$(echo "$sw" | awk '{print $1}')" = "ABABABABABABABABABAB" ] \
    && ok "arch_switch: ABABABABABABABABABAB -- twenty handovers, in order" \
    || bad "the pattern was '$(echo "$sw" | awk '{print $1}')'"
[ "$(echo "$sw" | awk '{print $2}')" = "20" ] \
    && ok "and the counter the two tasks share says 20" \
    || bad "the counter says '$(echo "$sw" | awk '{print $2}')'"

echo "== 7. virtio is memory here, not a bus =="
v=$(feld virtio)
[ "$(echo "$v" | awk '{print $1}')" = "32" ] \
    && ok "32 virtio-mmio slots answer with the magic number 0x74726976" \
    || bad "slots answering: '$(echo "$v" | awk '{print $1}')'"
[ "$(echo "$v" | awk '{print $2}')" = "0" ] \
    && ok "counter-check: with nothing attached, 0 of them name a device" \
    || bad "with nothing attached, $(echo "$v" | awk '{print $2}') named a device"

dd if=/dev/zero of="$TMPD/disk.img" bs=1M count=4 status=none
lauf "$TMPD/osum-a64.elf" 30 \
    -drive file="$TMPD/disk.img",if=none,format=raw,id=d0 \
    -device virtio-blk-device,drive=d0 \
    -netdev user,id=n0 -device virtio-net-device,netdev=n0
v=$(feld virtio)
[ "$(echo "$v" | awk '{print $2}')" = "2" ] \
    && ok "with a disk and a net card attached, 2 slots name a device" \
    || bad "with two devices attached, $(echo "$v" | awk '{print $2}') were found"

echo "== 8. the counter-checks =="

bash tools/arm/build.sh "$TMPD/nomm.elf" -DNO_MMU >/dev/null 2>&1
lauf "$TMPD/nomm.elf" 20
[ "$(feld mmu)" = "0" ] \
    && ok "nomm: SCTLR_EL1.M reads back 0 -- the switch really was skipped" \
    || bad "nomm: mmu reads '$(feld mmu)' with mmu_init left out"
esr=$(grep -o '^osum-arm: TRAP kind=4 [0-9a-f]*' "$TMPD/out" | awk '{print $4}')
far=$(sed -n 's/^osum-arm: TRAP kind=4 [0-9a-f]* \([0-9a-f]*\).*/\1/p' "$TMPD/out" | head -1)
if [ -n "$esr" ] && [ "$((0x${esr:8:8} >> 26))" -eq $((0x25)) ] \
   && [ "$((0x$far))" -eq "$((0x80000000))" ]; then
    ok "nomm: the write to 0x80000000 becomes a data abort (ESR 0x$esr, class 0x25, FAR 0x$far) -- without a table there is no page there"
else
    bad "nomm: expected a data abort at 0x80000000, got '$(grep '^osum-arm: TRAP' "$TMPD/out" | head -1)'"
fi
[ "$(feld page)" = "" ] \
    && ok "nomm: and no page proof is printed at all, so it cannot pass by accident" \
    || bad "nomm: a page proof appeared anyway: '$(feld page)'"

bash tools/arm/build.sh "$TMPD/noaf.elf" -DNO_AF >/dev/null 2>&1
lauf "$TMPD/noaf.elf" 20
rc=$?
# This one is worth reading closely. Every descriptor is built exactly as in
# the passing image except for bit 10. The result is not a wrong value and
# not an error message: the machine goes SILENT. The instruction after
# `mmu_init` cannot be fetched, the fault vector cannot be fetched either,
# and the processor loops in an exception it can never take. That silence is
# the counter-check, and it is why AF is called out in mmu.S by name.
if [ $rc -ne 0 ] && [ "$(feld mmu)" = "" ] && grep -q '^osum-arm: svc=' "$TMPD/out"; then
    ok "noaf: the access flag left clear stops the machine dead the moment translation is switched on -- no line after 'svc=', no fault report, nothing"
else
    bad "noaf: expected silence after 'svc='; got mmu='$(feld mmu)', page='$(feld page)', exit $rc"
fi

bash tools/arm/build.sh "$TMPD/notimer.elf" -DNO_TIMER_IRQ >/dev/null 2>&1
lauf "$TMPD/notimer.elf" 12
rc=$?
[ $rc -ne 0 ] && ok "notimer: without INTID 27 enabled the tick count is never reached (the run had to be stopped)" \
              || bad "notimer: the run finished anyway -- ticks '$(feld ticks)'"

bash tools/arm/build.sh "$TMPD/noeoi.elf" -DNO_EOI >/dev/null 2>&1
lauf "$TMPD/noeoi.elf" 12
rc=$?
if [ $rc -ne 0 ] && [ "$(feld freq)" = "62500000" ] && ! grep -q '^osum-arm: ticks=' "$TMPD/out"; then
    ok "noeoi: the run gets as far as 'freq=' and stops there -- one interrupt is taken, GICC_EOIR is never written, and the controller never delivers another"
else
    bad "noeoi: expected a stall after 'freq='; got ticks='$(feld ticks)', exit $rc"
fi

echo "== 9. how long until the machine says anything =="
python3 tools/arm/firstchar.py "$TMPD/osum-a64.elf" 5 | sed 's/^/   /' \
    && ok "the start was timed (the figure includes QEMU's own start, so it is an upper bound)" \
    || bad "timing the start failed"

echo
echo "ARM: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
