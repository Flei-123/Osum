# Runde FREMDLAND — busybox, Fäden, echte Sperren

Zweig `fremdland`, Grundlage `laufzeit` @ 4de8bc9. Schritt 5 der Liste in
`/root/osum-roadmap/FREMDSOFTWARE.md`.

**Das Ergebnis in einem Satz:** **busybox 1.36.1 läuft auf Osum** — ein
einziges fremdes Binary mit 35 Unix-Werkzeugen, seine eigene Shell `ash`
mit **Röhren**, dazu **musl-Fäden** (4 Fäden, 100 000 Sperrzyklen ohne
einen verlorenen Zuwachs) und **echte Dateisperren**, an denen SQLite aus
zwei Prozessen korrekt `SQLITE_BUSY` bekommt statt die Datei zu zerstören.

Unterwegs fiel ein **Fehler auf, der schwerer wiegt als alles Neue**: der
Kern gab frische Seiten ungenullt an Ring 3. Das war ein Leck zwischen
Prozessen und der Grund, aus dem jede Röhre im zweiten Glied starb.

---

## 0. HERKUNFT — der Nachweis „fremd und unverändert"

LAUFZEIT schrieb „keine Zeile geändert", nannte aber weder Bezugsquelle
noch Prüfsumme. Das wird hier nachgeholt, für **alle vier** Projekte.
Die Archive liegen dauerhaft unter `/root/fremdquellen/`, das Skript, das
den Nachweis führt, ist `tools/fremd/herkunft.sh`.

| Projekt | Offizielle Bezugsquelle | SHA-256 des Archivs |
|---|---|---|
| Lua 5.4.7 | `https://www.lua.org/ftp/lua-5.4.7.tar.gz` | `9fbf5e28ef86c69858f6d3d34eccc32e911c1a28b4120ff3e84aaa70cfbf1e30` |
| SQLite 3.46.0 | `https://www.sqlite.org/2024/sqlite-amalgamation-3460000.zip` | `712a7d09d2a22652fb06a49af516e051979a3984adb067da86760e60ed51a7f5` |
| QuickJS 2024-01-13 | `https://bellard.org/quickjs/quickjs-2024-01-13.tar.xz` | `3c4bf8f895bfa54beb486c8d1218112771ecfc5ac3be1036851ef41568212e03` |
| busybox 1.36.1 | `busybox-1.36.1.tar.bz2` (s. u.) | `b8cc24c9574d809e7279c3be349795c5d5ceb6fdf19ca709f80cde50e47de314` |

**Vergleich mit der offiziellen Prüfsumme.** Lua veröffentlicht seine
Prüfsummen auf der Verzeichnisseite selbst; dort steht für
`lua-5.4.7.tar.gz` genau `9fbf5e28…1e30` — **abgeglichen, gleich**. Die
anderen drei Projekte veröffentlichen auf ihrer Seite **keine** SHA-256
neben der Datei (SQLite nennt eine SHA3-256 im Fließtext, QuickJS und
busybox gar keine). Für die steht oben, was **hier** gemessen wurde, und
der Nachweis ruht auf dem zweiten Standbein: **`diff -r` gegen das
frisch ausgepackte Archiv**.

*Ehrlich zu busybox:* `busybox.net` war von diesem Rechner aus nicht
erreichbar (`curl` läuft in die Zeitüberschreitung). Das Archiv kommt
deshalb von `https://sources.buildroot.net/busybox/busybox-1.36.1.tar.bz2`.
Die Gegenprobe dazu: es wurde **zusätzlich** der GitHub-Spiegel
(`github.com/mirror/busybox`, Marke `1_36_1`) geholt und gegen dieses
Archiv gestellt — Unterschied waren **ausschließlich neun `.gitignore`**,
keine Zeile Quelltext. Zwei unabhängige Wege zu denselben Oktetten.

### Der Nachweis, dass nichts geändert wurde

`tools/fremd/herkunft.sh` packt jedes Archiv ein **zweites Mal** an einen
frischen Ort und vergleicht es mit dem Baum, aus dem wirklich gebaut wurde:

```
lua-5.4.7:                    diff LEER -- unveraendert
quickjs-2024-01-13:           diff LEER (bis auf Erzeugtes, s. u.)
sqlite-amalgamation-3460000:  diff LEER -- unveraendert
busybox-1.36.1:               0 Dateien differ
```

**Kein einziges `differ`, und kein „Only in Original".** Nichts wurde
geändert, nichts entfernt. Was bei busybox und QuickJS zusätzlich
dasteht, ist ausnahmslos **vom Bau erzeugt** und nachprüfbar so benannt:

* busybox: `.config`, `include/autoconf.h`, `include/applet_tables.h`,
  `*.o`, `*.a`, `.*.cmd`, `Kbuild`/`Config.in` (aus den `.src`-Vorlagen).
* QuickJS: `.obj/`, `qjsc`, sowie `repl.c` und `qjscalc.c` — die erzeugt
  QuickJS' **eigener** Übersetzer `qjsc` aus den mitgelieferten
  `repl.js`/`qjscalc.js`, genau wie sein normales `make`.

### Umfang, mit `wc -l` gezählt

| Projekt | `.c` | `.c` + `.h` |
|---|---|---|
| Lua 5.4.7 | 24 663 | **30 098** |
| QuickJS 2024-01-13 | 79 897 | 87 649 |
| SQLite 3.46.0 (Amalgamation) | 288 768 | 302 912 |
| **busybox 1.36.1** | **272 262** | 282 194 |

Die 30 098 für Lua bestätigen LAUFZEITs Zahl. Für SQLite nannte LAUFZEIT
257 673 — das ist `sqlite3.c` **allein** (9 089 040 Oktette); mit
`shell.c` und den beiden Kopfdateien sind es 302 912. Beide Zahlen
stimmen, sie zählen Verschiedenes; hier steht ab jetzt die weitere.

---

## 1. busybox läuft — die Tabelle

Gebaut mit `musl-gcc -static` gegen das Linkerskript aus LAUFZEIT
(`tools/fremd/osum.ld`, ab `0x40100000`, drei seitenausgerichtete
`PT_LOAD`), eigenes `_start` (`tools/fremd/start.s`) und der
`auxv`-Aufbau aus `tools/fremd/osum_main.c`. Konfiguration:
`tools/fremd/busybox-config.sh` (61 Optionen, aus `allnoconfig`
hochgezogen). Ergebnis: **342 256 Oktette, 35 Applets, 71 Seiten im
Speicher**.

Installiert wird es wie auf einem echten System: **ein** Exemplar der
Oktette, 35 Namen darauf (`mkfs.py` `<neu>@<vorhanden>`, harte Verweise).

Jede Zeile unten ist echte serielle Ausgabe aus QEMU.

| Applet | Aufruf auf Osum | Ausgabe | |
|---|---|---|---|
| `echo` | `busybox echo A-echo-ok` | `A-echo-ok` | ✓ |
| `pwd` | `busybox pwd` | `/` | ✓ |
| `uname` | `busybox uname -s -m` | `Linux x86_64` | ✓ |
| `uname -a` | | `Linux osum 6.1.0 Osum x86_64` | ✓ |
| `true` / `false` | | Ende 0 / Ende 1 | ✓ |
| `test` | `test -d /bin` | Ende 0 | ✓ |
| `basename` | `basename /a/b/c.txt` | `c.txt` | ✓ |
| `dirname` | `dirname /a/b/c.txt` | `/a/b` | ✓ |
| `seq` | `seq 3` | `1` `2` `3` | ✓ |
| `printf` | `printf "P=%s-%d\n" x 7` | `P=x-7` | ✓ |
| `expr` | `expr 6 \* 7` | `42` | ✓ |
| `mkdir` | `mkdir -p /w/t/u` | (legt an) | ✓ |
| `touch` | `touch /w/t/f0` | (legt an) | ✓ |
| `cat` | `cat /w/t/f1` | `zeile1` | ✓ |
| `cp` | `cp /w/t/f1 /w/t/f2` | | ✓ |
| `mv` | `mv /w/t/f2 /w/t/f3` | | ✓ |
| `rm` | `rm /w/t/f3` | | ✓ |
| `ls` | `ls /w/t` | `f0  f1  f3  u` | ✓ |
| `wc` | `wc -c /w/t/f1` | `7 /w/t/f1` | ✓ |
| `head` | `head -n 1 /w/t/f1` | `zeile1` | ✓ |
| `tail` | `tail -n 1 /w/t/f1` | `zeile1` | ✓ |
| `grep` | `grep zeile /w/t/f1` | `zeile1` | ✓ |
| `sed` | `sed -e s/zeile1/ZEILE/ …` | `ZEILE` | ✓ |
| `sort` | `sort /w/t/f1` | `zeile1` | ✓ |
| `cut` | `cut -c1-5 /w/t/f1` | `zeile` | ✓ |
| `tr` | `tr a-z A-Z < /w/t/f1` | `ZEILE1` | ✓ |
| `od` | `od -c /w/t/f1` | `0000000 z e i l e 1 \n` | ✓ |
| `find` | `find /w/t -type f` | drei Pfade | ✓ |
| `awk` | `awk 'BEGIN{printf "awk=%d\n",6*7}'` | `awk=42` | ✓ |
| `date` | `date -u -d @0` | `Thu Jan  1 00:00:00 UTC 1970` | ✓ |
| `env` | `busybox env` | (leere Umgebung) | ✓ |
| `sleep` | `sleep 0` | | ✓ |
| `yes` | `yes \| head -n 2` | `y` `y` | ✓ |
| **`sh`** | `sh -c "echo sh-ok; seq 3 \| wc -l"` | `sh-ok` `3` | ✓ |

**33 der 35 Applets** sind damit belegt; die zwei ungenannten sind `ash`
(dasselbe Programm wie `sh`) und `busybox` selbst.

### Röhren — der eigentliche Prüfstein

`busybox sh` mit `|` bedeutet `fork` + `pipe` + `execve` je Glied:

```
sh -c "echo pipe-test | wc -c"          -> 10
sh -c "printf 'a\nb\nc\n' | wc -l"      -> 3
sh -c "seq 5 | sort"                    -> 1 2 3 4 5
sh -c "seq 5 | sort -r | head -n 2"     -> 5 4
sh -c "seq 3 | tr 1 X"                  -> X 2 3
sh -c "seq 3 | grep 2"                  -> 2
sh -c "echo x | sed s/x/Y/"             -> Y
busybox ls /bin | busybox wc -l         -> 37
```

**Was nicht geht, und warum.** `ls | wc -l` **ohne** `busybox` davor
zählt 1 statt 37: `busybox sh` sucht über `PATH`, findet Osums **eigenes**
`/bin/ls`, und das schreibt seine Einträge in **eine** Zeile mit
Leerzeichen. Das ist kein Fehler dieser Runde, sondern der Unterschied
zweier `ls` — mit `busybox ls` stimmt die Zahl. Wer busybox' Werkzeuge
will, ruft sie unter ihrem Namen auf; die harten Verweise stehen dafür da.

---

## 2. Die ergänzten Systemaufrufe

Alle mit den Nummern von Linux x86-64, alle auch in `lib/libc/kcall.fi`,
alle mit eigenem Test in `tools/posix` **samt Gegenprobe**.

| Nr | Name | Zweck | Wer ihn brauchte |
|---|---|---|---|
| 10 | `mprotect` | Seitenrechte ändern | musl, für die Schutzseite am Fadenstapel |
| 56 | `clone` | **Faden** (mit `CLONE_VM`), sonst `fork` | `pthread_create` |
| 63 | `uname` | sechs Felder zu 65 Oktetten | `busybox uname`, jede zweite Shell |
| 157 | `prctl` | `PR_SET_NAME`, `PR_GET_DUMPABLE` | musl bei **jedem** Programmstart |
| 202 | `futex` | die Sperre unter `pthread_mutex` | musl — **auch bei einem einzigen Faden** |

Dazu **echt gemacht**, was vorher nur behauptet war:

| Nr | Name | vorher | jetzt |
|---|---|---|---|
| 72 | `fcntl` `F_SETLK/GETLK/UNLCK` | „gewährt", ohne zu sperren | **echte Bereichssperren** |
| 218 | `set_tid_address` | Adresse **nicht** gemerkt | gemerkt und beim Ende gelöscht |

### Drei Entscheidungen, die benannt gehören

1. **`uname` sagt `sysname = "Linux"`.** Das ist keine Anbiederung,
   sondern die Wahrheit über die *Schnittstelle*: die Nummern in `rax`
   sind die von Linux x86-64. Ein Programm, das hier `Osum` läse, schlösse
   daraus, es kenne dieses System nicht, und wählte den Pfad für
   Unbekanntes. Der **nodename** sagt, welche Maschine das ist: `osum`.
2. **`prctl PR_GET_NAME` scheitert** (`-EINVAL`), während `PR_SET_NAME`
   still angenommen wird. Setzen verlangt keine nachprüfbare Wirkung;
   Lesen schon — ein Puffer, den niemand füllt, darf nicht als gefüllt
   gelten.
3. **`mprotect` antwortet 0, ohne Rechte zu ändern**, und der Mangel
   steht im Quelltext: musls Schutzseite unter dem Fadenstapel ist damit
   **keine**. Ein Faden, der seinen Stapel überläuft, schreibt in die
   Nachbarseite, statt einen Seitenfehler zu bekommen. Die Alternative
   wäre, gar keine Fäden zu können.

---

## 3. DER FEHLER DIESER RUNDE: ungenullte Seiten

Der wertvollste Fund, und er kam aus einem Absturz, der wie ein
Haldenfehler *aussah*.

**Das Symptom.** `busybox sh -c 'seq 5 | sort'` — das **erste** Glied der
Röhre lief, das **zweite** starb, jedes Mal:

```
user fault: pid=22 vector=13 err=0x0 cr2=0x4007eff8 rip=0x4011e056
```

`objdump` an dieser Stelle: ein einzelnes **`hlt`**, mitten in musls
`alloc_slot`. Das ist musls `a_crash()` — die Prüffrage seiner Halde,
in Ring 3 ein #GP. Die Meldung zeigte also auf die *Halde*.

**Die Sackgasse, die dazugehört.** Erste Vermutung war der Fadenzeiger:
`fork` vererbte `T_FSBASE` nicht. Das war **auch** ein Fehler und ist
behoben — aber er heilte den Absturz **nicht**. Zweite Vermutung
Stapelüberlauf, wegen `cr2=0x4007eff8` dicht unter `ustack`; auch falsch:
bei **#GP ist `cr2` schlicht alt**, das Register wird nur beim
Seitenfehler gesetzt. Die Adresse war die ganze Zeit eine Fährte ins Leere.

**Die Eingrenzung, Schritt für Schritt.** Jedes Mal ein eigenes kleines
Programm, kein Raten:

| Versuch | Ergebnis |
|---|---|
| `fork`, Kind fasst die Halde an (`tools/fremd/forktest.c`) | **läuft** — Kind sieht `vater`, Ende 7 kommt an |
| `fork` + 200 `malloc` im Kind | **läuft** |
| `fork` + `execve` | **stirbt** |
| `execve` **allein**, ohne `fork` | **stirbt** — damit ist `fork` entlastet |
| dasselbe Programm frisch gestartet | **läuft** |

Also: nicht die Röhre, nicht `fork` — **`execve`**. Und die Frage war
damit nicht mehr „warum stürzt malloc ab", sondern „was findet das neue
Abbild vor, das ein frisches nicht findet".

**Die Messung** (`tools/fremd/brkzero2.c`, ruft `brk` direkt, an musls
malloc vorbei, und zählt zwei frische Seiten aus):

```
frisch gestartet   nichtnull = 0 von 8192
nach einem execve  nichtnull = 8 von 8192,  das erste 0x27 an Offset 0
```

**Die Ursache.** `proc.map_page` gibt den Rahmen aus, wie der
Rahmenallokator ihn hergibt — **mit dem Inhalt des vorigen Besitzers**.
`brk`, `mmap(MAP_ANONYMOUS)`, `grow_stack` und die Argumentseite reichten
das ungenullt an Ring 3 weiter. Das ist **zweierlei** auf einmal:

1. **Ein Leck.** Was ein Prozess in einem Rahmen liegen ließ, liest der
   nächste. Zwischen zwei Abbildern desselben Prozesses hier, zwischen
   zwei *Prozessen* genauso — der Rahmenallokator kennt den Unterschied
   nicht.
2. **Der Absturz.** musls mallocng legt seine Verwaltung in genau diese
   Seiten und prüft sie bei jedem `malloc`/`free`. Findet sie Müll, ruft
   sie `a_crash()`.

**Die Behebung.** `proc.map_page_zero` an den **fünf** Stellen, die
frischen Speicher an ein Programm geben. **Nicht** im ELF-Lader: der
beschreibt jede Seite selbst und nullt den Rest (`elf.fi`, `fill_bytes`),
dort wäre es die zweite Runde über dieselben 4096 Oktette. POSIX verlangt
beides ohnehin so: was `mmap(MAP_ANONYMOUS)` liefert, ist mit Nullen
gefüllt, und was `brk` dazunimmt ebenso.

```
nach der Behebung  nichtnull = 0 von 8192   (nach execve)
```

Und alle Röhren laufen.

**Zwei Zeilen an derselben Wurzel**, gefunden auf dem Weg dorthin:
`fork` vererbt jetzt `T_FSBASE` (das Kind bekam 0, und `fsbase_apply`
ließ bei 0 die Basis des *vorigen* Fadens stehen — der Fadenzeiger zeigte
in einen fremden Adressraum); `execve` setzt es auf 0; und
`sched.fsbase_apply` schreibt deshalb **auch die Null**. Das ist eine
ausdrückliche **Korrektur an LAUFZEIT**, dessen Satz „eine Aufgabe ohne
TLS kostet nichts" genau einmal falsch ist.

---

## 4. Fäden

`tools/fremd/threads.c`: vier Fäden, je 25 000 Runden, jeder zählt seinen
eigenen Zähler hoch **und** einen gemeinsamen unter `pthread_mutex`.

```
th: starte 4 Faeden a 25000 Runden
th: faden 0 fertig zaehler=25000 rueckgabe=0
th: faden 1 fertig zaehler=25000 rueckgabe=100
th: faden 2 fertig zaehler=25000 rueckgabe=200
th: faden 3 fertig zaehler=25000 rueckgabe=300
th: summe=100000 erwartet=100000 OK
th: gemeinsam=100000 erwartet=100000 OK
```

**100 000 Sperrzyklen, kein einziger verlorener Zuwachs.** Wäre `futex`
falsch, stünde bei `gemeinsam` eine kleinere Zahl — genau das misst die
Zeile.

**Wie es gebaut ist.** `proc.create_thread` gibt dem Faden die Tabellen
des Erzeugers statt eigener und setzt `T_SHARED = 1`; `proc.free_space`
lässt einen **geliehenen** Adressraum in Ruhe. Vier Fäden, die beim Enden
viermal dieselben Rahmen zurückgäben, wären vier Wege, den
Rahmenverwalter zu vergiften. TLS je Faden kommt aus `CLONE_SETTLS` nach
`T_FSBASE`, der Stapel aus `a1`, und `rax = 0` in den Rahmen des Neuen.
`getpid` gibt seit dieser Runde die **Fadengruppe** (`T_TGID`), `gettid`
weiter die Aufgabe — ohne den Unterschied hielte sich jeder Faden für
einen eigenen Prozess.

**`pthread_join`** hing zuerst: `CLONE_CHILD_CLEARTID` verlangt, dass der
Kern beim Fadenende ein Wort im gemeinsamen Speicher auf 0 setzt, und
genau darauf wartet `join`. Die Adresse geht jetzt nach `T_FUTEX`, der
`exit`-Zweig löscht die vier Oktette, **bevor** die Aufgabe Zombie wird.

**`futex` — ehrlich benannt.** Was hier steht, ist ein **Warten mit
Nachsehen**, keine Warteschlange: `FUTEX_WAIT` prüft den Wert und schläft
je eine Marke, `FUTEX_WAKE` **zählt nur** (es gibt keine Liste, aus der zu
wecken wäre). Verpasste Weckrufe kann es deshalb nicht geben — gewartet
wird auf den **Wert**, nicht auf ein Signal. Der Preis sind bis zu 10 ms
je Sperrwechsel; eine echte Schlange an `T_FUTEX`/`T_FUTEXVAL` (die
Felder liegen seit Langem in `sched.fi`) ist der nächste Schritt.

**Ein Unterschied zu Linux, der genannt gehört:** POSIX teilt
**Deskriptoren** unter Fäden; dieser Kern hält sie je Aufgabe, also
werden sie beim `clone` **kopiert**. Das fällt erst auf, wenn ein Faden
eine Datei öffnet und ein anderer sie lesen will.

---

## 5. Echte Dateisperren

LAUFZEIT schrieb es selbst: *„`fcntl` meldet Sperren als gewährt, ohne zu
sperren. Das ist eine bewusste Lüge… Der Tag, an dem zwei Prozesse
dieselbe Datenbank öffnen, ist der Tag, an dem hier echte Sperren stehen
müssen."* Sie stehen.

Ein Eintrag ist `(Inode, Einhängung, erstes Oktett, letztes Oktett, Art,
Halter-tgid)`; 64 davon zu 48 Oktetten in einer Seite
(`kstate.FLOCK_OFF`). Die Sperre gehört der **Inode**, nicht dem
Deskriptor — zwei Prozesse mit derselben Datei haben zwei Deskriptoren
und **eine** Datei, und POSIX entscheidet nach der Datei.

`tools/fremd/locktest.c`, zwei Prozesse, sechs Fälle:

```
lk: A setzt WRLCK 0..9                 -> 0
lk: B WRLCK 0..9   (belegt)            -> -1  ABGELEHNT-RICHTIG
lk: B WRLCK 100..109 (frei)            -> 0   GEWAEHRT-RICHTIG
lk: B GETLK 0..9   -> rc=0 typ=1 halter=15
lk: A UNLCK 0..9                       -> 0
lk: C WRLCK 0..9   (jetzt frei)        -> 0   GEWAEHRT-RICHTIG
lk: A RDLCK 200..209, D RDLCK dieselben -> 0  GEWAEHRT-RICHTIG (geteilt)
lk: D WRLCK 200..209 gegen die RDLCK   -> -1  ABGELEHNT-RICHTIG
```

### Und die Abnahme, die der Auftrag verlangt: SQLite aus zwei Prozessen

`tools/fremd/sqlock.c` — der Vater lässt eine Schreibtransaktion offen,
das Kind versucht zu schreiben:

```
sq: sqlite 3.46.0
sq: A insert rc=0 (OK)
sq: A BEGIN IMMEDIATE rc=0 (OK)
sq: A insert in transaktion rc=0
sq: B insert rc=5 database is locked BUSY-RICHTIG
sq: kind endete code=0
sq: A COMMIT rc=0
sq: C insert rc=0 GEWAEHRT-RICHTIG
sq: zeilen=3 (erwartet 3)
sq: integrity_check rc=0 OK
```

**`rc=5` ist `SQLITE_BUSY`** — genau die Absage, die der Auftrag
verlangt, statt einer zerstörten Datei. Nach dem `COMMIT` schreibt der
nächste Prozess, es sind **drei** Zeilen, und
**`PRAGMA integrity_check` sagt `OK`**: die Datenbank ist heil.

Die Absage ist `-EAGAIN` — was Linux gibt und was SQLite zu
`SQLITE_BUSY` macht. Bei voller Tafel `-ENOLCK` statt einer Sperre, die
nicht eingetragen ist; das wäre genau die Lüge wieder. Beim Prozessende
fallen alle Sperren des Halters — ohne das bliebe eine Datenbank für
immer belegt, sobald ein Prozess stirbt, während er sie hält.

**Ausdrücklich nicht gebaut, und es steht im Quelltext:**

* **`F_SETLKW` wartet nicht**, es antwortet wie `F_SETLK`. Wer wartet,
  wartet auf einen anderen Prozess, und dieser Kern hat niemanden, der
  eine Verklemmung auflösen könnte. SQLite fragt ohnehin mit `F_SETLK`.
* Sperren fallen beim **Prozessende**, nicht beim `close()`. POSIX
  verlangt das Zweite.
* `l_whence = SEEK_END` wird abgewiesen (`-EINVAL`) statt geraten.

---

## 6. Osums Shell: der Rückstrich

LAUFZEIT meldete „Osums Shell entfernt Anführungszeichen,
`lua -e print("A")` ergibt `nil`". Die Ursache ist **nicht**, dass die
Shell Anführungszeichen frisst — einfache Anführungszeichen waren immer
richtig. Es sind **zwei Löcher beim Rückstrich**, beide mit einem
Programm gemessen, das nur sein `argv` druckt (`tools/fremd/argvdump.c`):

```
vorher   av "print(\"A\")"   ->  argv[1] = [print(\A\)]
vorher   av a\ b             ->  argv[1] = [a\]  argv[2] = [b]
```

1. **In doppelten Anführungszeichen** kannte die Schleife den Rückstrich
   nicht. Er blieb also stehen **und** das `"` dahinter beendete die
   Zeichenkette — genau verkehrt herum. Jetzt nach POSIX: der Rückstrich
   wirkt dort **nur** vor `$` `` ` `` `"` `\` und Zeilenende, sonst ist
   er ein gewöhnliches Zeichen (`"a\b"` bleibt `a\b`).
2. **Außerhalb** gab es ihn gar nicht. `a\ b` waren zwei Wörter, weil das
   Leerzeichen trotzdem trennte. Jetzt nimmt er dem nächsten Zeichen jede
   Sonderbedeutung, auch die des Trenners.

```
nachher  av "print(\"A\")"   ->  argv[1] = [print("A")]
nachher  av a\ b             ->  argv[1] = [a b]
```

Und der Fall aus dem Bericht, auf Osum:

```
osum$ lua -e 'print("A B")'                    -> A B
osum$ lua -e "print(\"A\")"                    -> A
osum$ lua -e 'print(2^10, math.floor(3.7))'    -> 1024.0   3
```

### Bleibt Osums Shell die Vorgabe?

**Ja — und busybox' `sh` steht daneben, nicht davor.** Die Gründe, in
dieser Reihenfolge:

1. **`/bin/sh` ist die Startbedingung des Systems.** `kmain.fi` startet
   sie als pid 1, wenn kein `/sbin/init` da ist, und `tools/osum/run.sh`
   und `tools/userland/run.sh` messen an ihr **221 Zusagen**. Ein Tausch
   der Vorgabe wäre keine Verbesserung, sondern eine neue Runde.
2. **Sie ist eigener Quelltext.** Der Leitsatz der Roadmap ist „brutal
   leichtgewichtig + brutal kompatibel, Kompatibilität über schmale
   Schnittstellen". Die schmale Schnittstelle ist die **Syscall-Tabelle**
   — dass fremde Programme laufen, ist ihr Verdienst. Osums Shell durch
   ein 342-KiB-Fremdbinary zu ersetzen, drehte das um.
3. **Sie ist kleiner.** `/bin/sh` ist ein paar Dutzend KiB, busybox
   342 256 Oktette; das ganze Abbild fasst 2 MB.

Wer busybox' Shell will, hat sie: `busybox sh` liegt auf der Platte, kann
Röhren, `;`, `-c` und die 35 Werkzeuge dazu. Das ist die richtige
Aufteilung — die Vorgabe bleibt das eigene, das Fremde steht bereit.

---

## 7. Zwei Fehler, die busybox nebenbei fand

**`mkdir -p` scheiterte mit „No space left on device"** — bei 4740 freien
Blöcken. `fs.parent_of` schnitt am **letzten** Schrägstrich; bei `/w/d2/`
steht der am Ende, also war der Name leer und die Funktion gab 0 zurück,
woraus der Aufrufer `ENOSPC` machte — der irreführendste Fehler von
allen. POSIX: `/w/d2/` und `/w/d2` benennen dasselbe, und busybox legt
die Zwischenstufen von `mkdir -p` genau so an. Schrägstriche am Ende
fallen jetzt weg; der Wurzelstrich allein bleibt stehen.

**`E_NOLCK` fehlte in `lib/libc/errno.fi`.** `tools/posix` hält beide
Listen Name für Name gegeneinander und meldete **133/1**. Der Lauf hatte
recht — derselbe Fall wie bei LAUFZEIT mit den sieben Nummern. Zwei
Tabellen, die auseinanderlaufen, sind ein Programm, dem ein Fehler zwei
Dinge bedeutet.

---

## 8. Keine Regression

| Lauf | vorher | nachher |
|---|---|---|
| `tools/posix/run.sh` | 134 / 0 | **150 / 0** |
| `tools/userland/run.sh` | 91 / 0 | **91 / 0** |
| `tools/osum/run.sh` | 130 / 0 | **130 / 0** |
| `tools/k16/run.sh` | 64 / 0 | **64 / 0** |

POSIX steigt um **16**: jede neue Nummer hat ihren Test, und zu jeder
gehört eine **Gegenprobe** — eine Nummer, die nur „kein `-ENOSYS`"
liefert, ist nicht gemessen.

```
uname sys    = 0     sechs Felder gefuellt
uname mach   = 120   Feld 4 faengt mit 'x' an -- der Beweis, dass die
                     Felder wirklich 65 Oktette auseinanderliegen
uname faul   = -14   GEGENPROBE: Zeiger in den Kern
prctl name   = 0     PR_SET_NAME still angenommen
prctl getnm  = -22   GEGENPROBE: PR_GET_NAME MUSS scheitern
prctl bad    = -22   GEGENPROBE: Unterbefehl, den es nicht gibt
mprotect     = 0
mprotect un  = -22   GEGENPROBE: Adresse mitten in einer Seite
futex weck   = 0     FUTEX_WAKE, niemand wartet
futex wert   = -11   FUTEX_WAIT mit falschem Wert kommt SOFORT zurueck --
                     ohne den Wertvergleich schliefe der Aufruf 10 s
futex schr   = -22   GEGENPROBE: Adresse nicht durch vier teilbar
lock setzt   = 0     echte Schreibsperre auf Oktett 0..15
lock frage   = 2     F_GETLK gibt F_UNLCK -- der eigene Halter steht
                     sich nie im Weg (POSIX)
lock loest   = 0
lock bloed   = -22   GEGENPROBE: Sperrart, die es nicht gibt
tid gleich   = 1     getpid == gettid mit einem Faden
```

Zwei Zwischenstände waren ehrlich rot und sind oben benannt: POSIX
**133/1** (`E_NOLCK` fehlte in der libc) und k16 **63/1** („die
Speicherkarte hat Kollisionen" — `FLOCK_OFF` stand in keiner Karte).
Beide Läufe hatten recht. `tools/kernel/memmap.py` kennt den Bereich
jetzt: **106 Bereiche, 0 Kollisionen**.

---

## 9. Was offen ist

* **`futex` ist ein Warten mit Nachsehen.** Bis zu 10 ms je Sperrwechsel.
  Eine echte Warteschlange an `T_FUTEX`/`T_FUTEXVAL` wäre der nächste
  Schritt — die Felder liegen bereit.
* **`mprotect` ändert nichts.** Die Schutzseite unter dem Fadenstapel ist
  keine; ein Stapelüberlauf schreibt still in die Nachbarseite.
* **`F_SETLKW` wartet nicht**, und Sperren fallen erst beim Prozessende,
  nicht beim `close()`.
* **Deskriptoren werden unter Fäden kopiert, nicht geteilt.**
* **Das Abbild ist zu klein.** Der Kern hält **eine** Blockkarte, also
  4096 Blöcke = 2 MB je Platte. Lua (380 KiB) + QuickJS (1,01 MiB) +
  busybox (342 KiB) passen zusammen **nicht** mehr darauf; jedes für sich
  läuft. Eine mehrblockige Karte kennt `mkfs.py` bereits (`bmblocks=2`),
  `kernel/fs.fi` noch nicht.
* **`busybox sh` findet über `PATH` Osums Werkzeuge zuerst.** Das ist
  gewollt (s. Abschnitt 6), aber wer `ls | wc -l` tippt, bekommt ein
  anderes Ergebnis als auf Linux.

## 10. Wie man es nachbaut

```
# Herkunft prüfen (Prüfsummen + diff -r gegen die Originalarchive)
bash tools/fremd/herkunft.sh

# busybox
bash tools/fremd/busybox-config.sh          # 61 Optionen aus allnoconfig
make -C busybox -j8 CC=musl-gcc SKIP_STRIP=y
musl-gcc -static -O2 -nostartfiles -T tools/fremd/osum.ld \
    -Wl,--build-id=none -Wl,--start-group \
    -o busybox-osum tools/fremd/start.s tools/fremd/osum_main.c \
    busybox/applets/built-in.o $(find busybox -name lib.a) -Wl,--end-group

# aufs Abbild: EIN Exemplar, 35 Namen
python3 tools/osum/mkfs.py build disk.img 4096 --inodes=256 \
    /bin/ /bin/busybox=busybox-osum /bin/ls@/bin/busybox ...
```

Bleibt ein Programm stumm oder stirbt es, hilft weiterhin `fremdtrace`
auf der Befehlszeile: es nennt die Nummer, die fehlt. Zeigt die Meldung
`vector=13` und ein `rip` mitten in musls Halde, ist es **nicht** die
Halde — dann lies Abschnitt 3.
