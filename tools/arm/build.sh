#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/arm/build.sh -- ONE AArch64 image, out of the repository.
#
#   ./tools/arm/build.sh OUTPUT [-DSWITCH ...]
#
# The counterpart to tools/build-kernel.sh. Round ARM built the image out of
# assembly ALONE, because the pinned compiler refused `profile kernel` for
# aarch64. Firn's round ARM-FREESTANDING removed that refusal, so this script
# now does what the x86 one does: it calls the compiler, and what is left in
# assembly is what a language cannot say.
#
#   kernel/kmain_a64.fi -> firnc --target=aarch64-none   the kernel
#   start.S    the machine before there is a stack, and `osum_panic`
#   vectors.S  sixteen entries of 0x80 octets each
#   switch.S   swapping the stack pointer under a running function
#
# BUILD IT WITH firnc0. `firnc1`, the compiler written in Firn, refuses
# `--target=aarch64-*` and says so -- there is no A64 code generator in Firn
# yet. So this script has no `--stufe 1`, and pretending otherwise would be
# a build option that cannot work.
#
# The switches are the counter-checks (`tools/arm/run.sh`):
#   -DNO_MMU        do not switch translation on
#   -DNO_AF         build the descriptors with the access flag CLEAR
#   -DNO_TIMER_IRQ  do not enable INTID 27 in the distributor
#   -DNO_EOI        acknowledge the interrupt but never finish it
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

OUT=${1:-}
if [[ -z $OUT ]]; then
    sed -n '2,20p' "$0"
    exit 1
fi
shift
DEFS=("$@")

SRC="$ROOT/kernel/arch/aarch64"
AS=aarch64-linux-gnu-gcc
LD=aarch64-linux-gnu-ld

command -v "$AS" >/dev/null || { echo "missing: $AS (apt install gcc-aarch64-linux-gnu)" >&2; exit 1; }
command -v "$LD" >/dev/null || { echo "missing: $LD" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# The order is the link order and it is not alphabetical: `start.S` holds
# `.text.boot`, which `virt.ld` keeps first, and the entry point has to be
# the first thing in the image for a loader that ignores the ELF header.
FILES=(start vectors switch)

for f in "${FILES[@]}"; do
    "$AS" -x assembler-with-cpp -c -I"$SRC" "${DEFS[@]}" \
        -o "$TMP/$f.o" "$SRC/$f.S" || { echo "assembling $f.S failed" >&2; exit 1; }
done

export FIRNLIB="$ROOT/lib"
bash vendor/firn/fetch-firnc.sh >/dev/null || {
    echo "vendor/firn/fetch-firnc.sh failed" >&2; exit 1; }
FIRNC="$ROOT/vendor/firn/bin/firnc"
[[ -x $FIRNC ]] || { echo "the compiler is missing: $FIRNC" >&2; exit 1; }

# The counter-check switches of tools/arm/run.sh reach the Firn side as
# `--define`d constants would on the assembly side; there is no preprocessor
# here, so they are passed as a source-level switch instead. `-DNO_*` that
# the assembly does not know is simply not used by it.
FIRNDEFS=()
for d in "${DEFS[@]}"; do FIRNDEFS+=("$d"); done

"$FIRNC" --target=aarch64-none -c -o "$TMP/kernel.o" "$ROOT/kernel/kmain_a64.fi" \
    || { echo "compiling kernel/kmain_a64.fi for aarch64-none failed" >&2; exit 1; }

OBJS=()
for f in "${FILES[@]}"; do OBJS+=("$TMP/$f.o"); done
OBJS+=("$TMP/kernel.o")

mkdir -p "$(dirname "$OUT")"
"$LD" -T "$SRC/virt.ld" \
    --defsym=KERN_MAIN=_F0.start \
    --defsym=KERN_TRAP=_F0.amain__kexception \
    -o "$OUT" "${OBJS[@]}" 2> >(grep -vE 'LOAD segment with RWX' >&2) \
    || { echo "linking failed" >&2; exit 1; }

fi_octets=$(stat -c%s "$TMP/kernel.o")
echo "$OUT ($(stat -c%s "$OUT") octets, of which the Firn object is $fi_octets${DEFS[*]:+, ${DEFS[*]}})"
