/* SPDX-License-Identifier: GPL-2.0-only */
/* kernel/kernel.ld -- round 59: the layout of the small kernel.
 *
 * Binds `boot.s` (multiboot header, long mode), `isr.s` (interrupt entry
 * points) and the freestanding object file out of `kmain.fi` into an image
 * that `qemu-system-x86_64 -kernel` loads. No libc, no start files
 * (crt*.o), no dynamic linker.
 *
 * Three things this script decides and the kernel relies on:
 *
 *   1. the multiboot header lies in the first 8 KiB -- therefore first,
 *      immediately followed by the 32-bit prologue,
 *   2. `.utext` gets a 4 KiB page OF ITS OWN. The kernel sets the
 *      user bit for exactly that page; without a page of its own, ring 3
 *      would be able to read kernel code,
 *   3. `kernel_end` marks the first byte behind the image. The frame
 *      allocator reads it and never hands out anything below it.
 *
 * `KERNEL_MAIN`, `KERNEL_TRAP`, `KERNEL_SYSCALL`, `KERNEL_TASK_MAIN`,
 * `KERNEL_USER_START` and `USER_MAIN` are set by `ld --defsym` when
 * linking: firnc0 puts `_F0.` in front of every symbol, firnc1 `_F1.`
 * (docs/SELF_HOSTING.md).
 */
ENTRY(_boot)

SECTIONS
{
    . = 1M;

    .text : ALIGN(4K)
    {
        *(.multiboot)
        *(.text.boot)
        *(EXCLUDE_FILE(*uprog*.o) .text)
        *(EXCLUDE_FILE(*uprog*.o) .text.*)
    }

    /* Round 62: everything between `__user_begin` and `__user_end` is
     * what ring 3 may see. That is the hand-written user program of round
     * 59 (`.utext` out of isr.s) AND the whole code of `uprog.fi`, which
     * is compiled into an object file of its own for exactly this reason.
     * The kernel sets the user bit for these pages and for no others
     * (`proc.map_programs`). */
    /* RUNDE K18: ALIGN(2M) UND NICHT MEHR ALIGN(4K).
     *
     * `proc.map_programs` macht diesen Abschnitt fuer Ring 3 sichtbar
     * und teilt dafuer jede 2-MiB-Kachel, die er beruehrt, in 512 Seiten
     * zu 4 KiB. Fuer die ERSTE Kachel nimmt es die feste Tabelle aus
     * `kdata` (PT_OFF); fuer jede WEITERE einen Rahmen aus dem
     * Rahmenverwalter -- und dieser Pfad ist kaputt. Gemessen, nicht
     * vermutet: mit einem `.utext`, das ueber die Grenze reicht, faellt
     * derselbe Kernel unter `osum gfx` mit einem #PF im Rahmenpuffer
     * (`fb.copy_words`, Lesen auf eine Adresse in der zweiten Kachel,
     * die nicht mehr abgebildet ist) und danach mit einem
     * DREIFACHFEHLER. Und zwar AUCH DER KERNEL OHNE RUNDE K18: es
     * genuegt, seinem `uprog.fi` genug Fuellcode zu geben, dass
     * `.utext` von 0x1f4000 bis 0x205000 reicht. Der Fehler ist also
     * aelter als diese Runde -- sie hat ihn nur als erste ausgeloest,
     * weil sie drei Programme in Ring 3 dazugelegt hat (12 Seiten -> 14).
     *
     * Diese Zeile nimmt dem Fehler den Anlass, statt ihn zu verstecken:
     * mit einer 2-MiB-Ausrichtung faengt `.utext` immer AM ANFANG einer
     * Kachel an und passt in EINE, solange es unter zwei Megabyte
     * bleibt -- das ist das Hundertfache dessen, was heute darin steht.
     * `map_programs` nimmt damit wieder nur die feste Tabelle und
     * keinen Rahmen aus dem Verwalter.
     *
     * Der Preis ist Fuellung im Abbild (bis zu 2 MiB Nullen). Das ist
     * ein Abbild auf einer Platte, kein Speicher zur Laufzeit; die
     * Alternative waere ein Kernel, der bei genuegend Ring-3-Code ohne
     * Vorwarnung dreifach faellt.
     *
     * WAS DAMIT NICHT BEHOBEN IST: der Pfad in `map_programs` fuer die
     * ZWEITE Kachel bleibt kaputt. Er wird jetzt nur nicht mehr
     * betreten. Wer `.utext` ueber zwei Megabyte wachsen laesst, faellt
     * wieder hinein -- das steht in docs/ROUNDK18.md als offene Kante. */
    .utext : ALIGN(2M)
    {
        __user_begin = .;
        *(.utext)
        *uprog*.o(.text .text.*)
        . = ALIGN(4K);
        __user_end = .;
    }

    .rodata : ALIGN(4K) { *(.rodata .rodata.*) }
    .data   : ALIGN(4K) { *(.data .data.*) }
    .bss    : ALIGN(4K) { *(COMMON) *(.bss .bss.*) }

    kernel_end = .;

    /DISCARD/ : { *(.note.GNU-stack) *(.comment) *(.eh_frame) }
}
