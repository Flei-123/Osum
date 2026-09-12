# Runde LAUFZEIT — fremder Quelltext läuft auf Osum

Zweig `laufzeit`, Grundlage `merge8` @ c0f7151. Schritt 2 der Liste in
`/root/osum-roadmap/FREMDSOFTWARE.md`, Abschnitt 7.

**Das Ergebnis in einem Satz:** ein statisch gegen musl gelinktes
Linux-Binary läuft auf Osum, und damit laufen **Lua, SQLite und
QuickJS** — 367 349 Zeilen fremdes C, keine Zeile davon geändert.

---

## 1. Die Frage, die alles entschied

Osum baut mit `firnc`. Lua, SQLite und QuickJS sind C. Die Roadmap nannte
zwei Wege: (a) ein C-Übersetzer für Osum, (b) nach Firn übersetzen — laut
Recherche eine Sackgasse (c2rust 22 % Erfolgsquote).

**Es war (a), und der Übersetzer musste nicht gebaut werden.** Er ist
schon da: `musl-gcc` auf dem Bauserver. Der Grund steht in Abschnitt 0
der Roadmap und ist diese Runde erstmals ausgenutzt worden:

> `kernel/sys.fi` benutzt **die Syscallnummern von Linux x86-64**.

musls `write()` legt die 1 in `rax`. Osums `SYS_WRITE` **ist** 1. Es gibt
keine Übersetzungsschicht, weil keine nötig ist.

---

## 2. Das Protokoll des musl-Experiments

Der wertvollste Teil dieser Runde, Schritt für Schritt, mit dem, was
jeweils wirklich gemessen wurde.

### Versuch 1 — Standard-`musl-gcc -static`, unverändert

```
$ musl-gcc -static -O2 -o hello hello.c
$ readelf -hl hello
Type: EXEC   Entry: 0x401051
LOAD 0x000000 0x0000000000400000  R    0x1000
LOAD 0x001000 0x0000000000401000  R E  0x1000
LOAD 0x002000 0x0000000000402000  R    0x1000
LOAD 0x002fd0 0x0000000000403fd0  RW   0x1000
```

**Drei Verstöße gegen `kernel/elf.fi` auf einmal**, alle drei im
LINKER begründet und keiner im Kernel:

| # | Befund | Grund in `elf.fi` |
|---|---|---|
| 1 | `vaddr = 0x400000` liegt unter `proc.IMAGE_BASE` (0x40100000) | 15 `R_RANGE` |
| 2 | RW-Segment beginnt auf `0x403fd0`, nicht seitenausgerichtet | 16 `R_ALIGN` |
| 3 | dieses Segment teilt Seite `0x403000` mit dem vorigen | 17 `R_OVERLAP` |

Regel 3 ist keine Schikane: eine Seitentabelle hat **einen** Satz Rechte
je Seite. Ein Lader, der die Vereinigung nähme, machte die Konstanten
schreibbar und die Daten ausführbar, ohne es zu sagen.

### Versuch 2 — eigenes Linkerskript (`tools/foreign/osum.ld`)

Ab `0x40100000`, `ALIGN(4096)` zwischen den Segmenten, drei `PT_LOAD` mit
`FILEHDR PHDRS` wie in `kernel/user/user.ld`. Ergebnis: der Lader nimmt
die Datei an.

```
elf: seg 5 v=0x40100000 filesz=590  memsz=590  w=0 x=1
elf: seg 4 v=0x40101000 filesz=144  memsz=144  w=0 x=0
elf: start 4 entry=0x401000f0 ustack=0x4007f000
start ok
hallo
osum$ hallo -> 0
```

**Ein echtes Linux-Binary mit musls eigenem `write()` lief auf Osum, beim
ersten Anlauf, ohne eine einzige Kernel-Änderung.** Das ist der Befund
dieser Runde.

Nötig war nur ein eigenes `_start` (`tools/foreign/start.s`): Osum übergibt
den Argumentblock **in RDI** (`elf.fi`), nicht als Linux-SysV-Stapel
(`[rsp]=argc`). Osums Block: `+0` argc, `+8` argv[], `+2048` envc,
`+2056` envp[].

### Versuch 3 — Lua, und der erste echte Absturz

```
user fault: pid=4 vector=14 err=0x5 cr2=0x28 rip=0x4012b918 -- process killed
```

`objdump` an genau dieser Stelle, in musls `__malloc_alloc_meta`:

```
4012b918:  64 48 8b 04 25 28 00 00 00   mov %fs:0x28,%rax
```

**Das ist der Stapelwächter über die FS-Basis.** Sie ist 0, also ist
`%fs:0x28` ein Zugriff auf die Adresse 0x28. Das ist der eine Grund, aus
dem fremde Programme hier bisher nicht laufen konnten — und er hat mit
den Syscallnummern nichts zu tun.

`-fno-stack-protector` half **nicht**: musls fertige `libc.a` bringt den
Wächter mit, und `%fs:0x0` (der Fadenzeiger selbst) ist für musl ohnehin
unverzichtbar. 130 `%fs:`-Zugriffe blieben stehen. TLS ist nicht
verhandelbar, also gehört es in den Kern.

### Versuch 4 — `arch_prctl` im Kernel, und der Fehler wanderte

`cr2` sprang von `0x28` auf `0x0`, der Absturz 0xDD Oktette weiter:

```
4012b9e3:  mov 0x25c1e(%rip),%rdx   # 40151608 <__libc+0x8>
4012b9f5:  mov (%rdx),%rax          <- hier, rdx = 0
```

`__libc+0x8` ist laut musl-Quelltext (`src/internal/libc.h`, v1.2.3)
`size_t *auxv`. musls malloc liest den **Hilfsvektor** und dereferenziert
ihn ohne Prüfung; `elf.fi` liefert keinen.

**Gelöst im Benutzerraum, nicht im Kern** (`tools/foreign/osum_main.c`):
argc/argv/envp/auxv werden aufgebaut (`AT_PAGESZ`, `AT_UID/GID`,
`AT_SECURE`, `AT_CLKTCK`, `AT_PHDR/PHENT/PHNUM`) und musls eigenes
`__init_libc()` gerufen — genau das, was ein Linux-Kern täte. Damit
richtet musl seinen Fadenzeiger selbst ein, korrekt und vollständig.

### Versuch 5 — `fremdtrace`, und die Lücken wurden sichtbar

Lua lief durch, gab Ende 0 zurück **und schwieg**. Damit man so etwas
nicht raten muss, gibt es jetzt den Schalter `fremdtrace`
(`kstate.M_FREMDTRACE`): er lässt `sys.entry` jede Antwort `-ENOSYS`
**mit ihrer Nummer** auf die serielle Leitung schreiben, ohne sonst
etwas am Verhalten zu ändern.

```
osum$ lua -e print(1+1)
sys: ENOSYS nr218      <- set_tid_address
sys: ENOSYS nr20       <- writev
```

Das war die Antwort: **musls stdio schreibt gepuffert, und gepuffert
heißt `writev`, nicht `write`.** Deshalb die Stille. Dasselbe Werkzeug
fand später bei SQLite `fcntl` (72) und `pread64` (17).

---

## 3. Was läuft — belegt

Jede Zeile ist echte serielle Ausgabe aus QEMU, kein Nacherzählen.

| Projekt | Umfang | Ausgabe auf Osum | Ende |
|---|---|---|---|
| musl-Hello | 6 Zeilen | `hallo` | 0 |
| **Lua 5.4.7** | **30 098 Zeilen C** | s. u. | 0 |
| **SQLite 3.46.0** | **257 673 Zeilen C** | s. u. | 0 |
| **QuickJS 2024-01-13** | **79 578 Zeilen C** | s. u. | 0 |

### Lua 5.4.7 — `lua /test.lua`

```
hallo von lua
Lua 5.4
1024.0	3	6
1,4,9,16,25
OSUM!
osum$ lua -> 0
```

Das ist `print`, `_VERSION`, `2^10`, `math.floor`, `#"abcdef"`, eine
`for`-Schleife mit Tabelle, `table.concat`, `string.upper` und
Konkatenation — die Datei kam von Osums eigener Platte.

### QuickJS — `qjs /test.js`

```
hallo von quickjs
2
1,4,9
{"os":"Osum","jahr":2026}
ABC!
osum$ qjs -> 0
```

Pfeilfunktionen, `Array.map`, `JSON.stringify`, `String.toUpperCase`.
**QuickJS brauchte keinen einzigen zusätzlichen Systemaufruf** — alles,
was es wollte, war nach Lua und SQLite schon da.

### SQLite — ein Osum-Programm ruft die Datenbank (`/bin/db`)

Das ist die Abnahme: nicht „SQLite übersetzt", sondern ein Programm
dieses Systems legt eine Datenbank an und liest sie wieder.

```
osum$ db
db: sqlite 3.46.0, datei /w/osum.db
db: tabelle steht
db: vier zeilen geschrieben
db: SELECT name, wert FROM messwerte ORDER BY wert:
  syscalls101
  lua     30098
  quickjs 79578
  sqlite  257673
db: 4 zeilen gelesen
db: SELECT SUM(wert) WHERE wert > 1000:
  367349
db: fertig, alles gut
osum$ db -> 0
```

Datei angelegt, Tabelle, vier `INSERT`, ein sortiertes `SELECT` und ein
`SUM`. Die Summe stimmt nachgerechnet: 30 098 + 79 578 + 257 673 =
**367 349**. Das normale Unix-VFS von SQLite, kein `SQLITE_OS_OTHER`,
kein eigenes VFS — die 20 Callbacks aus der Roadmap waren nicht nötig,
weil `pread`/`pwrite`/`fcntl` jetzt da sind.

---

## 4. Die ergänzten Systemaufrufe

Sieben Nummern, alle in `kernel/sys.fi`, alle mit den Nummern von Linux
x86-64, alle auch in `lib/libc/kcall.fi` (sonst schlägt `tools/posix`
zu Recht fehl).

| Nr | Name | Zweck | Wer ihn brauchte |
|---|---|---|---|
| 17 | `pread64` | Lesen mit Position, ohne die Schreibmarke zu bewegen | SQLite |
| 18 | `pwrite64` | dasselbe zum Schreiben | SQLite |
| 19 | `readv` | Vektor-Lesen | musl-stdio |
| 20 | `writev` | Vektor-Schreiben — **der Grund für Lues Stille** | musl-stdio |
| 72 | `fcntl` | `F_GETFL/SETFL/GETFD/SETFD/DUPFD`, Sperren | SQLite |
| 158 | `arch_prctl` | `ARCH_SET_FS`/`ARCH_GET_FS` — der Fadenzeiger | jedes musl-Programm |
| 218 | `set_tid_address` | gibt die eigene tid | musls Start |

Dazu ein neues Aufgabenfeld `sched.T_FSBASE` (648, `TASK_BYTES` ist
1024) und `sched.fsbase_apply()`, gerufen in `switch_to` direkt neben
`fpu.switch` — aus demselben Grund: die FS-Basis steht in einem
Modellregister des Prozessors und nicht im Aufgabensatz, also fände der
nächste Faden sonst den Fadenzeiger des vorigen vor. Geschrieben wird
über `msr.wr` (Fängerpfad aus `msr.fi`), nicht mit nacktem `wrmsr`.

### Drei Entscheidungen, die ausdrücklich benannt gehören

1. **`ARCH_SET_GS` gibt es nicht** (`-EINVAL`). `%gs` gehört in diesem
   Kern dem Prozessorblock (`cpu.fi`, `swapgs`); ein Programm, das es
   umbiegen dürfte, schickte den Kern beim nächsten Systemaufruf auf
   einen Zeiger seiner Wahl.
2. **Die FS-Basis wird geprüft**: kanonisch und untere Hälfte. Ein
   `wrmsr` mit nichtkanonischem Wert ist ein #GP — ohne die Prüfung wäre
   die Maschine tot statt des Prozesses.
3. **`fcntl` meldet Sperren als gewährt, ohne zu sperren.** Das ist eine
   bewusste Lüge und steht deshalb als Satz im Quelltext: SQLite fragt
   vor jedem Zugriff nach einer Sperre und gibt auf, wenn sie verweigert
   wird. Solange **ein** Prozess auf die Datenbank sieht, ist „gewährt"
   die richtige Antwort. Der Tag, an dem zwei Prozesse dieselbe Datenbank
   öffnen, ist der Tag, an dem hier echte Sperren stehen müssen.
   Ebenso merkt sich `set_tid_address` die Adresse **nicht** — dieser
   Kern räumt beim Fadenende keine Futex-Adresse auf, und ein
   Aufräumversprechen, das niemand einlöst, wäre schlimmer als keines.

---

## 5. Keine Regression

Alle vier Läufe, nach den Änderungen, auf demselben Baum:

| Lauf | vorher | nachher |
|---|---|---|
| `tools/posix/run.sh` | 134 / 0 | **134 / 0** |
| `tools/userland/run.sh` | 91 / 0 | **91 / 0** |
| `tools/osum/run.sh` | 130 / 0 | **130 / 0** |
| `tools/k16/run.sh` | 64 / 0 | **64 / 0** |

Ein Zwischenstand war ehrlich rot: nach den sieben neuen Nummern im
Kernel meldete `tools/posix` **133/1** —
„system call numbers on which kernel and libc disagree: 7". Der Lauf
hatte recht: die Nummern standen nur im Kern, nicht in
`lib/libc/kcall.fi`. Zwei Tabellen, die auseinanderlaufen, sind ein
Programm, das nach `writev` fragt und `readv` bekommt. Nach dem Nachtrag
wieder 134/0.

---

## 6. Was offen ist

* **Kein `fork` in einem musl-Programm.** `set_tid_address` merkt sich
  nichts, `futex` ist im Kern vorhanden, aber mit musls Fadenmodell nicht
  erprobt. Ein Programm mit Fäden ist die nächste Bewährungsprobe.
* **Echte Dateisperren** (s. o.), sobald zwei Prozesse eine Datenbank
  teilen sollen.
* **Die Größe.** Ein Programm liegt zwischen `IMAGE_BASE` (0x40100000)
  und `proc.IMAGE_END`; SQLite belegt schon 1,07 MB. Für größeres muss
  das Abbildfenster wachsen.
* **Osums Shell entfernt Anführungszeichen.** `lua -e print("A")` ergibt
  `nil` — das ist **kein** Lua-Fehler, mit einer Skriptdatei stimmt
  alles. Gehört in der Shell repariert, nicht hier.
* **Der Weg zu einem Ports-System** ist ab hier der von SerenityOS: jeder
  weitere Port ist ein Fehlerbericht gegen die eigene libc, und die
  ersten drei waren die teuren.

## 7. Wie man es nachbaut

```
musl-gcc -static -O2 -nostartfiles -T tools/foreign/osum.ld \
    -Wl,--build-id=none -o prog \
    tools/foreign/start.s tools/foreign/osum_main.c prog.c
```

Dann mit `tools/osum/mkfs.py` ins Abbild legen und starten. Bleibt ein
Programm stumm oder stirbt es, hilft `fremdtrace` auf der Befehlszeile:
es nennt die Nummer, die fehlt.
