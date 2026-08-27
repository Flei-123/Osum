#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/arch/a64gap.sh -- THE GAP THE REGISTER CHECK LEAVES OPEN.
#
# Round ARM found this while measuring, and it is worth four lines of its
# own because it makes a whole class of module look ported when it is not.
#
# The AArch64 back end of Firn checks the REGISTER NAMES inside an `asm`
# block: `in("dx")` is refused with "unknown register name 'dx'". It does
# not check the INSTRUCTION. So a block with no operands at all sails
# through the compiler and lands, unchanged, in the text handed to
# `aarch64-linux-gnu-as`.
#
# Two of them, and the second is the dangerous one:
#
#   mfence   does not exist on AArch64. The assembler says so. Noisy, cheap.
#   hlt      DOES exist on AArch64 -- and means "trap to the debugger", not
#            "wait for an interrupt". Bare `hlt` fails only because it wants
#            an immediate; `asm("hlt #0")` would assemble without a word and
#            do something else entirely.
#
#   FIRNC_A64=/path/to/firnc ./tools/arch/a64gap.sh
set -uo pipefail
cd "$(dirname "$0")/../.."
FIRNC=${FIRNC_A64:-}
[[ -x ${FIRNC:-} ]] || { echo "set FIRNC_A64 (see the header)" >&2; exit 2; }

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export FIRNLIB="$(pwd)/lib"

cat > "$TMP/gap.fi" <<'EOF'
profile kernel
export { fence, halt }
fn fence() { asm("mfence") }
fn halt() { asm("hlt") }
EOF

echo "== the compiler, --target=aarch64-none --emit=asm =="
if "$FIRNC" --target=aarch64-none --emit=asm -o "$TMP/gap.s" "$TMP/gap.fi" 2>"$TMP/c.err"; then
    echo "  the compiler accepted both blocks"
    grep -nE '^\s+(mfence|hlt)' "$TMP/gap.s" | sed 's/^/    emitted: /'
else
    echo "  the compiler refused them:"; sed 's/^/    /' "$TMP/c.err"
    exit 0
fi

echo "== the assembler, aarch64-linux-gnu-as =="
if aarch64-linux-gnu-as -o "$TMP/gap.o" "$TMP/gap.s" 2>"$TMP/a.err"; then
    echo "  it assembled -- which would mean the instructions mean something here"
else
    sed 's/^/    /' "$TMP/a.err"
fi
