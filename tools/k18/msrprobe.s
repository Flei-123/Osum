/* SPDX-License-Identifier: GPL-2.0-only */
/* tools/k18/msrprobe.s -- DIE VORABPRUEFUNG DER RUNDE K18.
 *
 * Bevor eine Zeile Kernelcode entsteht, muss die Frage beantwortet sein,
 * an der diese ganze Runde haengt: WAS TUT DIESER WIRT MIT DEN
 * ENERGIEREGISTERN? Die Messmaschine ist ein AMD EPYC unter QEMU/TCG,
 * ohne /dev/kvm. Ein MSR-Zugriff kann dort dreierlei tun:
 *
 *   1. eine allgemeine Schutzverletzung (#GP) ausloesen -- das Register
 *      gibt es fuer diesen Gast nicht,
 *   2. angenommen werden und beim Lesen den geschriebenen Wert
 *      zurueckgeben -- QEMU haelt den Wert,
 *   3. angenommen werden und beim Lesen etwas ANDERES zurueckgeben --
 *      QEMU hat eine eigene Meinung dazu.
 *
 * Welcher der drei Faelle eintritt, entscheidet, was Runde K18 ueberhaupt
 * messen kann. Raten waere hier das Schlimmste: ein Test, der einen
 * geschriebenen Wert zurueckliest, misst im Fall 2 die Attrappe von QEMU
 * und nicht den Kernel.
 *
 * Dieses Programm ist absichtlich KEIN Firn und benutzt nichts aus dem
 * Kernel: es ist ein Multiboot-Abbild aus einer einzigen Assemblerdatei
 * mit eigener IDT, damit ein #GP wirklich abgefangen und nicht zu einem
 * dreifachen Fehler wird. Es laeuft im 32-Bit-Schutzmodus -- rdmsr und
 * wrmsr gibt es dort genauso, und der lange Modus braeuchte
 * Seitentabellen, die zu dieser Frage nichts beitragen.
 *
 * Bauen und laufen lassen: bash tools/k18/probe.sh
 */
    .set MB_MAGIC, 0x1BADB002
    .set MB_FLAGS, 0x0
    .set COM1,     0x3F8

    .section .multiboot, "a"
    .align 4
    .long MB_MAGIC
    .long MB_FLAGS
    .long -(MB_MAGIC + MB_FLAGS)

    .section .text
    .code32
    .globl _start
_start:
    cli
    movl $stack_top, %esp

    /* Eine IDT, in der JEDER der 32 Ausnahmevektoren auf denselben
     * Einsprung zeigt. Der Einsprung setzt ein Merkzeichen und springt
     * hinter den Befehl, der gefehlt hat. */
    call    idt_setup
    lidt    idtr

    /* --- CPUID: was sagt dieser Prozessor ueber sich selbst? --- */
    movl    $0, %eax
    cpuid
    movl    $s_cpuid0, %esi
    call    puts
    movl    %eax, %ebx
    call    hex32
    call    nl

    movl    $1, %eax
    cpuid
    pushl   %edx
    movl    $s_cpuid1c, %esi
    call    puts
    movl    %ecx, %ebx
    call    hex32
    movl    $s_edx, %esi
    call    puts
    popl    %ebx
    call    hex32
    call    nl

    /* Blatt 5: MONITOR/MWAIT */
    movl    $5, %eax
    xorl    %ecx, %ecx
    cpuid
    pushl   %edx
    pushl   %ecx
    pushl   %ebx
    movl    $s_cpuid5a, %esi
    call    puts
    movl    %eax, %ebx
    call    hex32
    movl    $s_ebx, %esi
    call    puts
    popl    %ebx
    call    hex32
    movl    $s_ecx, %esi
    call    puts
    popl    %ebx
    call    hex32
    movl    $s_edx, %esi
    call    puts
    popl    %ebx
    call    hex32
    call    nl

    /* Blatt 6: Waerme und Energie */
    movl    $6, %eax
    xorl    %ecx, %ecx
    cpuid
    pushl   %ecx
    movl    $s_cpuid6a, %esi
    call    puts
    movl    %eax, %ebx
    call    hex32
    movl    $s_ecx, %esi
    call    puts
    popl    %ebx
    call    hex32
    call    nl

    /* Blatt 0x80000007: AMDs Energiezaehler */
    movl    $0x80000007, %eax
    cpuid
    movl    $s_cpuid87, %esi
    call    puts
    movl    %edx, %ebx
    call    hex32
    call    nl

    /* --- DIE REGISTER LESEN --- */
    movl    $0x199, %edi ; movl $n_perfctl, %esi ; call rd_show
    movl    $0x198, %edi ; movl $n_perfsts, %esi ; call rd_show
    movl    $0x1A0, %edi ; movl $n_misc,    %esi ; call rd_show
    movl    $0x19C, %edi ; movl $n_therm,   %esi ; call rd_show
    movl    $0x1A2, %edi ; movl $n_target,  %esi ; call rd_show
    movl    $0x770, %edi ; movl $n_pmen,    %esi ; call rd_show
    movl    $0x771, %edi ; movl $n_hwpcap,  %esi ; call rd_show
    movl    $0x774, %edi ; movl $n_hwpreq,  %esi ; call rd_show
    movl    $0xE7,  %edi ; movl $n_mperf,   %esi ; call rd_show
    movl    $0xE8,  %edi ; movl $n_aperf,   %esi ; call rd_show
    movl    $0x64F, %edi ; movl $n_perflim, %esi ; call rd_show
    movl    $0xC0010062, %edi ; movl $n_amdctl, %esi ; call rd_show
    movl    $0xC0010063, %edi ; movl $n_amdsts, %esi ; call rd_show
    movl    $0xC0010064, %edi ; movl $n_amdp0,  %esi ; call rd_show

    /* --- SCHREIBEN UND ZURUECKLESEN --- */
    movl    $0x199, %edi
    movl    $n_perfctl, %esi
    movl    $0x00000E00, %eax
    xorl    %edx, %edx
    call    wr_show

    movl    $0x774, %edi
    movl    $n_hwpreq, %esi
    movl    $0x80001004, %eax
    xorl    %edx, %edx
    call    wr_show

    movl    $0x1A0, %edi
    movl    $n_misc, %esi
    xorl    %eax, %eax
    movl    $0x40, %edx
    call    wr_show

    movl    $0x770, %edi
    movl    $n_pmen, %esi
    movl    $1, %eax
    xorl    %edx, %edx
    call    wr_show

    /* DIE ENTSCHEIDENDE FRAGE FUER DIE GEGENPROBE DER RUNDE:
     * behaelt IA32_MISC_ENABLE die DREI Muster, die die drei Profile
     * schreiben? Bit 16 = EIST an, Bit 38 = Turbo AUS. */
    movl    $0x1A0, %edi ; movl $n_misc, %esi
    movl    $0x00010000, %eax ; movl $0x40, %edx ; call wr_show   /* sparen  */
    movl    $0x1A0, %edi ; movl $n_misc, %esi
    movl    $0x00010000, %eax ; xorl %edx, %edx ; call wr_show    /* mitte   */
    movl    $0x1A0, %edi ; movl $n_misc, %esi
    xorl    %eax, %eax ; xorl %edx, %edx ; call wr_show           /* volle   */

    /* Weitere Register, die vielleicht doch etwas behalten. */
    movl    $0x1B0, %edi ; movl $n_epb, %esi
    movl    $15, %eax ; xorl %edx, %edx ; call wr_show
    movl    $0x19A, %edi ; movl $n_clkmod, %esi
    movl    $0x1E, %eax ; xorl %edx, %edx ; call wr_show
    movl    $0x19B, %edi ; movl $n_thrint, %esi
    movl    $0x1000015, %eax ; xorl %edx, %edx ; call wr_show
    movl    $0xCE, %edi ; movl $n_platinfo, %esi ; call rd_show
    movl    $0x1AD, %edi ; movl $n_turbolim, %esi ; call rd_show
    movl    $0x606, %edi ; movl $n_rapl, %esi ; call rd_show
    movl    $0x611, %edi ; movl $n_pkgeng, %esi ; call rd_show

    /* --- MONITOR/MWAIT: geht der Befehl ueberhaupt? --- */
    movl    $s_mwait, %esi
    call    puts
    movl    $0, gp_flag
    movl    $mwait_line, %eax
    xorl    %ecx, %ecx
    xorl    %edx, %edx
    monitor
    movl    $s_gpm, %esi
    call    puts
    movl    gp_flag, %ebx
    call    hex32
    movl    $s_vec, %esi
    call    puts
    movl    gp_vec, %ebx
    call    hex32
    movl    $0, gp_flag
    xorl    %eax, %eax
    xorl    %ecx, %ecx
    mwait
    movl    $s_gpw2, %esi
    call    puts
    movl    gp_flag, %ebx
    call    hex32
    movl    $s_vec, %esi
    call    puts
    movl    gp_vec, %ebx
    call    hex32
    call    nl

    movl    $s_done, %esi
    call    puts

    movw    $0xF4, %dx
    movb    $10, %al
    outb    %al, %dx
1:  hlt
    jmp     1b

/* ---------------------------------------------------------------- MSR */

rd_show:
    pushl   %esi
    call    puts
    movl    $s_r, %esi
    call    puts
    movl    $0, gp_flag
    movl    %edi, %ecx
    xorl    %eax, %eax
    xorl    %edx, %edx
    rdmsr
    pushl   %eax
    movl    %edx, %ebx
    call    hex32
    popl    %ebx
    call    hex32
    movl    $s_gp, %esi
    call    puts
    movl    gp_flag, %ebx
    call    hex32
    call    nl
    popl    %esi
    ret

wr_show:
    pushl   %esi
    call    puts
    movl    $s_w, %esi
    call    puts
    pushl   %eax
    pushl   %edx
    movl    %edx, %ebx
    call    hex32
    popl    %edx
    popl    %eax
    pushl   %eax
    pushl   %edx
    movl    %eax, %ebx
    call    hex32
    popl    %edx
    popl    %eax
    movl    $0, gp_flag
    movl    %edi, %ecx
    wrmsr
    movl    gp_flag, %ebx
    pushl   %ebx
    movl    $s_arrow, %esi
    call    puts
    movl    $0, gp_flag
    movl    %edi, %ecx
    rdmsr
    pushl   %eax
    movl    %edx, %ebx
    call    hex32
    popl    %ebx
    call    hex32
    movl    $s_gpw, %esi
    call    puts
    popl    %ebx
    call    hex32
    movl    $s_gpr, %esi
    call    puts
    movl    gp_flag, %ebx
    call    hex32
    call    nl
    popl    %esi
    ret

/* ---------------------------------------------------------------- IDT */

idt_setup:
    movl    $0, %ecx
1:  movl    isr_table(,%ecx,4), %eax
    movl    $idt, %edi
    leal    (%edi,%ecx,8), %edi
    movw    %ax, (%edi)
    movw    $0x08, 2(%edi)
    movb    $0, 4(%edi)
    movb    $0x8E, 5(%edi)
    shrl    $16, %eax
    movw    %ax, 6(%edi)
    incl    %ecx
    cmpl    $32, %ecx
    jb      1b
    ret

/* JEDER Vektor bekommt einen eigenen Einsprung, der seine Nummer legt --
 * und die Vektoren MIT Fehlercode (8, 10..14, 17, 21) legen einen
 * Fuellwert dazu, damit der Stapel in beiden Faellen gleich aussieht.
 * Die erste Fassung dieses Programms hatte das nicht: sie warf bei JEDEM
 * Vektor vier Oktette weg. Beim #UD von `monitor` -- der KEINEN
 * Fehlercode hat -- war das die Ruecksprungadresse, und der Lauf lief in
 * die Landschaft statt eine Antwort zu geben. Genau der Fehler, den
 * dieses Programm eigentlich finden soll. */
    .macro ISR_NOERR n
isr_\n:
    pushl   $0
    pushl   $\n
    jmp     isr_common
    .endm
    .macro ISR_ERR n
isr_\n:
    pushl   $\n
    jmp     isr_common
    .endm

    ISR_NOERR 0
    ISR_NOERR 1
    ISR_NOERR 2
    ISR_NOERR 3
    ISR_NOERR 4
    ISR_NOERR 5
    ISR_NOERR 6
    ISR_NOERR 7
    ISR_ERR   8
    ISR_NOERR 9
    ISR_ERR   10
    ISR_ERR   11
    ISR_ERR   12
    ISR_ERR   13
    ISR_ERR   14
    ISR_NOERR 15
    ISR_NOERR 16
    ISR_ERR   17
    ISR_NOERR 18
    ISR_NOERR 19
    ISR_NOERR 20
    ISR_ERR   21
    ISR_NOERR 22
    ISR_NOERR 23
    ISR_NOERR 24
    ISR_NOERR 25
    ISR_NOERR 26
    ISR_NOERR 27
    ISR_NOERR 28
    ISR_NOERR 29
    ISR_NOERR 30
    ISR_NOERR 31

isr_common:
    popl    %eax
    movl    %eax, gp_vec
    movl    $1, gp_flag
    addl    $4, %esp            /* Fehlercode bzw. Fuellwert weg */
    movl    $resume, %eax
    movl    %eax, (%esp)
    iret

    .align 4
isr_table:
    .long isr_0,  isr_1,  isr_2,  isr_3,  isr_4,  isr_5,  isr_6,  isr_7
    .long isr_8,  isr_9,  isr_10, isr_11, isr_12, isr_13, isr_14, isr_15
    .long isr_16, isr_17, isr_18, isr_19, isr_20, isr_21, isr_22, isr_23
    .long isr_24, isr_25, isr_26, isr_27, isr_28, isr_29, isr_30, isr_31

resume:
    xorl    %eax, %eax
    xorl    %edx, %edx
    ret

/* -------------------------------------------------------------- Ausgabe */

putc:
    pushl   %edx
    pushl   %eax
    movw    $COM1+5, %dx
1:  inb     %dx, %al
    testb   $0x20, %al
    jz      1b
    popl    %eax
    movw    $COM1, %dx
    outb    %al, %dx
    popl    %edx
    ret

puts:
    pushl   %eax
1:  movb    (%esi), %al
    testb   %al, %al
    jz      2f
    call    putc
    incl    %esi
    jmp     1b
2:  popl    %eax
    ret

nl:
    pushl   %eax
    movb    $10, %al
    call    putc
    popl    %eax
    ret

hex32:
    pushl   %ecx
    pushl   %eax
    pushl   %ebx
    movl    $8, %ecx
1:  roll    $4, %ebx
    movl    %ebx, %eax
    andl    $0xF, %eax
    cmpb    $10, %al
    jb      2f
    addb    $('a'-10), %al
    jmp     3f
2:  addb    $'0', %al
3:  call    putc
    loop    1b
    popl    %ebx
    popl    %eax
    popl    %ecx
    ret

    .section .data
s_cpuid0:  .asciz "cpuid0 eax="
s_cpuid1c: .asciz "cpuid1 ecx="
s_cpuid5a: .asciz "cpuid5 eax="
s_cpuid6a: .asciz "cpuid6 eax="
s_cpuid87: .asciz "cpuid80000007 edx="
s_ebx:     .asciz " ebx="
s_ecx:     .asciz " ecx="
s_edx:     .asciz " edx="
s_r:       .asciz " r="
s_w:       .asciz " w="
s_arrow:   .asciz " -> "
s_gp:      .asciz " gp="
s_gpw:     .asciz " gpw="
s_gpr:     .asciz " gpr="
s_vec:     .asciz " vec="
s_gpm:     .asciz " monitor_gp="
s_gpw2:    .asciz " mwait_gp="
s_mwait:   .asciz "monitor/mwait"
s_done:    .asciz "probe done\n"

n_perfctl: .asciz "IA32_PERF_CTL(0x199)"
n_perfsts: .asciz "IA32_PERF_STATUS(0x198)"
n_misc:    .asciz "IA32_MISC_ENABLE(0x1a0)"
n_therm:   .asciz "IA32_THERM_STATUS(0x19c)"
n_target:  .asciz "IA32_TEMPERATURE_TARGET(0x1a2)"
n_pmen:    .asciz "IA32_PM_ENABLE(0x770)"
n_hwpcap:  .asciz "IA32_HWP_CAPABILITIES(0x771)"
n_hwpreq:  .asciz "IA32_HWP_REQUEST(0x774)"
n_mperf:   .asciz "IA32_MPERF(0xe7)"
n_aperf:   .asciz "IA32_APERF(0xe8)"
n_perflim: .asciz "MSR_CORE_PERF_LIMIT(0x64f)"
n_epb:     .asciz "IA32_ENERGY_PERF_BIAS(0x1b0)"
n_clkmod:  .asciz "IA32_CLOCK_MODULATION(0x19a)"
n_thrint:  .asciz "IA32_THERM_INTERRUPT(0x19b)"
n_platinfo:.asciz "MSR_PLATFORM_INFO(0xce)"
n_turbolim:.asciz "MSR_TURBO_RATIO_LIMIT(0x1ad)"
n_rapl:    .asciz "MSR_RAPL_POWER_UNIT(0x606)"
n_pkgeng:  .asciz "MSR_PKG_ENERGY_STATUS(0x611)"
n_amdctl:  .asciz "AMD_PSTATE_CTL(0xc0010062)"
n_amdsts:  .asciz "AMD_PSTATE_STS(0xc0010063)"
n_amdp0:   .asciz "AMD_PSTATE_DEF0(0xc0010064)"

    .section .bss
    .align 16
gp_flag:    .skip 4
gp_vec:     .skip 4
mwait_line: .skip 128
idt:        .skip 32*8
    .align 16
stack:      .skip 8192
stack_top:

    .section .rodata
    .align 8
idtr:
    .word 32*8 - 1
    .long idt
