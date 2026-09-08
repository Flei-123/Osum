# tools/fremd -- fremde C-Programme auf Osum

Runde LAUFZEIT. Der Befund: **ein statisch gegen musl gelinktes
Linux-Binary laeuft auf Osum unveraendert.** Kein Kernel-Patch, kein
neuer Syscall. Grund: `kernel/sys.fi` benutzt die Syscallnummern von
Linux x86-64, und musls `write()` legt die 1 in `rax` -- Osums
`SYS_WRITE = 1` versteht das direkt.

Drei Dinge muss der LINKER liefern, nicht der Kernel:

1. **Ab `0x40100000` linken.** `kernel/elf.fi` weist alles unter
   `proc.IMAGE_BASE` mit Grund 15 (`R_RANGE`) ab; Standard-musl linkt
   auf `0x400000`.
2. **Jedes PT_LOAD in eigenen Seiten** (`ALIGN(4096)`), sonst Grund 16
   (`R_ALIGN`) bzw. 17 (`R_OVERLAP`). Eine Seite hat einen Satz Rechte.
3. **Eigenes `_start`.** Osum uebergibt den Argumentblock in `RDI`, nicht
   als Linux-SysV-Stapel, und liefert kein `auxv`. `start.s` baut
   `argc/argv/envp` daraus und ruft `main`.

Bauen:

    musl-gcc -static -O2 -nostartfiles -T tools/fremd/osum.ld \
        -Wl,--build-id=none -o prog tools/fremd/start.s prog.c
