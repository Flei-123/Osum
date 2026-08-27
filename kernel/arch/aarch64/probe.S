/* kernel/arch/aarch64/probe.S -- the AArch64 side, proving itself.
 *
 * Round ARM, step E. Every claim this port makes is made HERE, out of the
 * running machine, in a line the test runner on the host reads back:
 *
 *   hello          the first octet ever to leave this kernel, written to
 *                  the PL011 BEFORE the MMU, the GIC or the timer exist.
 *                  If it appears, the image was loaded, the processor
 *                  reached `_start`, the stack was set and .bss was
 *                  cleared. If it does not, nothing below is worth reading.
 *   el=            the exception level the kernel actually runs at.
 *   svc=           a deliberate `svc #0`. The vector table caught it, the
 *                  handler read ESR_EL1 and recognised class 0x15, and the
 *                  `eret` came back to the instruction after it.
 *   mmu=           SCTLR_EL1.M read back OUT OF THE PROCESSOR.
 *   page=          a 4 KiB page mapped by hand at 0x80000000 through three
 *                  levels: written through the mapping, read back through
 *                  the physical address. Equal means the walk works.
 *   ttbr1=         the same octet read through TTBR0 and through TTBR1.
 *                  Equal means the second table base does something.
 *   freq=          CNTFRQ_EL0, as the machine states it.
 *   ticks=         how many virtual timer interrupts arrived through the
 *                  GIC. Not a flag: a count that has to reach its target.
 *   switch=        two tasks handing the processor back and forth through
 *                  `arch_switch`. The pattern is the proof; a switch that
 *                  half works prints ABBB or stops.
 *
 * Nothing here is printed unless the thing happened. A line that says `ok`
 * without a number attached is a line that cannot fail, and this file has
 * none of those.
 */

#include "virt.inc"


    .set TICK_TARGET,   100
    .set TICK_HZ,       100
    .set SWITCH_ROUNDS, 10

    .text
    .globl arch_main
arch_main:
    stp     x29, x30, [sp, #-48]!
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    mov     x19, x0                         /* the device tree pointer */

    bl      uart_init

    /* ---------------------------------------------------- the first octet */
    adrp    x0, s_hello
    add     x0, x0, :lo12:s_hello
    bl      uart_puts

    /* ------------------------------------------------- the exception level */
    adrp    x0, s_el
    add     x0, x0, :lo12:s_el
    bl      uart_puts
    mrs     x0, CurrentEL
    lsr     x0, x0, #2
    bl      uart_dec
    bl      nl

    /* ------------------------------------------- the device tree we were given */
    adrp    x0, s_dtb
    add     x0, x0, :lo12:s_dtb
    bl      uart_puts
    mov     x0, x19
    bl      uart_hex
    bl      nl

    /* ------------------------------------------------ a deliberate exception */
    adrp    x0, svc_seen
    add     x0, x0, :lo12:svc_seen
    str     xzr, [x0]
    svc     #0
    adrp    x0, s_svc
    add     x0, x0, :lo12:s_svc
    bl      uart_puts
    adrp    x0, svc_seen
    add     x0, x0, :lo12:svc_seen
    ldr     x0, [x0]
    bl      uart_dec
    mov     w0, #' '
    bl      uart_putc
    adrp    x0, svc_esr
    add     x0, x0, :lo12:svc_esr
    ldr     x0, [x0]
    lsr     x0, x0, #26
    bl      uart_hex
    bl      nl

    /* ------------------------------------------------------------- the MMU */
#ifndef NO_MMU
    bl      mmu_init
#endif
    adrp    x0, s_mmu
    add     x0, x0, :lo12:s_mmu
    bl      uart_puts
    bl      mmu_is_on
    bl      uart_dec
    bl      nl

    /* --- one page, mapped by hand, written through the mapping and read
     * back through the physical address it points at. */
    bl      mmu_test_va
    mov     x20, x0
    ldr     x21, =0x0BADC0DE0DDBA11
    str     x21, [x20]
    dsb     sy
    adrp    x22, test_page
    add     x22, x22, :lo12:test_page
    ldr     x0, [x22]
    adrp    x1, s_page
    add     x1, x1, :lo12:s_page
    mov     x2, x0
    mov     x0, x1
    bl      uart_puts
    mov     x0, x20
    bl      uart_hex
    mov     w0, #' '
    bl      uart_putc
    ldr     x0, [x22]
    bl      uart_hex
    mov     w0, #' '
    bl      uart_putc
    ldr     x0, [x22]
    cmp     x0, x21
    cset    x0, eq
    bl      uart_dec
    bl      nl

    /* --- the same octet through both table base registers. */
    adrp    x20, __image_start
    add     x20, x20, :lo12:__image_start
    ldr     x21, [x20]
    mov     x0, x20
    bl      mmu_high_va
    mov     x22, x0
    ldr     x0, [x22]
    mov     x2, x0
    adrp    x0, s_ttbr1
    add     x0, x0, :lo12:s_ttbr1
    bl      uart_puts
    mov     x0, x22
    bl      uart_hex
    mov     w0, #' '
    bl      uart_putc
    ldr     x0, [x22]
    cmp     x0, x21
    cset    x0, eq
    bl      uart_dec
    bl      nl

    /* ------------------------------------------------ the GIC and the timer */
    bl      gic_init
#ifndef NO_TIMER_IRQ
    mov     w0, #TIMER_INTID
    bl      gic_enable
#endif

    adrp    x0, s_freq
    add     x0, x0, :lo12:s_freq
    bl      uart_puts
    bl      timer_freq
    bl      uart_dec
    bl      nl

    mov     w0, #TICK_HZ
    bl      timer_period_hz
    adrp    x1, tick_period
    add     x1, x1, :lo12:tick_period
    str     x0, [x1]
    bl      timer_arm
    bl      irq_on

    /* Wait for the ticks. `wfi` and not a spin: if the interrupt never
     * arrives the machine sleeps and the runner's time limit reports it,
     * instead of a busy loop that looks like work. */
    adrp    x20, tick_count
    add     x20, x20, :lo12:tick_count
1:  ldr     x0, [x20]
    cmp     x0, #TICK_TARGET
    b.hs    2f
    wfi
    b       1b
2:
    bl      irq_off
    bl      timer_off
    adrp    x0, s_ticks
    add     x0, x0, :lo12:s_ticks
    bl      uart_puts
    ldr     x0, [x20]
    bl      uart_dec
    bl      nl

    /* ------------------------------------------------- two tasks, one processor */
    adrp    x0, ctx_a
    add     x0, x0, :lo12:ctx_a
    adrp    x1, stack_a_top
    add     x1, x1, :lo12:stack_a_top
    adr     x2, task_a
    mov     x3, #0
    bl      task_prepare

    adrp    x0, ctx_b
    add     x0, x0, :lo12:ctx_b
    adrp    x1, stack_b_top
    add     x1, x1, :lo12:stack_b_top
    adr     x2, task_b
    mov     x3, #0
    bl      task_prepare

    adrp    x0, s_switch
    add     x0, x0, :lo12:s_switch
    bl      uart_puts

    adrp    x0, ctx_main
    add     x0, x0, :lo12:ctx_main
    adrp    x1, ctx_a
    add     x1, x1, :lo12:ctx_a
    bl      arch_switch

    mov     w0, #' '
    bl      uart_putc
    adrp    x0, switch_count
    add     x0, x0, :lo12:switch_count
    ldr     x0, [x0]
    bl      uart_dec
    bl      nl

    /* --------------------------------------------- virtio, and it is MMIO here */
    /* On the PC these devices sit on the PCI bus and `kernel/virtio.fi`
     * finds them by walking configuration space over the ports 0xCF8/0xCFC.
     * On `-M virt` they are THIRTY-TWO FIXED ADDRESSES, 0x200 apart, each
     * one either holding the magic number 0x74726976 ("virt") or reading
     * back as an empty slot. There is no bus to walk. What is counted here
     * is how many slots answer and how many of those name a device. */
    adrp    x0, s_virtio
    add     x0, x0, :lo12:s_virtio
    bl      uart_puts
    ldr     x20, =VIRTIO_MMIO
    mov     x21, #0                         /* slots that answer          */
    mov     x22, #0                         /* slots with a device id     */
    mov     x23, #0
1:  ldr     w0, [x20]
    ldr     w1, =0x74726976
    cmp     w0, w1
    b.ne    2f
    add     x21, x21, #1
    ldr     w0, [x20, #8]                   /* DeviceID                   */
    cbz     w0, 2f
    add     x22, x22, #1
2:  add     x20, x20, #VIRTIO_STRIDE
    add     x23, x23, #1
    cmp     x23, #VIRTIO_SLOTS
    b.lo    1b
    mov     x0, x21
    bl      uart_dec
    mov     w0, #' '
    bl      uart_putc
    mov     x0, x22
    bl      uart_dec
    bl      nl

    /* ------------------------------------------------------------------ done */
    adrp    x0, s_done
    add     x0, x0, :lo12:s_done
    bl      uart_puts

    ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    b       arch_poweroff

/* ------------------------------------------------------------------ tasks */

task_a:
    stp     x29, x30, [sp, #-32]!
    str     x19, [sp, #16]
    mov     x19, #SWITCH_ROUNDS
1:  mov     w0, #'A'
    bl      uart_putc
    bl      bump_switches
    adrp    x0, ctx_a
    add     x0, x0, :lo12:ctx_a
    adrp    x1, ctx_b
    add     x1, x1, :lo12:ctx_b
    bl      arch_switch
    subs    x19, x19, #1
    b.ne    1b
    /* back to where the round started */
    adrp    x0, ctx_a
    add     x0, x0, :lo12:ctx_a
    adrp    x1, ctx_main
    add     x1, x1, :lo12:ctx_main
    bl      arch_switch
    b       arch_halt

task_b:
    stp     x29, x30, [sp, #-32]!
    str     x19, [sp, #16]
1:  mov     w0, #'B'
    bl      uart_putc
    bl      bump_switches
    adrp    x0, ctx_b
    add     x0, x0, :lo12:ctx_b
    adrp    x1, ctx_a
    add     x1, x1, :lo12:ctx_a
    bl      arch_switch
    b       1b

bump_switches:
    adrp    x9, switch_count
    add     x9, x9, :lo12:switch_count
    ldr     x10, [x9]
    add     x10, x10, #1
    str     x10, [x9]
    ret

nl:
    stp     x29, x30, [sp, #-16]!
    mov     w0, #'\n'
    bl      uart_putc
    ldp     x29, x30, [sp], #16
    ret

/* ------------------------------------------------------------ the handler */

/* arch_exception(x0 = the frame vectors.S pushed, x1 = which of the sixteen
 * entries was taken). The frame layout is the one declared in vectors.S. */
    .set F_ELR,  248
    .set F_SPSR, 256
    .set F_ESR,  264
    .set F_FAR,  272

    .globl arch_exception
arch_exception:
    stp     x29, x30, [sp, #-32]!
    stp     x19, x20, [sp, #16]
    mov     x19, x0

    cmp     x1, #5
    b.eq    irq_at_el1
    cmp     x1, #4
    b.eq    sync_at_el1
    b       unexpected

sync_at_el1:
    ldr     x2, [x19, #F_ESR]
    lsr     x3, x2, #26
    cmp     x3, #0x15                       /* SVC from AArch64            */
    b.ne    unexpected
    adrp    x4, svc_esr
    add     x4, x4, :lo12:svc_esr
    str     x2, [x4]
    adrp    x4, svc_seen
    add     x4, x4, :lo12:svc_seen
    mov     x5, #1
    str     x5, [x4]
    b       9f

irq_at_el1:
    bl      gic_ack
    mov     w20, w0
    cmp     w0, #TIMER_INTID
    b.ne    1f
    adrp    x9, tick_count
    add     x9, x9, :lo12:tick_count
    ldr     x10, [x9]
    add     x10, x10, #1
    str     x10, [x9]
    adrp    x9, tick_period
    add     x9, x9, :lo12:tick_period
    ldr     x0, [x9]
    bl      timer_arm
1:  mov     w0, w20
#ifndef NO_EOI
    bl      gic_eoi
#endif
    b       9f

unexpected:
    adrp    x0, s_trap
    add     x0, x0, :lo12:s_trap
    bl      uart_puts
    mov     x0, x1
    bl      uart_dec
    mov     w0, #' '
    bl      uart_putc
    ldr     x0, [x19, #F_ESR]
    bl      uart_hex
    mov     w0, #' '
    bl      uart_putc
    ldr     x0, [x19, #F_FAR]
    bl      uart_hex
    mov     w0, #' '
    bl      uart_putc
    ldr     x0, [x19, #F_ELR]
    bl      uart_hex
    bl      nl
    b       arch_poweroff

9:  ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

/* ------------------------------------------------------------------ words */

    .section .rodata
s_hello:  .asciz "osum-arm: hello\n"
s_el:     .asciz "osum-arm: el="
s_dtb:    .asciz "osum-arm: dtb=0x"
s_svc:    .asciz "osum-arm: svc="
s_mmu:    .asciz "osum-arm: mmu="
s_page:   .asciz "osum-arm: page=0x"
s_ttbr1:  .asciz "osum-arm: ttbr1=0x"
s_freq:   .asciz "osum-arm: freq="
s_ticks:  .asciz "osum-arm: ticks="
s_switch: .asciz "osum-arm: switch="
s_virtio: .asciz "osum-arm: virtio="
s_done:   .asciz "osum-arm: done\n"
s_trap:   .asciz "osum-arm: TRAP kind="

/* ------------------------------------------------------------------ state */

    .bss
    .balign 8
svc_seen:     .space 8
svc_esr:      .space 8
tick_count:   .space 8
tick_period:  .space 8
switch_count: .space 8
ctx_main:     .space 112
ctx_a:        .space 112
ctx_b:        .space 112
    .balign 4096
stack_a:      .space 16384
stack_a_top:
    .balign 4096
stack_b:      .space 16384
stack_b_top:
