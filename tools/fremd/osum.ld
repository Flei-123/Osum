ENTRY(_start)
PHDRS {
    text   PT_LOAD FILEHDR PHDRS FLAGS(5);
    rodata PT_LOAD FLAGS(4);
    data   PT_LOAD FLAGS(6);
}
SECTIONS {
    . = 0x40100000 + SIZEOF_HEADERS;
    .text : { *(.text.unlikely) *(.text) *(.text.*) *(.init) *(.fini) } :text
    . = ALIGN(4096);
    .rodata : { *(.rodata) *(.rodata.*) *(.eh_frame) *(.eh_frame_hdr) *(.gcc_except_table*) } :rodata
    . = ALIGN(4096);
    .data : {
        *(.init_array) *(.init_array.*) *(.fini_array) *(.fini_array.*)
        *(.got) *(.got.plt) *(.data) *(.data.*) *(.tdata) *(.tdata.*)
    } :data
    .bss : { *(.bss) *(.bss.*) *(.tbss) *(.tbss.*) *(COMMON) } :data
    /DISCARD/ : { *(.comment) *(.note.*) *(.debug*) }
}
