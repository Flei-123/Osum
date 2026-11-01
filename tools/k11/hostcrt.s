/* SPDX-License-Identifier: GPL-2.0-only */
    .section .text
    .globl _start
_start:
    xorq %rbp, %rbp
    movq %rsp, %rdi    andq $-16, %rsp
    call USER_ENTRY
    movq %rax, %rdi
    movq $60, %rax
    syscall
1:  jmp 1b

    .globl osum_panic
osum_panic:
    movq %rsi, %rdx
    movq %rdi, %rsi
    movq $2, %rdi
    movq $1, %rax
    syscall
    movq $70, %rdi
    movq $60, %rax
    syscall
2:  jmp 2b

    .text
    .globl osum_sighandler
osum_sighandler:
    incq osum_sigcount(%rip)
    movq %rdi, osum_siglast(%rip)
    ret
    .globl osum_sighandler2
osum_sighandler2:
    incq osum_sigcount2(%rip)
    movq %rdi, osum_siglast(%rip)
    ret
    .globl osum_sigexit
osum_sigexit:
    incq osum_sigcount(%rip)
    movq %rdi, osum_siglast(%rip)
    addq $40, %rdi
    movq $60, %rax
    syscall
1:  jmp 1b

    .bss
    .align 8
    .globl osum_sigcount
osum_sigcount:
    .skip 8
    .globl osum_sigcount2
osum_sigcount2:
    .skip 8
    .globl osum_siglast
osum_siglast:
    .skip 8

    .section .note.GNU-stack,"",@progbits
