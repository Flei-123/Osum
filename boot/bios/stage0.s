    .code16
    .text
    .globl stage0_start
stage0_start:
    cli
    xorw %ax, %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %ss
    movw $0x7C00, %sp
    sti
    movb %dl, drive
    movl stage2_sectors, %ecx
    movl stage2_lba, %eax
    movl %eax, dap_lba
    movw $0x0800, dap_seg
next:
    movw $32, %ax
    cmpw %cx, %ax
    jbe 1f
    movw %cx, %ax
1:
    movw %ax, dap_count
    movb drive, %dl
    movb $0x42, %ah
    movw $dap, %si
    int $0x13
    jc fail
    movw dap_count, %ax
    xorl %edx, %edx
    movw %ax, %dx
    addl %edx, dap_lba
    shlw $5, %ax
    addw %ax, dap_seg
    subw dap_count, %cx
    jnz next
    movb drive, %dl
    ljmpw $0, $0x8000
fail:
    movw $0x0E45, %ax
    xorw %bx, %bx
    int $0x10
1:
    hlt
    jmp 1b
drive:
    .byte 0
    .align 4
dap:
    .byte 16, 0
dap_count:
    .word 0
    .word 0
dap_seg:
    .word 0
dap_lba:
    .quad 0
    .org 424
esp_lba:
    .long 0
stage2_lba:
    .long 0
stage2_sectors:
    .long 0
    .long 0x3042534F
