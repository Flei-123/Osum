# STATUS-HAERTUNG2.md — die Runde LIB-HÄRTUNG, mit Zahlen

Arbeitsbaum `/root/osum-haertung2`, Zweig `haertung2`, Basis `merge6`
(`a92fa00`). **Nicht gepusht, nicht gemergt.**
Firn-Seite: `/root/firn-haertung2`, Zweig `haertung2` von `4af14c3e`,
Commit `eeade326`. **Ebenfalls nicht gepusht.**

---

## 0. Das Wichtigste zuerst: zwei Annahmen des Auftrags waren falsch

Diese Runde hat beide Befunde **nachgemessen, bevor sie sie geflickt
hat**, und in beiden Fällen wich das Gemessene von der Beschreibung ab.
Das ist kein Streit um Worte — es entscheidet, *was* zu reparieren war.

### Befund 1 — „stiller Heap-Overflow“: für zwei von drei Wegen falsch

Der Auftrag sagte: `buf_grow` schweigt bei OOM, `cap` bleibt alt, **der
Aufrufer schreibt danach über das Pufferende**.

Gemessen (Kanarienvogel unmittelbar hinter dem Puffer, Arena echt
erschöpft über eine mmap-Absage):

| Weg | `capnach` | `len` | Kanarienvogel |
|---|---|---|---|
| `buf_push` | 128 | **128** | **1 — heil** |
| `buf_push_bytes` | 128 | **128** | **1 — heil** |
| `buf_reserve` + eigene Schreibschleife | 128 | **192** | **0 — überschrieben** |

`buf_push` und `buf_push_bytes` prüfen die Kapazität **ein zweites Mal**
nach dem Wachsen (`if (*b).len < (*b).cap`) und schreiben dann nicht.
Sie sind still — aber sie laufen **nicht** über.

Der echte Fehler liegt bei `buf_reserve`: es hatte **keinen
Rückgabewert**, der Aufrufer konnte also gar nicht hinsehen.

### Befund 2 — „42 der 43 Wege“ heißt etwas anderes als vermutet

Der Auftrag vermutete: Syscall-Eintrittspfade ohne Argumentprüfung, ohne
`user_ok`, ohne Vielkern-Sperre.

Die Quelle sagt etwas Engeres (`docs/RUNDE-MERGE6.md` 6.2,
`docs/RUNDE-GLYPHE.md` 276/568): gezählt werden von
`tools/multicore/onecore.py` die Funktionen, die einen Puffer der
**Datenseite** (`state + kstate.X_OFF`) als **Arbeitsfläche** nehmen,
ohne dass ein Sperrwort im Rumpf steht. Es ist ausdrücklich ein
**Vertrag** („die Zahl darf nicht wachsen“) und **keine Fehlerliste** —
das Werkzeug liest Text, keine Abläufe.

Argumentprüfung ist davon **nicht** berührt: `user_ok`, Längengrenzen
und Rechte prüft `sys.fi` an diesen Wegen sehr wohl.

### Dritte Annahme: der `do_unmap`-LIFO-Fix in BRIDGE-2 existiert nicht

Der Auftrag verwies auf einen LIFO-Fix in `/root/osum-bridge2`.
`git diff a92fa00..1b37234 -- kernel/` zeigt an `do_unmap`
**keine Änderung**; die Funktion ist dort Zeile für Zeile die aus
`merge6`. Richtig ist die Sache selbst: `do_unmap` (sys.fi:5183) gibt
mit `proc.page_drop` die **Seiten** zurück, den **Adressraum** aber
nicht — der Stoßallokator wächst nur. `docs/ROUNDK4.md` 190 benennt das
seit Runde K4 selbst. **Nicht angefasst** in dieser Runde: es ist eine
eigene Runde wert und war ohne Messung nicht zu entscheiden.

---

## 1. Befund 1 — was geändert wurde

### 1.1 Die Bibliothek antwortet jetzt

`buf_grow`, `buf_reserve`, `buf_push` und `buf_push_bytes` geben `bool`
zurück. Dazu `buf_reserve_or_die` für die Stellen, die ohne den Platz
nicht weiterkönnen — **ein** Abbruch an einer Stelle statt
vierundzwanzig verschiedener.

Warum `bool` und nicht Panik: eine Bibliothek, die bei knappem Speicher
den Prozess beendet, nimmt dem Aufrufer die Entscheidung ab. Die
Entscheidung fiel nach **Aufruferzahl**: `buf_grow` hat im ganzen Baum
nur **8** Aufrufer (6 davon in den drei `rt.fi`-Kopien selbst),
`buf_reserve` **24** außerhalb von `rt.fi`.

### 1.2 Der zweite, schlechtere Puffer

`vendor/firn/lib/html/mem.fi` ist eine **zweite** Pufferbauform im Baum.
Ihr `buf_push` hatte **keine** zweite Kapazitätsprüfung und schrieb nach
gescheitertem Wachsen **bedingungslos**. Das ist der stille Überlauf in
Reinform — in der Bauform, die niemand liest. Dazu: ihr `buf_grow` sah
den Rückgabewert von `heap_alloc` gar nicht an, und `read_all_stdin` las
65536 Oktett in einen Puffer, der so groß nicht sein musste.

### 1.3 Die Aufrufer, die wirklich hinsehen mussten

Von den 24 `buf_reserve`-Aufrufern prüfen **17 seit jeher** nach
(`if cap < n { return }`) — `tls.fi` 293/420, `http.fi`, `x11.fi`,
`httpstate.fi` und fünf der sechs Stellen in `deflate.fi`. Die blieben
unberührt.

**Sieben taten es nicht** und wurden geändert:

| Datei | Stellen | was danach geschrieben wurde |
|---|---|---|
| `std/crypto/crypto_main.fi` | 6 | `chacha20`, `aead_seal/open`, `gcm_seal/open`, `hkdf_expand` schreiben `n` Oktett nach `o.ptr` |
| `tls/tls.fi` 468 | 1 | `aead_seal_suite` schreibt `clen` Oktett ab `out.ptr + at` |
| `std/deflate.fi` 1230 | 1 | vier Oktett, ohne jede Prüfung |
| `kernel/app/jarvisd.fi` | 3 | Zeilenpuffer des Bildschirmfotos, `sys_read` hinein |

`buf_set_len` deckelt zwar `len` auf `cap` — aber die Kryptofunktion
bekommt `n` und schreibt `n`. Der Deckel schützt den **Puffer** nicht.

### 1.4 Wo der Fix liegt, und warum dort

`vendor/firn/lib/` ist **nicht eingecheckt**. `fetch-firnc.sh` löscht es
mit `rm -rf` und legt es aus dem festgenagelten Firn-Commit neu an.

**Das ist in dieser Runde wirklich passiert:** der erste Anlauf lag in
`vendor/firn/lib/`, ein `fetch-firnc.sh --force` lief dazwischen, und
danach stand der alte Rumpf wieder da. Deshalb liegt die Änderung als
eingecheckter Flicken:

* `vendor/firn/patches/0002-buf-grow-antwortet.patch` — `rt.fi`
  (dreifach: `rt/`, `std/`, `firnc1/`), `html/mem.fi`, `deflate.fi`
* `vendor/firn/patches/0003-aufrufer-pruefen-den-platz.patch` —
  `crypto_main.fi`, `tls.fi` (die gibt es im Firn-Repo nicht)

Derselbe Stand liegt als Firn-Commit `eeade326` im Firn-Repo. Zieht Firn
nach, fällt Flicken 0002 ersatzlos weg.

### 1.5 Der Nachweis

`tools/hardening/run.sh` — **19 gehalten, 0 gefallen**, Laufzeit 0,14 s.

```
  -- satt (Gegenprobe: heap_alloc gelingt)
     fall=1  capvor=128  capnach=256  len=192  kanarie=1
     fall=2  capvor=128  capnach=256  len=192  kanarie=1
     fall=3  capvor=128  capnach=256  len=192  kanarie=1
     fall=4  capvor=128  capnach=256  len=192  kanarie=1
  -- hungrig (die Arena ist wirklich erschöpft)
     fall=1  capvor=128  capnach=128  len=128  kanarie=1
     fall=2  capvor=128  capnach=128  len=128  kanarie=1
     fall=3  capvor=128  capnach=128  len=128  kanarie=1
  -- die Gegenprobe (Fall 4: der ungeprüfte Aufrufer)
     fall=4  capvor=128  capnach=128  len=192  kanarie=0
```

**Die Gegenprobe fällt** — Fall 4 ist derselbe Aufrufer *ohne* Prüfung
und läuft weiter über. Ohne sie würde dieser Abschnitt nichts messen.

Drei Dinge daran waren Arbeit und stehen als Kommentar im Nachweis:

1. **`ulimit -v` allein reicht nicht.** Unter jedem Limit bis 4200 KiB
   bekam `buf_grow` seine 256 Oktett anstandslos. Die Arena wird deshalb
   **im Programm** aufgebraucht, zweistufig: erst grob (64 KiB, 509
   Runden), dann fein (eine Seite) — ohne die feine Stufe lieferte
   `heap_alloc(256)` weiter eine Adresse.
2. **mmap wächst hier nach unten** (`73d57c78e000`, dann
   `73d57c78d000`). Die zweite Zuteilung ist die *untere*. Stimmt die
   Nachbarschaft nicht, bricht der Lauf mit 2 ab statt grün zu melden.
3. **Der Kanarienvogel wird gedruckt.** `firnc` entfernt ungenutzte
   Lesezugriffe (Befund der Runde PROTOKOLL — dort lief ein
   Nullzeigertest genau deshalb durch). Was in die Ausgabe geht, kann
   nicht wegoptimiert werden.

Ein vierter Punkt kostete den ersten Anlauf: gelingt `buf_grow`, gibt es
die alte Seite per `heap_free` zurück — lag der Vogel darin, war der
Lesezugriff danach ein SIGSEGV.

---

## 2. Befund 2 — der Pfadpuffer je Kern

### 2.1 Was der größte Posten war

`kstate.NAME_OFF` ist **eine Seite für die ganze Maschine**. **29
Stellen** in `sys.fi` machen dasselbe:

```firn
let buf: u64 = state + kstate.NAME_OFF
fetch_path(state, me, name, buf, MAX_NAME)   // Ring 3 -> Kern
... und danach wird AUS buf gearbeitet
```

Zwischen Füllen und Gebrauch liegt kein Riegel. `fs.path` nimmt die
Dateisystemsperre erst **danach**. Zwei Ring-3-Prozesse auf zwei Kernen
in `open` öffnen den Namen des jeweils anderen.

### 2.2 Die Lösung, und warum nicht die Sperre

Eine Seite **je Kern** (`kstate.NAMEK_OFF`), aufgelöst über
`sys.nameb(state)`. Das ist genau die Bauform, die Runde GLYPHE gegen
die gemeinsame Sperre **gemessen** hat: 2,25× (smp4) und 2,46× (smp8)
schneller. Eine Sperre um Füllen *und* Gebrauch läge auf dem heißesten
Weg des Systems — jedem `open`, jedem `stat`.

Sicher ist es aus demselben Grund wie `WIGST_OFF` und `SCANB_OFF`: der
Puffer wird ausschließlich **innerhalb** eines Systemaufrufs angefasst,
und `MSR_SFMASK` hält IF für den ganzen Systemaufruf unten — eine
Aufgabe kann darin nicht verdrängt und auf einem anderen Kern
fortgesetzt werden.

`uio.resolve` nimmt seine Arbeitsfläche jetzt **relativ zum übergebenen
Puffer** (`buf + 2048`) statt absolut; sonst läge sie wieder in einer
gemeinsamen Seite.

### 2.3 Die Zahlen

| | vorher | nachher |
|---|---|---|
| `einkern` offen | **64** | **47** |
| davon in `sys.fi` | 36 | 19 |
| `KDATA_SIZE` | 0xC0000 (768 KiB) | 0xE0000 (896 KiB) |
| Abbild | 4 175 880 | **4 171 656** |

Das Abbild wurde **kleiner**: `KDATA_SIZE` ist `.bss`, kostet also kein
Oktett — die Differenz kommt aus dem entfallenen Code.

**Ein Loch von acht Seiten gab es nicht mehr.** Eine Zählung nur über
`kstate.fi` zeigt 40 KiB frei bei `0x9F000` — in Wahrheit liegen dort
`hidrep.fi` und `hidin.fi`. Die vollständige Karte
(`tools/kernel/memmap.py` über **alle** Dateien) hat als größtes freies
Stück 16 KiB. `memmap.py` kennt `NAMEK` jetzt: **94 Bereiche, 0
Kollisionen.**

Die beiden Zahlen für `KDATA_SIZE` stehen in `kstate.fi` **und** in
`arch/x86_64/boot.s`; `tools/hv/run.sh` vergleicht sie.

---

## 3. Der Fuzzer — und was er sofort gefunden hat

`kernel/uprog.fi` (`u_fuzz`, Programm 54), gestartet mit
`fuzz fuzzrunden=<n>`. Er ruft die Systemaufrufe **aus Ring 3**, mit
einem eigenen, wiederholbaren xorshift und einer Liste **böser Werte**
(0, 1, `0xFFFFFFFFFFFFFFFF`, Kernadressen, Adressen knapp am Rand).

### 3.1 Der Fund: der Riegel war von außen umlegbar

**Erster Lauf, nach weniger als tausend Aufrufen:**

```
panic: integer overflow in 'u64 + u64' at kernel/proc.fi:812
```

Das ist `user_ok` — **die Zeigerprüfung selbst**, und zwar genau ihre
Überlaufprüfung:

```firn
if addr + len < addr { return false }   // "it wrapped around"
```

Seit Runde 72 ist `+` in Firn eine **geprüfte** Addition. `addr + len`
mit `len = 0xFFFFFFFFFFFFFFFF` ruft seither `osum_panic`, **bevor** der
Vergleich stattfindet. **Die Zeile konnte ihre Arbeit nie tun** — und
ein Programm in Ring 3 konnte den Kern mit **einem** Aufruf anhalten:
`read(fd, irgendwas, 0xFFFFFFFFFFFFFFFF)` genügte.

`sys.fi` wurde damals auf `+%`/`-%` umgestellt, `proc.fi` übersehen.
Behoben an drei Stellen in `user_ok` (`+%`, `-%`). Danach übersteht der
Kern denselben Lauf: `kernel: done`, QEMU-Rückgabe **21**.

Das ist der Ertrag dieser Runde, den keine der vier Abnahmen gefunden
hat — sie prüfen *Rückgabewerte*, der Fuzzer prüft, **dass der Kern
weiterlebt**.

### 3.2 Was der Fuzzer NICHT ruft, und warum

Ehrlich aufgeschrieben, weil jede Auslassung eine Lücke ist:

| ausgenommen | Grund (gemessen) |
|---|---|
| `exit`/`exit_group` | kämen nicht zurück |
| `fork` | ein Kind verdoppelt die Zahl der Aufrufe |
| `munmap`/`brk` | räumen dem Programm den Boden weg — Programm-, kein Kernfehler |
| `wait4` | ein Fuzzer, der wartet, misst nichts |
| `nanosleep` | nimmt bis zu **60 s** je Aufruf (darüber `-EINVAL`) |
| `read` | `tty_read` wartet `BLOCK_ROUNDS` = 400 Ticks auf Konsoleneingabe |
| `getdents64` | arbeitet auf der Platte; `fstat` deckt dieselbe Zeigerprüfung ohne Platte ab |

In allen sechs Fällen tut der **Kern das Richtige** — er wartet begrenzt
oder lehnt ab. Geprüft werden diese Grenzen in `tools/kernel/run.sh`
(seit Runde 62) und `tools/posix/run.sh`.

### 3.3 Was NICHT eingelöst ist

**Die Zusage „0 Panics in 100 000 Aufrufen bei `-smp 4`“ steht
aus.** Gemessen sind rund **30 000** Aufrufe ohne Panik und ohne
Ausnahme; danach lief der Lauf in das Zeitlimit des Läufers. Der Grund
ist nicht der Kern, sondern die Kosten: `open` und die
Dateisystemaufrufe arbeiten mit Zufallszeigern unbegrenzt lange.

Ich schreibe das als **offen** hin und nicht als „bestanden“ — eine
Zahl, die niemand gesehen hat, ist keine Abnahme.

---

## 4. Die Abnahmen

| Läufer | Ergebnis | Sollwert |
|---|---|---|
| `tools/kernel/run.sh` | **176 passed, 0 failed** | 176/0 ✅ |
| `tools/posix/run.sh` | **134 passed, 0 failed** | 134/0 ✅ |
| `tools/caps/run.sh` | **67 passed, 0 failed** | 67/0 ✅ |
| `tools/handle/run.sh` | **80 bestanden, 0 gefallen** | 80/0 ✅ |
| `tools/hardening/run.sh` | **19 gehalten, 0 gefallen** | neu |
| `test.sh` Abschnitt 43 | **bestanden**, 0,14 s | neu |
| `memmap.py` | 94 Bereiche, **0 Kollisionen** | 0 |
| `onecore.py` | gesperrt 18, **offen 47** (war 64) | Vertrag |

### 4.1 `handle` — und eine Falle, die man kennen muss

Der erste Lauf gab **76/1**: `firnc1 übersetzt kernel/uprog.fi nicht`.
Der Fehler ließ sich danach **nicht** nachstellen (`firnc1
kernel/uprog.fi -o …` läuft durch) — er stammt aus einem
Zwischenstand, in dem der Fuzzer noch nicht übersetzte.

**Der dritte Lauf, auf ruhigem Wirt, gab 80 bestanden, 0 gefallen** —
der Sollwert. Der Weg dorthin ist trotzdem lehrreich.

Der zweite Lauf gab **77/3**, und zwei davon waren **keine Regression,
sondern der Wirt**:

```
  FAIL  lseek aus Ring 3 bleibt unter 700 Zyklen: 1125, erwartet lt 700
  FAIL  getpid (von dieser Runde unberührt) bleibt unter 450 Zyklen: 798
```

Im ersten Lauf standen dort **620** und **422**, im dritten **617** und
**430** — beide Male grün. Dazwischen lief mein eigener Fuzzer-QEMU auf
denselben Kernen. `getpid` ist von dieser Runde nachweislich unberührt;
die Zusage misst also die Last des Wirts, nicht den Kernel. **Ein
Prüfstand auf einem ausgelasteten Wirt misst den Wirt** — dieselbe Lehre
wie in Runde GLYPHE (dort volles Dateisystem), und der Grund, warum hier
drei Läufe stehen und nicht einer.

Der dritte FAIL war **echt und ist behoben**: `memmap.py` meldete eine
Kollision, weil ich `M_FUZZ` auf Modusindex **646** gelegt hatte — den
hat schon `M_SERCON`. Jetzt 652, wieder **0 Kollisionen**. Genau dafür
gibt es das Werkzeug.

### 4.2 Firn

`cargo build --release` — durch. `./test.sh` im Firn-Repo lief bis
Abschnitt 17 (*the fixpoint: Firn compiles itself*) **ohne eine einzige
gefallene Zusage**. Abschnitt 16 (`self_compare.sh`) im Klartext:

```
   SAME BEHAVIOUR:     337
   DIFFERING:            0
   FAULTY:               0
   CODEGEN MISSING:      0
```

Dass `firnc1`
— der Übersetzer, der selbst in Firn geschrieben ist und `rt.fi`
benutzt — sich mit dem geänderten `rt.fi` neu baut, ist der härteste
verfügbare Test dieser Änderung, und er hält.

---

## 5. Was diese Runde nicht angefasst hat

* **`k16` 60/4** — der Assembler meldet Fehler 6 aus `schreib_elf`, das
  Programm läuft trotzdem und endet mit 42. Angesehen, nicht behoben:
  der Widerspruch liegt in `fas.fi`/`mkfs.py` und ist Oktett für Oktett
  derselbe wie in `merge6`. Eigene Runde.
* **Das `init`-Zeitlimit** — die erste Zusage läuft auf **beiden**
  Zweigen in ein QEMU-Zeitlimit; alles danach ist Folge. Unverändert.
* **`do_unmap`** — der Adressraum wird nicht zurückgegeben (0.3).
* **Die 47 verbleibenden `einkern`-Wege** — darunter `fs.buf_*` (die
  Blockpuffer, die über `enter` schon gedeckt sind, aber textlich
  auffallen) und `hw.list_dir`/`kmain.list_dir` (Boot-Diagnose, läuft
  vor SMP). Sie stehen weiter im Vertrag.

---

## 6. Commits

```
82e1b98  HAERTUNG-2 2/n: der Pfadpuffer je Kern
d5fb0b8  HAERTUNG-2 1/n: buf_grow antwortet -- gemessen statt geglaubt
a92fa00  (Basis) GLYPHE 21/n
```

Firn: `eeade326` in `/root/firn-haertung2`.
Beides **nicht gepusht** — das entscheidet Justin.
