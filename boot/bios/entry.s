    .text
    .code16
    .globl stage2_start
stage2_start:
    cli
    xorw %ax, %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %ss
    movw $0x7000, %sp
    movb %dl, 0x6080
    movl 0x7DA8, %eax
    movl %eax, 0x6084
    inb $0x92, %al
    orb $2, %al
    andb $0xFE, %al
    outb %al, $0x92
    movw $0x2401, %ax
    int $0x15
    cli
    lgdtl gdtr
    movl %cr0, %eax
    orl $1, %eax
    movl %eax, %cr0
    ljmpl $0x28, $pm_first

    .code32
pm_first:
    movw $0x10, %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %fs
    movw %ax, %gs
    movw %ax, %ss
    movl $0x7000, %esp
    movl $0x60000, %edi
    xorl %eax, %eax
    movl $6144, %ecx
    cld
    rep stosl
    movl $0x61003, 0x60000
    movl $0x62003, 0x61000
    movl $0x63003, 0x61008
    movl $0x64003, 0x61010
    movl $0x65003, 0x61018
    movl $0x62000, %edi
    movl $0x83, %eax
    movl $2048, %ecx
1:
    movl %eax, (%edi)
    movl $0, 4(%edi)
    addl $0x200000, %eax
    addl $8, %edi
    loop 1b
    movl $long_first, %esi

to_long:
    movl %cr4, %eax
    orl $0x20, %eax
    movl %eax, %cr4
    movl $0x60000, %eax
    movl %eax, %cr3
    movl $0xC0000080, %ecx
    rdmsr
    orl $0x100, %eax
    wrmsr
    movl %cr0, %eax
    orl $0x80000000, %eax
    movl %eax, %cr0
    pushl $0x08
    pushl %esi
    lret

    .code64
long_first:
    movl $0x10, %eax
    movl %eax, %ds
    movl %eax, %es
    movl %eax, %fs
    movl %eax, %gs
    movl %eax, %ss
    leaq bss_start(%rip), %rdi
    leaq bss_end(%rip), %rcx
    subq %rdi, %rcx
    xorl %eax, %eax
    cld
    rep stosb
    movq $0x9E000, %rsp
    call bios_main
1:
    cli
    hlt
    jmp 1b

    .globl bios_int
bios_int:
    pushq %rbx
    pushq %rbp
    pushq %r12
    pushq %r13
    pushq %r14
    pushq %r15
    movb %dil, int_op + 1(%rip)
    movq %rsp, saved_rsp(%rip)
    cli
    pushq $0x18
    leaq thunk16(%rip), %rax
    pushq %rax
    lretq

    .code16
thunk16:
    movw $0x20, %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %fs
    movw %ax, %gs
    movw %ax, %ss
    movl $0x7000, %esp
    movl %cr0, %eax
    andl $0x7FFFFFFF, %eax
    movl %eax, %cr0
    movl $0xC0000080, %ecx
    rdmsr
    andl $0xFFFFFEFF, %eax
    wrmsr
    movl %cr0, %eax
    andl $0xFFFFFFFE, %eax
    movl %eax, %cr0
    ljmpw $0, $real16
real16:
    xorw %ax, %ax
    movw %ax, %ds
    movw %ax, %ss
    movw $0x7000, %sp
    lidtl idtr_real
    movw 0x6022, %ax
    movw %ax, %es
    movl 0x6004, %ebx
    movl 0x6008, %ecx
    movl 0x600C, %edx
    movl 0x6010, %esi
    movl 0x6014, %edi
    movl 0x6018, %ebp
    pushl 0x6000
    movw 0x6020, %ax
    movw %ax, %ds
    popl %eax
    sti
int_op:
    int $0
    cli
    movl %eax, %cs:0x6000
    movl %ebx, %cs:0x6004
    movl %ecx, %cs:0x6008
    movl %edx, %cs:0x600C
    movl %esi, %cs:0x6010
    movl %edi, %cs:0x6014
    movl %ebp, %cs:0x6018
    pushfl
    popl %eax
    movl %eax, %cs:0x601C
    movw %ds, %ax
    movw %ax, %cs:0x6020
    movw %es, %ax
    movw %ax, %cs:0x6022
    xorw %ax, %ax
    movw %ax, %ds
    movw %ax, %es
    lgdtl gdtr
    movl %cr0, %eax
    orl $1, %eax
    movl %eax, %cr0
    ljmpl $0x28, $pm_back

    .code32
pm_back:
    movw $0x10, %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %fs
    movw %ax, %gs
    movw %ax, %ss
    movl $0x7000, %esp
    movl $long_back, %esi
    jmp to_long

    .code64
long_back:
    movl $0x10, %eax
    movl %eax, %ds
    movl %eax, %es
    movl %eax, %fs
    movl %eax, %gs
    movl %eax, %ss
    movq saved_rsp(%rip), %rsp
    popq %r15
    popq %r14
    popq %r13
    popq %r12
    popq %rbp
    popq %rbx
    ret

    .globl bios_outb
bios_outb:
    movw %di, %dx
    movb %sil, %al
    outb %al, %dx
    ret

    .globl bios_inb
bios_inb:
    movw %di, %dx
    xorl %eax, %eax
    inb %dx, %al
    ret

    .align 8
saved_rsp:
    .quad 0
    .align 8
gdt:
    .quad 0
    .quad 0x00209A0000000000
    .quad 0x00CF92000000FFFF
    .quad 0x00009A000000FFFF
    .quad 0x000092000000FFFF
    .quad 0x00CF9A000000FFFF
gdtr:
    .word 47
    .long gdt
idtr_real:
    .word 0x3FF
    .long 0

    .include "handoff.s"
