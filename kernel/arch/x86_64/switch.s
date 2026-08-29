/* SPDX-License-Identifier: GPL-2.0-only */
/* kernel/switch.s -- round 62: the context switch.
 *
 * The third and last non-Firn file of the kernel, and it is here for the
 * same reason as the other two: what happens in it CANNOT be written in a
 * language. `context_switch` leaves one function and comes back in
 * another one -- it changes the stack pointer under the feet of the
 * running code. A compiler that is told nothing about this would keep
 * values in registers across the switch and read them back afterwards out
 * of the wrong task.
 *
 * Therefore the rule of this file: `context_switch` preserves EVERY
 * general purpose register and the flags. Only `rsp` changes. Whatever
 * the register allocator of firnc0 or the straight-line code of firnc1
 * believes about the machine stays true across the call -- with the one
 * exception of memory, and that is what `clobber("memory")` in
 * `sched.fi` is for.
 *
 *     context_switch(rdi = &old_task.rsp, rsi = new_task.rsp)
 *
 * The stack the switch leaves behind (from the new rsp upwards):
 *
 *     +0   rflags
 *     +8   r15   +16 r14  +24 r13  +32 r12  +40 r11  +48 r10
 *     +56  r9    +64 r8   +72 rdi  +80 rsi  +88 rbp  +96 rbx
 *     +104 rdx   +112 rcx +120 rax
 *     +128 the return address
 *
 * `sched.frame_build` writes exactly this layout for a task that has
 * never run: the return address is the first Firn function of the task,
 * and rdi/rsi/rdx are its arguments. A new task is therefore not a
 * special case in the switch -- it looks like a task that was switched
 * away from a moment ago.
 */

    .section .text

    .globl context_switch
context_switch:
    pushq %rax
    pushq %rcx
    pushq %rdx
    pushq %rbx
    pushq %rbp
    pushq %rsi
    pushq %rdi
    pushq %r8
    pushq %r9
    pushq %r10
    pushq %r11
    pushq %r12
    pushq %r13
    pushq %r14
    pushq %r15
    pushfq

    /* ---------------------------------------- RUNDE FEEDBACK: xmm ---
     *
     * Ab dieser Runde darf Ring 3 die 128-Bit-Register benutzen
     * (`kernel/sse.fi` setzt CR4.OSFXSR). Wer sie erlaubt, muss sie
     * auch aufheben: `sha256_ni_blocks` in `/bin/fetch` rechnet in
     * xmm0..xmm5, und ein Zeitgeber-Wechsel mitten darin wuerde die
     * halb gerechneten Runden der einen Aufgabe der naechsten in die
     * Hand geben.
     *
     * Die 512 Oktette liegen auf dem KERNSTAPEL DER AUFGABE, die
     * weggelegt wird -- unter dem Registerblock, nicht daneben. Damit
     * braucht ein Aufgabendatensatz kein neues Feld und `frame_build`
     * nur eine Anfangsablage.
     *
     * `fxsave` verlangt 16 Oktette Ausrichtung. Statt sie aus der
     * Aufrufregel zu FOLGERN, wird sie hier ERZWUNGEN (`and $-16`) --
     * und weil `and` den Abstand zum Registerblock unbekannt macht,
     * steht dessen Adresse mit im Rahmen (bei +512).
     *
     * DAS BIT WIRD JEDES MAL GELESEN, nicht angenommen: auf einer
     * Maschine ohne FXSR steht OSFXSR nicht, und `fxsave` waere dort
     * ein ungueltiger Befehl IM KERN. Ein `mov %cr4` kostet weniger als
     * ein zweiter Weg durch diese Datei.
     */
    movq %rsp, %rax                 /* Anfang des Registerblocks */
    subq $528, %rsp
    andq $-16, %rsp
    movq %rax, 512(%rsp)
    movq %cr4, %rax
    testl $0x200, %eax              /* CR4.OSFXSR */
    jz 1f
    fxsave (%rsp)
1:
    movq %rsp, (%rdi)               /* rdi still holds the slot */
    movq %rsi, %rsp                 /* from here on: the other task */
    movq %cr4, %rax
    testl $0x200, %eax
    jz 2f
    fxrstor (%rsp)
2:
    movq 512(%rsp), %rsp            /* zurueck auf den Registerblock */
    popfq
    popq %r15
    popq %r14
    popq %r13
    popq %r12
    popq %r11
    popq %r10
    popq %r9
    popq %r8
    popq %rdi
    popq %rsi
    popq %rbp
    popq %rbx
    popq %rdx
    popq %rcx
    popq %rax
    ret

/* The return address under the first frame of a new task. A task body
 * that returns instead of calling `exit` would land here -- and a kernel
 * that goes on running on a stack it has already left is worse than a
 * kernel that stops. */
    .globl task_guard
task_guard:
    cli
1:
    hlt
    jmp 1b

/* ------------------------------------------------- into ring 3 ---
 *
 * `enter_user(rip, rsp, arg)` is the way a PROCESS starts: the kernel
 * part of it has run (its kernel stack carries the frame of
 * `proc.user_start`), and from here on the task lives in ring 3. Unlike
 * `enter_user` in isr.s (round 59) this one does not come back at all --
 * the way out of a process is `exit`, a fault, or the timer.
 *
 * Every register that is not an argument is zeroed. What ring 3 gets to
 * see should be what the kernel meant to hand over, and nothing that
 * happened to be left lying around in a register.
 */
    .globl enter_user_task
enter_user_task:
    movq %rdi, %rcx                 /* sysret takes the rip out of rcx */
    movq $0x202, %r11               /* rflags: reserved bit + IF */
    movq %rsi, %rsp                 /* the user stack */
    movq %rdx, %rdi                 /* argument 0 for the user program */
    xorl %eax, %eax
    xorl %esi, %esi
    xorl %edx, %edx
    xorl %ebx, %ebx
    xorl %ebp, %ebp
    xorl %r8d, %r8d
    xorl %r9d, %r9d
    xorl %r10d, %r10d
    xorl %r12d, %r12d
    xorl %r13d, %r13d
    xorl %r14d, %r14d
    xorl %r15d, %r15d
    sysretq
