#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
ULD=kernel/user/user.ld
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

. tools/lib/firnenv.sh
as --64 -o "$TMPD/hostcrt.o" tools/k11/hostcrt.s || exit 1
FIRNLIB="$ROOT/lib" "$FIRNC" -c -o "$TMPD/fas.o" kernel/user/fas.fi > "$TMPD/fas.err" 2>&1 || { bad "fas.fi compile"; head -3 "$TMPD/fas.err"; exit 1; }
ld -T "$ULD" --defsym=USER_ENTRY=_F0.u_start -o "$TMPD/fas.host" "$TMPD/hostcrt.o" "$TMPD/fas.o" || exit 1

assemble_both() {
    local name=$1 body=$2
    printf '.intel_syntax noprefix\n.text\n.globl _start\n_start:\n%s\n    ret\n' "$body" > "$TMPD/$name.s"
    as --64 -o "$TMPD/$name.o" "$TMPD/$name.s" && objcopy -O binary -j .text "$TMPD/$name.o" "$TMPD/$name.gnu"
    "$TMPD/fas.host" "$TMPD/$name.s" -o "$TMPD/$name.elf" > "$TMPD/$name.fas" 2>&1
    local n
    n=$(stat -c%s "$TMPD/$name.gnu" 2>/dev/null || echo 0)
    tail -c +233 "$TMPD/$name.elf" > "$TMPD/$name.fasfull" 2>/dev/null
    head -c "$n" "$TMPD/$name.fasfull" > "$TMPD/$name.fasbin"
}

disasm() { objdump -D -b binary -mi386:x86-64 -M intel "$1" | sed -n 's/^[ 0-9a-f]*:\t[0-9a-f ]*\t//p' | sed 's/+0x0\]/]/; s/ *$//' | sed '/^ret/q'; }

regs=""
for op in addss subss mulss divss sqrtss; do
    for pair in "xmm0, xmm1" "xmm2, xmm1" "xmm7, xmm3" "xmm8, xmm15" "xmm9, xmm0" "xmm1, xmm12" "xmm15, xmm15"; do
        regs+="    $op $pair"$'\n'
    done
done
assemble_both regs "$regs"
if cmp -s "$TMPD/regs.gnu" "$TMPD/regs.fasbin" && [ -s "$TMPD/regs.gnu" ]; then ok "scalar single-precision register forms: bytes identical to GNU as ($(stat -c%s "$TMPD/regs.gnu") octets)"; else bad "register forms differ from GNU as"; head -3 "$TMPD/regs.fas"; fi

mems=""
for op in addss subss mulss divss sqrtss; do
    for m in "[rax]" "[rbx+8]" "[r12+16]" "[rsp]" "[r13]" "[rax+1000]"; do
        mems+="    $op xmm1, $m"$'\n'
        mems+="    $op xmm11, $m"$'\n'
    done
done
assemble_both mems "$mems"
disasm "$TMPD/mems.gnu" > "$TMPD/mems.gnu.txt"
disasm "$TMPD/mems.fasfull" > "$TMPD/mems.fas.txt"
if [ -s "$TMPD/mems.gnu.txt" ] && cmp -s "$TMPD/mems.gnu.txt" "$TMPD/mems.fas.txt"; then ok "scalar single-precision memory forms: decode identical to GNU as ($(wc -l < "$TMPD/mems.gnu.txt") instructions)"; else bad "memory forms decode differently"; diff "$TMPD/mems.gnu.txt" "$TMPD/mems.fas.txt" | head -5; fi

mkdir -p "$TMPD/old"
cp kernel/user/*.fi "$TMPD/old/"
git show 9e965032:kernel/user/fas.fi > "$TMPD/old/fas.fi"
if FIRNLIB="$ROOT/lib" "$FIRNC" -c -o "$TMPD/old/fas.o" "$TMPD/old/fas.fi" > "$TMPD/old/err" 2>&1 \
   && ld -T "$ULD" --defsym=USER_ENTRY=_F0.u_start -o "$TMPD/old/fas.host" "$TMPD/hostcrt.o" "$TMPD/old/fas.o"; then
    "$TMPD/old/fas.host" "$TMPD/regs.s" -o "$TMPD/old/regs.elf" > "$TMPD/old/regs.out" 2>&1
    if [ -s "$TMPD/old/regs.elf" ] && cmp -s <(tail -c +233 "$TMPD/old/regs.elf" | head -c "$(stat -c%s "$TMPD/regs.gnu")") "$TMPD/regs.gnu"; then bad "control: assembler before the change accepted the forms"; else ok "control: assembler before the change rejects the forms"; fi
else
    bad "control: old assembler did not build"; head -3 "$TMPD/old/err"
fi

echo "SSE: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
