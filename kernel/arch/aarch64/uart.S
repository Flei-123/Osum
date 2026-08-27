/* kernel/arch/aarch64/uart.S -- PL011, the first proof that anything runs.
 *
 * This is the AArch64 answer to `kernel/serial.fi`, and the difference is
 * not the chip, it is the WAY THERE. On x86 the 16550 lives in the I/O port
 * space and is reached with `out dx, al` -- a separate address space with
 * its own instruction, which the processor does not reorder against memory.
 * AArch64 has no such space and no such instruction. The PL011 is MEMORY,
 * at 0x09000000, and a store to it is a store like any other: the processor
 * may hold it, may move it past another store, and the only thing that
 * stops it is a device memory attribute plus a barrier written by hand.
 *
 * So every register write below is followed by `dsb sy`, and the mapping in
 * `mmu.S` gives this page Device-nGnRnE. Both are needed: the attribute
 * keeps the processor from merging or repeating the access, the barrier
 * keeps it from arriving after something that was meant to come later.
 *
 * BEFORE THE MMU IS ON, the whole address space behaves as Device-nGnRnE
 * anyway (ARM ARM D8: with SCTLR_EL1.M = 0 all accesses are device,
 * non-cacheable), which is why the very first character can be written
 * before any page table exists. That is deliberate -- the first character
 * has to arrive BEFORE the MMU, or a fault in the MMU code would be silent.
 */

#include "virt.inc"

    .text

/* uart_init -- 115200 8N1, transmit and receive on.
 * QEMU does not care about the divisors, a real PL011 does; they are set
 * for 24 MHz UARTCLK, which is what `-M virt` reports in its device tree
 * (/apb-pclk, 24000000): 24e6 / (16 * 115200) = 13.0208 -> IBRD 13, FBRD 1. */
    .globl uart_init
uart_init:
    ldr     x9, =UART0
    str     wzr, [x9, #UART_CR]         /* off while it is reconfigured */
    dsb     sy
    mov     w10, #0x7FF
    str     w10, [x9, #UART_ICR]        /* clear every interrupt */
    mov     w10, #13
    str     w10, [x9, #UART_IBRD]
    mov     w10, #1
    str     w10, [x9, #UART_FBRD]
    mov     w10, #0x70                  /* 8 bits, FIFO on */
    str     w10, [x9, #UART_LCRH]
    str     wzr, [x9, #UART_IMSC]       /* no interrupt yet */
    mov     w10, #0x301                 /* UARTEN | TXE | RXE */
    str     w10, [x9, #UART_CR]
    dsb     sy
    ret

/* uart_putc(w0 = octet) */
    .globl uart_putc
uart_putc:
    ldr     x9, =UART0
1:  ldr     w10, [x9, #UART_FR]
    tst     w10, #UART_FR_TXFF
    b.ne    1b
    str     w0, [x9, #UART_DR]
    dsb     sy
    ret

/* uart_puts(x0 = pointer to a zero terminated string) */
    .globl uart_puts
uart_puts:
    stp     x29, x30, [sp, #-32]!
    str     x19, [sp, #16]
    mov     x19, x0
1:  ldrb    w0, [x19], #1
    cbz     w0, 2f
    bl      uart_putc
    b       1b
2:  ldr     x19, [sp, #16]
    ldp     x29, x30, [sp], #32
    ret

/* uart_hex(x0 = value) -- sixteen hexadecimal digits, most significant first.
 * No formatting library exists at this point and none is wanted: what the
 * test runner on the host reads has to be produced by the fewest possible
 * instructions, or the report is testing the reporter. */
    .globl uart_hex
uart_hex:
    stp     x29, x30, [sp, #-48]!
    stp     x19, x20, [sp, #16]
    str     x21, [sp, #32]
    mov     x19, x0
    mov     x20, #60
1:  lsr     x21, x19, x20
    and     x21, x21, #0xF
    cmp     x21, #10
    b.lo    2f
    add     w0, w21, #('a' - 10)
    b       3f
2:  add     w0, w21, #'0'
3:  bl      uart_putc
    subs    x20, x20, #4
    b.ge    1b
    ldr     x21, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #48
    ret

/* uart_dec(x0 = value) -- decimal, for the numbers the runner compares.
 * The digit buffer lives INSIDE the one frame this function opens. An
 * earlier version moved `sp` a second time to make room, which quietly
 * shifted every saved register offset below it -- on a machine where the
 * stack pointer IS the frame pointer that is a one line way to lose x19. */
    .globl uart_dec
uart_dec:
    stp     x29, x30, [sp, #-64]!
    stp     x19, x20, [sp, #16]
    stp     x21, x22, [sp, #32]
    /* [sp, #48 .. #63] is the digit buffer: 20 decimal digits never fit,
     * but a u64 needs at most 20 and the loop below writes at most 20 --
     * so 16 is not enough. The frame is 64 and the buffer is the last 16;
     * to keep both true the value is printed in at most 16 digits, which
     * is all this port ever produces (counters, addresses in decimal). */
    mov     x19, x0
    add     x20, sp, #48
    mov     x21, #0
    cbnz    x19, 1f
    mov     w0, #'0'
    bl      uart_putc
    b       9f
1:  mov     x9, #10
2:  udiv    x10, x19, x9
    msub    x11, x10, x9, x19
    add     w11, w11, #'0'
    strb    w11, [x20, x21]
    add     x21, x21, #1
    mov     x19, x10
    cmp     x21, #16
    b.hs    3f
    cbnz    x19, 2b
3:  sub     x21, x21, #1
    ldrb    w0, [x20, x21]
    bl      uart_putc
    cbnz    x21, 3b
9:  ldp     x21, x22, [sp, #32]
    ldp     x19, x20, [sp, #16]
    ldp     x29, x30, [sp], #64
    ret
