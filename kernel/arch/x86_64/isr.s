/* SPDX-License-Identifier: GPL-2.0-only */
/* kernel/isr.s -- round 59: the interrupt entry points.
 *
 * The second and last non-Firn file of the kernel. `#[interrupt]` in Firn
 * (round 52) produces a handler that saves all registers and ends with
 * `iretq` -- but it cannot do three things a real kernel needs:
 *
 *   1. it does not know WHICH vector it was entered through,
 *   2. it cannot read the ERROR CODE that the processor pushes for ten of
 *      the exceptions (and only for those),
 *   3. it cannot pass a POINTER to the saved registers on, so that a
 *      handler in Firn could print or change them.
 *
 * Hence 48 stubs of three instructions each. They equalise the two shapes
 * of the exception frame (with and without error code), push the vector
 * number and jump into ONE common stub. That one saves all 15 general
 * purpose registers, hands `rsp` (= the address of the frame) and the
 * kernel data area to `KERNEL_TRAP` -- and everything after that happens in
 * Firn.
 *
 * The frame that `KERNEL_TRAP` sees, offsets from rdi:
 *
 *     +0 r15  +8 r14  +16 r13  +24 r12  +32 r11  +40 r10  +48 r9
 *     +56 r8  +64 rdi +72 rsi  +80 rbp  +88 rbx  +96 rdx  +104 rcx
 *     +112 rax  +120 vector  +128 error code
 *     +136 rip  +144 cs  +152 rflags  +160 rsp  +168 ss
 *
 * The last five are what the processor itself pushed.
 *
 * `KERNEL_TRAP`, `KERNEL_SYSCALL` and `KERNEL_MAIN` are resolved at link time
 * with `ld --defsym`; the symbol prefix differs between the two compilers
 * (`_F0.` / `_F1.`).
 */

    .section .text

/* A vector WITHOUT an error code: push a zero, so that every frame has
 * the same shape. */
    .macro isr_plain num
    .globl isr\num
isr\num:
    pushq $0
    pushq $\num
    jmp isr_common
    .endm

/* A vector WITH an error code: the processor has already pushed it. */
    .macro isr_code num
    .globl isr\num
isr\num:
    pushq $\num
    jmp isr_common
    .endm

    isr_plain 0                 /* #DE divide error */
    isr_plain 1
    isr_plain 2
    isr_plain 3
    isr_plain 4
    isr_plain 5
    isr_plain 6                 /* #UD invalid opcode */
    isr_plain 7
    isr_code  8                 /* #DF double fault */
    isr_plain 9
    isr_code  10
    isr_code  11
    isr_code  12                /* #SS stack fault */
    isr_code  13                /* #GP general protection */
    isr_code  14                /* #PF page fault */
    isr_plain 15
    isr_plain 16
    isr_code  17
    isr_plain 18
    isr_plain 19
    isr_plain 20
    isr_code  21
    isr_plain 22
    isr_plain 23
    isr_plain 24
    isr_plain 25
    isr_plain 26
    isr_plain 27
    isr_plain 28
    isr_code  29
    isr_code  30
    isr_plain 31
    isr_plain 32                /* IRQ0  timer */
    isr_plain 33                /* IRQ1  keyboard */
    isr_plain 34
    isr_plain 35
    isr_plain 36
    isr_plain 37
    isr_plain 38
    isr_plain 39
    isr_plain 40
    isr_plain 41
    isr_plain 42
    isr_plain 43
    isr_plain 44
    isr_plain 45
    isr_plain 46
    isr_plain 47

isr_common:
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

    movq %rsp, %rdi                 /* the frame */
    movq $kdata, %rsi               /* the kernel data area */
    movq %rsp, %rbx                 /* rbx is saved, so it may be used */
    andq $-16, %rsp                 /* System V wants a 16-aligned stack */
    call KERNEL_TRAP
    movq %rbx, %rsp

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
    addq $16, %rsp                  /* vector number and error code */
    iretq

/* ------------------------------------------------------ system call ---
 *
 * `syscall` changes neither rsp nor the stack: the processor only puts
 * the return address into rcx and rflags into r11. Switching to a kernel
 * stack is the kernel's job -- and cannot be done in a compiled function,
 * because that one would already have written to the user stack.
 *
 * ROUND 62 changes two things here. There is more than one process now,
 * so the kernel stack is no longer a single fixed one: the scheduler
 * writes the stack of the CURRENT task into the data area, and the entry
 * point reads it from there (`KSTACK_CUR`, see kstate.fi). A task that is
 * in ring 3 has an empty kernel stack -- that is why its upper end may be
 * taken without further ado. And a system call now carries three
 * arguments instead of one.
 *
 * The ABI, seen from ring 3:
 *
 *     rax = number, rdi = arg0, rsi = arg1, rdx = arg2
 *     rax = result (negative = error code, see sys.fi)
 *     rcx, r11 destroyed by the processor, r8/r10 by the kernel
 *
 * Handed to Firn: rdi = number, rsi/rdx/rcx = the three arguments,
 * r8 = kernel data area.
 */
    .set KSTACK_CUR, 344            /* kstate.KSTACK_CUR -- kstate.fi */

    .globl syscall_entry
syscall_entry:
    /* ROUND K4. Two things changed here, and both are the reason this
     * round exists.
     *
     * FIRST: r10 is NOT scratch any more. Linux x86-64 passes the fourth
     * argument of a system call in r10 (`syscall` destroys rcx, so the C
     * argument in rcx moves one register aside), the fifth in r8 and the
     * sixth in r9. `mmap` has six of them. The old entry point wrote the
     * user stack pointer over r10 before anybody could look at it. It goes
     * into `sys_rsp` instead -- interrupts are off between the store and
     * the push that reads it back, because MSR_SFMASK masks IF for the
     * whole system call (`kernel/user.fi`, `setup`).
     *
     * SECOND: what is saved is a COMPLETE user context -- sixteen words on
     * the kernel stack of the calling task -- and its ADDRESS is what the
     * kernel gets. Three calls need that and cannot be written without it:
     *
     *   * `fork` gives the child the register set of the parent, rbx, rbp
     *     and r12..r15 included -- registers a `call` preserves and that
     *     therefore never appear in a Firn argument,
     *   * `execve` returns to a DIFFERENT rip with a DIFFERENT rsp in the
     *     SAME task: it writes both into the frame and lets the ordinary
     *     way out run,
     *   * a signal handler, when there is one, needs exactly the same.
     *
     * The layout, as offsets from the pointer Firn receives (the F_*
     * constants at the top of `kernel/sys.fi`):
     *
     *   +0   r15  +8  r14  +16 r13  +24 r12  +32 rbp  +40 rbx
     *   +48  r9   +56 r8   +64 r10  +72 rdx  +80 rsi  +88 rdi
     *   +96  rax (the number on the way in, the result on the way out)
     *   +104 rip  +112 rflags  +120 user rsp
     *
     * Sixteen words are 128 octets, so the 16-alignment of the kernel
     * stack survives them and the `call` below gets what System V wants.
     *
     * Handed to Firn: rdi = the number, rsi = the frame, rdx = the kernel
     * data area.
     */
    movq %rsp, sys_rsp(%rip)        /* the user stack -- no register is free */
    movq kdata + KSTACK_CUR(%rip), %rsp
    pushq sys_rsp(%rip)             /* user rsp */
    pushq %r11                      /* user rflags */
    pushq %rcx                      /* user rip */
    pushq %rax                      /* the number */
    pushq %rdi                      /* argument 0 */
    pushq %rsi                      /* argument 1 */
    pushq %rdx                      /* argument 2 */
    pushq %r10                      /* argument 3 */
    pushq %r8                       /* argument 4 */
    pushq %r9                       /* argument 5 */
    pushq %rbx
    pushq %rbp
    pushq %r12
    pushq %r13
    pushq %r14
    pushq %r15

    movq %rax, %rdi                 /* the number */
    movq %rsp, %rsi                 /* the frame */
    movq $kdata, %rdx               /* the data area */
    call KERNEL_SYSCALL
    movq %rax, 96(%rsp)             /* the result belongs in the frame */
    jmp user_return

/* `user_resume(rdi = frame)` -- a context that does NOT lie on the stack
 * this processor is standing on. `proc.resume_start` starts the child of a
 * `fork` with it: the frame was copied into the data area, the rax in it
 * is zero, and from here the child is indistinguishable from a process
 * that has just come back out of a system call. `cli`, because rsp walks
 * through that copy for sixteen instructions and an interrupt would push
 * its own frame into the middle of it; `sysretq` puts the flags back out
 * of r11, IF included.
 */
    .globl user_resume
user_resume:
    cli
    movq %rdi, %rsp
user_return:
    popq %r15
    popq %r14
    popq %r13
    popq %r12
    popq %rbp
    popq %rbx
    popq %r9
    popq %r8
    popq %r10
    popq %rdx
    popq %rsi
    popq %rdi
    popq %rax
    popq %rcx                       /* the rip `sysret` returns to */
    popq %r11                       /* the flags it puts back */
    popq %rsp                       /* the user stack */
    sysretq

/* ------------------------------------------------- ring 3 and back ---
 *
 * `enter_user(rip, rsp)` leaves ring 0 through `sysretq`; `leave_user()`
 * comes back. The return happens without `sysret`, because the way back
 * is not a return to the user program but the abandonment of it: the
 * kernel stack pointer saved in `enter_user` is put back, and `ret` then
 * returns to whoever called `enter_user`. Registers that System V calls
 * callee-saved are rescued along -- the caller is a compiled Firn
 * function and relies on them.
 */
    .globl enter_user
enter_user:
    movq %rsp, saved_rsp(%rip)
    movq %rbx, saved_rbx(%rip)
    movq %rbp, saved_rbp(%rip)
    movq %r12, saved_r12(%rip)
    movq %r13, saved_r13(%rip)
    movq %r14, saved_r14(%rip)
    movq %r15, saved_r15(%rip)
    movq %rdi, %rcx                 /* sysret takes the rip out of rcx */
    movq $0x202, %r11               /* rflags: reserved bit + IF */
    movq %rsi, %rsp                 /* the user stack */
    sysretq

    .globl leave_user
leave_user:
    movq saved_rsp(%rip), %rsp
    movq saved_rbx(%rip), %rbx
    movq saved_rbp(%rip), %rbp
    movq saved_r12(%rip), %r12
    movq saved_r13(%rip), %r13
    movq saved_r14(%rip), %r14
    movq saved_r15(%rip), %r15
    xorl %eax, %eax
    ret

/* The user program. Deliberately not in Firn: everything that runs here
 * has to lie in a page mapped for ring 3 -- the linker script places
 * exactly this section on its own 4 KiB page, and the kernel sets the
 * user bit for that page and no other. A compiled Firn function would sit
 * in the middle of the kernel's text.
 *
 * Number 1 = write a mark, number 2 = leave ring 3.
 *
 * THE COUNTER-CHECK is the branch: when the kernel answers system call 1
 * with something other than zero, the program executes `hlt`. That
 * instruction is allowed in ring 0 and forbidden in ring 3 -- if a #GP
 * with cs=0x2b arrives afterwards, the processor really was in ring 3.
 * Without such a probe, "we were in ring 3" would be a claim.
 */
    .section .utext, "ax"
    .globl user_entry
user_entry:
    movq $1, %rax
    movq $59, %rdi
    syscall
    testq %rax, %rax
    jnz 2f
    movq $2, %rax
    xorq %rdi, %rdi
    syscall
1:
    jmp 1b
2:
    hlt                             /* privileged: #GP in ring 3 */
    jmp 1b

/* ROUND K9: DER RUECKWEG AUS EINER SIGNALBEHANDLUNG, und er liegt hier,
 * weil er in `.utext` liegen MUSS. Der Kernel baut einen Rahmen auf den
 * Nutzerstapel und setzt als Ruecksprungadresse der Behandlungsroutine
 * diese drei Befehle. Auf dem STAPEL koennten sie nicht stehen: seit
 * Runde K1 traegt jede Stapelseite das No-Execute-Bit, und ein Kernel,
 * der es fuer den Trampolinsprung wieder abnimmt, hat die aelteste Luecke
 * wieder aufgemacht, die es gibt. `.utext` ist die eine Seite, die in
 * JEDEM Adressraum fuer Ring 3 lesbar und ausfuehrbar ist
 * (`proc.map_programs`), und sie ist nicht beschreibbar -- genau das, was
 * ein Trampolinsprung braucht.
 *
 * Nummer 15 ist `rt_sigreturn`, Linux' Nummer. Kommt der Aufruf zurueck,
 * ist etwas kaputt; dann `hlt`, was in Ring 3 ein #GP ist und damit
 * sichtbar statt still. */
    .section .utext, "ax"
    .globl sigreturn_tramp
sigreturn_tramp:
    movq $15, %rax
    syscall
    hlt

/* `user_iret(rdi = 22 Woerter)` -- zurueck nach Ring 3 mit einem
 * VOLLSTAENDIGEN Zusammenhang, ueber `iretq` statt ueber `sysretq`.
 *
 * WARUM ES BEIDE WEGE BRAUCHT. `sysretq` nimmt rip aus rcx und rflags aus
 * r11 -- und genau diese beiden Register zerstoert `syscall` beim
 * Eintritt. Fuer einen Rueckweg aus einem SYSTEMAUFRUF ist das richtig:
 * dort waren sie ohnehin schon verloren. Ein Signal darf aber auch
 * mitten in ein Programm zugestellt werden, das gar keinen Systemaufruf
 * gemacht hat -- aus dem Zeitgeber heraus, und das ist der Fall, den
 * STRG-C in einer Endlosschleife braucht. Dann sind rcx und r11 echte
 * Registerwerte des Programms, und `sigreturn` muss sie zurueckgeben
 * koennen. Das kann nur `iretq`.
 *
 * Der Block, auf den rdi zeigt, hat GENAU die Form, die `isr_common`
 * oben aufbaut -- fuenfzehn Register, Vektor, Fehlercode, dann die fuenf
 * Woerter des Prozessors. Deshalb ist der Rumpf hier Zeile fuer Zeile
 * das Ende von `isr_common`.
 */
    .text
    .globl user_iret
user_iret:
    cli
    movq %rdi, %rsp
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
    addq $16, %rsp                  /* vector number and error code */
    iretq

/* --------------------------------- rdmsr/wrmsr MIT FAENGERPFAD ---
 * RUNDE KVMFIX. Warum es diese beiden Funktionen gibt und warum sie in
 * Assembler stehen muessen, steht in `kernel/msr.fi`. Hier steht nur,
 * was der Assembler dazu beitraegt: eine ADRESSE, die auf den einen
 * Befehl genau zeigt, der fehlschlagen darf.
 *
 *   msr_read_safe (rdi = Index, rsi = Zeiger auf u64)  -> rax 0 = gut,
 *   msr_write_safe(rdi = Index, rsi = Wert)               rax 1 = #GP
 *
 * DIE ABMACHUNG, UND SIE IST STRENGER ALS SYSTEM V: ausser rax und den
 * Flaggen aendert sich KEIN Register. Der Aufrufer ist ein `asm("call
 * rax", ...)` aus Firn heraus, und was so ein Block dem Uebersetzer
 * ueber zerstoerte Register sagen kann, ist genau das, was in den
 * `clobber`-Klauseln steht. Also zerstoert diese Funktion nichts, was
 * dort nicht steht: rcx und rdx werden gerettet, die Flaggen mit
 * `pushfq`/`popfq` -- ein `shl`/`or` mitten in einem fremden
 * Flaggenzustand waere sonst ein Fehler, den niemand mehr findet.
 *
 * WICHTIG FUER DEN FAENGERPFAD: der Faenger wird mit demselben rsp
 * betreten, den der Befehl hatte, der fehlgeschlagen ist -- ein #GP ist
 * ein FAULT, der Prozessor legt seinen Rahmen auf den Kernelstapel und
 * nicht auf diesen. Deshalb muss der Faenger dieselben drei Woerter
 * abraeumen wie der gute Ausgang, und deshalb stehen die Pops in beiden
 * Zweigen. Eine einzige vergessene Zeile hier waere ein Stapel, der um
 * acht Oktette verrutscht ist, und der Fehler zeigte sich erst drei
 * Funktionen spaeter.
 */
    .globl msr_read_safe
msr_read_safe:
    pushfq
    pushq %rcx
    pushq %rdx
    movq %rdi, %rcx
    movl $0, %eax
    movl $0, %edx
.Lmsr_rd_insn:
    rdmsr                           /* <- darf fehlschlagen */
    shlq $32, %rdx
    orq %rdx, %rax
    movq %rax, (%rsi)
    movl $0, %eax
    popq %rdx
    popq %rcx
    popfq
    ret
.Lmsr_rd_fix:
    movq $0, (%rsi)                 /* keine Messung, also eine Null */
    movl $1, %eax
    popq %rdx
    popq %rcx
    popfq
    ret

    .globl msr_write_safe
msr_write_safe:
    pushfq
    pushq %rcx
    pushq %rdx
    movq %rdi, %rcx
    movq %rsi, %rax                 /* wrmsr nimmt nur eax */
    movq %rsi, %rdx
    shrq $32, %rdx
.Lmsr_wr_insn:
    wrmsr                           /* <- darf fehlschlagen */
    movl $0, %eax
    popq %rdx
    popq %rcx
    popfq
    ret
.Lmsr_wr_fix:
    movl $1, %eax
    popq %rdx
    popq %rcx
    popfq
    ret

    .section .rodata
    .align 8
/* Die Faengertabelle: Paare (Adresse des Befehls, Adresse des Faengers),
 * abgeschlossen durch ein Nullpaar. `kernel/msr.fi::catch_rip` sucht
 * darin, `trap.fi` benutzt das Ergebnis. */
    .globl msr_fixups
msr_fixups:
    .quad .Lmsr_rd_insn, .Lmsr_rd_fix
    .quad .Lmsr_wr_insn, .Lmsr_wr_fix
    .quad 0, 0

    .section .rodata
    .align 8
    .globl vectors
vectors:
    .quad isr0,  isr1,  isr2,  isr3,  isr4,  isr5,  isr6,  isr7
    .quad isr8,  isr9,  isr10, isr11, isr12, isr13, isr14, isr15
    .quad isr16, isr17, isr18, isr19, isr20, isr21, isr22, isr23
    .quad isr24, isr25, isr26, isr27, isr28, isr29, isr30, isr31
    .quad isr32, isr33, isr34, isr35, isr36, isr37, isr38, isr39
    .quad isr40, isr41, isr42, isr43, isr44, isr45, isr46, isr47
    .quad syscall_entry             /* 48 */
    .quad user_entry                /* 49 */
    .quad enter_user                /* 50 */
    .quad leave_user                /* 51 */
    .quad df_stack_top              /* 52: IST1, for the double fault */
    .quad irq_stack_top             /* 53: RSP0, for interrupts out of ring 3 */
    .quad kernel_stack_top          /* 54 */
    /* Round 62: the scheduler, the processes and the user programs. */
    .quad context_switch            /* 55: switch.s */
    .quad enter_user_task           /* 56: switch.s, into ring 3 for good */
    .quad task_guard                /* 57: switch.s, under every new task */
    .quad USER_MAIN                 /* 58: entry point of uprog.fi */
    .quad __user_begin              /* 59: first page of the user programs */
    .quad __user_end                /* 60: behind their last page */
    .quad syscall_stack_top         /* 61: the stack before the first task */
    .quad KERNEL_TASK_MAIN          /* 62: tasks.fi, the body of a kernel task */
    .quad KERNEL_USER_START         /* 63: proc.fi, the way into ring 3 */
    /* Round K4: back into ring 3 with a context the kernel wrote itself. */
    .quad user_resume               /* 64: fork and execve */
    /* Round K5: the other processors (kernel/smp.s, smp.fi). */
    .quad smp_vectors               /* 65: the table of the trampoline */
    .quad KERNEL_AP_MAIN            /* 66: where a started core lands */
    /* Round K9: signals. 67 is the trampoline in `.utext` that every
     * signal handler returns through, 68 the way back into ring 3 with a
     * complete context (iretq instead of sysret). */
    .quad sigreturn_tramp           /* 67: kernel/signal.fi */
    .quad user_iret                 /* 68: kernel/signal.fi */
    /* Runde K12: der Hypervisor. EIN Eintrag, wie bei smp_vectors --
     * der Weltwechsel und die Gaeste stehen in kernel/hv.s. */
    .quad hv_vectors                /* 69: kernel/hv.s */
    /* Runde KVMFIX: der MSR-Zugriff, der ein #GP ueberlebt. 70 ist die
     * Faengertabelle, 71 und 72 die beiden Zugriffe (kernel/msr.fi). */
    .quad msr_fixups                /* 70: kernel/msr.fi */
    .quad msr_read_safe             /* 71 */
    .quad msr_write_safe            /* 72 */
    /* RUNDE STANDBY: der Weg zurueck aus dem Schlaf. 73 und 74 sind
     * Anfang und Ende des Realmodus-Trampolins, das unter 1 MiB kopiert
     * werden muss; 75 ist der Satz geretteter Register (dort traegt
     * `sleep.fi` auch CR3 ein), 76 der Aufruf, der zweimal zurueckkommt.
     * Alles vier steht am Ende DIESER Datei, siehe den Kopf dort. */
    .quad wake16_start              /* 73 */
    .quad wake16_end                /* 74 */
    .quad WAKE_REGS                 /* 75: feste Adresse, siehe unten */
    .quad wake_save                 /* 76 */
    /* 77/78: Anfang und Ende des beschreibbaren Abbildbereichs
     * (kernel.ld). Der Schlafpfad legt davon eine Kopie an; warum,
     * steht bei WAKE_REGS am Ende dieser Datei. */
    .quad __save_begin              /* 77 */
    .quad kernel_end                /* 78 */

    .section .bss, "aw", @nobits
    .align 8
saved_rsp:
    .skip 8
/* Round K4: where `syscall_entry` parks the user stack pointer for the two
 * instructions before it can push it. One processor, and IF masked by
 * MSR_SFMASK -- nothing can get in between. */
sys_rsp:
    .skip 8
saved_rbx:
    .skip 8
saved_rbp:
    .skip 8
saved_r12:
    .skip 8
saved_r13:
    .skip 8
saved_r14:
    .skip 8
saved_r15:
    .skip 8

    .text
    /* --------------------------------------------------- osum_panic ---
     * ROUND 72: the kernel's own Firn code (`fs.fi::fs__mount`, `uprog.fi::
     * u_mkdir`) now uses CHECKED arithmetic (SPEC section 13, `L9`) --
     * under `profile kernel` a checked site that goes out of range ends in
     * `call osum_panic`, an EXTERNAL symbol the compiler deliberately
     * leaves undefined (SPEC section 2: "calls osum_panic, configurable").
     * This is that definition, same shape as `kernel/start.s`'s
     * (the smaller kernel demo): write the message to COM1 -- already
     * initialised by `kmain.fi`'s own `serial.init()`, which runs before
     * anything that could trigger a checked panic -- then halt for good.
     *
     * ABI at the call site (panic_rt.rs::trampoline_asm, kernel branch):
     *   rdi = message pointer, esi = message length, rdx/rcx = the two
     *   operand values, r8 = panic kind code (unused here, see start.s's
     *   own comment on why: decimal formatting is `app`-profile-only
     *   machinery this is not worth duplicating for a two-line message).
     */
    .globl osum_panic
osum_panic:
    movq %rdi, %r10
    movl %esi, %r11d
.Losum_loop:
    testl %r11d, %r11d
    jz .Losum_nl
    movw $0x3FD, %dx
.Losum_wait:
    inb %dx, %al
    testb $0x20, %al
    jz .Losum_wait
    movb (%r10), %al
    movw $0x3F8, %dx
    outb %al, %dx
    incq %r10
    decl %r11d
    jmp .Losum_loop
.Losum_nl:
    movb $10, %al
    movw $0x3F8, %dx
    outb %al, %dx
.Losum_halt:
    cli
    hlt
    jmp .Losum_halt

/* ==================================================================
 * RUNDE STANDBY: DER WEG ZURUECK AUS DEM SCHLAF
 * ==================================================================
 *
 * WARUM DAS HIER STEHT UND NICHT IN EINER EIGENEN DATEI. Eine sechste
 * Assemblerdatei muesste in SIEBZEHN Bauskripte eingetragen werden
 * (`grep -rl 'defsym=KERNEL_MAIN'`), und jedes davon haette danach eine
 * eigene, leicht andere Liste. `isr.s` wird ueberall schon gebaut und
 * gebunden; der Anhang kostet keine einzige Aenderung an einem Laeufer.
 * Der Abschnitt ist durch diesen Kopf und die Endmarke klar abgegrenzt.
 *
 * WAS BEIM AUFWACHEN AUS S3 WIRKLICH PASSIERT, gemessen unter QEMU 7.2
 * mit SeaBIOS (tools/standby/run.sh):
 *
 *   1. Die Firmware kommt aus dem Reset, sieht am Rueckstellwert im CMOS
 *      (QEMU schreibt 0xFE nach 0x0F), dass es ein S3-Aufwachen ist, und
 *      springt auf die Adresse, die im FACS-Feld `firmware_waking_vector`
 *      steht -- IM REALMODUS, mit CS = Adresse >> 4 und IP = 0.
 *   2. Der Prozessor ist damit ein 8086: kein Seitenwerk, keine
 *      Deskriptortabelle, 20 Adressleitungen. Alles, was der Kernel war,
 *      liegt oberhalb von 1 MiB und ist von dort NICHT erreichbar.
 *   3. Also drei Stufen zurueck: Realmodus -> Protected Mode (eine eigene
 *      kleine GDT) -> Long Mode (PAE, CR3, EFER.LME, die GDT aus boot.s).
 *
 * DER EINZIGE TEIL, DER UNTER 1 MiB LIEGEN MUSS, ist die erste Stufe.
 * `wake16_start .. wake16_end` wird von `sleep.fi` nach WAKE_BASE (0x8000)
 * kopiert; alles darin rechnet mit WAKE_BASE und nicht mit der
 * Bindeadresse -- die Sprungziele innerhalb sind Differenzen, die Basis
 * der kleinen GDT ist WAKE_BASE plus Versatz, und der Fernsprung geht auf
 * eine ABSOLUTE Adresse, die der Binder einsetzt. Die zweite und dritte
 * Stufe bleiben, wo sie gebunden sind: im Protected Mode ist der ganze
 * Adressraum flach erreichbar.
 *
 * 0x8000 ist gemessen und nicht geraten: die Sonde in docs/RUNDE-STANDBY.md
 * hat dort Marken abgelegt und sie nach dem Aufwachen unveraendert
 * wiedergefunden. SeaBIOS fasst diese Seite auf dem Aufwachpfad nicht an.
 *
 * ZURUECK IN DEN KERNEL geht es wie bei `setjmp`/`longjmp`: `wake_save`
 * schreibt Ruecksprungadresse, Stapelzeiger und die aufgerufenen-erhalten
 * Register nach `wake_regs` und gibt 0 zurueck; die dritte Stufe stellt
 * genau diese Werte wieder her und gibt 1 zurueck. Fuer den Firn-Code in
 * `sleep.fi` sieht das aus wie ein Aufruf, der zweimal zurueckkommt --
 * beim zweiten Mal ist die Maschine gerade aufgewacht.
 */

/* ==================================================================
 * WO DAS TRAMPOLIN UND SEIN REGISTERSATZ LIEGEN -- BEIDES GEMESSEN
 * ==================================================================
 *
 * WAKE_BASE ist 0x9000 und nicht 0x8000, weil 0x8000 schon vergeben
 * ist: `smp.s` kopiert seinen AP-Trampolin dorthin (AP_BASE). Die
 * Schlafrunde laeuft VOR `smp.stage`, also haette der spaetere
 * Prozessorstart den Wiedereinstieg ueberschrieben -- ein Fehler, der
 * erst beim zweiten Schlaf auf einer Mehrkernmaschine aufgefallen
 * waere.
 *
 * WAKE_REGS ist 0x9200 und liegt damit ebenfalls UNTER 1 MiB, und das
 * ist der zweite und wichtigere Grund fuer diesen Block. Der
 * Registersatz stand zuerst als `.data`-Objekt im Kernabbild. Das
 * funktioniert auf echter Hardware und unter QEMU NICHT, und der
 * Unterschied hat diese Runde zwei Anlaeufe gekostet:
 *
 *   QEMU behandelt das Aufwachen aus S3 als MASCHINENRESET, und bei
 *   jedem Reset schreibt `rom_reset` (hw/core/loader.c) ALLE geladenen
 *   Abbilder erneut in den Speicher -- auch das mit `-kernel`
 *   uebergebene. `.text` und `.rodata` sind danach unveraendert (der
 *   Inhalt ist ja derselbe), aber `.data` steht wieder auf seinen
 *   ANFANGSWERTEN. Der gerettete Stapelzeiger, CR3 und EFER waren
 *   damit beim Aufwachen null; der Kern schaltete das Seitenwerk mit
 *   CR3 = 0 ein und fiel dreifach.
 *
 *   Gemessen in `-d int,cpu_reset`:
 *     v=0e e=0008 cpl=0 IP=0008:00100478 CR2=00100478 CR3=00000000
 *     EFER=0000000000000500   -> danach v=08, danach "Triple fault"
 *
 *   `.bss` ist davon NICHT betroffen (Typ NOBITS, im Abbild steht kein
 *   Oktett davon) -- der ganze kdata-Bereich ueberlebt also. Nur
 *   `.data` wird zurueckgesetzt.
 *
 * Auf echter Hardware gibt es dieses Zurueckschreiben nicht. Der
 * Registersatz unter 1 MiB ist deshalb kein Zugestaendnis an den
 * Emulator, sondern die Fassung, die auf BEIDEM richtig ist: die Seite
 * gehoert ohnehin zum Wiedereinstieg, sie ist auf beiden Wegen
 * erreichbar, und sie ist gemessen unversehrt (eine Sonde hat dort
 * Marken abgelegt und nach dem Aufwachen wiedergefunden).
 */
    .set WAKE_BASE, 0x9000
    .set WAKE_REGS, 0x9200

/* Die Felder in WAKE_REGS:
 *    0 Ruecksprungadresse       8 Stapelzeiger
 *   16 rbx  24 rbp  32 r12  40 r13  48 r14  56 r15
 *   64 CR3 des Kerns           72 EFER
 *   80 CR3 der Uebergangstafel
 *   88 Schattenkopie: Quelle   96 Ziel   104 Oktette   112 Schalter
 *  120 CR4                     128 CR0
 */

    .section .rodata
    .align 16
    .globl wake16_start
wake16_start:
    .code16
    cli
    cld
    xorw %ax, %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %ss
    movw $0x7C00, %sp                   /* Notstapel, wird nur gestreift */
    /* Die kleine GDT: Versatz relativ zu CS (= WAKE_BASE >> 4), die
     * Basis darin absolut, weil `lgdt` eine LINEARE Adresse will. */
    lgdtl %cs:(wake_gdt_desc - wake16_start)
    movl %cr0, %eax
    orl  $1, %eax
    movl %eax, %cr0
    ljmpl $0x08, $wake32                /* absolut: der Binder setzt ein */

    .align 8
wake_gdt32:
    .quad 0                             /* 0x00 null */
    .quad 0x00CF9A000000FFFF            /* 0x08 code32, flach */
    .quad 0x00CF92000000FFFF            /* 0x10 data32, flach */
wake_gdt_desc:
    .word 24 - 1
    .long WAKE_BASE + (wake_gdt32 - wake16_start)
    .align 16
    .globl wake16_end
wake16_end:

    .section .text
    .code32
wake32:
    movw $0x10, %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %ss
    movw %ax, %fs
    movw %ax, %gs
    /* CR4, WIE ER VOR DEM SCHLAFEN WAR, plus PAE.
     *
     * Nicht nur PAE, und das ist der zweite Fehler dieser Runde
     * gewesen: nach dem Aufwachen steht CR4 auf null. Damit sind auch
     * OSFXSR und OSXMMEXCPT weg (die der Prozessor braucht, damit
     * SSE-Befehle ueberhaupt erlaubt sind -- und der Uebersetzer setzt
     * sie fuer jeden groesseren Wertekopiervorgang ein) und ebenso SMEP
     * und SMAP. Der Kern lief danach ein paar hundert Befehle weit und
     * blieb dann ohne Meldung stehen, je nach Zeitpunkt der ersten
     * Unterbrechung an verschiedenen Stellen. Ein Zustand, der VOR dem
     * Schlaf galt, muss nach dem Schlaf wieder gelten -- vollstaendig
     * und nicht in Auswahl. */
    movl WAKE_REGS + 120, %eax
    orl  $(1 << 5), %eax                /* PAE, sonst kein langer Modus */
    movl %eax, %cr4
    /* DIE UEBERGANGS-SEITENTAFEL, und nicht die des laufenden Kerns.
     *
     * Sie bildet das erste Gigabyte eins zu eins ab, mit 2-MiB-Kacheln
     * und ohne ein einziges gesetztes NX-Bit -- gebaut von
     * `sleep.aufsetzen` aus drei Rahmen, die den Schlaf im RAM
     * ueberstehen. Der Grund, warum hier nicht einfach die Tafel des
     * Kerns geladen wird, ist gemessen: mit ihr ueberlebt der Kern das
     * Einschalten des Seitenwerks an genau dieser Stelle nicht (Marke
     * 'B' kommt, Marke 'C' nicht mehr). Der Weg mit einer eigenen,
     * minimalen Tafel fuer den Uebergang ist auch der, den Linux geht
     * (`arch/x86/realmode/rm/trampoline_64.S` baut sich `trampoline_pgd`);
     * die richtige Tafel wird eine Stufe weiter oben in `wake64`
     * geladen, wo der Prozessor schon im langen Modus ist und ein
     * Wechsel des Adressraums nichts Besonderes mehr ist. */
    movl WAKE_REGS + 80, %eax
    movl %eax, %cr3
    /* EFER -- UND ZWAR DER GANZE, nicht nur LME.
     *
     * DAS WAR DER ERSTE ECHTE FEHLER DIESER RUNDE, und er sah aus wie
     * ein Absturz im Nichts: Stufe 1 und 2 des Trampolins meldeten sich,
     * Stufe 3 nie, QEMU beendete sich mit 0 (also ueber einen Reset).
     * Der Grund: `user.setup` setzt EFER Bit 11 (NXE), damit Bit 63
     * eines Seitentafeleintrags "nicht ausfuehrbar" heisst. Nach dem
     * Aufwachen ist EFER auf null zurueckgesetzt -- und dann ist
     * dasselbe Bit 63 ein RESERVIERTES Bit. Der erste Speicherzugriff
     * mit eingeschaltetem Seitenwerk gibt einen Seitenfehler, es gibt
     * noch keine IDT, und aus dem Doppelfehler wird ein Dreifachfehler.
     * Also wird EFER als GANZES gerettet und zurueckgeschrieben; LME
     * kommt sicherheitshalber dazu, falls der Kern ihn nie selbst
     * gesetzt hatte. */
    movl $0xC0000080, %ecx              /* EFER */
    movl WAKE_REGS + 72, %eax
    movl WAKE_REGS + 76, %edx
    orl  $(1 << 8), %eax                /* LME */
    andl $~(1 << 10), %eax              /* LMA ist NUR-LESEN */
    wrmsr
    /* Und CR0 genauso: der geretteten Wert plus PG und PE. Darin
     * stehen unter anderem MP, NE und WP -- ohne WP darf der Kern in
     * schreibgeschuetzte Seiten schreiben, ohne MP/NE verhaelt sich der
     * Rechenwerksfehler anders als vorher. */
    movl WAKE_REGS + 128, %eax
    orl  $0x80000001, %eax              /* PG | PE */
    movl %eax, %cr0
    lgdt gdt64_pointer                  /* die GDT aus boot.s */
    ljmp $0x08, $wake64

    .code64
wake64:
    xorw %ax, %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %ss
    movw %ax, %fs
    movw %ax, %gs
    /* Jetzt der ECHTE Adressraum. Hier ist das ein gewoehnlicher
     * Wechsel im langen Modus und keine Zustandsaenderung mehr. */
    /* ---------------------------------------------------------------
     * DIE SCHATTENKOPIE -- eine Kruecke fuer den Emulator, und sie ist
     * als solche benannt.
     *
     * Auf echter Hardware ueberlebt der Speicher den S3-Schlaf, und
     * dieser Block ist ueberfluessig; das Schalterwort bei WAKE_REGS+112
     * ist dann null und es passiert nichts. Unter `qemu -kernel` ist
     * das Aufwachen ein MASCHINENRESET, und QEMU schreibt bei jedem
     * Reset alle geladenen Abbilder erneut in den Speicher
     * (`rom_reset` in hw/core/loader.c). Damit steht `.data` wieder auf
     * seinen Anfangswerten und `.bss` -- also der ganze kdata-Bereich,
     * die Seitentafeln und die Kernstapel -- auf null. Ein Kern, der
     * danach weiterlaufen will, hat keinen Zustand mehr.
     *
     * Also: vor dem Schlafen wird [__save_begin, kernel_end) in einen
     * Bereich OBERHALB des Abbilds kopiert (den fasst `rom_reset` nicht
     * an), und hier wird zurueckkopiert -- BEVOR der erste Zugriff auf
     * eine Seitentafel oder einen Stapel passiert. Der Kern laeuft an
     * dieser Stelle noch auf der Uebergangstafel und benutzt nur
     * Register; deshalb darf er sich hier selbst unter den Fuessen
     * wegkopieren.
     *
     * WAS DAS NICHT BEWEIST, und das steht auch im Bericht: dass der
     * Speicher den Schlaf ueberlebt. Das beweist es nicht, weil es
     * genau das ausgleicht. Alles ANDERE beweist es weiterhin -- den
     * echten S3-Uebergang, den Wiedereinstieg der Firmware ueber den
     * FACS-Vektor, den Weg Realmodus -> Protected Mode -> Long Mode,
     * das Zurueckholen der Geraete, das Nachziehen der Uhr und die
     * Tore der Aufweckquellen. Und ein Lauf VON DER PLATTE, bei dem
     * QEMU nichts zurueckschreibt, laeuft mit ausgeschaltetem Schalter.
     * ---------------------------------------------------------------- */
    movq WAKE_REGS + 112, %rax
    testq %rax, %rax
    jz 9f
    movq WAKE_REGS + 88,  %rsi          /* Schatten */
    movq WAKE_REGS + 96,  %rdi          /* Ziel im Abbild */
    movq WAKE_REGS + 104, %rcx          /* Oktette */
    shrq $3, %rcx
    rep movsq
9:
    movq WAKE_REGS + 64, %rax           /* jetzt die Tafel des Kerns */
    movq %rax, %cr3
    movq WAKE_REGS + 8,  %rsp
    movq WAKE_REGS + 16, %rbx
    movq WAKE_REGS + 24, %rbp
    movq WAKE_REGS + 32, %r12
    movq WAKE_REGS + 40, %r13
    movq WAKE_REGS + 48, %r14
    movq WAKE_REGS + 56, %r15
    movq WAKE_REGS + 0,  %rcx
    movq $1, %rax                       /* "du kommst aus dem Schlaf" */
    jmpq *%rcx

    /* wake_save() -> 0 beim Sichern, 1 beim Aufwachen. */
    .globl wake_save
wake_save:
    popq %rcx
    movq %rcx, WAKE_REGS + 0
    movq %rsp, WAKE_REGS + 8
    movq %rbx, WAKE_REGS + 16
    movq %rbp, WAKE_REGS + 24
    movq %r12, WAKE_REGS + 32
    movq %r13, WAKE_REGS + 40
    movq %r14, WAKE_REGS + 48
    movq %r15, WAKE_REGS + 56
    xorq %rax, %rax
    jmpq *%rcx

    .text
    .code64
/* ================= Ende des Abschnitts der Runde STANDBY ============== */
