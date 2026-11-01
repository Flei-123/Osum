/* SPDX-License-Identifier: GPL-2.0-only */

    .section .text

    .globl hv_vmrun
hv_vmrun:
    pushq %rbp
    pushq %rbx
    pushq %r12
    pushq %r13
    pushq %r14
    pushq %r15

    pushq %rdi                      /* [16] das VMCB */
    pushq %rdx                      /* [8]  Wirtsbereich */
    pushq %rsi                      /* [0]  Registerblock */

    clgi

    movq %rdx, %rax
    vmsave

    movq %rdi, %rax
    vmload

    movq %rdi, %rax                 /* VMRUN nimmt das VMCB in rax */
    movq   0(%rsi), %rbx
    movq   8(%rsi), %rcx
    movq  16(%rsi), %rdx
    movq  24(%rsi), %rbp
    movq  32(%rsi), %r8
    movq  40(%rsi), %r9
    movq  48(%rsi), %r10
    movq  56(%rsi), %r11
    movq  64(%rsi), %r12
    movq  72(%rsi), %r13
    movq  80(%rsi), %r14
    movq  88(%rsi), %r15
    movq  96(%rsi), %rdi
    movq 104(%rsi), %rsi

    vmrun

    pushq %rsi                      /* rsi des Gasts zwischenlagern */
    movq 8(%rsp), %rsi              /* der Registerblock */
    movq %rbx,   0(%rsi)
    movq %rcx,   8(%rsi)
    movq %rdx,  16(%rsi)
    movq %rbp,  24(%rsi)
    movq %r8,   32(%rsi)
    movq %r9,   40(%rsi)
    movq %r10,  48(%rsi)
    movq %r11,  56(%rsi)
    movq %r12,  64(%rsi)
    movq %r13,  72(%rsi)
    movq %r14,  80(%rsi)
    movq %r15,  88(%rsi)
    movq %rdi,  96(%rsi)
    popq %rax                       /* rsi des Gasts */
    movq %rax, 104(%rsi)

    popq %rsi
    popq %rdx                       /* Wirtsbereich */
    popq %rdi                       /* das VMCB */
    movq %rdi, %rax
    vmsave                          /* Gast: FS/GS/TR/LDTR zurueck ins VMCB */
    movq %rdx, %rax
    vmload                          /* Wirt: FS/GS/TR/LDTR/STAR/LSTAR zurueck */
    stgi

    popq %r15
    popq %r14
    popq %r13
    popq %r12
    popq %rbx
    popq %rbp
    ret

    .globl hv_guest_save
hv_guest_save:
    movq %rdi, %rax
    vmsave
    ret

/* `hv_stgi()` / `hv_clgi()` -- das globale Unterbrechungsflag. */
    .globl hv_stgi
hv_stgi:
    stgi
    ret

    .globl hv_clgi
hv_clgi:
    clgi
    ret


    .section .rodata
    .align 16

    .code16
    .globl g_hello_start, g_hello_end
g_hello_start:
    cli
    movw $0x0100, %ax
    movw %ax, %ds                   /* DS.base = 0x1000: das Abbild */
    xorw %ax, %ax
    movw %ax, %es
    movw %ax, %ss
    movw $0x0FF0, %sp

    movw $(g_hello_txt - g_hello_start), %si
    movw $0x03F8, %dx
1:  movb (%si), %al
    testb %al, %al
    jz 2f
    outb %al, %dx
    incw %si
    jmp 1b
2:
    xorl %eax, %eax
    cpuid
    movl $1, %ecx
    movl $1, %eax
    vmmcall

    movl $1, %eax
    cpuid
    movl %ecx, %ebx                 /* ecx Bit 31 = "du bist ein Gast" */
    movl $2, %ecx
    movl $1, %eax
    vmmcall

    movw $0x0800, %si
    movw %es:(%si), %bx
    movzwl %bx, %ebx
    movl $3, %ecx
    movl $1, %eax
    vmmcall

    movw $0x0080, %si
    movw $(g_hello_isr - g_hello_start), %ax
    movw %ax, %es:(%si)
    movw $0x0100, %ax               /* Segment 0x0100 -> linear 0x1000 */
    movw %ax, %es:2(%si)
    xorl %ebp, %ebp
    movl $1, %ecx
    movl $3, %eax
    vmmcall
    movl %ebp, %ebx
    movl $4, %ecx
    movl $1, %eax
    vmmcall

    movl $0x1234, %ebx
    movl $2, %eax
    vmmcall
    hlt
3:  jmp 3b

g_hello_isr:
    movw $0xABCD, %bp
    iret

g_hello_txt:
    .asciz "hallo vom gast\n"
    .align 4
g_hello_end:

    .code16
    .globl g_pm_start, g_pm_end
g_pm_start:
    cli
    movw $0x0100, %ax
    movw %ax, %ds
    xorw %ax, %ax
    movw %ax, %ss
    movw $0x0FF0, %sp

    movw $(g_pm_gdtr - g_pm_start), %si
    lgdtl (%si)

    movl %cr0, %eax
    orl  $1, %eax
    movl %eax, %cr0                 /* geschuetzter Modus an */

    ljmpl $0x08, $(g_pm_32 - g_pm_start + 0x1000)

    .code32
g_pm_32:
    movw $0x10, %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %fs
    movw %ax, %gs
    movw %ax, %ss
    movl $0x6FF0, %esp              /* Seite 6, weit weg vom Abbild */

    cld
    movl $0x2000, %edi
    xorl %eax, %eax
    movl $3072, %ecx                /* 0x3000 Oktette / 4 */
    rep stosl

    /* Verzeichnis[0] -> 0x3000, Verzeichnis[1] -> 0x4000 */
    movl $0x00003003, 0x2000
    movl $0x00004003, 0x2004

    movl $0x3000, %edi
    movl $0x00000003, %eax
    movl $1024, %ecx
1:  movl %eax, (%edi)
    addl $0x1000, %eax
    addl $4, %edi
    loop 1b

    /* Tabelle 0x4000, Eintrag 0: virtuell 0x00400000 -> physisch 0x5000 */
    movl $0x00005003, 0x4000

    movl $0x2000, %eax
    movl %eax, %cr3
    movl %cr0, %eax
    orl  $0x80000000, %eax
    movl %eax, %cr0                 /* das eigene Paging an */

    movl $0x5A5AC0DE, %eax
    movl %eax, 0x00400000

    movl 0x5000, %ebx
    movl $5, %ecx
    movl $1, %eax
    vmmcall

    movl %cr0, %ebx
    movl $6, %ecx
    movl $1, %eax
    vmmcall
    movl %cr3, %ebx
    movl $7, %ecx
    movl $1, %eax
    vmmcall

    movw $0x0510, %dx
    movb $0x37, %al
    outb %al, %dx

    movl $0x2222, %ebx
    movl $2, %eax
    vmmcall
    hlt
2:  jmp 2b

    .align 8
g_pm_gdt:
    .quad 0x0000000000000000
    .quad 0x00CF9A000000FFFF        /* 0x08  Code  32 Bit, Basis 0 */
    .quad 0x00CF92000000FFFF        /* 0x10  Daten 32 Bit, Basis 0 */
g_pm_gdtr:
    .word 3 * 8 - 1
    .long g_pm_gdt - g_pm_start + 0x1000
    .align 4
g_pm_end:

    .code16
    .globl g_loop_start, g_loop_end
g_loop_start:
    cli
    xorw %ax, %ax
    movw %ax, %ds
    movw %ax, %ss
    movw $0x0FF0, %sp
    xorl %ebx, %ebx
1:  incl %ebx
    jmp 1b
    .align 4
g_loop_end:

    .code16
    .globl g_fault_start, g_fault_end
g_fault_start:
    cli
    movw $0x0100, %ax
    movw %ax, %ds
    xorw %ax, %ax
    movw %ax, %es
    movw %ax, %ss
    movw $0x0FF0, %sp

    movw $0x7000, %si
    movw $0xC0DE, %ax
    movw %ax, %es:(%si)
    movw %es:(%si), %bx             /* danach muss dasselbe dastehen */
    movzwl %bx, %ebx
    movl $8, %ecx
    movl $1, %eax
    vmmcall

    movl $0x3333, %ebx
    movl $2, %eax
    vmmcall
    hlt
1:  jmp 1b
    .align 4
g_fault_end:

    .code16
    .globl g_crash_start, g_crash_end
g_crash_start:
    cli
    xorw %ax, %ax
    movw %ax, %ds
    movw %ax, %ss
    movw $0x0FF0, %sp
    movl $0x4444, %ebx
    movl $9, %ecx
    movl $1, %eax
    vmmcall                         /* noch lebt er */
    ud2
1:  jmp 1b
    .align 4
g_crash_end:

    .code16
    .globl g_lm_start, g_lm_end
g_lm_start:
    cli
    movw $0x0100, %ax
    movw %ax, %ds                   /* DS.base = 0x1000: die eigene GDT */
    xorw %ax, %ax
    movw %ax, %ss
    movw $0x0FF0, %sp

    movw $(g_lm_gdtr - g_lm_start), %si
    lgdtl (%si)

    movl %cr0, %eax
    orl  $1, %eax
    movl %eax, %cr0                 /* geschuetzter Modus */
    ljmpl $0x08, $(g_lm_32 - g_lm_start + 0x1000)

    .code32
g_lm_32:
    movw $0x10, %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %ss
    movl $0xBFF0, %esp


    cld
    movl $0x8000, %edi
    xorl %eax, %eax
    movl $3072, %ecx                /* 0x3000 Oktette / 4 */
    rep stosl

    /* PML4[0] -> PDP, PDP[0] -> PD. Vorhanden, schreibbar. */
    movl $0x00009003, 0x8000
    movl $0x0000A003, 0x9000

    movl $0x00000083, 0xA000
    movl $0x00200083, 0xA008

    movl %cr4, %eax
    orl  $0x20, %eax
    movl %eax, %cr4

    movl $0x8000, %eax
    movl %eax, %cr3


    movl $0xC0000080, %ecx
    rdmsr
    orl  $0x100, %eax               /* LME, Bit 8 */
    wrmsr


    movl %cr0, %eax
    orl  $0x80000000, %eax
    movl %eax, %cr0


    ljmpl $0x18, $(g_lm_64 - g_lm_start + 0x1000)

    .code64
g_lm_64:
    movq $0x20, %rax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %ss
    movq $0xBFF0, %rsp

    movl $0xC0000080, %ecx
    rdmsr                           /* eax = die unteren 32 Bit */
    movl %eax, %ebx
    movl $10, %ecx
    movl $1, %eax
    vmmcall

    movq %cr0, %rbx
    movl $11, %ecx
    movl $1, %eax
    vmmcall
    movq %cr4, %rbx
    movl $12, %ecx
    movl $1, %eax
    vmmcall

    movabsq $0x1234567800000000, %rbx
    shrq $32, %rbx
    movl $13, %ecx
    movl $1, %eax
    vmmcall

    movq $0x00200000, %rdi
    movl $0xC0FFEE64, %eax
    movl %eax, (%rdi)
    movl (%rdi), %ebx
    movl $14, %ecx
    movl $1, %eax
    vmmcall

    movw $0x03F8, %dx
    movb $0x4C, %al                 /* 'L' */
    outb %al, %dx

    movl $0x6464, %ebx              /* "64" */
    movl $2, %eax
    vmmcall
    hlt
1:  jmp 1b

    .align 8
g_lm_gdt:
    .quad 0x0000000000000000
    .quad 0x00CF9A000000FFFF        /* 0x08  Code  32 Bit */
    .quad 0x00CF92000000FFFF        /* 0x10  Daten 32 Bit */
    .quad 0x00AF9A000000FFFF        /* 0x18  Code  64 Bit: L=1, D=0 */
    .quad 0x00CF92000000FFFF        /* 0x20  Daten */
g_lm_gdtr:
    .word 5 * 8 - 1
    .long g_lm_gdt - g_lm_start + 0x1000
    .align 4
g_lm_end:

    .code16
    .globl g_bench_start, g_bench_end
g_bench_start:
    cli
    xorw %ax, %ax
    movw %ax, %ds
    movw %ax, %ss
    movw $0x0FF0, %sp
    xorl %ebx, %ebx
1:  movl $31, %ecx
    movl $1, %eax
    vmmcall
    jmp 1b
    .align 4
g_bench_end:

    .code16
    .globl g_dev_start, g_dev_end
g_dev_start:
    cli
    xorw %ax, %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %ss
    movw $0x0FF0, %sp

    movw $0x03FF, %dx
    movb $0x5A, %al
    outb %al, %dx
    xorl %ebx, %ebx
    inb %dx, %al
    movb %al, %bl
    movl $40, %ecx
    movl $1, %eax
    vmmcall

    /* --- 2. Das Zeilenzustandsregister. --- */
    movw $0x03FD, %dx
    inb %dx, %al
    movzbl %al, %ebx
    movl $41, %ecx
    movl $1, %eax
    vmmcall

    /* --- 3. DLAB: Teiler schreiben, zurueklesen, wieder ausschalten. */
    movw $0x03FB, %dx
    movb $0x83, %al                 /* DLAB an, 8N1 */
    outb %al, %dx
    movw $0x03F8, %dx
    movb $0x0C, %al
    outb %al, %dx
    inb %dx, %al                    /* muss 12 zurueckgeben */
    movzbl %al, %ebx
    movl $42, %ecx
    movl $1, %eax
    vmmcall

    movw $0x03FB, %dx
    movb $0x03, %al                 /* DLAB aus */
    outb %al, %dx
    inb %dx, %al
    movzbl %al, %ebx
    movl $43, %ecx
    movl $1, %eax
    vmmcall

    /* --- 4. Der Unterbrechungsverteiler, vollstaendige Anfangsfolge. */
    movw $0x0021, %dx
    movb $0xFF, %al                 /* erst alles maskieren */
    outb %al, %dx
    movw $0x0020, %dx
    movb $0x11, %al                 /* ICW1: Kaskade, ICW4 folgt */
    outb %al, %dx
    movw $0x0021, %dx
    movb $0x30, %al                 /* ICW2: Vektorbasis 0x30 */
    outb %al, %dx
    movb $0x04, %al                 /* ICW3: Zweiter haengt an IR2 */
    outb %al, %dx
    movb $0x01, %al                 /* ICW4: 8086-Modus */
    outb %al, %dx
    movb $0xFD, %al
    outb %al, %dx
    inb %dx, %al                    /* und zurueklesen */
    movzbl %al, %ebx
    movl $44, %ecx
    movl $1, %eax
    vmmcall

    movw $0x0043, %dx
    movb $0x36, %al                 /* Kanal 0, beide Oktette, Modus 3 */
    outb %al, %dx
    movw $0x0040, %dx
    movb $0x9C, %al                 /* unteres Oktett */
    outb %al, %dx
    movb $0x2E, %al                 /* oberes Oktett -> 0x2E9C = 11932 */
    outb %al, %dx
    movl $45, %ecx
    movl $1, %eax
    vmmcall

    movw $(g_dev_txt - g_dev_start), %si
    movw $0x0100, %ax
    movw %ax, %ds
    movw $0x03F8, %dx
1:  movb (%si), %al
    testb %al, %al
    jz 2f
    outb %al, %dx
    incw %si
    jmp 1b
2:
    movl $0x7777, %ebx
    movl $2, %eax
    vmmcall
    hlt
3:  jmp 3b

g_dev_txt:
    .asciz "geraete geprueft\n"  # // DRAHT: Mitschnitt, tools/hv/run.sh
    .align 4
g_dev_end:

    .code64

    .globl g_linux_none
g_linux_none:

    .align 8
    .globl hv_vectors
hv_vectors:
    .quad hv_vmrun                  /*  0 */
    .quad g_hello_start             /*  1 */
    .quad g_hello_end               /*  2 */
    .quad g_pm_start                /*  3 */
    .quad g_pm_end                  /*  4 */
    .quad g_loop_start              /*  5 */
    .quad g_loop_end                /*  6 */
    .quad g_fault_start             /*  7 */
    .quad g_fault_end               /*  8 */
    .quad g_crash_start             /*  9 */
    .quad g_crash_end               /* 10 */
    .quad g_bench_start             /* 11 */
    .quad g_bench_end               /* 12 */
    .quad g_lm_start                /* 13 */
    .quad g_lm_end                  /* 14 */
    .quad g_dev_start               /* 15 */
    .quad g_dev_end                 /* 16 */
    .quad g_linux_none              /* 17 */
    .quad g_linux_none              /* 18 */
    .quad hv_guest_save             /* 19 */
    .quad hv_stgi                   /* 20 */
    .quad hv_clgi                   /* 21 */
