/* SPDX-License-Identifier: GPL-2.0-only */
/* kernel/hv.s -- Runde K12: der Weltwechsel und die Gaeste.
 *
 * Die fuenfte Assemblerdatei dieses Kernels, und sie ist aus demselben
 * Grund da wie die vier anderen: was in ihr steht, kann eine Sprache
 * nicht ausdruecken.
 *
 * ZWEI DINGE STEHEN HIER.
 *
 * 1. `hv_vmrun` -- DER WELTWECHSEL. `VMRUN` sichert und laedt NICHT alles.
 *    Was der Prozessor selbst tut (AMD APM Band 2, 15.5.1), und was
 *    QEMUs Umsetzung nachweislich genauso tut (target/i386/tcg/sysemu/
 *    svm_helper.c, helper_vmrun Zeilen 339-345 und do_vmexit 746-786):
 *
 *      gesichert in VM_HSAVE_PA:  ES CS SS DS, GDTR IDTR, EFER,
 *                                 CR0 CR3 CR4, RFLAGS, RIP, RSP, RAX
 *      geladen aus dem VMCB:      dieselben Felder des Gasts
 *
 *    NICHT dabei: RBX RCX RDX RBP RSI RDI R8..R15 -- die stehen in KEINEM
 *    der beiden Bereiche und wandern unveraendert in den Gast hinein und
 *    wieder heraus. Wer sie nicht selbst rettet, gibt dem Gast die
 *    Register des Wirts und bekommt die des Gasts zurueck. Genau das tut
 *    die Schleife unten mit dem Registerblock, den `hv.fi` fuehrt.
 *
 *    Ebenfalls NICHT dabei: FS GS TR LDTR, KernelGsBase, STAR LSTAR
 *    CSTAR SFMASK, SYSENTER_*. Dafuer gibt es `VMSAVE`/`VMLOAD`, und
 *    dieser Kernel BRAUCHT das: er lebt von `syscall`/`sysret` (MSR_STAR,
 *    MSR_LSTAR, MSR_SFMASK aus `kernel/user.fi`) und von seinem TSS
 *    (Unterbrechungen aus Ring 3). Ein Gast, der TR oder LSTAR umsetzt
 *    und dessen Werte stehenbleiben, nimmt den Wirt beim naechsten
 *    Systemaufruf mit. Deshalb die vier Befehle um `vmrun` herum:
 *
 *      vmsave (Wirtsbereich)   Wirt FS/GS/TR/LDTR/STAR/... wegschreiben
 *      vmload (VMCB)           Gastwerte hereinholen
 *      vmrun  (VMCB)           ---- Weltwechsel ----
 *      vmsave (VMCB)           Gastwerte zurueckschreiben
 *      vmload (Wirtsbereich)   Wirt wiederherstellen
 *
 *    Alle drei Befehle nehmen ihre Adresse in rAX.
 *
 * 2. DIE GAESTE. Fuenf kleine Programme, deren Verhalten vollstaendig
 *    bekannt ist, weil sie hier stehen. Sie werden vom Wirt in den
 *    physischen Gastspeicher kopiert; jede Adresse in ihnen ist
 *    GASTPHYSISCH und faengt bei 0 an.
 *
 *    Warum in Assembler und nicht als Zahlenfeld in Firn: ein von Hand
 *    kodiertes Zahlenfeld ist nicht nachpruefbar. Was hier steht, uebersetzt
 *    `as` und `objdump` liest es zurueck.
 *
 * DAS ABKOMMEN MIT DEM WIRT (`hv.fi`, `hv_hypercall`). Ein Gast meldet
 * sich ueber `vmmcall`:
 *
 *      eax = 1   Wert melden:   ecx = Nummer, ebx = Wert
 *      eax = 2   fertig:        ebx = Ergebnis
 *
 * und ueber den Anschluss 0x3F8 gibt er Text aus. Beides faengt der Wirt
 * ab -- der Gast hat weder einen Anschluss noch eine Konsole.
 */

    .section .text

/* ------------------------------------------------------- der Weltwechsel
 *
 *   hv_vmrun(rdi = VMCB physisch,
 *            rsi = Registerblock, 14 Woerter,
 *            rdx = Wirtsbereich fuer vmsave/vmload)
 *
 * Der Registerblock in der Reihenfolge, in der `hv.fi` ihn fuehrt:
 *   0 rbx   8 rcx  16 rdx  24 rbp  32 r8   40 r9   48 r10
 *  56 r11  64 r12  72 r13  80 r14  88 r15  96 rdi 104 rsi
 */
    .globl hv_vmrun
hv_vmrun:
    pushq %rbp
    pushq %rbx
    pushq %r12
    pushq %r13
    pushq %r14
    pushq %r15

    pushq %rdi                      /* [16] das VMCB */
    pushq %rdx                      /* [8]  Wirtsbereich */
    pushq %rsi                      /* [0]  Registerblock */

    /* 0. Kein Interrupt darf in das Fenster fallen, in dem TR und LSTAR
     *    dem Gast gehoeren. GIF schliesst ALLES aus, auch NMI. */
    clgi

    /* 1. Wirtszustand retten, den VMRUN nicht anfasst. */
    movq %rdx, %rax
    vmsave

    /* 2. Gastzustand hereinholen, den VMRUN nicht laedt. */
    movq %rdi, %rax
    vmload

    /* 3. Die Register des Gasts. rsi zuletzt -- es traegt den Block. */
    movq %rdi, %rax                 /* VMRUN nimmt das VMCB in rax */
    movq   0(%rsi), %rbx
    movq   8(%rsi), %rcx
    movq  16(%rsi), %rdx
    movq  24(%rsi), %rbp
    movq  32(%rsi), %r8
    movq  40(%rsi), %r9
    movq  48(%rsi), %r10
    movq  56(%rsi), %r11
    movq  64(%rsi), %r12
    movq  72(%rsi), %r13
    movq  80(%rsi), %r14
    movq  88(%rsi), %r15
    movq  96(%rsi), %rdi
    movq 104(%rsi), %rsi

    vmrun

    /* ------------------ ab hier ist der Wirt wieder da ------------------
     * rsp ist der des Wirts (aus VM_HSAVE_PA). Ganz oben liegt der
     * Registerblock, darunter der Wirtsbereich. */
    pushq %rsi                      /* rsi des Gasts zwischenlagern */
    movq 8(%rsp), %rsi              /* der Registerblock */
    movq %rbx,   0(%rsi)
    movq %rcx,   8(%rsi)
    movq %rdx,  16(%rsi)
    movq %rbp,  24(%rsi)
    movq %r8,   32(%rsi)
    movq %r9,   40(%rsi)
    movq %r10,  48(%rsi)
    movq %r11,  56(%rsi)
    movq %r12,  64(%rsi)
    movq %r13,  72(%rsi)
    movq %r14,  80(%rsi)
    movq %r15,  88(%rsi)
    movq %rdi,  96(%rsi)
    popq %rax                       /* rsi des Gasts */
    movq %rax, 104(%rsi)

    /* 4. Gastzustand wegschreiben, 5. Wirtszustand zurueckholen.
     *    Die drei Zeiger liegen noch auf dem Stapel -- rdi und rdx sind
     *    seit Schritt 3 die des GASTS und taugen dafuer nicht mehr. */
    popq %rsi                       /* Registerblock, wird nicht mehr gebraucht */
    popq %rdx                       /* Wirtsbereich */
    popq %rdi                       /* das VMCB */
    movq %rdi, %rax
    vmsave                          /* Gast: FS/GS/TR/LDTR zurueck ins VMCB */
    movq %rdx, %rax
    vmload                          /* Wirt: FS/GS/TR/LDTR/STAR/LSTAR zurueck */
    stgi

    popq %r15
    popq %r14
    popq %r13
    popq %r12
    popq %rbx
    popq %rbp
    ret

/* `hv_guest_save(rdi = VMCB)` -- die zweite Haelfte von Schritt 4.
 * Getrennt, weil sie nur gebraucht wird, wenn der Gast FS/GS/TR/LDTR
 * ueberhaupt benutzt; die Gaeste dieser Runde tun es nicht, ein Linux
 * taete es. */
    .globl hv_guest_save
hv_guest_save:
    movq %rdi, %rax
    vmsave
    ret

/* `hv_stgi()` / `hv_clgi()` -- das globale Unterbrechungsflag. */
    .globl hv_stgi
hv_stgi:
    stgi
    ret

    .globl hv_clgi
hv_clgi:
    clgi
    ret

/* ===================================================================
 *                            DIE GAESTE
 * ===================================================================
 *
 * WO SIE LIEGEN. Jeder Gast wird auf die GASTPHYSISCHE Adresse 0x1000
 * kopiert, und im Realmodus setzt der Wirt CS.base auf 0x1000. Die Seite
 * darunter bleibt frei, und das ist kein Zufall: bei 0x0000 liegt im
 * Realmodus die Tabelle der Unterbrechungsvektoren, und ohne sie kann
 * der Wirt dem Gast keine Unterbrechung zustellen. Ausserdem liegt dort
 * der Stapel (SS.base 0, SP 0x0FF0) und bei 0x0800 ein Muster, das der
 * Wirt hinterlegt -- der Gast liest es, und dass er den richtigen Wert
 * bekommt, ist der Beweis, dass die verschachtelte Seitentabelle
 * uebersetzt.
 *
 * DIE AUFTEILUNG DES GASTSPEICHERS (gastphysisch, acht Seiten):
 *   0x0000  Vektortabelle, Stapel, das Muster des Wirts bei 0x0800
 *   0x1000  das Programm des Gasts
 *   0x2000  Seitenverzeichnis (Gast 2)
 *   0x3000  Seitentabelle 0..4 MiB, identisch (Gast 2)
 *   0x4000  Seitentabelle 4..8 MiB (Gast 2)
 *   0x5000  die Seite, die unter 0x00400000 erscheinen soll (Gast 2)
 *   0x6000  Stapel im geschuetzten Modus (Gast 2)
 *   0x7000  ABSICHTLICH NICHT ABGEBILDET -- Gast 4 laeuft dagegen
 *
 * DAS ABKOMMEN MIT DEM WIRT (`vmmcall`):
 *   eax = 1   Wert melden:  ecx = Nummer, ebx = Wert
 *   eax = 2   fertig:       ebx = Ergebnis
 *   eax = 3   "wirf mir Vektor 0x20 ein"
 */

    .section .rodata
    .align 16

/* ------------------------------------------------------------ 1. hallo
 *
 * Realmodus, 16 Bit. Er sagt etwas ueber den Anschluss 0x3F8, fragt den
 * Prozessor nach seinem Namen, liest das Muster des Wirts, haengt sich
 * einen Unterbrechungsbehandler in die Vektortabelle und laesst sich
 * vom Wirt eine Unterbrechung einwerfen. Nichts davon darf er wirklich:
 * jeder dieser Schritte ist ein Austritt.
 */
    .code16
    .globl g_hello_start, g_hello_end
g_hello_start:
    cli
    movw $0x0100, %ax
    movw %ax, %ds                   /* DS.base = 0x1000: das Abbild */
    xorw %ax, %ax
    movw %ax, %es                   /* ES.base = 0: der niedrige Speicher */
    movw %ax, %ss
    movw $0x0FF0, %sp

    /* 1. Text ueber einen Anschluss, den es nicht gibt. */
    movw $(g_hello_txt - g_hello_start), %si
    movw $0x03F8, %dx
1:  movb (%si), %al
    testb %al, %al
    jz 2f
    outb %al, %dx
    incw %si
    jmp 1b
2:
    /* 2. Wer bin ich? Der Wirt entscheidet, was der Gast erfaehrt. */
    xorl %eax, %eax
    cpuid                           /* ebx = die ersten vier Zeichen */
    movl $1, %ecx
    movl $1, %eax
    vmmcall

    movl $1, %eax
    cpuid
    movl %ecx, %ebx                 /* ecx Bit 31 = "du bist ein Gast" */
    movl $2, %ecx
    movl $1, %eax
    vmmcall

    /* 3. Das Muster des Wirts, gastphysisch 0x0800. */
    movw $0x0800, %si
    movw %es:(%si), %bx
    movzwl %bx, %ebx
    movl $3, %ecx
    movl $1, %eax
    vmmcall

    /* 4. Einen Behandler in die Vektortabelle haengen -- Vektor 0x20
     *    liegt bei 4 * 0x20 = 0x80. Offset, dann Segment. */
    movw $0x0080, %si
    movw $(g_hello_isr - g_hello_start), %ax
    movw %ax, %es:(%si)
    movw $0x0100, %ax               /* Segment 0x0100 -> linear 0x1000 */
    movw %ax, %es:2(%si)
    xorl %ebp, %ebp
    movl $1, %ecx
    movl $3, %eax                   /* Befehl 3: wirf mir 0x20 ein */
    vmmcall
    /* Hier hat der Wirt die Unterbrechung eingeworfen. Sie wurde
     * zugestellt, BEVOR der naechste Befehl lief -- also steht in bp,
     * was der Behandler hineingeschrieben hat. */
    movl %ebp, %ebx
    movl $4, %ecx
    movl $1, %eax
    vmmcall

    movl $0x1234, %ebx
    movl $2, %eax
    vmmcall
    hlt
3:  jmp 3b

g_hello_isr:
    movw $0xABCD, %bp
    iret

g_hello_txt:
    .asciz "hallo vom gast\n"
    .align 4
g_hello_end:

/* ------------------------------------------------- 2. geschuetzter Modus
 *
 * DER EIGENTLICHE BEWEIS DIESER RUNDE. Der Gast
 *
 *   1. geht selbst in den geschuetzten Modus -- eigene Deskriptortabelle,
 *      eigenes `mov cr0`, eigener weiter Sprung,
 *   2. baut sich eine EIGENE ZWEISTUFIGE SEITENTABELLE in seinem eigenen
 *      physischen Speicher,
 *   3. schaltet sein eigenes Paging ein (cr3, cr0.pg),
 *   4. schreibt durch eine VIRTUELLE Adresse, die es selbst abgebildet
 *      hat, und liest denselben Wert ueber die identische Abbildung
 *      wieder zurueck.
 *
 * Damit haengen ZWEI Uebersetzungen hintereinander: gastvirtuell ->
 * gastphysisch macht der GAST mit seinen Tabellen, gastphysisch ->
 * wirtsphysisch macht die NPT des WIRTS. Schritt 4 kann nur ankommen,
 * wenn beide stimmen -- und der Gast weiss von der zweiten nichts.
 */
    .code16
    .globl g_pm_start, g_pm_end
g_pm_start:
    cli
    movw $0x0100, %ax
    movw %ax, %ds                   /* DS.base = 0x1000 fuer die eigene GDT */
    xorw %ax, %ax
    movw %ax, %ss
    movw $0x0FF0, %sp

    movw $(g_pm_gdtr - g_pm_start), %si
    lgdtl (%si)

    movl %cr0, %eax
    orl  $1, %eax
    movl %eax, %cr0                 /* geschuetzter Modus an */

    ljmpl $0x08, $(g_pm_32 - g_pm_start + 0x1000)

    .code32
g_pm_32:
    movw $0x10, %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %fs
    movw %ax, %gs
    movw %ax, %ss
    movl $0x6FF0, %esp              /* Seite 6, weit weg vom Abbild */

    /* Verzeichnis und die beiden Tabellen nullen: 0x2000..0x5000 */
    cld
    movl $0x2000, %edi
    xorl %eax, %eax
    movl $3072, %ecx                /* 0x3000 Oktette / 4 */
    rep stosl

    /* Verzeichnis[0] -> 0x3000, Verzeichnis[1] -> 0x4000 */
    movl $0x00003003, 0x2000
    movl $0x00004003, 0x2004

    /* Tabelle 0x3000: die ersten 4 MiB identisch abgebildet. */
    movl $0x3000, %edi
    movl $0x00000003, %eax
    movl $1024, %ecx
1:  movl %eax, (%edi)
    addl $0x1000, %eax
    addl $4, %edi
    loop 1b

    /* Tabelle 0x4000, Eintrag 0: virtuell 0x00400000 -> physisch 0x5000 */
    movl $0x00005003, 0x4000

    movl $0x2000, %eax
    movl %eax, %cr3
    movl %cr0, %eax
    orl  $0x80000000, %eax
    movl %eax, %cr0                 /* das eigene Paging an */

    /* Durch die selbstgebaute virtuelle Adresse schreiben ... */
    movl $0x5A5AC0DE, %eax
    movl %eax, 0x00400000

    /* ... und ueber die identische Abbildung zurueckholen. Steht hier
     * derselbe Wert, dann haben BEIDE Uebersetzungen gestimmt. */
    movl 0x5000, %ebx
    movl $5, %ecx
    movl $1, %eax
    vmmcall

    movl %cr0, %ebx                 /* was der Gast wirklich eingeschaltet hat */
    movl $6, %ecx
    movl $1, %eax
    vmmcall
    movl %cr3, %ebx
    movl $7, %ecx
    movl $1, %eax
    vmmcall

    /* Ein Anschlusszugriff aus dem geschuetzten Modus heraus. */
    movw $0x0510, %dx
    movb $0x37, %al
    outb %al, %dx

    movl $0x2222, %ebx
    movl $2, %eax
    vmmcall
    hlt
2:  jmp 2b

    .align 8
g_pm_gdt:
    .quad 0x0000000000000000
    .quad 0x00CF9A000000FFFF        /* 0x08  Code  32 Bit, Basis 0 */
    .quad 0x00CF92000000FFFF        /* 0x10  Daten 32 Bit, Basis 0 */
g_pm_gdtr:
    .word 3 * 8 - 1
    .long g_pm_gdt - g_pm_start + 0x1000
    .align 4
g_pm_end:

/* ------------------------------------------------------- 3. der Laeufer
 *
 * Er gibt den Prozessor NIE freiwillig her: kein Systemaufruf, kein
 * Anschluss, kein `hlt`. Ohne einen Wirt, der die physische Unterbrechung
 * abfaengt, steht die Maschine hier fuer immer. Genau das ist die
 * Gegenprobe -- mit `INTR`-Abfangen muss der Wirt ZAEHLBAR
 * zurueckkommen, und der Gast darf trotzdem weiterlaufen.
 */
    .code16
    .globl g_loop_start, g_loop_end
g_loop_start:
    cli
    xorw %ax, %ax
    movw %ax, %ds
    movw %ax, %ss
    movw $0x0FF0, %sp
    xorl %ebx, %ebx
1:  incl %ebx
    jmp 1b
    .align 4
g_loop_end:

/* --------------------------------------------------- 4. der Seitenfehler
 *
 * Er greift auf eine gastphysische Seite zu, die der Wirt NICHT
 * abgebildet hat. Das gibt einen NPF-Austritt, und in EXITINFO2 steht
 * die gastphysische Adresse. Der Wirt legt einen Rahmen unter und laesst
 * ihn weiterlaufen: Seiten auf Zuruf, fuer eine ganze Maschine.
 */
    .code16
    .globl g_fault_start, g_fault_end
g_fault_start:
    cli
    movw $0x0100, %ax
    movw %ax, %ds
    xorw %ax, %ax
    movw %ax, %es
    movw %ax, %ss
    movw $0x0FF0, %sp

    /* 0x7000 ist absichtlich nicht abgebildet. */
    movw $0x7000, %si
    movw $0xC0DE, %ax
    movw %ax, %es:(%si)             /* -> NPF, der Wirt legt nach */
    movw %es:(%si), %bx             /* danach muss dasselbe dastehen */
    movzwl %bx, %ebx
    movl $8, %ecx
    movl $1, %eax
    vmmcall

    movl $0x3333, %ebx
    movl $2, %eax
    vmmcall
    hlt
1:  jmp 1b
    .align 4
g_fault_end:

/* ------------------------------------------------------- 5. der Absturz
 *
 * DIE ANDERE GEGENPROBE, und die wichtigere. Er tut etwas, das nicht
 * geht, und der Wirt darf davon nichts abbekommen. Der Wirt setzt fuer
 * diesen Gast IDTR.limit auf 0: aus dem ungueltigen Befehl wird ein #UD,
 * daraus ein #DF, daraus ein Dreifachfehler -- Austrittsgrund SHUTDOWN.
 * Der Wirt raeumt die Gastmaschine ab und laeuft weiter.
 */
    .code16
    .globl g_crash_start, g_crash_end
g_crash_start:
    cli
    xorw %ax, %ax
    movw %ax, %ds
    movw %ax, %ss
    movw $0x0FF0, %sp
    movl $0x4444, %ebx
    movl $9, %ecx
    movl $1, %eax
    vmmcall                         /* noch lebt er */
    ud2                             /* und jetzt nicht mehr */
1:  jmp 1b
    .align 4
g_crash_end:

/* -------------------------------------------------------- 6. der Messgast
 *
 * Er tut NICHTS ausser austreten. Damit ist messbar, was ein Austritt
 * kostet: eine Runde ist genau ein `vmmcall` und die Behandlung dazu.
 * Alles andere -- Anschluesse, CPUID, Seitenfehler -- kostet mehr, und
 * dieser Wert ist die untere Schranke.
 */
    .code16
    .globl g_bench_start, g_bench_end
g_bench_start:
    cli
    xorw %ax, %ax
    movw %ax, %ds
    movw %ax, %ss
    movw $0x0FF0, %sp
    xorl %ebx, %ebx
1:  movl $31, %ecx
    movl $1, %eax
    vmmcall
    jmp 1b
    .align 4
g_bench_end:

    .code64

/* --------------------------------------------------------- die Tabelle
 *
 * Wie `smp_vectors` in `smp.s`: EIN Eintrag in `vectors` von `isr.s`
 * zeigt hierher, und alles Weitere steht in dieser Datei. Runden, die
 * gleichzeitig laufen, fassen `isr.s` damit nur an EINER Zeile an.
 */
    .align 8
    .globl hv_vectors
hv_vectors:
    .quad hv_vmrun                  /*  0 */
    .quad g_hello_start             /*  1 */
    .quad g_hello_end               /*  2 */
    .quad g_pm_start                /*  3 */
    .quad g_pm_end                  /*  4 */
    .quad g_loop_start              /*  5 */
    .quad g_loop_end                /*  6 */
    .quad g_fault_start             /*  7 */
    .quad g_fault_end               /*  8 */
    .quad g_crash_start             /*  9 */
    .quad g_crash_end               /* 10 */
    .quad g_bench_start             /* 11 */
    .quad g_bench_end               /* 12 */
    .quad hv_guest_save             /* 13 */
    .quad hv_stgi                   /* 14 */
    .quad hv_clgi                   /* 15 */
