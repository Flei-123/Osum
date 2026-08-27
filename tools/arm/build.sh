#!/usr/bin/env bash
# tools/arm/build.sh -- ONE AArch64 image, out of the repository.
#
#   ./tools/arm/build.sh OUTPUT [-DSWITCH ...]
#
# The counterpart to tools/build-kernel.sh, and deliberately a separate
# script rather than a flag on that one: the two builds have nothing in
# common except the word "kernel". The x86 image is a Multiboot ELF32 shell
# around ELF64 with six assembly files and two Firn modules; this one is an
# ELF64 for `-M virt` built out of assembly ALONE, because the pinned Firn
# compiler refuses `profile kernel` for `--target=aarch64-linux`
# (`codegen_a64.rs`, "does not support the kernel profile yet"). The moment
# that refusal goes away, the Firn modules join in here and this script
# grows the two lines that call the compiler -- and not before, because a
# build script that pretends to compile something is worse than one that
# does not try.
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
FILES=(start vectors uart mmu gic timer switch atomic probe)

for f in "${FILES[@]}"; do
    "$AS" -x assembler-with-cpp -c -I"$SRC" "${DEFS[@]}" \
        -o "$TMP/$f.o" "$SRC/$f.S" || { echo "assembling $f.S failed" >&2; exit 1; }
done

OBJS=()
for f in "${FILES[@]}"; do OBJS+=("$TMP/$f.o"); done

mkdir -p "$(dirname "$OUT")"
"$LD" -T "$SRC/virt.ld" -o "$OUT" "${OBJS[@]}" 2> >(grep -vE 'LOAD segment with RWX' >&2) \
    || { echo "linking failed" >&2; exit 1; }

echo "$OUT ($(stat -c%s "$OUT") octets${DEFS[*]:+, ${DEFS[*]}})"
