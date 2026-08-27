/* kernel/arch/aarch64/virt.ld -- the counterpart to kernel/kernel.ld.
 *
 * `-M virt` puts its RAM at 0x40000000 and every AArch64 loader in the
 * world (QEMU's own `-kernel`, U-Boot, the Raspberry Pi firmware) expects
 * the image a little way into it. 0x40080000 is the address the Linux
 * arm64 boot protocol names as the usual one (TEXT_OFFSET 0x80000 above
 * the start of RAM), and QEMU's ELF loader simply honours the addresses in
 * the program headers -- so this is a choice, not a constraint, and it is
 * written down here rather than repeated in the runner.
 */

ENTRY(_start)

SECTIONS
{
    . = 0x40080000;

    __image_start = .;

    .text : ALIGN(4096) {
        KEEP(*(.text.boot))
        *(.text .text.*)
    }

    .rodata : ALIGN(4096) {
        *(.rodata .rodata.*)
    }

    .data : ALIGN(4096) {
        *(.data .data.*)
    }

    .bss : ALIGN(4096) {
        __bss_start = .;
        *(.bss .bss.*)
        *(COMMON)
        . = ALIGN(8);
        __bss_end = .;
    }

    /* The page tables are built at run time into this region. Putting them
     * in .bss would work too, but they need 4 KiB alignment each and a name
     * the runner can look up in the symbol table when it wants to read a
     * descriptor back out of a memory dump. */
    .pagetables (NOLOAD) : ALIGN(4096) {
        __pt_start = .;
        *(.pagetables)
        __pt_end = .;
    }

    __image_end = .;

    /DISCARD/ : { *(.comment) *(.note.*) *(.eh_frame) }
}
