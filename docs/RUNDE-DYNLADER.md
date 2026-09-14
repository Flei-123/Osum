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

Alles in diesem Abschnitt ist aus einem Lauf abgeschrieben, nicht
gerechnet. QEMU mit `-accel kvm -cpu host`, Kern aus diesem Zweig,
Abnahme `tools/dynlader/run.sh`.

### 5.1 Der Lauf, der die Runde entscheidet

```
elf: start 3   entry=0x401000e8  ustack=0x4007f000  bytes=305652  pages=88
elf: interp    /lib/ld-musl-x86_64.so.1
elf: start 4   entry=0x40a777ee  ustack=0x4007e000  bytes=696140  pages=175
hallo dynamisch
```

Drei Zahlen sagen, dass es wirklich der dynamische Weg war:

* **`entry=0x40a777ee`** ist der Einsprung des INTERPRETERS, nicht des
  Programms: `ld-musl` hat `e_entry = 0x777ee`, dazu `INTERP_BASE`
  0x40A00000. Der Kern springt in den Lader; das Programm erfaehrt
  dieser ueber `AT_ENTRY`.
* **`ustack=0x4007e000`** ist der neue System-V-Stapel (`SP_PAGE`) und
  nicht `ARGS_BASE` (0x4007f000), den ein Osum-Programm bekommt.
* **zwei `elf: start`-Zeilen** fuer EINEN Befehl: erst die Shell, dann
  das Programm samt Lader, 175 Seiten statt 88.

### 5.2 Wo die beiden Bilder liegen

```
Hauptbild (hello_dyn, ET_DYN, auf PIE_BASE geschoben)
  seg 4  v=0x40100000  filesz=1208    memsz=1208    w=0 x=0
  seg 5  v=0x40101000  filesz=364     memsz=364     w=0 x=1
  seg 4  v=0x40102000  filesz=132     memsz=132     w=0 x=0
  seg 6  v=0x40103e00  filesz=536     memsz=544     w=1 x=0

Interpreter (ld-musl-x86_64.so.1, auf INTERP_BASE)
  seg 4  v=0x40a00000  filesz=83480   memsz=83480   w=0 x=0
  seg 5  v=0x40a15000  filesz=403460  memsz=403460  w=0 x=1
  seg 4  v=0x40a78000  filesz=206908  memsz=206908  w=0 x=0
  seg 6  v=0x40aabb20  filesz=2292    memsz=13376   w=1 x=0
```

Die beiden letzten Zeilen jeder Gruppe sind die, um die es in
Abschnitt 2 ging: `0x40103e00` und `0x40aabb20` sind NICHT
seitenausgerichtet. Vor dieser Runde waere an dieser Stelle `R_ALIGN`
gestanden und nichts gelaufen.

### 5.3 Die Messlatte

| Stufe | Inhalt | Ergebnis |
|---|---|---|
| **1** | eigenes `hello.c`, dynamisch, PT_INTERP | **GEFALLEN** -- `hallo dynamisch`, Ende 0 |
| **2** | dynamisch gelinktes busybox | **GEFALLEN** -- laeuft, Applets antworten wie auf dem Wirt |
| **3** | `dlopen`/`dlsym` | **GEFALLEN** -- `dlsym ok` |

Stufe 3 kostete keine einzige zusaetzliche Zeile: `ld-musl-x86_64.so.1`
IST `libc.so`, also bringt der Interpreter `dlopen`/`dlsym` mit, sobald
er ueberhaupt laeuft. Das ist der Ertrag der Entscheidung aus
Abschnitt 0 -- ein eigener Lader haette beides einzeln nachbauen
muessen.

### 5.4 Die Tabelle "fehlende Syscalls"

**Sie ist leer.** Kein einziger Systemaufruf wurde in dieser Runde
ergaenzt. Die vollstaendige Liste dessen, was der Lader verlangt, steht
in Abschnitt 1; der Kern kannte jede Nummer davon schon aus den Runden
LAUFZEIT und FREMDLAND. Die Arbeit lag im Lader und im Startstapel.

### 5.5 Die Gegenproben

| Fall | Erwartung | Ergebnis |
|---|---|---|
| `PT_INTERP` zeigt auf `/lib/gibtesnicht.so` | sauberer Fehler, kein Haenger | Grund 26 `interpreter missing`, Maschine laeuft weiter |
| Interpreter hat selbst `PT_INTERP` | abgewiesen | Grund 27 `interpreter chained` |
| die statisch gebundenen Programme | unveraendert | laufen weiter |
| Textkonstanten in `elf.fi` | so lang wie ihr Feld | 47 geprueft, 0 falsch |

---

## 6. Was diese Runde gekostet hat, das nicht im Plan stand

Vier Fehler, und keiner davon war durch Nachdenken zu finden -- alle
vier kamen erst beim Messen heraus. Sie stehen hier, weil die naechste
Runde sie sonst noch einmal macht.

1. **`firnc1` bricht STILL ab, wenn eine Zeichenkette laenger ist als
   ihr Feld.** Rueckgabewert 1, leeres stderr, keine Ausgabedatei. Hier
   war es `var t25: [u8; 20] = "bad PT_INTERP path\0"` -- 19 Oktette in
   einem Feld von 20. Gefunden durch Halbierung ueber den ganzen Kern,
   weil es keine Meldung gibt, an der man haette anfangen koennen.
   `tools/dynlader/run.sh` Abschnitt 1 prueft das jetzt als eigene
   Zusage.

2. **`R_OK` ist 0 -- und "kein PT_INTERP" war es auch.** Zwei Zustaende
   auf demselben Wort: `read_interp` meldete "das Bild braucht keinen
   Lader" mit derselben Zahl wie "der Pfad steht bereit". Damit hielt
   der Aufrufer jedes Bild fuer eines mit Lader. Behoben mit einem
   eigenen Wert `R_KEINER`.

3. **`say_segment` druckte die DATEI statt des SYSTEMS.** Sie nahm
   `p_vaddr` roh und fragte die Seitentabelle dort -- bei einem
   verschobenen Bild also an einer Adresse, an der nichts liegt. Die
   Meldung sagte `v=0x0 f=0x0` und sah aus wie ein Fehler des Laders,
   waehrend alles richtig lag.

4. **`as u8` auf einer Rechnung ist unter `profile kernel` ein
   Panik-Pfad.** Die sechzehn Oktette fuer `AT_RANDOM` entstehen aus
   Uhr und Aufgabenindex; ohne `& 255` endete der Lauf mit
   `panic: integer overflow casting 'u64 as u8'` -- und zwar erst,
   nachdem beide Bilder schon korrekt lagen.

Ein fuenfter Punkt betraf nicht den Kern, sondern die Abnahme selbst
und ist trotzdem der lehrreichste: die ersten Zusagen fuer `busybox
echo` und `busybox grep` galten als BESTANDEN, waehrend der Lader in
Wahrheit noch mit Grund 1 abbrach. Der Kern druckt beim Start seine
eigene Kommandozeile (`mb: flags=... script=busybox echo hallo-echo`),
und die enthielt den gesuchten Text woertlich. Eine Zusage, die auch
ohne das Programm haelt, misst das Programm nicht -- `run.sh` schneidet
diese Zeile jetzt weg, bevor verglichen wird.

---

## 7. Was das im Kern kostet -- und was es normalen Programmen kostet

Justins Zusatzvorgabe vom 14.09.2026, Punkt 2. Alle Zahlen gemessen,
keine geschaetzt.

### 7.1 Quelltext

```
kernel/elf.fi     +826  -37 Zeilen      (die EINZIGE Kerndatei der Runde)
davon Kommentar    347
davon leer          21
echter CODE        458 Zeilen
```

`kernel/sys.fi` ist **unberuehrt** -- `git diff` darauf ist 0 Zeilen
lang. Das ist die praezise Form der Aussage aus Abschnitt 5.4: diese
Runde hat **keinen einzigen Systemaufruf** hinzugefuegt, geaendert oder
umgehaengt.

### 7.2 Abbildgroesse

Zwei Kernabbilder aus demselben Baum, `--stufe 1`, einziger Unterschied
ist `kernel/elf.fi`:

| | Oktette | MiB |
|---|---|---|
| vorher (elf.fi vom Abzweigpunkt) | 12 688 320 | 12,10 |
| nachher (dieser Zweig) | 12 737 684 | 12,15 |
| **Differenz** | **+49 364** | **+48,2 KiB, +0,389 %** |

Zum Vergleich, und das ist der eigentliche Punkt der Vorgabe: die beiden
Pakete, die dadurch NICHT im Grundabbild liegen muessen, sind zusammen
**856 338 Oktette (836 KiB)** -- **17,3-mal so viel wie der Kernanteil**.

### 7.3 Was ein normales Osum-Programm davon merkt

Ein Programm ohne `PT_INTERP` (also jedes der 135 dieses Userlands) geht
ab `build()` denselben Weg wie vorher. Was dazukommt, ist genau
zweierlei:

1. **`read_header` laeuft zweimal statt einmal.** `build()` muss den
   Kopf lesen, BEVOR es entscheidet, auf welche Basis das Bild kommt;
   `load_at` liest ihn danach noch einmal. Fuer ein Osum-Programm mit
   drei Segmenten sind das `64 + 3*56 = 232` Oktette, die ein zweites
   Mal von der Platte kommen -- gegen die 100-200 KiB, die dasselbe
   Programm unmittelbar danach laedt, ist das der Faktor 1/650. Das ist
   der einzige echte Mehraufwand, und er ist hier genannt, statt ihn
   unter "vernachlaessigbar" zu verstecken. Er liesse sich wegbekommen,
   indem `load_at` den schon gelesenen Kopf weiterbenutzt; das waere
   eine Aenderung an der Schnittstelle von `load`, die drei andere
   Aufrufer hat, und gehoert deshalb nicht in diese Runde.

2. **`read_interp` laeuft einmal.** Es liest NICHTS von der Platte, wenn
   kein `PT_INTERP` da ist: es geht die schon im Puffer stehenden
   Programmkoepfe durch (bei Osum-Programmen drei Stueck) und gibt
   `R_KEINER` zurueck. Das sind drei Vergleiche.

**Kein Nachteil entsteht durch neue Systemaufrufe, weil es keine gibt.**
Die Zusage "die statisch gebundenen Programme laufen unveraendert
weiter" ist in `tools/dynlader/run.sh` Abschnitt 8 als eigene Messung
gefahren, und Abschnitt 9(e) misst zusaetzlich, dass ein System OHNE das
Paket `linux-abi` nicht kaputt ist, sondern nur keine dynamischen
Programme starten kann.

---

## 8. Modularitaet: was ist Paket, was ist Kern

Justins Zusatzvorgabe, Punkt 1. Hausregel 3 aus
`/root/osum-roadmap/FREMDSOFTWARE.md`: *"Kein Ballast im Standardabbild.
Alles Optionale kommt aus dem Store, nicht ins Grundabbild."*

### 8.1 Die Trennung

| Teil | wo | abschaltbar? |
|---|---|---|
| `PT_INTERP`-Behandlung, ET_DYN, auxv-Startstapel | Kern (`kernel/elf.fi`) | nein -- aber kostet ohne dynamisches Bild nichts (7.3) |
| `ld-musl-x86_64.so.1` (= `libc.so`) | **Paket `linux-abi`** | **ja** |
| busybox, Lua, SQLite, QuickJS ... | **Paket je Programm** | **ja** |

Die Kernseite laesst sich nicht paketieren -- ein Lader ist kein
Ring-3-Programm. Sie ist aber **inert**: ohne ein Bild mit `PT_INTERP`
wird kein einziger der neuen Pfade betreten.

### 8.2 Die Pakete, wirklich gebaut

`tools/dynlader/paket/*.rezept`, gebaut mit dem vorhandenen
`pkg/opk.py` -- kein neues Format, kein neues Werkzeug:

```
linux-abi    1.2.3      703302 Oktette  250ac59ee5f6d555705ad588...
busybox      1.36.1     153036 Oktette  a855dd4e8f3c0cea095e4d88...
```

`busybox` traegt `braucht=linux-abi`. Nach der Installation beider:

```
Generation 2, 2 Paket(e)
  busybox      1.36.1   a855dd4e8f3c  BusyBox
               braucht linux-abi
  linux-abi    1.2.3    250ac59ee5f6  Linux-ABI (musl)

opk pruefen: 2 Eintraege, 0 kaputt, 0 verwaist, 0 fehlend
```

Damit haengen sie an allem, was die Runden INSTALL und UPDATE gebaut
haben: Ed25519-Signatur beim Installieren, Generationen, `opk zurueck`,
Store, Deduplizierung ueber harte Verweise.

### 8.3 Der Punkt, an dem es haette scheitern koennen

`PT_INTERP` nennt einen **absoluten** Pfad (`/lib/ld-musl-x86_64.so.1`),
ein Paket legt seine Dateien aber unter `/apps/<name>.prog/` ab. Ob der
Kern den Interpreter ueber einen symbolischen Verweis dorthin findet,
ist keine Geschmacksfrage, sondern entscheidet, ob "kommt aus dem Store"
ueberhaupt moeglich ist.

Gemessen (`run.sh` Abschnitt 9c), OFS v3, Datei unter `/apps`,
`/lib/ld-musl-x86_64.so.1` als 44-Oktett-Verweis darauf:

```
/lib/ld-musl-x86_64.so.1 44
/apps/linux-abi.prog/lib/ld-musl-x86_64.so.1 702960

elf: interp /lib/ld-musl-x86_64.so.1
hallo dynamisch
```

Und `busybox sha256sum` liefert in dieser Form dieselbe Summe wie der
Wirt. Der Weg ueber das Paket ist damit nicht geplant, sondern gefahren.

### 8.4 Ohne das Paket

| Fall | Ergebnis |
|---|---|
| dynamisches Programm, Paket fehlt | `elf: refused, reason 26 interpreter missing`, Maschine laeuft weiter |
| Osum-Programm, Paket fehlt | laeuft normal |

Ein System ohne `linux-abi` ist also kein beschaedigtes System -- es
kann nur keine Linux-Binaries starten. Genau das ist der Sinn eines
optionalen Pakets.

---

## 9. Welcher Fremdcode landet auf dem System

Justins Zusatzvorgabe, Punkt 3, und seine Frage woertlich: ist das
"originaler Fremdcode" oder nur Uebersetzung? `tools/dynlader/herkunft.sh`
rechnet jede Zahl dieses Abschnitts nach.

**Die ehrliche Antwort ist: beides, und es laesst sich sauber trennen.**

### 9.1 Was von uns ist

`kernel/elf.fi`, 458 Zeilen echter Code (7.1). Eigener Firn-Code, keine
Zeile uebernommen. Insbesondere ist **nichts nachgebaut**, was es fertig
gibt: kein abgeschriebener Relokationscode, keine nachgebaute
Symbolsuche, kein eigenes `ld.so`. Der fremde Lader wird **benutzt**.
Regel 4 der Hausregeln ("Kein Fremdcode im Kern") gilt unveraendert.

### 9.2 Was fremd ist

| | musl | BusyBox |
|---|---|---|
| **Paket** | `linux-abi` | `busybox` |
| **Ziel** | `/lib/ld-musl-x86_64.so.1` | `/bin/busybox` |
| **Ring** | **3** | **3** |
| **Fassung** | 1.2.3-1 (Debian `musl:amd64`) | 1.36.1 |
| **Lizenz** | **MIT**, (c) 2005-2020 Rich Felker u. a. | **GPL-2.0-only** |
| **Herkunft** | https://musl.libc.org/ | https://busybox.net/ |
| **Form** | **fertige Binaerdatei, unveraendert** | **Quelltext unveraendert, hier gebaut** |
| **Groesse** | 702 960 Oktette | 152 752 Oktette |
| **SHA-256** | `99261882506dab04...` | `169541fc3205f1bd...` |

Der Unterschied zwischen den beiden Zeilen "Form" ist der Kern von
Justins Frage:

* **musl ist eine FERTIGE FREMDE BINAERDATEI.** Dieselben 702 960
  Oktette, die auf dem Wirt liegen -- nicht uebersetzt, nicht neu
  gebaut, nicht angepasst. Das ist Absicht und der ganze Sinn der
  Runde: ein selbst gebauter Interpreter waere kein Nachweis, dass
  Linux-Programme laufen, sondern nur einer, dass unser Bau laeuft.
* **BusyBox ist fremder QUELLTEXT, hier uebersetzt.** Das Archiv ist
  unveraendert (SHA-256 gegen `/root/fremdquellen/SHA256SUMS.txt`
  geprueft: `b8cc24c9574d809e...`), gebaut mit `musl-gcc` und
  `CONFIG_STATIC` aus. Das Binaergebilde ist unseres, der Quelltext ist
  fremd.

Beides laeuft in **Ring 3**. Im Kern laeuft nichts Fremdes.

### 9.3 Lizenzfolgen

* musl ist **MIT** -- vertraeglich mit beidem, was dieses Repo fuehrt
  (GPL-2.0-only fuer den Kern, MIT fuer die Ring-3-Bibliotheken,
  `LICENSE-UEBERSICHT.md`). Es wird weder eingebunden noch veraendert,
  sondern als eigene Datei ausgeliefert.
* BusyBox ist **GPL-2.0-only** -- dieselbe Lizenz wie der Kern. Als
  eigenstaendiges Programm in einem eigenen Paket entsteht kein
  abgeleitetes Werk am Kern.
* Beide Pakete nennen Herkunft, Fassung und Lizenz in ihrer
  `INFO`/`info=`-Zeile, also dort, wo sie im System sichtbar sind.

---

## 10. Offene Punkte


* **Eine geteilte Seite bekommt die Rechte des ERSTEN Segments.** Bei
  musl trifft das genau die Naht zwischen `rodata` und `data`; die
  Seite bleibt lesbar statt schreibbar zu werden. Ein Programm, das in
  diese eine Seite schreiben muesste, liefe hier nicht. Der saubere Weg
  waere, die geteilte Seite mit der VEREINIGUNG beider Rechte zu legen
  -- das widerspricht aber Regel 3 dieser Datei und gehoert deshalb in
  eine eigene Runde mit eigener Gegenprobe.
* **`mprotect` antwortet weiterhin 0, ohne etwas zu tun** (Befund aus
  FREMDLAND, unveraendert). Fuer musls RELRO heisst das: der Bereich
  wird nicht wirklich schreibgeschuetzt. Das ist eine Haertungsluecke,
  keine Funktionsluecke.
* **`INTERP_BASE` ist fest.** Ein zweiter Interpreter im selben
  Adressraum ginge nicht; fuer `dlopen` auf eine FREMDE Bibliothek
  (nicht `dlopen(0)`) braeuchte es eine echte Vergabe von Basen.
* **Nur `MAP_ANONYMOUS`.** Ein `dlopen` auf eine Datei wuerde
  `mmap` mit Deskriptor verlangen, und das gibt es hier nur fuer
  `/dev/fb`. Deshalb misst Stufe 3 `dlopen(0)` und nicht `dlopen("...")`
  -- was gemessen wurde, ist genau das, was zugesagt wird.
