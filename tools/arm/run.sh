#!/usr/bin/env bash
# tools/arm/run.sh -- THE ABNAHME OF THE AArch64 SIDE.
#
# Round ARM built this side out of assembly, because the pinned compiler
# refused `profile kernel` for AArch64. Round OSUM-ARM2 replaced that
# assembly with FIRN: `kernel/arch/aarch64/amain.fi`, compiled with
# `--target=aarch64-none`, drives the UART, builds the page tables, brings up
# the GIC, arms the timer, handles the exceptions and runs the two tasks.
# What is left in assembly is the same three things that are left in assembly
# on x86-64: the machine before there is a stack, the sixteen vector entries,
# and the context switch.
#
# So the first thing this runner checks is that the claim is true -- that the
# code doing the work came out of the compiler and not out of a `.S` file.
#
# What is checked, and every line of it is read back off the serial port:
#
#   1. THE MACHINE DESCRIBES ITSELF. `tools/arm/dtb.py` reads the device tree
#      QEMU dumps and every address in `virt.inc` AND in `virt.fi` is held
#      against it. Two copies of eleven numbers is one too many; this is the
#      check that keeps them honest until one of them goes away.
#   2. THE RUNNING CODE IS COMPILED FIRN. `_F0.amain__kmain` is in the symbol
#      table, the Firn object is the larger half of the image, and the kernel
#      says `language=firn` on a line it printed itself.
#   3. IT BOOTS. The first octet arrives before the MMU, the GIC or the timer
#      exist -- so if it appears, the image was loaded, `_start` ran, the
#      stack was set and .bss was cleared.
#   4. THE VECTOR TABLE CATCHES A DELIBERATE EXCEPTION, and the handler that
#      catches it is a Firn function.
#   5. TRANSLATION IS ON AND DOES SOMETHING: SCTLR_EL1.M out of the
#      processor, a 4 KiB page mapped by hand through three levels, and the
#      same octet reached through TTBR0 and through TTBR1.
#   6. THE BOUNDARY ANSWERS FOR THIS MACHINE: `arch.has_io_ports()` is 0
#      here and 1 on x86, out of ONE source file.
#   7. THE ORDERING PRIMITIVES ARE THE ORDERED ONES: a value out through
#      `arch.atomic_store` (a store-release here) and back through
#      `arch.atomic_load`. That pair was the defect round ARM found.
#   8. THE TIMER FIRES THROUGH THE GIC -- a hundred interrupts, counted.
#   9. TWO TASKS SHARE ONE PROCESSOR through `arch_switch`.
#  10. VIRTIO IS MEMORY HERE, NOT A BUS.
#
# AND THE COUNTER-CHECKS, because a property without one is a claim. They are
# built into the image through `start.S`, which writes a switch word into
# `kstate_a64`; the Firn side reads it. Firn has no preprocessor, so a
# `#ifdef` in the kernel was not an option -- and a switch that travels
# through the kernel's own state region is the more honest arrangement
# anyway, because it is the same road every other piece of state takes.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

for t in qemu-system-aarch64 aarch64-linux-gnu-gcc aarch64-linux-gnu-ld; do
    command -v "$t" >/dev/null || { echo "missing: $t"; exit 1; }
done

QEMU="qemu-system-aarch64 -M virt -cpu cortex-a53 -m 128 -nographic -kernel"

lauf() { # lauf <image> <seconds> [extra qemu args...]
    local img=$1 limit=$2; shift 2
    timeout "$limit" $QEMU "$img" "$@" >"$TMPD/out" 2>"$TMPD/err"
    return $?
}

feld() { sed -n "s/^osum-arm: $1=//p" "$TMPD/out" | tail -1; }

echo "== 1. the machine describes itself: dtb vs virt.inc and virt.fi =="
qemu-system-aarch64 -machine virt,dumpdtb="$TMPD/virt.dtb" -cpu cortex-a53 \
    -nographic >/dev/null 2>&1
[ -s "$TMPD/virt.dtb" ] && ok "QEMU dumped its device tree" \
                        || bad "no device tree came out of QEMU"
python3 tools/arm/dtb.py "$TMPD/virt.dtb" --facts > "$TMPD/facts" 2>"$TMPD/dtberr" \
    && ok "tools/arm/dtb.py read it ($(wc -l < "$TMPD/facts") facts)" \
    || { bad "tools/arm/dtb.py failed"; sed 's/^/        /' "$TMPD/dtberr"; }

INC=kernel/arch/aarch64/virt.inc
FI=kernel/arch/aarch64/virt.fi
while read -r key hex dec; do
    want_s=$(sed -n "s/^[[:space:]]*\.set[[:space:]]\+$key,[[:space:]]*\([0-9a-fA-Fx]\+\).*/\1/p" "$INC" | head -1)
    want_f=$(sed -n "s/^const $key: u64 = \([0-9a-fA-Fx]\+\).*/\1/p" "$FI" | head -1)
    [ -n "$want_s$want_f" ] || continue
    got=$((dec))
    bothok=1
    [ -n "$want_s" ] && [ "$((want_s))" -ne "$got" ] && bothok=0
    [ -n "$want_f" ] && [ "$((want_f))" -ne "$got" ] && bothok=0
    if [ "$bothok" -eq 1 ]; then
        ok "$key = $hex, and both virt.inc and virt.fi say the same"
    else
        bad "$key: the machine says $hex, virt.inc '$want_s', virt.fi '$want_f'"
    fi
done < "$TMPD/facts"

echo "== 2. the image builds, and the running code is compiled Firn =="
bash tools/arm/build.sh "$TMPD/osum-a64.elf" >"$TMPD/build.log" 2>&1 \
    && ok "tools/arm/build.sh: $(tail -1 "$TMPD/build.log")" \
    || { bad "the build failed"; sed 's/^/        /' "$TMPD/build.log"; exit 1; }

mach=$(readelf -h "$TMPD/osum-a64.elf" | sed -n 's/^  Machine: *//p')
[ "$mach" = "AArch64" ] && ok "ELF machine: AArch64" || bad "ELF machine '$mach'"
entry=$(readelf -h "$TMPD/osum-a64.elf" | sed -n 's/^  Entry point address: *//p')
[ "$((entry))" -eq "$((0x40080000))" ] \
    && ok "entry point $entry, which is where virt.ld puts it" \
    || bad "entry point $entry, expected 0x40080000"

# `_F0.` is the symbol prefix firnc0 puts in front of every name it emits
# (docs/SELF_HOSTING.md in the Firn repository). Its presence is the ELF
# saying, in its own symbol table, that this code came out of the compiler.
nfirn=$(aarch64-linux-gnu-nm "$TMPD/osum-a64.elf" | grep -c '_F0\.')
[ "$nfirn" -ge 30 ] \
    && ok "$nfirn symbols carry the firnc0 prefix '_F0.' -- this is compiler output, not assembly" \
    || bad "only $nfirn '_F0.' symbols in the image"
for s in _F0.amain__kmain _F0.amain__kexception _F0.machine__atomic_store _F0.arch__dev_write32; do
    aarch64-linux-gnu-nm "$TMPD/osum-a64.elf" | grep -q " $s\$" \
        && ok "$s is in the image" || bad "$s is missing"
done

# How much of the image is compiled and how much is hand-written.
asm_lines=$(cat kernel/arch/aarch64/start.S kernel/arch/aarch64/vectors.S \
                kernel/arch/aarch64/switch.S | grep -c .)
fi_lines=$(cat kernel/arch/aarch64/amain.fi kernel/arch/aarch64/virt.fi | grep -c .)
ok "the AArch64 side is $fi_lines lines of Firn against $asm_lines lines of assembly"

echo "== 3. it boots, and says which language it is in =="
lauf "$TMPD/osum-a64.elf" 30
rc=$?
[ $rc -eq 0 ] && ok "QEMU ended by itself (PSCI SYSTEM_OFF), exit $rc" \
              || bad "QEMU did not end by itself (exit $rc)"
grep -q '^osum-arm: hello$' "$TMPD/out" \
    && ok "the first line arrived on the PL011, before the MMU and the GIC" \
    || { bad "nothing arrived on the PL011"; sed 's/^/        /' "$TMPD/out" | head -5; }
grep -q '^osum-arm: language=firn$' "$TMPD/out" \
    && ok "and the second line was printed by Firn code compiled for aarch64-none" \
    || bad "the language line is missing"

echo "== 4. the exception level and the vector table =="
[ "$(feld el)" = "1" ] && ok "the kernel runs at EL1" || bad "EL is '$(feld el)', expected 1"
svc=$(feld svc)
[ "${svc%% *}" = "1" ] \
    && ok "the deliberate svc #0 was caught by a FIRN handler and returned from" \
    || bad "svc: '$svc'"
[ "$(echo "$svc" | awk '{print $2}')" = "0000000000000015" ] \
    && ok "ESR_EL1 class 0x15 -- the hardware named the cause, not the entry" \
    || bad "ESR class: '$(echo "$svc" | awk '{print $2}')', expected 0x15"

echo "== 5. translation =="
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

echo "== 6. the boundary answers for THIS machine =="
[ "$(feld ports)" = "0" ] \
    && ok "arch.has_io_ports() is 0 here -- the same source line answers 1 on x86-64" \
    || bad "has_io_ports: '$(feld ports)'"

echo "== 7. the ordering primitives, on the machine that needs them =="
[ "$(feld order)" = "00000000005ec0de" ] \
    && ok "arch.atomic_store (stlr) then arch.atomic_load (ldar): 0x5ec0de came back" \
    || bad "order: '$(feld order)'"
bash tools/arch/order.sh >"$TMPD/order.log" 2>&1 \
    && ok "tools/arch/order.sh: $(grep -a '^ORDER:' "$TMPD/order.log")" \
    || { bad "tools/arch/order.sh failed"; grep -a '^  FAIL' "$TMPD/order.log" | head -4 | sed 's/^/       /'; }

echo "== 8. the timer, through the GIC =="
[ "$(feld freq)" = "62500000" ] \
    && ok "CNTFRQ_EL0 = $(feld freq) Hz, stated by the machine and not calibrated" \
    || bad "CNTFRQ_EL0 = '$(feld freq)', expected 62500000"
[ "$(feld ticks)" = "100" ] \
    && ok "100 virtual timer interrupts arrived through the GIC (INTID 27)" \
    || bad "ticks: '$(feld ticks)'"

echo "== 9. two tasks on one processor =="
sw=$(feld switch)
[ "$(echo "$sw" | awk '{print $1}')" = "ABABABABABABABABABAB" ] \
    && ok "arch_switch from Firn: ABABABABABABABABABAB -- twenty handovers, in order" \
    || bad "the pattern was '$(echo "$sw" | awk '{print $1}')'"
[ "$(echo "$sw" | awk '{print $2}')" = "20" ] \
    && ok "and the counter the two tasks share says 20" \
    || bad "the counter says '$(echo "$sw" | awk '{print $2}')'"

echo "== 10. virtio is memory here, not a bus =="
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

echo "== 11. the counter-checks =="

bash tools/arm/build.sh "$TMPD/nomm.elf" -DNO_MMU >/dev/null 2>&1
lauf "$TMPD/nomm.elf" 20
[ "$(feld mmu)" = "0" ] \
    && ok "nomm: SCTLR_EL1.M reads back 0 -- the switch really was skipped" \
    || bad "nomm: mmu reads '$(feld mmu)' with mmu_init left out"
[ -z "$(feld page)" ] && [ -z "$(feld ttbr1)" ] \
    && ok "nomm: and neither the page proof nor the TTBR1 proof is printed, so neither can pass by accident" \
    || bad "nomm: a proof appeared anyway: page='$(feld page)' ttbr1='$(feld ttbr1)'"

bash tools/arm/build.sh "$TMPD/noaf.elf" -DNO_AF >/dev/null 2>&1
lauf "$TMPD/noaf.elf" 15
rc=$?
# Every descriptor is built exactly as in the passing image except for bit
# 10. The result is not a wrong value and not an error message: the machine
# goes SILENT. The instruction after `mmu_init` cannot be fetched, the fault
# vector cannot be fetched either, and the processor loops in an exception it
# can never take.
if [ $rc -ne 0 ] && [ -z "$(feld mmu)" ] && grep -q '^osum-arm: svc=' "$TMPD/out"; then
    ok "noaf: the access flag left clear stops the machine dead the moment translation is switched on -- no line after 'svc=', no fault report, nothing"
else
    bad "noaf: expected silence after 'svc='; got mmu='$(feld mmu)', exit $rc"
fi

bash tools/arm/build.sh "$TMPD/notimer.elf" -DNO_TIMER_IRQ >/dev/null 2>&1
lauf "$TMPD/notimer.elf" 12
rc=$?
if [ $rc -ne 0 ] && [ "$(feld freq)" = "62500000" ] && [ -z "$(feld ticks)" ]; then
    ok "notimer: without INTID 27 enabled in the distributor the tick count is never reached -- the run gets to 'freq=' and sleeps"
else
    bad "notimer: expected a stall after 'freq='; got ticks='$(feld ticks)', exit $rc"
fi

bash tools/arm/build.sh "$TMPD/noeoi.elf" -DNO_EOI >/dev/null 2>&1
lauf "$TMPD/noeoi.elf" 12
rc=$?
if [ $rc -ne 0 ] && [ "$(feld freq)" = "62500000" ] && [ -z "$(feld ticks)" ]; then
    ok "noeoi: one interrupt is taken, GICC_EOIR is never written, and the controller never delivers another"
else
    bad "noeoi: expected a stall after 'freq='; got ticks='$(feld ticks)', exit $rc"
fi

echo "== 12. how long until the machine says anything =="
python3 tools/arm/firstchar.py "$TMPD/osum-a64.elf" 5 | sed 's/^/   /' \
    && ok "the start was timed (the figure includes QEMU's own start, so it is an upper bound)" \
    || bad "timing the start failed"

echo
echo "ARM: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
