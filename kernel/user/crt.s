/* SPDX-License-Identifier: MIT */
/* kernel/user/crt.s -- round K1: the four instructions a user
 * program cannot write in Firn.
 *
 * Everything else down here is Firn. What is left over is exactly what a
 * language has no words for:
 *
 *   1. THE ENTRY POINT. The kernel jumps to `_start` with `rdi` pointing
 *      at the argument block it built on the top stack page (see
 *      `kernel/elf.fi`), and with a stack pointer that is 16
 *      aligned. System V wants `rsp % 16 == 8` INSIDE a function -- the
 *      `call` below is what produces that, and a Firn function cannot
 *      emit a `call` to itself.
 *   2. THE WAY OUT. A Firn `fn` ends in `ret`, and there is nothing to
 *      return to: under `_start` lies no frame. The return value is the
 *      exit code, and `exit` is a system call.
 *   3. `osum_panic`. Under `profile kernel` a checked arithmetic site
 *      that goes out of range calls this name (SPEC section 13, item L9);
 *      the compiler leaves it undefined on purpose. In the kernel
 *      `isr.s` defines it. A program on the disk has no kernel to fall
 *      back on, so it defines its own: say what happened on descriptor 2
 *      and leave with 70. Without this definition every user program
 *      would carry an undefined symbol, and `ld` would refuse it.
 *
 * The system call numbers are the ones in `kernel/sys.fi`, and since
 * ROUND K4 those are Linux's: 60 = exit, 1 = write. Round K1 had 10 and 11
 * here, and the day the table changed underneath them this file was the
 * one that went quiet -- a program that printed everything it had and then
 * spun in the loop under `exit`, because `exit` had become a call the
 * kernel does not have and -ENOSYS does not stop anybody.
 */

    .section .text
    .globl _start
_start:
    xorq %rbp, %rbp                 /* no caller frame under us */
    andq $-16, %rsp                 /* System V: aligned before the call */
    call USER_ENTRY                 /* rdi already holds the arguments */
    movq %rax, %rdi                 /* the return value is the exit code */
    movq $60, %rax                  /* exit */
    syscall
1:  jmp 1b                          /* exit does not come back */

    .globl osum_panic
osum_panic:
    /* rdi = message, esi = length, rdx/rcx = the two operands. */
    movq %rsi, %rdx
    movq %rdi, %rsi
    movq $2, %rdi                   /* descriptor 2 */
    movq $1, %rax                   /* write */
    syscall
    movq $70, %rdi                  /* and out, with a code of its own */
    movq $60, %rax                  /* exit */
    syscall
2:  jmp 2b


/* ---------------------------------------------------- round K9: signals
 *
 * EINE BEHANDLUNGSROUTINE IST EINE ADRESSE, und Stufe 0 von Firn kann die
 * Adresse einer eigenen Funktion nicht nennen (SPEC 14) -- derselbe
 * Grund, aus dem `isr.s` eine Tabelle von Wahlnummern hat. Ohne diese
 * neun Zeilen koennte kein Programm auf dieser Platte `sigaction` auch
 * nur AUFRUFEN, egal wie vollstaendig der Kernel darunter ist.
 *
 * Also liegt die Routine hier, neben `_start`, und sie tut genau das,
 * was eine Routine tun darf und ein Programm nachpruefen kann: mitzaehlen
 * und die Nummer aufheben. Kein Systemaufruf, kein Speicher, den ein
 * zweites Signal mitten darin zerreissen koennte -- zwei Speicherzugriffe
 * und ein `ret`. Der `ret` geht in den Trampolinsprung, den der Kernel
 * als Ruecksprungadresse untergelegt hat (`sigreturn_tramp` in isr.s),
 * und der legt den Zusammenhang zurueck.
 *
 * Ein Firn-Programm kommt an die drei Namen mit `lea rax, [rip + name]`
 * in einem `asm`-Block heran; der Binder loest sie auf, weil crt.o und
 * das Programm zusammen gebunden werden.
 */
    .text
    .globl osum_sighandler
osum_sighandler:
    incq osum_sigcount(%rip)
    movq %rdi, osum_siglast(%rip)
    ret

/* Die zweite Routine: sie zaehlt in einen anderen Zaehler, damit ein
 * Programm zwei Signale unterscheiden kann, ohne die Nummer zu lesen. */
    .globl osum_sighandler2
osum_sighandler2:
    incq osum_sigcount2(%rip)
    movq %rdi, osum_siglast(%rip)
    ret

/* Die dritte: sie kehrt NICHT zurueck, sie beendet den Prozess mit
 * 40 + Signalnummer. Das ist die einzige Art, das Abfangen eines
 * PROZESSORFEHLERS zu messen: kehrte die Routine zurueck, liefe derselbe
 * Befehl noch einmal und faellt noch einmal -- jedes Unix macht das so,
 * und deshalb setzt der Kernel eine Routine fuer ein Fehlersignal beim
 * Zustellen auf das Standardverhalten zurueck. Ein Beendigungscode von
 * 51 sagt also zweierlei auf einmal: die Routine LIEF in Ring 3 (sie hat
 * von dort einen Systemaufruf gemacht), und sie bekam die Nummer 11. */
    .globl osum_sigexit
osum_sigexit:
    incq osum_sigcount(%rip)
    movq %rdi, osum_siglast(%rip)
    addq $40, %rdi
    movq $60, %rax                  /* exit */
    syscall
1:  jmp 1b

    .bss
    .align 8
    .globl osum_sigcount
osum_sigcount:
    .skip 8
    .globl osum_sigcount2
osum_sigcount2:
    .skip 8
    .globl osum_siglast
osum_siglast:
    .skip 8

    .section .note.GNU-stack,"",@progbits
