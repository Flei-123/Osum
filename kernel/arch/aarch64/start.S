/* SPDX-License-Identifier: GPL-2.0-only */
/* kernel/arch/aarch64/start.S -- the counterpart to kernel/arch/x86_64/start.s.
 *
 * The x86 file has to climb: a Multiboot loader hands the machine over in
 * 32-bit protected mode, and before a single compiled function can run,
 * paging and the long mode have to be switched on. Here the machine is
 * already 64 bit when the first instruction runs -- but it may be at the
 * WRONG PRIVILEGE LEVEL, and that is this file's climb, downwards.
 *
 * What arrives here (QEMU `-kernel <elf>` on `-M virt`):
 *   x0 = the address of the device tree QEMU wrote for us
 *   the other processors are asleep; PSCI wakes them (round ARM does not)
 *   EL1 if the machine has no EL2, EL2 with `virtualization=on`
 *
 * What leaves here: SP set, .bss zeroed, the vector table installed, and
 * `arch_main` called with the device tree pointer as its first argument.
 *
 * THE FIRST TRAP OF THIS PORT, and it is in this file. `.align 8` means
 * eight BYTES in the x86 port of GNU as and 2^8 = 256 bytes in the AArch64
 * port -- the compiler round 80 documented that for the code generator, and
 * it is just as true in hand written assembly. Everything below therefore
 * says `.balign`, which counts bytes in both ports. The vector table in
 * `vectors.S` needs 2048-byte alignment and says so with `.balign 2048`; if
 * it said `.align 2048` it would ask for 2^2048 and the assembler would
 * refuse -- that at least fails loudly. `.align 8` would NOT fail loudly:
 * it would silently align to 256 and everything would still work, which is
 * how a wrong habit survives a port.
 */

#include "virt.inc"

    .section .text.boot, "ax"
    .globl _start
_start:
    /* Only the first processor goes on; round ARM does not start the
     * others (docs/ARCH.md, "what stays out"). MPIDR_EL1's low 24 bits are
     * the affinity; on `-M virt` core 0 is all zero. */
    mrs     x1, mpidr_el1
    and     x1, x1, #0xFF
    cbz     x1, 1f
0:  wfe
    b       0b
1:

    /* The stack, before anything that could push. */
    adrp    x1, stack_top
    add     x1, x1, :lo12:stack_top
    mov     sp, x1

    /* --- which level are we on? CurrentEL bits [3:2]: 1=EL1, 2=EL2. */
    mrs     x1, CurrentEL
    lsr     x1, x1, #2
    cmp     x1, #2
    b.ne    at_el1

    /* --- EL2 -> EL1. Four registers and an exception return.
     *   HCR_EL2.RW  = 1   EL1 is AArch64 and not AArch32
     *   CNTHCTL_EL2 |= 3  EL1 may read the counter and use the timer
     *   CNTVOFF_EL2 = 0   the virtual timer counts what the physical one does
     *   SPSR_EL2         return to EL1h with D,A,I,F masked
     */
    mov     x2, #(1 << 31)
    msr     hcr_el2, x2
    mrs     x2, cnthctl_el2
    orr     x2, x2, #3
    msr     cnthctl_el2, x2
    msr     cntvoff_el2, xzr
    mov     x2, #0x3C5              /* D A I F masked, mode EL1h */
    msr     spsr_el2, x2
    adr     x2, at_el1
    msr     elr_el2, x2
    /* SP_EL1 has to be set from here; after the eret the stack is EL1's. */
    adrp    x2, stack_top
    add     x2, x2, :lo12:stack_top
    msr     sp_el1, x2
    eret

at_el1:
    /* Everything below runs at EL1. Interrupts stay masked until the GIC
     * and the vector table are up. */
    msr     daifset, #0xF

    /* --- .bss to zero. A Multiboot loader does not promise it on x86 and
     * QEMU does not promise it here; the ELF only says the region exists. */
    adrp    x1, __bss_start
    add     x1, x1, :lo12:__bss_start
    adrp    x2, __bss_end
    add     x2, x2, :lo12:__bss_end
2:  cmp     x1, x2
    b.hs    3f
    str     xzr, [x1], #8
    b       2b
3:

    /* --- the counter-check switches.
     *
     * `tools/arm/run.sh` builds the image four more times with one thing
     * deliberately broken, and the kernel has to KNOW which thing. Round ARM
     * did that with `#ifdef` inside the assembly. The kernel is Firn now and
     * Firn has no preprocessor, so the switches travel the way every other
     * piece of kernel state travels on this side: as a word in `kstate_a64`,
     * written here, read there. `.bss` was cleared four instructions ago, so
     * this store has to come after it and not before.
     */
    mov     x1, #0
#ifdef NO_MMU
    orr     x1, x1, #1
#endif
#ifdef NO_AF
    orr     x1, x1, #2
#endif
#ifdef NO_TIMER_IRQ
    orr     x1, x1, #4
#endif
#ifdef NO_EOI
    orr     x1, x1, #8
#endif
    adrp    x2, kstate_a64
    add     x2, x2, :lo12:kstate_a64
    str     x1, [x2, #40]

    /* --- the vector table. VBAR_EL1 wants a 2048-byte aligned address;
     * `vectors.S` guarantees it with `.balign 2048`. */
    adrp    x1, vector_table
    add     x1, x1, :lo12:vector_table
    msr     vbar_el1, x1
    isb

    /* --- into the kernel, with the device tree pointer that arrived in x0.
     * KERN_MAIN is `_F0.start` out of `kernel/kmain_a64.fi`, put in at the
     * link step with `--defsym` -- the same arrangement `kernel/arch/x86_64/
     * start.s` uses, and for the same reason: this file cannot know which
     * compiler stage prefixed the symbol. */
    bl      KERN_MAIN

    /* If it ever returns: stop the machine the way this platform does. */
    b       arch_halt

/* ------------------------------------------------------------------ halt */

    .globl arch_halt
arch_halt:
    msr     daifset, #0xF
4:  wfi
    b       4b

/* --- power off through PSCI. `-M virt` says `method = "hvc"` in its device
 * tree; from EL1 without EL2 present QEMU takes `hvc` for PSCI all the same.
 * If it does not, the `wfi` loop below catches it and the runner's time
 * limit reports it -- an exit code is not invented here. */
    .globl arch_poweroff
arch_poweroff:
    ldr     w0, =PSCI_SYSTEM_OFF
    hvc     #0
    b       arch_halt

/* ------------------------------------------------------------- osum_panic ---
 *
 * Where the checked arithmetic of round 72 ends up when a value really does
 * go out of range. The compiler leaves the symbol UNDEFINED on purpose: a
 * kernel that never defines it gets a link error, which is the honest
 * outcome (SPEC section 13).
 *
 * The hand-over is plain AAPCS64, and this is the one place A64 is simpler
 * than x86-64 -- there the trampoline has to shuffle r9 into r8 first:
 *   x0 = message pointer (into .rodata, no closing zero)
 *   x1 = message length
 *   x2, x3 = the two operands
 *   x4 = which kind of overflow (PANIC_ADD=1 .. PANIC_CAST=6)
 *   x5 = 1 when the two values are to be read as unsigned
 *
 * It prints the message on the PL011 and stops. No formatting of the
 * operands: the message names the operation and the file, and a kernel that
 * is already wrong is not the place to run more arithmetic.
 */
    .globl osum_panic
osum_panic:
    mov     x9, x0
    mov     x10, x1
    ldr     x11, =UART0
5:  cbz     x10, 7f
6:  ldr     w12, [x11, #UART_FR]
    tst     w12, #UART_FR_TXFF
    b.ne    6b
    ldrb    w12, [x9], #1
    str     w12, [x11, #UART_DR]
    sub     x10, x10, #1
    b       5b
7:  mov     w12, #'\n'
    str     w12, [x11, #UART_DR]
    dsb     sy
    b       arch_halt

/* ------------------------------------------------------------------ stack */

    .section .bss
    .balign 4096
    .globl stack_bottom
stack_bottom:
    .space  65536
    .globl stack_top
stack_top:

/* --- The kernel's own mutable state.
 *
 * Stage 0 of Firn has `const` and no mutable globals (SPEC 14, item 5). On
 * x86-64 the kernel solves that by putting its state in a region whose
 * address the assembly hands over -- `kdata` in `kernel/arch/x86_64/boot.s`,
 * 0x60000 octets of it. This is the same idea at the size this side needs:
 * five words, and `kernel/arch/aarch64/amain.fi` reaches them through
 * `adrp`/`add` on this symbol.
 */
    .balign 64
    .globl kstate_a64
    .globl kdata
kdata:
kstate_a64:
    .space  256
