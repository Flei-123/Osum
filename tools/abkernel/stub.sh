#!/usr/bin/env bash
set -euo pipefail
OUT=${1:?usage: stub.sh <out.mb> <marker> <hang|reset|up>}
MARKER=${2:?}
MODE=${3:?}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
case "$MODE" in
    reset) TAIL=$'    lidt idt_zero\n    int3' ;;
    *) TAIL=$'halt:\n    hlt\n    jmp halt' ;;
esac
cat > "$W/stub.s" <<ASM
.section .text
.align 4
.long 0x1BADB002
.long 0
.long -0x1BADB002
.globl _start
_start:
    cli
    mov \$msg, %esi
    mov \$0x3f8, %dx
next:
    lodsb
    test %al, %al
    jz done
    out %al, %dx
    jmp next
done:
$TAIL
.align 4
idt_zero:
    .word 0
    .long 0
msg:
    .asciz "$MARKER\n"
ASM
as --32 -o "$W/stub.o" "$W/stub.s"
ld -m elf_i386 -Ttext=0x101000 -z noseparate-code --build-id=none -e _start -o "$OUT" "$W/stub.o"
