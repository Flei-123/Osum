/* kernel/arch/aarch64/gic.S -- the interrupt controller, and why it is not an APIC.
 *
 * `kernel/apic.fi` is 575 lines and 47 of them touch the machine: an MSR to
 * find the local APIC, a page mapped for its registers, a spurious vector,
 * an end-of-interrupt write, and the I/O APIC's redirection table to say
 * which pin becomes which vector. The GIC does the same job with a
 * different shape, and three differences decide how much of that code can
 * be reused: none of it.
 *
 * 1. TWO BLOCKS, NOT ONE. The DISTRIBUTOR (0x08000000) is shared by all
 *    processors and decides which interrupt goes where. The CPU INTERFACE
 *    (0x08010000) belongs to the processor that reads it and is where an
 *    interrupt is acknowledged and finished. The local APIC merges both.
 *
 * 2. THE NUMBER IS THE IDENTITY. On x86 a device is wired to a PIN and the
 *    kernel chooses which VECTOR that pin raises, so `apic.fi` carries a
 *    map from pins to vectors. On AArch64 an interrupt HAS a number
 *    (INTID) all the way through: 0..15 software generated, 16..31 private
 *    per processor (the timer is 27), 32.. shared (the PL011 is 33). There
 *    is nothing to allocate and nothing to map, and the vector table has
 *    no entry per device -- every interrupt arrives at the SAME entry
 *    (VECTOR 5 in `vectors.S`) and the handler asks GICC_IAR who it was.
 *
 * 3. ACKNOWLEDGING AND FINISHING ARE TWO WRITES. Reading GICC_IAR takes the
 *    interrupt and raises the running priority; writing the same number to
 *    GICC_EOIR lowers it again. Skip the second and the controller never
 *    delivers anything of equal or lower priority again -- the machine goes
 *    quiet and nothing reports why. On x86 the same mistake is forgetting
 *    the EOI to the APIC, so at least the shape of the bug is familiar.
 *
 * This is GICv2, which is what `-M virt` offers by default (its device tree
 * says `arm,cortex-a15-gic`). GICv3 moves the CPU interface into system
 * registers (ICC_*_EL1); round ARM does not do it, and the honest reason is
 * that nothing here needs more than eight processors.
 */

#include "virt.inc"

    .text

/* gic_init -- distributor and CPU interface on, everything unmasked by
 * priority, nothing enabled yet. */
    .globl gic_init
gic_init:
    ldr     x9, =GICD
    str     wzr, [x9, #GICD_CTLR]
    dsb     sy

    /* All shared interrupts to processor 0 and to a middling priority.
     * GICD_TYPER's low five bits give (lines/32 - 1). */
    ldr     w10, [x9, #GICD_TYPER]
    and     w10, w10, #0x1F
    add     w10, w10, #1
    lsl     w10, w10, #5                    /* w10 = number of INTIDs      */

    mov     w11, #32                        /* SPIs start at 32            */
1:  cmp     w11, w10
    b.hs    2f
    add     x12, x9, #GICD_IPRIORITY
    mov     w13, #0xA0
    strb    w13, [x12, x11]
    add     x12, x9, #GICD_ITARGETSR
    mov     w13, #1                         /* processor 0                 */
    strb    w13, [x12, x11]
    add     w11, w11, #1
    b       1b
2:
    mov     w13, #1
    str     w13, [x9, #GICD_CTLR]
    dsb     sy

    ldr     x9, =GICC
    mov     w13, #0xF0                      /* let every priority through  */
    str     w13, [x9, #GICC_PMR]
    mov     w13, #1
    str     w13, [x9, #GICC_CTLR]
    dsb     sy
    ret

/* gic_enable(w0 = INTID) */
    .globl gic_enable
gic_enable:
    ldr     x9, =GICD
    lsr     w10, w0, #5                     /* which ISENABLER word        */
    and     w11, w0, #31                    /* which bit in it             */
    mov     w12, #1
    lsl     w12, w12, w11
    add     x13, x9, #GICD_ISENABLER
    add     x13, x13, x10, lsl #2
    str     w12, [x13]
    /* a private interrupt (16..31) has its priority in the processor's own
     * copy of the register, so it is set here rather than in gic_init */
    add     x13, x9, #GICD_IPRIORITY
    mov     w12, #0xA0
    strb    w12, [x13, x0]
    dsb     sy
    ret

/* gic_disable(w0 = INTID) */
    .globl gic_disable
gic_disable:
    ldr     x9, =GICD
    lsr     w10, w0, #5
    and     w11, w0, #31
    mov     w12, #1
    lsl     w12, w12, w11
    add     x13, x9, #GICD_ICENABLER
    add     x13, x13, x10, lsl #2
    str     w12, [x13]
    dsb     sy
    ret

/* gic_ack -> w0 = the INTID that is now running (1023 = there was none) */
    .globl gic_ack
gic_ack:
    ldr     x9, =GICC
    ldr     w0, [x9, #GICC_IAR]
    ret

/* gic_eoi(w0 = the INTID that gic_ack returned) */
    .globl gic_eoi
gic_eoi:
    ldr     x9, =GICC
    str     w0, [x9, #GICC_EOIR]
    dsb     sy
    ret

/* irq_on / irq_off -- the counterpart to `sti` and `cli`. On AArch64 the
 * mask is four bits in one system register (DAIF: Debug, SError, IRQ, FIQ)
 * and they are set and cleared with their own instruction rather than with
 * a general move. */
    .globl irq_on
irq_on:
    msr     daifclr, #2
    ret

    .globl irq_off
irq_off:
    msr     daifset, #2
    ret

/* irq_are_on -> x0 = 1 if IRQs are unmasked (DAIF bit 7 clear) */
    .globl irq_are_on
irq_are_on:
    mrs     x0, daif
    lsr     x0, x0, #7
    eor     x0, x0, #1
    and     x0, x0, #1
    ret

/* wait_for_interrupt -- the counterpart to `hlt`. */
    .globl wait_for_interrupt
wait_for_interrupt:
    wfi
    ret
