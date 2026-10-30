OUTPUT_FORMAT(binary)
ENTRY(stage2_start)
SECTIONS {
    . = 0x8000;
    .text : { *entry.o(.text) *(.text*) }
    .rodata : { *(.rodata*) }
    .data : { *(.data*) }
    . = ALIGN(16);
    bss_start = .;
    .bss : { *(.bss*) *(COMMON) }
    . = ALIGN(16);
    bss_end = .;
    /DISCARD/ : { *(.note*) *(.comment*) *(.eh_frame*) }
}
