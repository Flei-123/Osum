/* kernel/arch/aarch64/switch.S -- the counterpart to kernel/arch/x86_64/switch.s.
 *
 * A context switch is the same idea on both machines and a different list
 * of registers. What has to be saved is what the calling convention says
 * the CALLEE must preserve, because the switch is reached through a call
 * and returns through one; everything else the compiler has already spilled
 * at the call site.
 *
 *   x86-64 System V : rbx, rbp, r12, r13, r14, r15, rsp   -- 7 words
 *   AArch64 AAPCS64 : x19..x28, x29 (frame), x30 (link), sp -- 13 words
 *
 * TWO THINGS ARE GENUINELY DIFFERENT, not just longer.
 *
 * 1. THE RETURN ADDRESS IS A REGISTER. On x86 the `call` that entered this
 *    function pushed the return address onto the stack, so switching the
 *    stack pointer switches the return address with it and `ret` lands in
 *    the new task all by itself -- `switch.s` is seven `mov`s and a `ret`.
 *    On AArch64 `bl` puts it in x30, so x30 has to be saved and loaded like
 *    any other register, and a NEW task is started by writing the entry
 *    point into its saved x30. That is the whole trick to starting a task
 *    here, and it is why `task_prepare` below exists and has no x86 twin.
 *
 * 2. THE STACK POINTER MUST BE 16-BYTE ALIGNED whenever it is used as a
 *    base address, and the processor CHECKS it (SCTLR_EL1.SA). On x86 a
 *    misaligned stack costs performance; here it is a synchronous
 *    exception, ESR class 0x25, at the first `stp`. The alignment is
 *    therefore forced in `task_prepare` rather than trusted.
 *
 * The saved block is 112 octets:
 *     0  x19 x20     16  x21 x22     32  x23 x24     48  x25 x26
 *    64  x27 x28     80  x29 x30     96  sp
 */

    .set CTX_SP,   96
    .set CTX_SIZE, 112

    .text

/* arch_switch(x0 = where to save the old context, x1 = the new context) */
    .globl arch_switch
arch_switch:
    stp     x19, x20, [x0, #0]
    stp     x21, x22, [x0, #16]
    stp     x23, x24, [x0, #32]
    stp     x25, x26, [x0, #48]
    stp     x27, x28, [x0, #64]
    stp     x29, x30, [x0, #80]
    mov     x9, sp
    str     x9, [x0, #CTX_SP]

    ldr     x9, [x1, #CTX_SP]
    mov     sp, x9
    ldp     x19, x20, [x1, #0]
    ldp     x21, x22, [x1, #16]
    ldp     x23, x24, [x1, #32]
    ldp     x25, x26, [x1, #48]
    ldp     x27, x28, [x1, #64]
    ldp     x29, x30, [x1, #80]
    ret

/* task_prepare(x0 = context block, x1 = stack top, x2 = entry, x3 = argument)
 *
 * Makes a context that has never run look like one that called
 * `arch_switch` and is waiting to come back out of it. The entry point goes
 * into the saved x30, the argument into the saved x19 -- the entry stub
 * below moves it to x0, because x0 is caller saved and would not survive
 * the switch. */
    .globl task_prepare
task_prepare:
    /* the stack pointer has to be 16-byte aligned or the first `stp` in the
     * new task takes a stack alignment fault */
    and     x1, x1, #0xFFFFFFFFFFFFFFF0

    stp     xzr, xzr, [x0, #0]
    stp     xzr, xzr, [x0, #16]
    stp     xzr, xzr, [x0, #32]
    stp     xzr, xzr, [x0, #48]
    stp     xzr, xzr, [x0, #64]
    str     x3, [x0, #0]                    /* x19 = the argument          */
    str     x2, [x0, #8]                    /* x20 = the entry point       */
    adr     x9, task_entry
    stp     xzr, x9, [x0, #80]              /* x29 = 0, x30 = task_entry   */
    str     x1, [x0, #CTX_SP]
    ret

/* Where a fresh task comes out of `arch_switch`. x19 and x20 were planted
 * by `task_prepare`; from here on it is an ordinary call. */
task_entry:
    mov     x0, x19
    blr     x20
    /* A task that returns has nothing to return to. Say so and stop rather
     * than fall into whatever follows in memory. */
    b       arch_halt
