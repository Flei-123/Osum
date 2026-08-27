#!/usr/bin/env bash
# tools/arch/a64probe.sh -- HOW MUCH OF THIS KERNEL IS ALREADY AArch64 CODE?
#
# Round ARM, step E. `tools/arch/inventory.py` answers that question by
# READING the sources: it counts the lines that carry a mark of one machine.
# This script answers it by ASKING THE COMPILER, which is a different and
# harder question -- a file can look clean and still use something the other
# back end cannot express.
#
# The method: compile every module of the kernel as a root, once for
# `--target=x86_64-none` and once for `--target=aarch64-none`, and count the
# errors that the compiler attributes to THAT FILE. Errors in imported files
# belong to those files and are counted there.
#
#   the x86 run is the CONTROL. A module that does not compile freestanding
#   for x86-64 either is not a module of this kernel or the compiler is
#   broken; either way its aarch64 result says nothing. Only modules that
#   pass the control are counted.
#
# AND THEN A SECOND CONDITION, WHICH THE FIRST VERSION OF THIS SCRIPT DID
# NOT HAVE AND WHICH TURNED A WRONG NUMBER INTO A RIGHT ONE. The AArch64
# back end checks the REGISTER NAMES in an `asm` block and not the
# INSTRUCTION. So this compiles for `aarch64-none` without a word of
# complaint:
#
#     fn fence() { asm("mfence") }
#     fn halt()  { asm("hlt") }
#
# and only `aarch64-linux-gnu-as` says, three steps later, "unknown mnemonic
# `mfence'". `hlt` is worse: AArch64 HAS an instruction of that name, it
# takes an immediate, and it means "trap to the debugger" and not "wait for
# an interrupt" -- so `asm("hlt #0")` would assemble cleanly and do
# something else entirely. Measured, not assumed: `tools/arch/a64gap.sh`
# reproduces both in four lines.
#
# Therefore a module counts as unchanged only if it has NO inline assembly
# at all. A module with operand-less x86 assembly is reported in a class of
# its own -- it passes the compiler and would die in the assembler, which is
# the most expensive kind of "it works".
#
# `kernel/arch/x86_64/` IS NOT COUNTED. Those files are x86 by
# construction; that is what the directory means since step B. Counting them
# would be like measuring how portable a port is.
#
# WHICH COMPILER. Not the pinned one. `vendor/firn/COMMIT` names a Firn from
# before the freestanding AArch64 target existed, and it answers
# `--target=aarch64-linux` with "does not support the kernel profile yet
# (round 80)". The compiler used here has to be given:
#
#   FIRNC_A64=/path/to/firnc ./tools/arch/a64probe.sh
#
# and the number it produces is a number about THAT compiler on THAT day.
# It is not a promise about the pinned build and this script does not
# pretend otherwise -- it prints which binary it used and what that binary
# says its version is.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

FIRNC=${FIRNC_A64:-}
if [[ -z $FIRNC || ! -x $FIRNC ]]; then
    echo "set FIRNC_A64 to a firnc that knows --target=aarch64-none" >&2
    echo "(the pinned one in vendor/firn/bin does not; see the header)" >&2
    exit 2
fi

export FIRNLIB="$ROOT/lib"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "compiler: $FIRNC"
"$FIRNC" --version 2>&1 | sed 's/^/          /'
echo

FILES=()
while IFS= read -r f; do FILES+=("$f"); done < <(
    ls kernel/*.fi kernel/arch/*.fi 2>/dev/null | sort)

clean=0
dirty=0
mnemonic=0
skipped=0
capped=0
clean_lines=0
dirty_lines=0
mnemonic_lines=0

for f in "${FILES[@]}"; do
    # the control: does it compile freestanding for the machine it was
    # written for?
    if ! "$FIRNC" --target=x86_64-none -c -o "$TMP/x.o" "$f" >"$TMP/x.log" 2>&1; then
        skipped=$((skipped + 1))
        printf '  --    %-34s does not compile for x86_64-none either (%s)\n' \
            "$f" "$(grep -m1 '^error:' "$TMP/x.log" | cut -c1-60)"
        continue
    fi

    "$FIRNC" --target=aarch64-none -c -o "$TMP/a.o" "$f" >"$TMP/a.log" 2>&1
    own=$(grep -oE '^[[:space:]]+--> [^:]+' "$TMP/a.log" | sed 's/.*--> //' \
          | grep -cx "$f")
    grep -q 'were suppressed' "$TMP/a.log" && capped=$((capped + 1))

    inline=$(grep -c 'asm(' "$f")

    nlines=$(wc -l < "$f")

    if [ "$own" -eq 0 ] && [ "$inline" -eq 0 ]; then
        clean=$((clean + 1)); clean_lines=$((clean_lines + nlines))
        printf '  OK    %-30s no inline assembly, no error -- unchanged\n' "$f"
    elif [ "$own" -eq 0 ]; then
        mnemonic=$((mnemonic + 1)); mnemonic_lines=$((mnemonic_lines + nlines))
        printf '  ASM   %-30s passes the register check but holds %d x86 asm blocks\n' \
            "$f" "$inline"
    else
        dirty=$((dirty + 1)); dirty_lines=$((dirty_lines + nlines))
        printf '  x86   %-30s %d errors of its own, %d asm blocks\n' "$f" "$own" "$inline"
    fi
done

total=$((clean + dirty + mnemonic))
echo
echo "of $total modules under kernel/ that compile freestanding for x86-64:"
echo "  $clean unchanged for aarch64-none (no inline assembly, and no error)"
echo "  $mnemonic pass the register check but carry x86 instructions the ASSEMBLER"
echo "     would reject -- counted as NOT ported; see the header"
echo "  $dirty are rejected by the compiler outright"
if [ "$total" -gt 0 ]; then
    echo "share unchanged: $(awk -v c=$clean -v t=$total 'BEGIN{printf "%.1f %%", 100*c/t}')"
fi
tl=$((clean_lines + mnemonic_lines + dirty_lines))
echo "by LINES, which is the fairer measure of how much work is left:"
echo "  $clean_lines unchanged, $mnemonic_lines half-way, $dirty_lines x86, $tl in all"
if [ "$tl" -gt 0 ]; then
    echo "  share unchanged by lines: $(awk -v c=$clean_lines -v t=$tl 'BEGIN{printf "%.1f %%", 100*c/t}')"
fi
if [ "$skipped" -gt 0 ]; then
    echo "not counted (they fail the x86 control too): $skipped"
fi
if [ "$capped" -gt 0 ]; then
    echo "NOTE: $capped runs hit the compiler's 40-error cap. A cap can only HIDE"
    echo "      errors, so the two failing classes are lower bounds. The unchanged"
    echo "      class is not affected: it additionally requires zero asm blocks,"
    echo "      and that is read out of the source, where nothing is suppressed."
fi
echo
echo "A64PROBE: $clean of $total modules unchanged, $mnemonic half-way, $dirty x86"
