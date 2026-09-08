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

## Was gemessen wurde (Runde LAUFZEIT)

| Programm | Umfang | Ergebnis auf Osum |
|---|---|---|
| musl-Hello | 6 Zeilen | `hallo`, Ende 0 |
| Lua 5.4.7 | 30 098 Zeilen C | Skript von der Platte, String-/Mathe-/Tabellenbibliothek |
| SQLite 3.46.0 | 257 673 Zeilen C | Datenbank angelegt, INSERT, SELECT, SUM |
| QuickJS 2024-01-13 | 79 578 Zeilen C | Pfeilfunktionen, `map`, `JSON.stringify` |

Ergaenzte Systemaufrufe: 17 `pread64`, 18 `pwrite64`, 19 `readv`,
20 `writev`, 72 `fcntl`, 158 `arch_prctl`, 218 `set_tid_address`.

`osum_main.c` baut den Hilfsvektor (`auxv`), den musl braucht und den
`elf.fi` nicht liefert, und ruft `__init_libc`. `start.s` macht aus
Osums Argumentblock in RDI die drei Zeiger von `main`.
