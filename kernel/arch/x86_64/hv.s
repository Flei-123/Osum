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

/* ------------------------------------------------ 7. der lange Modus
 *
 * RUNDE HV2, STUFE 1. Die Gaeste der Runde K12 laufen im Real- und im
 * geschuetzten Modus. `EFER.LME`/`LMA` wurden durchgereicht, aber nie
 * gemessen -- und ein Gast, der keine 64 Bit kann, ist fuer ein echtes
 * Gastsystem nutzlos. Dieser Gast geht den ganzen Weg SELBST:
 *
 *   Realmodus -> geschuetzter Modus -> vierstufige Seitentabelle ->
 *   PAE an -> EFER.LME an -> Paging an -> langer Sprung -> 64 Bit.
 *
 * Das ist genau der Weg, den jeder x86-Kern beim Start geht, und er
 * haengt an vier Dingen, die alle stimmen muessen:
 *
 *   1. CR4.PAE MUSS vor CR0.PG gesetzt sein. Ohne PAE gibt es keinen
 *      langen Modus, und der Prozessor nimmt EFER.LME schweigend nicht an.
 *   2. Die Seitentabelle MUSS vierstufig sein (PML4 -> PDP -> PD -> Seite).
 *      Dieser Gast benutzt 2-MiB-Seiten, spart also die letzte Stufe:
 *      im PD steht das Bit PS, und der Eintrag zeigt unmittelbar auf
 *      zwei Mebioctets.
 *   3. EFER.LME wird ueber ein MSR-Schreiben gesetzt -- und dieser Wirt
 *      faengt ALLE MSR-Zugriffe ab. Der Wirt muss das Schreiben also
 *      wirklich ins Gast-EFER uebernehmen, sonst bleibt der Gast 32 Bit.
 *      GENAU DAS misst diese Stufe: `EFER.LMA` wird vom PROZESSOR
 *      gesetzt, nicht vom Gast -- der Gast kann es nur lesen.
 *   4. Das Codesegment braucht das L-Bit. Mit L=1 und D=1 zugleich
 *      wiese der Prozessor den Eintritt zurueck.
 *
 * SEIN SPEICHER (gastphysisch):
 *   0x8000  PML4     ->  0x9000
 *   0x9000  PDP      ->  0xA000
 *   0xA000  PD       ->  zwei 2-MiB-Seiten, PS-Bit, identisch
 *   0xB000  Stapel im langen Modus
 *
 * Er meldet ueber `vmmcall`: seine EFER (mit LMA), seine CR0, seine CR4,
 * dass er wirklich 64-Bit-Register hat (ein Wert oberhalb von 32 Bit,
 * den ein 32-Bit-Gast gar nicht bilden koennte), und einen Wert, den er
 * durch eine 2-MiB-Seite geschrieben und zurueckgelesen hat.
 */
    .code16
    .globl g_lm_start, g_lm_end
g_lm_start:
    cli
    movw $0x0100, %ax
    movw %ax, %ds                   /* DS.base = 0x1000: die eigene GDT */
    xorw %ax, %ax
    movw %ax, %ss
    movw $0x0FF0, %sp

    movw $(g_lm_gdtr - g_lm_start), %si
    lgdtl (%si)

    movl %cr0, %eax
    orl  $1, %eax
    movl %eax, %cr0                 /* geschuetzter Modus */
    ljmpl $0x08, $(g_lm_32 - g_lm_start + 0x1000)

    .code32
g_lm_32:
    movw $0x10, %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %ss
    movl $0xBFF0, %esp


    /* Die drei Tabellenseiten 0x8000..0xB000 nullen. */
    cld
    movl $0x8000, %edi
    xorl %eax, %eax
    movl $3072, %ecx                /* 0x3000 Oktette / 4 */
    rep stosl

    /* PML4[0] -> PDP, PDP[0] -> PD. Vorhanden, schreibbar. */
    movl $0x00009003, 0x8000
    movl $0x0000A003, 0x9000

    /* PD[0] und PD[1]: zwei 2-MiB-Seiten, identisch abgebildet.
     * 0x83 = vorhanden | schreibbar | GROSSE SEITE. Damit deckt das
     * Verzeichnis allein schon vier Mebioctets -- ohne letzte Stufe. */
    movl $0x00000083, 0xA000
    movl $0x00200083, 0xA008

    /* CR4.PAE. OHNE DAS KEIN LANGER MODUS -- und der Prozessor sagt es
     * nicht, er bleibt einfach 32 Bit. */
    movl %cr4, %eax
    orl  $0x20, %eax
    movl %eax, %cr4

    movl $0x8000, %eax
    movl %eax, %cr3


    /* EFER.LME. Das ist ein MSR-SCHREIBEN, und der Wirt faengt es ab --
     * er muss es wirklich uebernehmen, sonst bleibt der Gast 32 Bit. */
    movl $0xC0000080, %ecx
    rdmsr
    orl  $0x100, %eax               /* LME, Bit 8 */
    wrmsr


    /* Und jetzt Paging. In diesem Augenblick setzt DER PROZESSOR
     * EFER.LMA -- der Gast hat darauf keinen Zugriff. */
    movl %cr0, %eax
    orl  $0x80000000, %eax
    movl %eax, %cr0


    /* Der lange Sprung in ein Segment mit L=1. Erst hier ist er
     * wirklich 64 Bit. */
    ljmpl $0x18, $(g_lm_64 - g_lm_start + 0x1000)

    .code64
g_lm_64:
    movq $0x20, %rax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %ss
    movq $0xBFF0, %rsp

    /* 1. EFER zurueckmelden -- mit LMA, das der Prozessor gesetzt hat. */
    movl $0xC0000080, %ecx
    rdmsr                           /* eax = die unteren 32 Bit */
    movl %eax, %ebx
    movl $10, %ecx
    movl $1, %eax
    vmmcall

    /* 2. CR0 und CR4, damit nachlesbar ist, was wirklich an ist. */
    movq %cr0, %rbx
    movl $11, %ecx
    movl $1, %eax
    vmmcall
    movq %cr4, %rbx
    movl $12, %ecx
    movl $1, %eax
    vmmcall

    /* 3. DER BEWEIS, DASS ES WIRKLICH 64 BIT SIND. Dieser Wert passt in
     *    kein 32-Bit-Register; ein Gast im geschuetzten Modus koennte
     *    ihn gar nicht erst bilden. Der Wirt liest die oberen 32 Bit. */
    movabsq $0x1234567800000000, %rbx
    shrq $32, %rbx
    movl $13, %ecx
    movl $1, %eax
    vmmcall

    /* 4. Durch eine 2-MiB-Seite schreiben und zurueckholen. Die Adresse
     *    liegt jenseits der ersten zwei Mebioctets, also im ZWEITEN
     *    Verzeichniseintrag -- sie kann nur ankommen, wenn die grosse
     *    Seite wirklich uebersetzt. Der Wirt hat dort nichts abgebildet,
     *    also legt er sie auf Zuruf unter (NPF). */
    movq $0x00200000, %rdi
    movl $0xC0FFEE64, %eax
    movl %eax, (%rdi)
    movl (%rdi), %ebx
    movl $14, %ecx
    movl $1, %eax
    vmmcall

    /* 5. Und ein Anschlusszugriff aus dem langen Modus. */
    movw $0x03F8, %dx
    movb $0x4C, %al                 /* 'L' */
    outb %al, %dx

    movl $0x6464, %ebx              /* "64" */
    movl $2, %eax
    vmmcall
    hlt
1:  jmp 1b

    .align 8
g_lm_gdt:
    .quad 0x0000000000000000
    .quad 0x00CF9A000000FFFF        /* 0x08  Code  32 Bit */
    .quad 0x00CF92000000FFFF        /* 0x10  Daten 32 Bit */
    .quad 0x00AF9A000000FFFF        /* 0x18  Code  64 Bit: L=1, D=0 */
    .quad 0x00CF92000000FFFF        /* 0x20  Daten */
g_lm_gdtr:
    .word 5 * 8 - 1
    .long g_lm_gdt - g_lm_start + 0x1000
    .align 4
g_lm_end:

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

/* --------------------------------------------------- 8. der Geraetegast
 *
 * RUNDE HV2, STUFE 3. Die Gaeste bis hierher haben Geraete BENUTZT --
 * dieser hier PRUEFT sie, und zwar so, wie ein Betriebssystem es tut:
 * hineinschreiben, zurueklesen, und nur glauben, was zurueckkommt.
 *
 * Das ist der Unterschied, um den es in dieser Stufe geht. Ein Gast,
 * der blind in 0x3F8 schreibt, merkt nicht, ob dort ein Geraet ist.
 * Ein Betriebssystem schreibt erst ein Muster in ein Register, liest
 * es zurueck, und haelt den Anschluss fuer leer, wenn es nicht
 * wiederkommt. Genau diese Proben macht dieser Gast:
 *
 *   1. DAS KRATZREGISTER der seriellen Schnittstelle (0x3FF). Es hat
 *      keine Wirkung -- es ist reiner Speicher, und genau deshalb
 *      benutzt Linux es, um zu pruefen, ob ueberhaupt ein Baustein da
 *      ist. Der Gast schreibt 0x5A und liest zurueck.
 *   2. DAS ZEILENZUSTANDSREGISTER (0x3FD). Dort muessen die Bits
 *      THRE und TEMT stehen (0x60), sonst waere der Anschluss nie
 *      sendebereit. Und es darf NICHT 0xFF sein -- dann hielte Linux
 *      ihn fuer defekt.
 *   3. DAS TEILERLATCH hinter dem DLAB-Bit. Der Gast schaltet DLAB an,
 *      schreibt einen Teiler, schaltet DLAB aus und prueft, dass das
 *      Datenregister wieder Daten ist und nicht der Teiler.
 *   4. DER UNTERBRECHUNGSVERTEILER. Der Gast faehrt die vollstaendige
 *      vierteilige Anfangsfolge (ICW1..ICW4) mit der Vektorbasis 0x30
 *      -- der, die ein heutiger Linux nimmt -- und liest danach die
 *      Maske zurueck, die er geschrieben hat.
 *   5. DER ZEITGEBER. Der Gast setzt den Kanal 0 mit einem
 *      zweiteiligen Schreiben und liest den Zaehler zurueck.
 *
 * Jede dieser Zahlen geht per `vmmcall` an den Wirt, und jede einzelne
 * wird in `tools/hv/run.sh` nachgelesen.
 */
    .code16
    .globl g_dev_start, g_dev_end
g_dev_start:
    cli
    xorw %ax, %ax
    movw %ax, %ds
    movw %ax, %es
    movw %ax, %ss
    movw $0x0FF0, %sp

    /* --- 1. Das Kratzregister: schreiben und zurueklesen. --- */
    movw $0x03FF, %dx
    movb $0x5A, %al
    outb %al, %dx
    xorl %ebx, %ebx
    inb %dx, %al
    movb %al, %bl
    movl $40, %ecx
    movl $1, %eax
    vmmcall

    /* --- 2. Das Zeilenzustandsregister. --- */
    movw $0x03FD, %dx
    inb %dx, %al
    movzbl %al, %ebx
    movl $41, %ecx
    movl $1, %eax
    vmmcall

    /* --- 3. DLAB: Teiler schreiben, zurueklesen, wieder ausschalten. */
    movw $0x03FB, %dx
    movb $0x83, %al                 /* DLAB an, 8N1 */
    outb %al, %dx
    movw $0x03F8, %dx
    movb $0x0C, %al                 /* Teiler unten = 12 (9600 Baud) */
    outb %al, %dx
    inb %dx, %al                    /* muss 12 zurueckgeben */
    movzbl %al, %ebx
    movl $42, %ecx
    movl $1, %eax
    vmmcall

    movw $0x03FB, %dx
    movb $0x03, %al                 /* DLAB aus */
    outb %al, %dx
    inb %dx, %al                    /* das LCR selbst zurueklesen */
    movzbl %al, %ebx
    movl $43, %ecx
    movl $1, %eax
    vmmcall

    /* --- 4. Der Unterbrechungsverteiler, vollstaendige Anfangsfolge. */
    movw $0x0021, %dx
    movb $0xFF, %al                 /* erst alles maskieren */
    outb %al, %dx
    movw $0x0020, %dx
    movb $0x11, %al                 /* ICW1: Kaskade, ICW4 folgt */
    outb %al, %dx
    movw $0x0021, %dx
    movb $0x30, %al                 /* ICW2: Vektorbasis 0x30 */
    outb %al, %dx
    movb $0x04, %al                 /* ICW3: Zweiter haengt an IR2 */
    outb %al, %dx
    movb $0x01, %al                 /* ICW4: 8086-Modus */
    outb %al, %dx
    movb $0xFD, %al                 /* Maske: nur IRQ 1 offen */
    outb %al, %dx
    inb %dx, %al                    /* und zurueklesen */
    movzbl %al, %ebx
    movl $44, %ecx
    movl $1, %eax
    vmmcall

    /* --- 5. Der Zeitgeber: Kanal 0, zweiteiliges Schreiben. --- */
    movw $0x0043, %dx
    movb $0x36, %al                 /* Kanal 0, beide Oktette, Modus 3 */
    outb %al, %dx
    movw $0x0040, %dx
    movb $0x9C, %al                 /* unteres Oktett */
    outb %al, %dx
    movb $0x2E, %al                 /* oberes Oktett -> 0x2E9C = 11932 */
    outb %al, %dx
    movl $45, %ecx
    movl $1, %eax
    vmmcall

    /* --- 6. Und ein Wort ueber die Konsole, damit man es sieht. --- */
    movw $(g_dev_txt - g_dev_start), %si
    movw $0x0100, %ax
    movw %ax, %ds                   /* DS.base = 0x1000 fuer den Text */
    movw $0x03F8, %dx
1:  movb (%si), %al
    testb %al, %al
    jz 2f
    outb %al, %dx
    incw %si
    jmp 1b
2:
    movl $0x7777, %ebx
    movl $2, %eax
    vmmcall
    hlt
3:  jmp 3b

g_dev_txt:
    .asciz "geraete geprueft\n"  # // DRAHT: Mitschnitt, tools/hv/run.sh
    .align 4
g_dev_end:

    .code64

/* --------------------------------------------------------- die Tabelle
 *
 * Wie `smp_vectors` in `smp.s`: EIN Eintrag in `vectors` von `isr.s`
 * zeigt hierher, und alles Weitere steht in dieser Datei. Runden, die
 * gleichzeitig laufen, fassen `isr.s` damit nur an EINER Zeile an.
 */
/* Die Marke fuer den Gast ohne Abbild. Sie zeigt auf sich selbst;
 * Anfang und Ende sind dieselbe Adresse, also ist die Laenge 0. */
    .globl g_linux_none
g_linux_none:

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
    /* ---- Runde HV2 ----
     * DIE GAESTE MUESSEN LUECKENLOS STEHEN. `hv.fi` findet das Abbild
     * eines Gasts ueber HV_G_FIRST + Nummer * 2 -- ein neuer Gast
     * gehoert also HINTER den letzten Gast und NICHT hinter die
     * Hilfsfunktionen. Genau das hat diese Runde eine Stunde gekostet:
     * `g_lm` stand zuerst auf Platz 16, die Formel las Platz 13, fand
     * dort `hv_guest_save` -- und kopierte eine Funktion des WIRTS als
     * Gastabbild in den Gastspeicher. Der Gast lief dann durch eine
     * Seite aus Nullen bis ans Seitenende (RIP 0xFFF) und starb an
     * einem NPF, der wie ein Speicherfehler aussah und keiner war. */
    .quad g_lm_start                /* 13 */
    .quad g_lm_end                  /* 14 */
    .quad g_dev_start               /* 15 */
    .quad g_dev_end                 /* 16 */
    /* ---- Runde HV3 ----
     * DER LINUX-GAST HAT KEIN ABBILD IN DIESER DATEI, und trotzdem
     * steht hier ein Paar fuer ihn. Sein Abbild ist das Boot-Modul,
     * das der Lader hereingibt -- es ist zur Uebersetzungszeit nicht
     * da und kann hier nicht stehen. Was hier stehen MUSS, ist ein
     * Paar, denn `hv.fi` rechnet HV_G_FIRST + Nummer * 2 und wuerde
     * sonst die Hilfsfunktionen darunter als Gastabbild lesen -- genau
     * der Fehler (a) der Runde HV2. Zwei gleiche Adressen ergeben die
     * Laenge 0: `vm_create_big` kopiert dann nichts, und der Ladeweg
     * in `bzload.fi` legt das Abbild selbst hin. */
    .quad g_linux_none              /* 17 */
    .quad g_linux_none              /* 18 */
    .quad hv_guest_save             /* 19 */
    .quad hv_stgi                   /* 20 */
    .quad hv_clgi                   /* 21 */
