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

---

# RUNDE FREMDLAND

**busybox 1.36.1 laeuft auf Osum** -- ein Binary, 35 Applets, eigene
Shell mit Roehren. Dazu musl-Faeden und echte Dateisperren.
Vollstaendig in `STATUS-FREMDLAND.md`.

## Herkunft: fremd UND unveraendert

`herkunft.sh` fuehrt den Nachweis. Die Archive liegen unter
`/root/fremdquellen/`, ihre SHA-256 in `STATUS-FREMDLAND.md`
Abschnitt 0. Das Skript packt jedes Archiv ein ZWEITES Mal aus und
vergleicht mit dem Baubaum:

    lua-5.4.7                    diff LEER
    quickjs-2024-01-13           diff LEER (ausser Erzeugtem)
    sqlite-amalgamation-3460000  diff LEER
    busybox-1.36.1               0 Dateien differ

Kein `differ`, kein "Only in Original". Was zusaetzlich dasteht, ist
vom Bau erzeugt (`.o`, `.cmd`, `autoconf.h`, `applet_tables.h`, und bei
QuickJS `repl.c`/`qjscalc.c` aus seinem eigenen `qjsc`).

## Ergaenzte Systemaufrufe

| Nr | Name | Zweck |
|---|---|---|
| 10 | `mprotect` | antwortet 0, aendert nichts (s. STATUS, Mangel benannt) |
| 56 | `clone` | FADEN mit CLONE_VM, sonst `fork` |
| 63 | `uname` | sechs Felder zu 65 Oktetten, sysname "Linux" |
| 157 | `prctl` | PR_SET_NAME still, PR_GET_NAME scheitert |
| 202 | `futex` | Warten MIT NACHSEHEN, keine Warteschlange |

Und ECHT gemacht: `fcntl` 72 (Bereichssperren statt "gewaehrt ohne
Wirkung"), `set_tid_address` 218 (Adresse wird gemerkt und geloescht).

## Der Fund dieser Runde

`proc.map_page` gab frische Rahmen UNGENULLT an Ring 3 -- ein Leck
zwischen Prozessen, und der Grund, aus dem jede Roehre im zweiten Glied
starb (musls mallocng ruft `a_crash()`, ein `hlt`, wenn es Muell in
seiner Verwaltung findet). Gemessen: nach einem `execve` 8 von 8192
Oktetten ungleich null, danach 0. `proc.map_page_zero` an den fuenf
Stellen, die frischen Speicher ausgeben.

WARNUNG FUER DEN NAECHSTEN: zeigt eine Meldung `vector=13` und ein `rip`
mitten in musls Halde, ist es NICHT die Halde. Bei #GP ist `cr2` alt --
die Adresse dort ist eine Faehrte ins Leere.

## Die Programme dieser Runde

| Datei | misst |
|---|---|
| `argvdump.c` | was von `argv` wirklich ankommt (Shell-Anfuehrungszeichen) |
| `brkzero2.c` | ob frische `brk`-Seiten null sind -- ruft `brk` direkt |
| `forktest.c` | `fork`, Halde im Kind, Ende des Kindes beim Vater |
| `threads.c` | 4 Faeden a 25 000 Runden, Summe und Sperre |
| `locktest.c` | Sperren aus zwei Prozessen, sechs Faelle |
| `sqlock.c` | SQLite aus zwei Prozessen: SQLITE_BUSY statt Schaden |

Bauen wie in LAUFZEIT (`osum.ld`, `start.s`, `osum_main.c`);
`busybox-config.sh` erzeugt die Konfiguration, `busybox-applets.txt`
nennt die 35 Namen fuer die harten Verweise.
