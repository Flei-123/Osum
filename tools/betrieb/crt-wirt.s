/* SPDX-License-Identifier: GPL-2.0-only */
/* tools/betrieb/crt-wirt.s -- DERSELBE PROGRAMMTEXT, EIN ANDERER LADER.
 *
 * Ein Programm unter `kernel/user/` ist ein gewoehnliches statisches ELF
 * mit Linux' Systemaufrufnummern (Runde K4). Es laeuft deshalb NICHT NUR
 * auf Osum, sondern auch auf dem Wirt -- und das ist die Messstrecke
 * dieser Runde: `/bin/host` gegen `dig`, mit echten Nameservern und
 * echten Namen, ohne fuer jede Frage eine Maschine zu starten.
 *
 * DER EINZIGE UNTERSCHIED steht in diesen zwei Zeilen. Osums Lader
 * (`kernel/elf.fi`) legt den Argumentblock an und uebergibt seine
 * Adresse in `rdi`; Linux legt DENSELBEN Block (argc, die Zeiger, eine
 * Null, dann die Umgebung) auf den Stapel und uebergibt nichts. Also:
 * `rsp` nach `rdi`, und danach ist alles identisch. Firns eigenes
 * `_start` tut an dieser Stelle dasselbe.
 *
 * DIESE DATEI IST KEIN TEIL DES SYSTEMS. Sie wird von
 * `tools/betrieb/wirt.sh` benutzt und liegt in keinem Abbild.
 */
    .section .text
    .globl _start
_start:
    xorq %rbp, %rbp
    movq %rsp, %rdi                 /* Linux: der Block liegt auf dem Stapel */
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
