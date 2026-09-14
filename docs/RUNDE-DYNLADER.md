# Runde DYNLADER — der dynamische Lader

Zweig `dynlader`, Grundlage `main` = ce4a232.

**Ziel:** ein DYNAMISCH gelinktes Linux-Programm (mit `PT_INTERP`) laeuft auf
OrientOS. Bis zu dieser Runde lief nur, was STATISCH gelinkt war — der Befund
der Runden LAUFZEIT und FREMDLAND (`tools/foreign/README.md`).

---

## 0. Die Entscheidung, und warum sie so ausfaellt

Zwei Wege standen zur Wahl:

| Weg | was zu bauen waere |
|---|---|
| **A** eigener Lader in Firn (`kernel/user/ld.fi` oder im Kern) | ELF-Relokationen (`R_X86_64_RELATIVE`, `GLOB_DAT`, `JUMP_SLOT`, `TPOFF64`), Symbolsuche ueber `.hash`/`.gnu.hash`, `DT_NEEDED`-Kette, TLS-Aufbau, `dlopen`/`dlsym` — mehrere tausend Zeilen, und jede davon ein Nachbau von etwas, das es fertig gibt |
| **B** das ECHTE `ld-musl-x86_64.so.1` als Interpreter benutzen | die Schnittstelle bedienen, an der es schon andockt: ELF-Bild laden, Startstapel bauen, Syscalls liefern |

**Gewaehlt ist B**, und zwar nicht aus Bequemlichkeit, sondern nach der
Hausregel aus `/root/osum-roadmap/FREMDSOFTWARE.md` Abschnitt −1:
*„Schnittstelle vor Nachbau. Vor jedem grossen Vorhaben die Frage: gibt es
eine schmalere Stelle, an der dieselbe Software andockt?"*

Hier gibt es sie, und sie ist **sehr** schmal. Die Messung in Abschnitt 1
zeigt, warum: der Lader verlangt vom Kern fast nichts, was der Kern nicht
schon kann. Weg A wuerde Code schreiben, dessen einzige Aufgabe es waere,
sich genauso zu verhalten wie der Code, den Weg B einfach benutzt — mit dem
Unterschied, dass unser Nachbau die Fehler haette, die musl in 15 Jahren
schon gefunden hat.

Dazu kommt ein Argument, das erst beim Messen sichtbar wurde: derselbe
`ld-musl-x86_64.so.1` ist zugleich `libc.so`. Wer ihn als Interpreter
akzeptiert, bekommt `dlopen`/`dlsym` (Stufe 3 der Messlatte) geschenkt,
weil sie in derselben Datei stehen.

---

## 1. ZUERST GEMESSEN, NICHT GERATEN

Ein dynamisches `hello` gegen musl gebaut und auf dem Linux-Wirt unter
`strace` laufen lassen (`tools/dynlader/messung-wirt.sh`). Das ist die
vollstaendige Liste dessen, was zwischen `execve` und der Ausgabe passiert:

```
execve("./hello_dyn", ...)            = 0
arch_prctl(ARCH_SET_FS, 0x...)        = 0
set_tid_address(0x...)                = <pid>
brk(NULL)                             = 0x...
brk(0x...)                            = 0x...
mmap(0x..., 4096, PROT_NONE, MAP_PRIVATE|MAP_FIXED|MAP_ANONYMOUS, -1, 0)
mprotect(0x..., 4096, PROT_READ)      = 0
mprotect(0x..., 4096, PROT_READ)      = 0
ioctl(1, TIOCGWINSZ, ...)             = -1 ENOTTY
writev(1, [...], 2)                   = 16
exit_group(0)
```

**Elf Aufrufe. Acht verschiedene Nummern. Und der Kern kennt jede einzelne
davon schon** (`arch_prctl` 158, `set_tid_address` 218 aus LAUFZEIT;
`mprotect` 10 aus FREMDLAND; `brk` 12, `mmap` 9, `writev` 20, `ioctl` 16,
`exit_group` 231 laenger).

**Die Tabelle „fehlende Syscalls" dieser Runde ist damit LEER.** Das ist
das wichtigste Messergebnis der Runde, und es ist das Gegenteil dessen, was
der Auftrag erwartet hat (dort standen `readlink`, `getrandom`,
`set_robust_list`, `prlimit64`, `newfstatat` als Kandidaten). Der Grund,
aus dem sie nicht vorkommen: **musl fragt sie nicht**. Sie stehen in der
Erwartungsliste, weil glibc sie ruft — musls Lader ist erheblich sparsamer.
Hier zahlt sich die Wahl von musl ein zweites Mal aus.

Bemerkenswert ist auch, was NICHT in der Liste steht: der Lader oeffnet
`hello_dyn` **nicht** und `libc.so` **nicht**. Beide sind schon da, wenn er
anfaengt — der KERN hat sie geladen. Genau deshalb ist die Arbeit dieser
Runde im Kern und nicht in einer Bibliothek.

### Was der Lader stattdessen braucht — und was wirklich fehlt

| Nr | was | Stand vor der Runde |
|---|---|---|
| 1 | Bild vom Typ **`ET_DYN`** laden | **FEHLT**, `read_header` verlangt `ET_EXEC` (Grund 8, `R_TYPE`) |
| 2 | ZWEI Bilder in einem Adressraum (Programm + Interpreter) | **FEHLT**, `load` laedt genau eine Datei |
| 3 | `PT_INTERP` lesen und aufloesen | **FEHLT**, `elf.fi` kennt nur `PT_LOAD` |
| 4 | Einsprung des **Interpreters**, nicht des Programms | **FEHLT** |
| 5 | System-V-Startstapel mit **`auxv`** | **FEHLT**, der Block liegt in RDI |
| 6 | `%fs`-Basis fuer TLS | **da** (`arch_prctl`, LAUFZEIT) |
| 7 | genullte Seiten von `brk`/`mmap` | **da** (FREMDLAND) |

Fuenf Luecken, alle strukturell, keine davon ein Syscall.

---

## 2. Die fuenf Luecken im Einzelnen

### 2.1 `ET_DYN` statt `ET_EXEC`

`kernel/elf.fi` `read_header` weist alles ab, was nicht `ET_EXEC` ist.
Sowohl ein PIE-Programm als auch **jeder** Interpreter ist aber `ET_DYN`.
Gemessen am Wirt:

```
hello_dyn                : ELF 64-bit LSB pie executable, interpreter /lib/ld-musl-x86_64.so.1
ld-musl-x86_64.so.1      : Elf file type is DYN (Shared object file), Entry 0x777ee
```

Ein `ET_DYN`-Bild hat `p_vaddr` ab 0 — es wird auf eine frei gewaehlte
Basis GESCHOBEN. Die drei Regeln aus `tools/foreign/README.md` (ab
`0x40100000` linken, Seiten trennen, eigenes `_start`) betreffen genau
deshalb nur den statischen Fall: hier waehlt der KERN die Basis.

### 2.2 Zwei Bilder, ein Adressraum

`load` laedt eine Datei und prueft danach `page_exec(e_entry)`. Fuer den
dynamischen Fall muessen zwei Bilder nebeneinander liegen, die sich nicht
ueberlappen duerfen, und der Einsprung gehoert dem zweiten.

Platz ist da, und zwar reichlich — nachgerechnet:

```
IMAGE_BASE 0x40100000 .. IMAGE_END 0x40C00000  = 11,0 MiB
musl ld-musl-x86_64.so.1, Spanne aller PT_LOAD =  0,68 MiB
```

Der Interpreter passt also 16-mal in das Fenster, das ein Programm ohnehin
hat. Er bekommt eine feste Basis am OBEREN Ende des Fensters, das Programm
bleibt unten — so kann kein PIE-Programm, das von 0 an waechst, in ihn
hineinlaufen.

### 2.3 `PT_INTERP`

Der Pfad steht als Zeichenkette im Bild (`/lib/ld-musl-x86_64.so.1`, 25
Oktette). Er muss gelesen, im Dateisystem aufgeloest und die Datei als
zweites Bild geladen werden. Eine Kette ueber mehrere Stufen gibt es nicht:
ein Interpreter mit eigenem `PT_INTERP` wird ABGEWIESEN (Linux macht es
genauso).

### 2.4 Der Einsprung gehoert dem Interpreter

`e_entry` des Programms ist die Adresse, an die der LADER spaeter springt —
nicht die, an der der Kern anfaengt. Der Kern springt in `e_entry` des
Interpreters, plus dessen Basis. Das Programm-`e_entry` erfaehrt der Lader
ueber `AT_ENTRY` im `auxv`.

### 2.5 DER STARTSTAPEL — das Kernstueck

Das ist die eigentliche Arbeit der Runde. OrientOS uebergibt seit Runde K1
einen eigenen Block in RDI (`elf.fi`, `write_args`), und `tools/foreign/start.s`
rechnet ihn fuer statische musl-Programme in `argc/argv/envp` um. Ein
fremder Interpreter hat kein `start.s` — er erwartet den echten
System-V-Stapel, und er erwartet ihn genau so:

```
    rsp ->  argc
            argv[0] .. argv[argc-1]
            NULL
            envp[0] .. envp[envc-1]
            NULL
            auxv[0].a_type, auxv[0].a_val
            ...
            AT_NULL, 0
            <Zeichenketten>
```

Ohne `auxv` kommt musls Lader keine zehn Befehle weit: er findet ohne
`AT_PHDR`/`AT_PHNUM` die Programmkoepfe des Hauptbilds nicht und weiss ohne
`AT_BASE` nicht, wo er selbst liegt — er kann sich also nicht einmal selbst
relozieren. Die neun Werte, die gebraucht werden, stehen in Abschnitt 4.

---

## 3. Vorgehen

1. `ET_DYN` im Lader erlauben, mit Basisverschiebung.
2. `PT_INTERP` lesen, Interpreter als zweites Bild laden.
3. Startstapel mit `argc/argv/envp/auxv` bauen (RDI bleibt, wie es war —
   die 135 Osum-eigenen Programme mit `crt.s` duerfen nichts merken).
4. Einsprung auf den Interpreter setzen.
5. Messen, was wirklich passiert, und die Liste der fehlenden Syscalls aus
   dem LAUFENDEN System fuellen statt aus der Erwartung.

Gegenproben, die scheitern MUESSEN:
* ein `PT_INTERP`, der auf eine Datei zeigt, die es nicht gibt → sauberer
  Fehler, kein Haenger,
* ein Interpreter, der selbst `PT_INTERP` hat → abgewiesen,
* die 135 bestehenden Programme laufen unveraendert weiter.

---

## 4. Der Hilfsvektor

| Typ | Nr | Wert |
|---|---|---|
| `AT_PHDR` | 3 | Programmkoepfe des HAUPTBILDS im Adressraum |
| `AT_PHENT` | 4 | 56 |
| `AT_PHNUM` | 5 | `e_phnum` des Hauptbilds |
| `AT_PAGESZ` | 6 | 4096 |
| `AT_BASE` | 7 | Basis des INTERPRETERS |
| `AT_FLAGS` | 8 | 0 |
| `AT_ENTRY` | 9 | `e_entry` des Hauptbilds (+Basis bei PIE) |
| `AT_UID`/`AT_EUID`/`AT_GID`/`AT_EGID` | 11–14 | die Kennungen des Prozesses |
| `AT_SECURE` | 23 | 0 |
| `AT_RANDOM` | 25 | Zeiger auf 16 Oktette Zufall |
| `AT_HWCAP` | 16 | 0 |

`AT_PHDR` ist der Wert, der am haeufigsten falsch gesetzt wird: er zeigt
nicht auf den Dateianfang, sondern auf die Stelle IM ADRESSRAUM, an der die
Programmkoepfe nach dem Laden liegen. Die findet man nur, indem man das
`PT_LOAD` sucht, das `e_phoff` enthaelt.

---

## 5. Messwerte

*(wird im Lauf der Runde gefuellt)*

---

## 6. Offene Punkte

*(wird im Lauf der Runde gefuellt)*
