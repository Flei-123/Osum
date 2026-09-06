/* SPDX-License-Identifier: MIT */
/* kernel/user/sysstub.s -- DIE TUER AUS EINEM PROGRAMM, ALS OKTETTE.
 * Runde CERTUS-AUF-OSUM.
 *
 * WARUM ES DIESE DATEI GIBT, in einem Satz: der Browser ist ein
 * Programm im Profil `app` (er hat einen Sammler), die Fensterschicht
 * dieses Systems ist Quelltext im Profil `kernel` -- und Firn laesst
 * `asm(...)` NUR unter `kernel` zu (compiler/src/core.rs, `hook_asm`,
 * SPEC 2) und das Schluesselwort `syscall` NUR unter `app`
 * (compiler/src/prof.rs). Das Profil bestimmt die WURZELDATEI. Ein
 * Programm, das beides bindet, gibt es also nicht -- solange die Tuer
 * in Firn steht.
 *
 * Hier steht sie nicht in Firn. `extern fn` (Runde 75) geht in BEIDEN
 * Profilen, und was dahinter liegt, sind acht Befehlsfolgen, die
 * genau das tun, was die `asm`-Bloecke in lib/libc/kcall.fi und
 * kernel/user/wlibc.fi bisher taten:
 *
 *     Aufruf (System V):  rdi rsi rdx rcx r8  r9
 *     Systemaufruf:       rax rdi rsi rdx r10 r8  r9
 *
 * Also: die Nummer aus rdi nach rax, alles andere um eine Stelle nach
 * links, und der vierte Platz wechselt von rcx nach r10 -- weil
 * `syscall` die Ruecksprungadresse selbst in rcx legt, bevor der Kern
 * irgendetwas sieht. Das ist Linus' Abmachung und seit Runde K4 auch
 * Osums.
 *
 * DIESE DATEI WIRD VON crt.s MITGELESEN (`.include`), damit jedes
 * Programm der Platte sie hat, ohne dass ein einziges Bauskript etwas
 * dazulernen muss. Der Browser bindet sie ALLEIN -- er bringt seinen
 * eigenen `_start` mit (firnc -c legt ihn selbst hinein), und crt.o
 * daneben waeren zwei davon.
 */

    .section .text

/* ---- die fuenf gewoehnlichen Tueren: 0 bis 5 Argumente hinter der Nummer */

    .globl osum_sys0
osum_sys0:
    movq %rdi, %rax
    syscall
    ret

    .globl osum_sys1
osum_sys1:
    movq %rdi, %rax
    movq %rsi, %rdi
    syscall
    ret

    .globl osum_sys2
osum_sys2:
    movq %rdi, %rax
    movq %rsi, %rdi
    movq %rdx, %rsi
    syscall
    ret

    .globl osum_sys3
osum_sys3:
    movq %rdi, %rax
    movq %rsi, %rdi
    movq %rdx, %rsi
    movq %rcx, %rdx
    syscall
    ret

    .globl osum_sys4
osum_sys4:
    movq %rdi, %rax
    movq %rsi, %rdi
    movq %rdx, %rsi
    movq %rcx, %rdx
    movq %r8,  %r10
    syscall
    ret

    .globl osum_sys5
osum_sys5:
    movq %rdi, %rax
    movq %rsi, %rdi
    movq %rdx, %rsi
    movq %rcx, %rdx
    movq %r8,  %r10
    movq %r9,  %r8
    syscall
    ret

/* ---- die vier mit SECHS Argumenten, jede mit ihrer eigenen Tuer
 *
 * Der Grund steht im Kopf von lib/libc/kcall.fi: eine Firn-Funktion
 * nimmt hoechstens sechs Argumente, und die Nummer waere das siebte.
 * Also steht die Nummer hier fest im Befehl.
 */

/* osum_map_anon(len, prot, flags) -> mmap(0, len, prot, flags, -1, 0) */
    .globl osum_map_anon
osum_map_anon:
    movq %rdx, %r10                 /* flags */
    movq %rsi, %rdx                 /* prot */
    movq %rdi, %rsi                 /* len */
    xorq %rdi, %rdi                 /* die Adresse ist ein Wunsch: keiner */
    movq $-1, %r8                   /* kein Deskriptor */
    xorq %r9, %r9                   /* Versatz 0 */
    movq $9, %rax                   /* mmap */
    syscall
    ret

/* osum_sock_send(fd, buf, len, addr, alen) -> sendto(fd,buf,len,0,addr,alen) */
    .globl osum_sock_send
osum_sock_send:
    movq %r8,  %r9                  /* alen */
    movq %rcx, %r8                  /* addr */
    xorq %r10, %r10                 /* keine Fahnen */
    movq $44, %rax                  /* sendto */
    syscall
    ret

/* osum_sock_recv(fd, buf, len, addr, lenp) -> recvfrom(...) */
    .globl osum_sock_recv
osum_sock_recv:
    movq %r8,  %r9                  /* lenp */
    movq %rcx, %r8                  /* addr */
    xorq %r10, %r10
    movq $45, %rax                  /* recvfrom */
    syscall
    ret

/* osum_aio_submit(op, fd, buf, len, ud) -- Runde ASYNC, Nummer 1981 */
    .globl osum_aio_submit
osum_aio_submit:
    /* op=rdi, fd=rsi, buf=rdx stehen schon richtig; ud=r8 auch.
     * Es fehlt nur der vierte Platz: rcx -> r10. */
    movq %rcx, %r10                 /* len */
    movq $1981, %rax
    syscall
    ret

    .section .note.GNU-stack,"",@progbits
