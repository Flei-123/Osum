/* SPDX-License-Identifier: GPL-2.0-only */
/* kernel/smp.s -- round K5: the sixty lines a second processor
 * cannot be started without.
 *
 * This is the fourth non-Firn file of the kernel and it is here for the
 * same reason as the other three: what stands in it runs BEFORE the
 * machine is in a state a compiled function could run in. An application
 * processor does not wake up in long mode with paging and a stack. It
 * wakes up the way an 8086 woke up in 1978: REAL MODE, 16 bit, cs set to
 * the vector of the startup message and ip at zero, no page tables, no
 * descriptor table it may trust, and 1 MiB of address space. Everything
 * the boot processor got done for it by `boot.s` and the boot loader has
 * to happen again, on the core itself, in the first hundred instructions.
 *
 * WHY THE CODE IS COPIED. The `SIPI` message carries ONE octet of
 * address: the processor starts at `vector << 12`, so the entry point has
 * to lie in the first megabyte and on a page boundary. The kernel image
 * lies at 1 MiB. So the blob between `ap_trampoline` and
 * `ap_trampoline_end` is copied to `AP_BASE` at run time (`smp.fi`), and
 * every address in it is written as "base plus the distance from the
 * start of the blob" -- which is what the `.set ABS_*` lines below do.
 * The alternative, linking this section at 0x8000, would have put a
 * second load segment into the multiboot image for eleven lines of code.
 *
 * WHY THE PARAMETERS LIE IN MEMORY AND NOT IN REGISTERS. A processor
 * started by `SIPI` gets no arguments; the only thing it knows is where
 * it starts. So the boot processor writes what the core needs into a
 * block behind the code -- page table root, its stack, the entry in the
 * kernel, the data area, its number -- and waits until the core has set
 * `P_FLAG`. Only then is the block free for the next core. Bringing them
 * up one at a time costs a few milliseconds and saves the whole question
 * of what happens when two cores read the block at once.
 *
 * WHY THE DESCRIPTOR TABLE HERE HAS THE SAME LAYOUT AS THE ONE IN boot.s
 * (code64 at 0x08, data at 0x10). Not for tidiness: the core stays on
 * this table until Firn code loads the real one, and if the selector
 * numbers differed, the `lgdt` in `smp.ap_main` would leave cs pointing
 * at a different descriptor than the one the processor is executing
 * under. There is no way to reload cs from a compiled function -- that
 * needs a far jump. Keeping the layouts equal removes the need for one.
 */

    .set AP_BASE,  0x8000           /* where the blob is copied to */
    .set AP_PARAM, 0x8F00           /* the parameter block, behind it */

    .set P_CR3,    0x00
    .set P_STACK,  0x08
    .set P_ENTRY,  0x10
    .set P_KDATA,  0x18
    .set P_CPU,    0x20
    .set P_FLAG,   0x28

    .section .text.ap, "ax"
    .code16
    .globl ap_trampoline
ap_trampoline:
    cli
    cld
    xorw %ax, %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %ss
    movw %ax, %fs
    movw %ax, %gs

    /* Protected mode, 32 bit. The table is the one at the end of this
     * blob; `ABS_GDTPTR` is its address after the copy. */
    lgdtl ABS_GDTPTR
    movl %cr0, %eax
    orl  $1, %eax
    movl %eax, %cr0
    ljmpl $0x18, $ABS_PROT32

    .code32
ap_prot32:
    movw $0x10, %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %ss
    movw %ax, %fs
    movw %ax, %gs

    /* PAE, without which long mode does not exist. */
    movl %cr4, %eax
    orl  $(1 << 5), %eax
    movl %eax, %cr4

    /* The page tables of the boot processor. Not a copy: the SAME ones.
     * Every core walks the same tree, which is what makes the kernel one
     * kernel and not four. */
    movl AP_PARAM + P_CR3, %eax
    movl %eax, %cr3

    /* EFER.LME */
    movl $0xC0000080, %ecx
    rdmsr
    orl  $(1 << 8), %eax
    wrmsr

    /* Paging on -- from this instruction the core is in compatibility
     * mode, and the far jump below makes it 64 bit. */
    movl %cr0, %eax
    orl  $0x80000001, %eax
    movl %eax, %cr0
    ljmp $0x08, $ABS_LONG64

    .code64
ap_long64:
    /* Everything out of the parameter block into registers FIRST, and
     * only then the flag: from the moment the flag is set the boot
     * processor may overwrite the block for the next core. */
    movl $AP_PARAM, %eax
    movq P_STACK(%rax), %rsp
    movq P_KDATA(%rax), %rdi        /* argument 0: the kernel data area */
    movq P_CPU(%rax), %rsi          /* argument 1: which processor this is */
    movq P_ENTRY(%rax), %rdx
    xorl %ebp, %ebp
    movq $1, P_FLAG(%rax)
    call *%rdx                      /* KERNEL_AP_MAIN, and it does not return */
1:
    cli
    hlt
    jmp 1b

    /* The table. Three usable descriptors, and the two the kernel uses
     * afterwards sit at the same selectors as in boot.s. */
    .align 16
ap_gdt:
    .quad 0                         /* 0x00 null */
    .quad 0x00AF9A000000FFFF        /* 0x08 code64  -- as gdt64 */
    .quad 0x00CF92000000FFFF        /* 0x10 data    -- as gdt64 */
    .quad 0x00CF9A000000FFFF        /* 0x18 code32, only for the way up */
ap_gdt_end:
ap_gdt_ptr:
    .word ap_gdt_end - ap_gdt - 1
    .long ABS_GDT
    .globl ap_trampoline_end
ap_trampoline_end:

    /* The addresses the blob has AFTER it was copied. Assembly time
     * constants: every one of them is the distance from the start of the
     * blob plus the place the blob is copied to. */
    .set ABS_GDT,     AP_BASE + (ap_gdt      - ap_trampoline)
    .set ABS_GDTPTR,  AP_BASE + (ap_gdt_ptr  - ap_trampoline)
    .set ABS_PROT32,  AP_BASE + (ap_prot32   - ap_trampoline)
    .set ABS_LONG64,  AP_BASE + (ap_long64   - ap_trampoline)

    /* The table the Firn side reads its two addresses out of. The same
     * mechanism as the `vectors` table of isr.s -- stage 0 of Firn cannot
     * name the address of a symbol in another object file, so the
     * addresses stand in a table whose own address is handed over. */
    .section .rodata
    .align 8
    .globl smp_vectors
smp_vectors:
    .quad ap_trampoline             /* 0: the blob */
    .quad ap_trampoline_end         /* 1: behind it */
    .quad AP_BASE                   /* 2: where it is copied to */
    .quad AP_PARAM                  /* 3: the parameter block */
    .quad gdt64                     /* 4: the descriptor table of boot.s */

/* =====================================================================
 * K-004 lives in this file and not in an s3.s of its own: sixteen
 * runners assemble exactly "boot isr switch smp hv", and a sixth file
 * would have meant touching every one of them. Same kind of blob, same
 * page, same reason to exist.
 * ===================================================================== */
/* K-004: the way back from ACPI S3.
 *
 * In S3 the processor loses everything but RAM. The firmware wakes up,
 * does its own reset work and then jumps -- in REAL MODE, 16 bit -- to
 * the FIRMWARE_WAKING_VECTOR in the FACS (ACPI 6.x, 5.2.10). Everything
 * between that jump and "the kernel continues where it went to sleep"
 * stands in this file, for the same reason smp.s exists: it runs before
 * a compiled function can.
 *
 * TWO HALVES:
 *
 *   s3_save(ctx)   called from Firn (pwr/s3.fi) just before the SLP_EN
 *                  write. Stores every general register, the control
 *                  registers, EFER, GDTR/IDTR/TR, the MSRs a running
 *                  kernel depends on, and returns 0. Like setjmp.
 *
 *   s3_wake        the blob that is copied to WAKE_BASE below 1 MiB and
 *                  whose address goes into the FACS. It climbs 16 -> 32
 *                  -> 64 bit on its own descriptor table, then puts back
 *                  what s3_save stored and "returns from s3_save a second
 *                  time" with rax = 1. Like longjmp.
 *
 * WHY EVERY REGISTER AND NOT ONLY THE CALLEE-SAVED ONES. Firn's
 * `asm("call rax", ...)` does not tell the compiler that the callee
 * clobbers rcx/rdx/rsi/rdi/r8-r11 (see msr_read_safe in isr.s, which
 * saves rcx and rdx itself). So the second return has to hand back the
 * exact register file of the first one, rax excepted.
 *
 * WHERE IT LIVES. WAKE_BASE is 0x8000, the page of the AP trampoline
 * (smp.s). Both are only needed while no other processor is running;
 * the application processors are dead in S3 and have to be started
 * again anyway, which copies their own blob back. 0x9000 is taken by
 * QEMU's multiboot information, 0x1000 by SeaBIOS' resume stack.
 * The context block sits at WAKE_CTX in the same page, below the AP
 * parameter block at 0x8F00.
 *
 * THE TRAP MEASURED ON 24.09.2026 (docs/RUNDE-ROADMAP-5.md, K-004): a
 * kernel image with a LOAD segment below 1 MiB overwrites the BIOS
 * shadow at 0xF0000, and the firmware's own resume path then jumps into
 * zeros without a single line of output. kernel.ld links at 1 MiB.
 */

    .set WAKE_BASE, 0x8000
    .set WAKE_CTX,  0x8C00

    /* context layout -- pwr/s3.fi reads the same offsets */
    .set C_RSP,    0x00
    .set C_RIP,    0x08
    .set C_RBX,    0x10
    .set C_RBP,    0x18
    .set C_R12,    0x20
    .set C_R13,    0x28
    .set C_R14,    0x30
    .set C_R15,    0x38
    .set C_CR0,    0x40
    .set C_CR3,    0x48
    .set C_CR4,    0x50
    .set C_EFER,   0x58
    .set C_GDTR,   0x60     /* 10 bytes */
    .set C_IDTR,   0x70     /* 10 bytes */
    .set C_TR,     0x80
    .set C_RFLAGS, 0x88
    .set C_FSB,    0x90
    .set C_GSB,    0x98
    .set C_KGSB,   0xA0
    .set C_STAR,   0xA8
    .set C_LSTAR,  0xB0
    .set C_CSTAR,  0xB8
    .set C_SFMASK, 0xC0
    .set C_PAT,    0xC8
    .set C_XCR0,   0xD0
    .set C_WOKE,   0xD8     /* the blob counts its own landings here */
    .set C_RCX,    0xE0
    .set C_RDX,    0xE8
    .set C_RSI,    0xF0
    .set C_RDI,    0xF8
    .set C_R8,     0x100
    .set C_R9,     0x108
    .set C_R10,    0x110
    .set C_R11,    0x118
    .set C_STAGE,  0x120    /* how far the blob got: 1 real, 2 prot, 3 long, 4 done */
    .set C_MXCSR,  0x128
    .set C_FCW,    0x130

    .text
    .code64
    .globl s3_save
/* s3_save(rdi = ctx) -> rax: 0 now, 1 after the wake-up */
s3_save:
    movq (%rsp), %rax
    movq %rax, C_RIP(%rdi)
    leaq 8(%rsp), %rax
    movq %rax, C_RSP(%rdi)
    movq %rbx, C_RBX(%rdi)
    movq %rbp, C_RBP(%rdi)
    movq %r12, C_R12(%rdi)
    movq %r13, C_R13(%rdi)
    movq %r14, C_R14(%rdi)
    movq %r15, C_R15(%rdi)
    movq %rcx, C_RCX(%rdi)
    movq %rdx, C_RDX(%rdi)
    movq %rsi, C_RSI(%rdi)
    movq %rdi, C_RDI(%rdi)
    movq %r8,  C_R8(%rdi)
    movq %r9,  C_R9(%rdi)
    movq %r10, C_R10(%rdi)
    movq %r11, C_R11(%rdi)
    pushfq
    popq %rax
    movq %rax, C_RFLAGS(%rdi)
    movq %cr0, %rax
    movq %rax, C_CR0(%rdi)
    movq %cr3, %rax
    movq %rax, C_CR3(%rdi)
    movq %cr4, %rax
    movq %rax, C_CR4(%rdi)
    sgdt C_GDTR(%rdi)
    sidt C_IDTR(%rdi)
    xorq %rax, %rax
    str %ax
    movq %rax, C_TR(%rdi)
    stmxcsr C_MXCSR(%rdi)
    fnstcw C_FCW(%rdi)

    /* the MSRs; rcx/rdx are restored below */
    movl $0xC0000080, %ecx
    call s3_rdmsr
    movq %rax, C_EFER(%rdi)
    movl $0xC0000100, %ecx
    call s3_rdmsr
    movq %rax, C_FSB(%rdi)
    movl $0xC0000101, %ecx
    call s3_rdmsr
    movq %rax, C_GSB(%rdi)
    movl $0xC0000102, %ecx
    call s3_rdmsr
    movq %rax, C_KGSB(%rdi)
    movl $0xC0000081, %ecx
    call s3_rdmsr
    movq %rax, C_STAR(%rdi)
    movl $0xC0000082, %ecx
    call s3_rdmsr
    movq %rax, C_LSTAR(%rdi)
    movl $0xC0000083, %ecx
    call s3_rdmsr
    movq %rax, C_CSTAR(%rdi)
    movl $0xC0000084, %ecx
    call s3_rdmsr
    movq %rax, C_SFMASK(%rdi)
    movl $0x277, %ecx
    call s3_rdmsr
    movq %rax, C_PAT(%rdi)
    movq $0, C_XCR0(%rdi)
    movq C_CR4(%rdi), %rax
    btq $18, %rax                   /* CR4.OSXSAVE */
    jnc 1f
    xorl %ecx, %ecx
    xgetbv
    shlq $32, %rdx
    orq %rdx, %rax
    movq %rax, C_XCR0(%rdi)
1:
    movq $0, C_STAGE(%rdi)
    movq C_RCX(%rdi), %rcx
    movq C_RDX(%rdi), %rdx
    xorl %eax, %eax
    ret

s3_rdmsr:
    rdmsr
    shlq $32, %rdx
    orq %rdx, %rax
    ret

/* ------------------------------------------------------------ the blob */

    .section .text.s3, "ax"
    .code16
    .globl s3_wake
s3_wake:
    cli
    cld
    movw %cs, %ax                   /* SeaBIOS enters at 0800:0000, others at 0000:8000 */
    xorw %ax, %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %ss
    movl $1, WAKE_CTX + C_STAGE
    lgdtl S3ABS_GDTPTR
    movl %cr0, %eax
    orl  $1, %eax
    movl %eax, %cr0
    ljmpl $0x18, $S3ABS_PROT32

    .code32
s3_prot32:
    movw $0x10, %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %ss
    movw %ax, %fs
    movw %ax, %gs
    movl $2, WAKE_CTX + C_STAGE

    movl %cr4, %eax
    orl  $(1 << 5), %eax            /* PAE */
    movl %eax, %cr4
    movl WAKE_CTX + C_CR3, %eax
    movl %eax, %cr3

    /* EFER as it was (LME, NXE, SCE), without the read-only LMA bit */
    movl $0xC0000080, %ecx
    movl WAKE_CTX + C_EFER, %eax
    movl WAKE_CTX + C_EFER + 4, %edx
    andl $~(1 << 10), %eax
    wrmsr

    movl %cr0, %eax
    orl  $0x80000001, %eax
    movl %eax, %cr0
    ljmp $0x08, $S3ABS_LONG64

    .code64
s3_long64:
    movl $WAKE_CTX, %edi
    movq $3, C_STAGE(%rdi)

    /* the kernel's own tables, back in their 64-bit form */
    lgdt C_GDTR(%rdi)
    lidt C_IDTR(%rdi)
    movw $0x10, %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %ss
    xorl %eax, %eax
    movw %ax, %fs
    movw %ax, %gs
    /* cs: same selector 0x08 in both tables, but reload it from the
     * kernel's GDT all the same */
    pushq $0x08
    movabsq $S3ABS_CSDONE, %rax
    pushq %rax
    lretq
s3_csdone:
    movq C_CR4(%rdi), %rax
    movq %rax, %cr4
    btq $18, %rax
    jnc 2f
    xorl %ecx, %ecx
    movl C_XCR0(%rdi), %eax
    movl C_XCR0 + 4(%rdi), %edx
    xsetbv
2:
    movq C_CR0(%rdi), %rax
    movq %rax, %cr0
    movq C_CR3(%rdi), %rax
    movq %rax, %cr3

    movl $0xC0000100, %ecx
    movq C_FSB(%rdi), %rax
    call s3_wrmsr_abs
    movl $0xC0000101, %ecx
    movq C_GSB(%rdi), %rax
    call s3_wrmsr_abs
    movl $0xC0000102, %ecx
    movq C_KGSB(%rdi), %rax
    call s3_wrmsr_abs
    movl $0xC0000081, %ecx
    movq C_STAR(%rdi), %rax
    call s3_wrmsr_abs
    movl $0xC0000082, %ecx
    movq C_LSTAR(%rdi), %rax
    call s3_wrmsr_abs
    movl $0xC0000083, %ecx
    movq C_CSTAR(%rdi), %rax
    call s3_wrmsr_abs
    movl $0xC0000084, %ecx
    movq C_SFMASK(%rdi), %rax
    call s3_wrmsr_abs
    movl $0x277, %ecx
    movq C_PAT(%rdi), %rax
    call s3_wrmsr_abs

    /* the task register: its descriptor is still marked BUSY from before
     * the sleep, and ltr on a busy descriptor is a #GP */
    movq C_TR(%rdi), %rax
    testq %rax, %rax
    jz 3f
    movq C_GDTR + 2(%rdi), %rdx
    andq $~7, %rax
    andb $0xFD, 5(%rdx,%rax)
    movq C_TR(%rdi), %rax
    ltr %ax
3:
    ldmxcsr C_MXCSR(%rdi)
    fldcw C_FCW(%rdi)

    incq C_WOKE(%rdi)
    movq $4, C_STAGE(%rdi)

    movq C_RSP(%rdi), %rsp
    movq C_RFLAGS(%rdi), %rax
    pushq %rax
    popfq
    movq C_RBX(%rdi), %rbx
    movq C_RBP(%rdi), %rbp
    movq C_R12(%rdi), %r12
    movq C_R13(%rdi), %r13
    movq C_R14(%rdi), %r14
    movq C_R15(%rdi), %r15
    movq C_RCX(%rdi), %rcx
    movq C_RDX(%rdi), %rdx
    movq C_RSI(%rdi), %rsi
    movq C_R8(%rdi),  %r8
    movq C_R9(%rdi),  %r9
    movq C_R10(%rdi), %r10
    movq C_R11(%rdi), %r11
    movq C_RIP(%rdi), %rax
    pushq %rax
    movq C_RDI(%rdi), %rdi
    movl $1, %eax
    ret                             /* the second return of s3_save */

s3_wrmsr_abs:
    movq %rax, %rdx
    shrq $32, %rdx
    wrmsr
    ret

    .align 16
s3_gdt:
    .quad 0                         /* 0x00 null */
    .quad 0x00AF9A000000FFFF        /* 0x08 code64 -- as gdt64 */
    .quad 0x00CF92000000FFFF        /* 0x10 data   -- as gdt64 */
    .quad 0x00CF9A000000FFFF        /* 0x18 code32, only for the way up */
s3_gdt_end:
s3_gdt_ptr:
    .word s3_gdt_end - s3_gdt - 1
    .long S3ABS_GDT
    .globl s3_wake_end
s3_wake_end:

    .set S3ABS_GDT,     WAKE_BASE + (s3_gdt      - s3_wake)
    .set S3ABS_GDTPTR,  WAKE_BASE + (s3_gdt_ptr  - s3_wake)
    .set S3ABS_PROT32,  WAKE_BASE + (s3_prot32   - s3_wake)
    .set S3ABS_LONG64,  WAKE_BASE + (s3_long64   - s3_wake)
    .set S3ABS_CSDONE,  WAKE_BASE + (s3_csdone   - s3_wake)

    .section .rodata
    .align 8
    .globl s3_vectors
s3_vectors:
    .quad s3_wake                   /* 0: the blob */
    .quad s3_wake_end               /* 1: behind it */
    .quad WAKE_BASE                 /* 2: where it is copied to */
    .quad WAKE_CTX                  /* 3: the context block */
    .quad s3_save                   /* 4: setjmp */
