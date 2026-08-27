/* SPDX-License-Identifier: GPL-2.0-only */
/* tools/k11/hostcrt.s -- NUR ZUM ENTWICKELN, nicht Teil des Systems.
 *
 * Dieselben Programme, gebunden fuer den WIRT. Das geht, weil die
 * Aufrufnummern dieses Userlands seit Runde K4 die von Linux sind: ein
 * Programm, das `open`, `read`, `write`, `lseek` und `exit` ruft, laeuft
 * unveraendert unter Linux -- es fehlt nur der Einstieg, denn Osum legt
 * den Argumentblock in rdi und Linux legt ihn auf den Stapel.
 *
 * Und genau da liegt die Ueberraschung: der Block, den `kernel/elf.fi`
 * baut (argc, dann die Zeiger, dann eine Null), hat DIESELBE Form wie
 * der Stapel bei `_start` unter Linux. `mov rdi, rsp` genuegt.
 *
 * Wozu das gut ist: `find`, `sed`, `diff`, `tar` und `gzip` lassen sich
 * damit unmittelbar gegen ihr GNU-Gegenstueck halten, ohne QEMU dazwischen
 * -- eine Runde dauert Millisekunden statt Minuten. Die ABNAHME misst
 * trotzdem in QEMU auf dem echten Kernel; das hier ist die Werkbank.
 *
 * Was hier NICHT laeuft: `xargs` und `top`. Sie rufen 1000 (spawn), 1002
 * (sysinfo) und 1003 (pstat), und die gibt es auf Linux nicht.
 */
    .section .text
    .globl _start
_start:
    xorq %rbp, %rbp
    movq %rsp, %rdi                 /* argc, dann argv[] -- wie in Osum */
    andq $-16, %rsp
    call USER_ENTRY
    movq %rax, %rdi
    movq $60, %rax
    syscall
1:  jmp 1b

    .globl osum_panic
osum_panic:
    movq %rsi, %rdx
    movq %rdi, %rsi
    movq $2, %rdi
    movq $1, %rax
    syscall
    movq $70, %rdi
    movq $60, %rax
    syscall
2:  jmp 2b

    .text
    .globl osum_sighandler
osum_sighandler:
    incq osum_sigcount(%rip)
    movq %rdi, osum_siglast(%rip)
    ret
    .globl osum_sighandler2
osum_sighandler2:
    incq osum_sigcount2(%rip)
    movq %rdi, osum_siglast(%rip)
    ret
    .globl osum_sigexit
osum_sigexit:
    incq osum_sigcount(%rip)
    movq %rdi, osum_siglast(%rip)
    addq $40, %rdi
    movq $60, %rax
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
