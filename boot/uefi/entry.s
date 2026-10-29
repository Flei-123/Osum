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

    .globl osum_panic
osum_panic:
    cli
1:  hlt
    jmp 1b

    .globl osboot_handoff
osboot_handoff:
    cli
    movq %rdi, %r14
    movq %rsi, %r12
    movq %rdx, %r13
    leaq tramp_start(%rip), %rsi
    movq %r14, %rdi
    movq $(tramp_end - tramp_start), %rcx
    cld
    rep movsb
    movq %r14, %rdi
    movq %r12, %rsi
    movq %r13, %rdx
    jmp *%r14

tramp_start:
    leaq 0x1000(%rdi), %rax
    movq %rax, %cr3
    leaq 0x7F0(%rdi), %rsp
    leaq (tramp_gdt - tramp_start)(%rdi), %rax
    movq %rax, (tramp_gdtr_base - tramp_start)(%rdi)
    lgdt (tramp_gdtr - tramp_start)(%rdi)
    movq %rdi, %r14
    movq %rsi, %r12
    movq %rdx, %r13
    movq 0x800(%r14), %r15
    leaq 0x808(%r14), %rbx
    cld
1:
    testq %r15, %r15
    jz 2f
    movq (%rbx), %rdi
    movq 8(%rbx), %rsi
    movq 16(%rbx), %rcx
    rep movsb
    movq 24(%rbx), %rcx
    subq 16(%rbx), %rcx
    xorl %eax, %eax
    rep stosb
    addq $32, %rbx
    decq %r15
    jmp 1b
2:
    movq %r14, %rdi
    movq %r12, %rsi
    movq %r13, %rdx
    leaq (tramp_prot - tramp_start)(%rdi), %rax
    pushq $0x08
    pushq %rax
    lretq
    .code32
tramp_prot:
    movl %edx, %ebx
    movw $0x10, %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %fs
    movw %ax, %gs
    movw %ax, %ss
    movl %cr0, %eax
    andl $0x7fffffff, %eax
    movl %eax, %cr0
    movl $0xC0000080, %ecx
    rdmsr
    andl $0xfffffeff, %eax
    wrmsr
    movl %cr4, %eax
    andl $0xffffffdf, %eax
    movl %eax, %cr4
    xorl %eax, %eax
    movl %eax, %cr3
    movl $0x2BADB002, %eax
    jmp *%esi
    .align 8
tramp_gdt:
    .quad 0
    .quad 0x00CF9A000000FFFF
    .quad 0x00CF92000000FFFF
tramp_gdtr:
    .word 23
tramp_gdtr_base:
    .quad 0
    .code64
tramp_end:
