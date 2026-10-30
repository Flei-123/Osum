    .text
    .code64

    .globl efi_main
efi_main:
    pushq %rbp
    movq %rsp, %rbp
    pushq %rbx
    pushq %rsi
    pushq %rdi
    pushq %r12
    pushq %r13
    pushq %r14
    pushq %r15
    subq $168, %rsp
    andq $-16, %rsp
    movdqu %xmm6, 0(%rsp)
    movdqu %xmm7, 16(%rsp)
    movdqu %xmm8, 32(%rsp)
    movdqu %xmm9, 48(%rsp)
    movdqu %xmm10, 64(%rsp)
    movdqu %xmm11, 80(%rsp)
    movdqu %xmm12, 96(%rsp)
    movdqu %xmm13, 112(%rsp)
    movdqu %xmm14, 128(%rsp)
    movdqu %xmm15, 144(%rsp)
    movq %rcx, %rdi
    movq %rdx, %rsi
    call osboot_main
    movdqu 0(%rsp), %xmm6
    movdqu 16(%rsp), %xmm7
    movdqu 32(%rsp), %xmm8
    movdqu 48(%rsp), %xmm9
    movdqu 64(%rsp), %xmm10
    movdqu 80(%rsp), %xmm11
    movdqu 96(%rsp), %xmm12
    movdqu 112(%rsp), %xmm13
    movdqu 128(%rsp), %xmm14
    movdqu 144(%rsp), %xmm15
    leaq -56(%rbp), %rsp
    popq %r15
    popq %r14
    popq %r13
    popq %r12
    popq %rdi
    popq %rsi
    popq %rbx
    popq %rbp
    ret

    .globl efi_call
efi_call:
    pushq %rbp
    movq %rsp, %rbp
    subq $64, %rsp
    andq $-16, %rsp
    movq 16(%rbp), %rax
    movq %rax, 40(%rsp)
    movq %r9, 32(%rsp)
    movq %rdi, %r10
    movq %r8, %r9
    movq %rcx, %r8
    movq %rsi, %rcx
    call *%r10
    movq %rbp, %rsp
    popq %rbp
    ret

    .include "handoff.s"
