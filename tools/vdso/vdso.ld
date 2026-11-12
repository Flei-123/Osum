PHDRS {
    text PT_LOAD FILEHDR PHDRS FLAGS(5);
    dynamic PT_DYNAMIC;
}
SECTIONS {
    . = SIZEOF_HEADERS;
    .hash : { *(.hash) } :text
    .gnu.version : { *(.gnu.version) }
    .gnu.version_d : { *(.gnu.version_d) }
    .dynsym : { *(.dynsym) }
    .dynstr : { *(.dynstr) }
    .text : { *(.text) }
    .dynamic : { *(.dynamic) } :text :dynamic
    . = 0xF00;
    .vdsodata : { *(.vdsodata) } :text
    /DISCARD/ : { *(.note*) *(.eh_frame*) *(.comment) *(.gnu.hash) }
}
