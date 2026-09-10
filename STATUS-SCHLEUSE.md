# RUNDE SCHLEUSE — fremde Software auf OrientOS, über WebAssembly

Zweig `schleuse`, Basis `merge8` @ c0f7151, Arbeitsbaum `/root/osum-schleuse`.
Schritt 3 der Liste in Abschnitt 7 von `/root/osum-roadmap/FREMDSOFTWARE.md`.

**Das Ergebnis in einem Satz:** SQLite 3.45.0 — 255 636 Zeilen C vom SQLite-Team,
niemand davon hat je von Osum gehört — legt auf OrientOS eine Datenbank an, füllt
eine Tabelle und liest sie zurück.

---

## 0. Die Wegentscheidung, mit Messung

Zwei Wege standen zur Wahl. Beide wurden angeprobt, bevor einer gebaut wurde.

### (b) wasm2c — GEPRÜFT UND VERWORFEN

Der Gedanke: `wasm2c` übersetzt das Modul auf dem Bauserver nach C, das übersetzt
unser eigener Compiler — dann bräuchte es gar keine Laufzeit.

Der Haken ist tödlich: **Osum baut mit `firnc`, nicht mit C.** Es gibt im Baum
keinen C-Compiler, der ein Osum-Binärformat erzeugt. Damit der Weg trüge, müsste
eines von zweien gelten:

1. **C nach Firn übersetzen.** Abschnitt 6 der FREMDSOFTWARE.md hat das schon als
   Sackgasse vermerkt: c2rust produziert 26,5–99 % `unsafe`, **79 % der
   Roh-Pointer** lassen sich nicht überführen; LLM-Übersetzung liegt bei **22 %**
   (CRUST-Bench). wasm2c-Ausgabe ist der denkbar schlechteste Eingang dafür:
   generiertes C, das fast nur aus Pointer-Arithmetik auf einem linearen Speicher
   besteht — genau die 79 %.
2. **Einen C-Compiler nach Osum bringen.** Ein größeres Projekt als der
   Interpreter, den wir stattdessen gebaut haben. Verschiebt das Problem.

Dazu: wasm2c erzeugt **pro Modul** neuen C-Code. Jedes fremde Programm wäre ein
neuer Bauserver-Lauf; Osum könnte nie ein `.wasm` nehmen, das ihm jemand hinlegt.
Das ist das Gegenteil einer Schleuse.

### (a) Eigene WASM-Laufzeit in Firn — GEWÄHLT UND GEBAUT

Die Bauserver-Seite trägt, gemessen:

| Messung | Ergebnis |
|---|---|
| `rustup target add wasm32-wasip1` | geht (rustc 1.99.0-nightly) |
| Rust-Hello-World nach `wasm32-wasip1` | 2 179 965 Oktett roh |
| dasselbe `-C debuginfo=0 -C strip=symbols` | **47 364 Oktett** |
| wasi-sdk 24 (clang + wasi-sysroot) | geht, SQLite übersetzt damit |
| wabt (`wat2wasm`) | nachinstalliert, für handgeschriebene Module |

Und die Zahl, die alles trägt — die Importe des Rust-Hello-World, aus Sektion 2
des Moduls selbst ausgelesen:

```
IMPORTE: 4
    wasi_snapshot_preview1 :: environ_get, environ_sizes_get, fd_write, proc_exit
```

**Vier.** Nicht 46, nicht 1200. Der ausführbare Teil war ~40 KB Code; die 2,1 MB
waren Debug-Info in Custom-Sections, die der Deuter ohnehin überspringt.

---

## 1. Was gebaut wurde

`kernel/app/wasm.fi`, **3137 Zeilen Firn**, `--profile=app`, **Ring 3**.

- **Modulparser** für die Binärform: magic `0x6d736100`, Sektionen type, import,
  function, table, memory, global, export, start, element, code, data; Custom
  wird übersprungen. LEB128 mit und ohne Vorzeichen.
- **Stapelmaschine** mit Kontrollfluss (block/loop/if/else/br/br_if/br_table/
  return/call/call_indirect), Parametern und Lokalen, i32/i64/f32/f64-Arithmetik
  und -Vergleichen, Speicherzugriffen load/store in allen Breiten mit Vorzeichen,
  memory.size/grow, select, drop, den Vorzeichen-Erweiterungen (0xC0-Gruppe) und
  memory.copy/fill (0xFC-Gruppe).
- **WASI preview1** als Importe, auf Osums Syscalls abgebildet.
- `/bin/wasm <datei.wasm> [argumente]`, dazu `-s` als Spurschalter.

Die Sicherheitsgrenze ist `mem_bound`: **jeder** Gastzugriff wird gegen die Größe
des linearen Speichers geprüft. Ein fremdes Modul kann den Deuter zum Anhalten
bringen, nicht aus seinem Speicher heraus.

---

## 2. ABNAHME — welche fremde Software wirklich lief

Alles unten ist **in QEMU auf echtem Osum** gelaufen, Ring 3, seriell
mitgeschnitten in `beleg-schleuse-osum.txt` (roher Mitschnitt, ungekürzt).

### (b) SQLite 3.45.0 — das eigentliche Ziel

Amalgamation 3.45.0, **unverändert** vom SQLite-Team, mit wasi-sdk nach
`wasm32-wasi` übersetzt (1 340 817 Oktett). Auf Osum:

```
==4-SQLITE==
SQLite-Version: 3.45.0
datenbank offen
tabelle angelegt, 3 zeilen eingefuegt
  zeile: 1 OrientOS 2026
  zeile: 2 Firn 2025
  zeile: 3 WASM-Schleuse 2026
zeilen gelesen: 3
  zeile: OrientOS
  zeile: WASM-Schleuse
davon aus 2026: 2
datenbank zu
rc=0
```

`CREATE TABLE`, drei `INSERT`, ein `SELECT ... ORDER BY`, ein zweites mit
`WHERE`. **Gegenprobe auf dem Wirt:** die vom WASM-Modul geschriebene Datei fängt
mit `SQLite format 3` an, das systemeigene `sqlite3` liest sie und sagt
`PRAGMA integrity_check` → `ok`.

### (a) Eigenes Hello-World, zwei Wege

Rust nach `wasm32-wasip1` (`hello2.wasm`, 47 364 Oktett):

```
==2-RUST==
Hallo von fremder Software auf OrientOS!
summe der quadrate 1..100 = 338350
rc=0
```

338350 ist nachgerechnet richtig. Dazu ein von Hand geschriebenes `.wat` über
`wat2wasm` (313 Oktett), das Schleife und `if` einzeln nachweist.

### Datei-Ein-/Ausgabe, echt

```
==3-DATEI==
zurueckgelesen: Diese Zeile hat ein WASM-Modul geschrieben.
laenge: 44 oktette, gleich: true
argumente: ["/dateitest.wasm", "alpha", "beta"]
rc=0
```

Ein Rust-Modul legt über `path_open` eine Datei an, schreibt, öffnet neu, liest
zurück und vergleicht — `gleich: true`. Die Argumente kommen durch.

---

## 3. Tempo — gemessen, nicht behauptet

**Derselbe Algorithmus** (Primzahlen per Probedivision), einmal als Firn-Programm
(`kernel/app/prim.fi`), einmal als WASM (`prim.wasm`). Beide liefern dieselbe
Zahl, sonst wäre der Vergleich wertlos.

**Auf Osum selbst** (`beleg-schleuse-tempo.txt`, Grenze 200000, beide 17984):

```
==NATIV==   15:03:38  /bin/prim 200000        15:03:38   -> unter 1 s
==DEUTER==  15:03:38  /bin/wasm /prim.wasm    15:03:44   -> 6 s
```

**Auf dem Wirt, feiner aufgelöst** (Grenze 500000, beide 41538):

| | Zeit | Faktor |
|---|---|---|
| Firn nativ | 0,101 s (Mittel aus 10) | 1× |
| Rust nativ | 0,106 s (Mittel aus 10) | 1,05× |
| **WASM im Deuter** | **15,99 s** (Mittel aus 2) | **158×** |

238 055 923 WASM-Befehle in 15,99 s = **14,9 Mio Befehle/s, 67 ns je Befehl**.

### Die 158× sind ehrlich, und hier steht, woher sie kommen

Die Erwartung war ~11,5× (wasm3). Der Auftrag sagte: bei 100× ist etwas faul. Es
wurde nachgesehen, in drei Runden:

**Runde 1 — Verdacht Blocksuche.** Der Deuter suchte bei jedem Sprung das `end`
eines Blocks neu. Gemessen: `blockscans=900585`, **51 472 015 Oktette** überflogen.
Abhilfe: ein Sprungspeicher (8192 Einträge, direkt adressiert).
Ergebnis: `blockscans=203`, **84 856 Oktette** — Faktor 600 weniger Sucherei.
**Tempogewinn: keiner.** Die Suche war nicht der Engpass.

**Runde 2 — Verdacht Aufbaukosten je Befehl.** Der `Leser` wurde je Befehl neu
gebaut (67 Mio Mal). Herausgezogen: **5,5 s → 4,8 s**, also 13 %. Danach die
häufigsten fünf Befehle (`local.get`, `i32.const`, `i32.add`, `local.set`,
`i32.sub`) an den Anfang der Verteilerkette gezogen: **kein messbarer Gewinn**.

**Runde 3 — die Ursache, mit Gegenprobe.** Ein gleichwertiger Deuterkern in C
(dieselbe Arbeit: Oktett lesen, verteilen, Stapel bewegen) macht auf demselben
Wirt 67 Mio Schritte in **0,12 s = 1,8 ns je Schritt**. Unser Deuter braucht
**67 ns**, also **37× mehr pro Schritt**. Der Blick in den erzeugten Assembler
(`--emit=asm`) sagt, warum:

```
4078  Überlaufprüfungen  (jc .Lchksite…)
 302  Indexprüfungen     (jae .Lchkidx…)
 394  nicht eingesetzte push/pop-Aufrufe
```

Jedes `push` ist ein echter Aufruf mit 288 Oktett Rahmen, jede Addition trägt
eine Überlaufprüfung, jeder Feldzugriff eine Grenzprüfung. **Das ist Firns
Sicherheitsmodell, kein Fehler im Deuter** — und es gibt in Stufe 0 kein Attribut,
das es abschaltet (`--list-attrs` geprüft). wasm3 ist C mit vorcodierten
Befehlsketten und ohne jede dieser Prüfungen; 158× gegen 11,5× ist genau dieser
Unterschied plus die fehlende Vorcodierung.

### Ein Nebenfund, der Geld wert ist

Höhere Optimierungsstufen waren **langsamer**. Gemessen, Grenze 200000:

| Stufe | Zeit |
|---|---|
| `dev` | 30,06 s |
| `dev-fast` (Standard) | 4,98 s |
| `release-safe` | 9,14 s |
| `release-fast` | 8,21 s |
| **`release-fast --no-pass=inline`** | **4,80 s** |

Der `inline`-Durchgang bläht die lange if/else-Kette über die Befehlsnummer auf und
verdrängt sie aus dem Befehlszwischenspeicher. `tools/install/build.sh` baut die
Apps seit dieser Runde mit `--no-pass=inline`.

---

## 4. Regression — keine

Alle drei Läufer vorher und nachher, volle Zahlen:

| Läufer | vorher | nachher |
|---|---|---|
| `tools/posix/run.sh` | **134 passed, 0 failed** | **134 passed, 0 failed** |
| `tools/k16/run.sh` | **64 passed, 0 failed** | **64 passed, 0 failed** |
| `tools/userland/run.sh` | (nicht vorher gefahren) | **91 passed, 0 failed** |

Der Deuter läuft in **Ring 3**, nicht im Kern: `kernel/app/wasm.fi`,
`--profile=app`, gebunden mit `user.ld`, kein `crt.s`. Der Kern hat sich um keine
Zeile geändert.

---

## 5. WASI preview1 — was da ist und was fehlt

**28 von 46 umgesetzt.**

### Da (28)

`args_get` · `args_sizes_get` · `environ_get` · `environ_sizes_get` ·
`clock_res_get` · `clock_time_get` · `fd_close` · `fd_datasync` ·
`fd_fdstat_get` · `fd_fdstat_set_flags` · `fd_filestat_get` ·
`fd_filestat_set_size` · `fd_prestat_dir_name` · `fd_prestat_get` · `fd_read` ·
`fd_seek` · `fd_sync` · `fd_tell` · `fd_write` · `path_create_directory` ·
`path_filestat_get` · `path_open` · `path_remove_directory` ·
`path_unlink_file` · `poll_oneoff` · `proc_exit` · `random_get` · `sched_yield`

Davon sind einige **ehrliche Vereinfachungen**, und das gehört gesagt:
`environ_get` meldet eine leere Umgebung; `fd_filestat_set_size` sagt Ja, ohne zu
kürzen (Osum hat kein `ftruncate`; SQLite verträgt das, weil es nach Kopfdaten
liest und nicht nach Dateilänge); `poll_oneoff` sagt Ja, ohne zu warten;
`clock_res_get` meldet feste 1000 ns.

### Fehlt (18)

`fd_advise` · `fd_allocate` · `fd_filestat_set_times` · `fd_pread` · `fd_pwrite` ·
`fd_readdir` · `fd_renumber` · `path_filestat_set_times` · `path_link` ·
`path_readlink` · `path_rename` · `path_symlink` · `proc_raise` ·
`sock_accept` · `sock_recv` · `sock_send` · `sock_shutdown` ·
`fd_fdstat_set_rights`

Sie melden `ENOSYS` (52) statt still Null zu liefern — ein Programm, das eine
davon braucht, sagt das dann auch. SQLite ruft `path_filestat_set_times`,
`path_readlink` und `fd_advise` und kommt ohne sie durch.

---

## 6. Fallstricke — was wirklich Zeit gekostet hat

1. **WASM rechnet umlaufend, Firn rechnet geprüft.** `i32.sub` von 0 und 1 ist in
   WASM `0xFFFFFFFF` und völlig regulär — so zählt jede Schleife rückwärts. In
   Firn ist dasselbe ein Abbruch: `integer overflow in 'u64 - u64'`. Das erste
   echte Rust-Modul starb daran. Abhilfe: `wadd`/`wsub`/`wmul`, die dasselbe
   rechnen wie WASM, ohne Firns Prüfung auszulösen. **Der größte Einzelfallstrick
   der Runde.** Auch `0 as u64 - 1 as u64` als "alle Einsen" fällt darunter — muss
   als Literal `18446744073709551615` geschrieben werden.
2. **Die Maschine war zu klein, und es sah aus wie ein fehlender Befehl.** Der
   VM-Bauplan braucht Stapel 64 KiB + Lokale 16 KiB + Label 32 KiB + Rahmen 32 KiB
   ≈ 144 KiB; alloziert waren 128 KiB. Weil `frames` hinter `label` liegt, schrieb
   jeder tiefere Aufruf hinter die Halde — SQLite endete mit `Segmentation fault`.
   gdb zeigte die Stelle, nicht die Ursache; gefunden durch Nachrechnen der
   Feldgrößen. Jetzt 512 KiB, und die Rechnung steht als Kommentar daneben.
3. **`fd_prestat_get` ist die Funktion, ohne die fast nichts startet.** Ein
   WASI-Programm fragt die Deskriptoren ab 3 durch: "bist du ein vorgeöffnetes
   Verzeichnis?". Ohne Antwort findet es seine Wurzel nicht, und Rusts
   `File::open` gibt NotFound zurück, egal was da liegt.
4. **`path_filestat_get` war der Grund für "unable to open database file".**
   SQLite fragt vor dem Öffnen nach Existenz und Größe. Die Meldung verrät nicht,
   dass ein STAT und nicht das OPEN gefehlt hat — gefunden erst, nachdem der
   Spurschalter `wasm -s` eingebaut war, der jede abschlägige WASI-Antwort nennt.
5. **SQLite sperrt mit einem VERZEICHNIS.** `<datei>.lock` wird per `mkdir`
   angelegt und per `rmdir` entfernt. Fehlte `path_remove_directory`, blieb die
   Sperre liegen und jeder zweite Lauf endete mit `database is locked`. Und
   `EEXIST` muss von anderen Fehlern unterschieden werden (Osum meldet Linux' 17,
   WASI nennt es 20), sonst wird aus einer alten Sperre ein `disk I/O error`.
6. **Ein iovec des Gastes ist acht Oktette, nicht sechzehn.** WASM ist 32-bittig.
   Wer `ld64` nimmt, weil iovec auf dem Wirt so aussieht, liest Müll.
7. **Die Argumente fangen beim Modulpfad an, nicht bei 1.** Sonst sieht das Modul
   den Schalter `-s`, der dem Deuter gilt, hält ihn für sein eigenes Argument und
   rechnet mit seinem Standardwert weiter. Das hat die Tempomessung verfälscht:
   jede Grenze ergab dieselbe Befehlszahl, bis es auffiel.
8. **Firn nimmt in Strukturen keine Konstanten als Feldlänge** — `[u8; MAX_PARAMS]`
   wird abgelehnt, es muss die Zahl dastehen.
9. **Die data-Sektion kann vor der memory-Sektion stehen.** Beim ersten Durchgang
   ist der lineare Speicher dann noch 0, und ein `mem_copy` dorthin ist der erste
   Absturz, den man sieht. Deshalb zwei Durchgänge: einmal alles, einmal nur data.

---

## 7. Was offen blieb

- **Tempo.** 158× statt 11,5×. Der Weg dahin ist bekannt und wurde bewusst nicht
  mehr in dieser Runde gegangen: **Vorcodierung** (den Bytecode einmal in eine
  Befehlskette mit aufgelösten Sprungzielen und Operanden übersetzen, wie wasm3)
  brächte den größten Einzelgewinn. Danach bliebe die Prüflast von Firn als
  Untergrenze — die 37× gegen den C-Kern sind nicht wegzuoptimieren, solange jede
  Addition eine Überlaufprüfung trägt.
- **18 WASI-Funktionen** (Liste oben), darunter die vier `sock_*`. Erst damit
  laufen WASM-Programme mit Netz.
- **`fd_readdir`** fehlt: ein Programm kann kein Verzeichnis auflisten.
- **Threads** (`wasi-threads`) gar nicht; `memory.atomic.*` ebenfalls nicht.
- **Kein Validierer im Sinne der Spezifikation.** Der Deuter prüft Form und
  Grenzen, nicht Typen. Ein böswillig verbogenes Modul kann ihn zu Unsinn bringen
  — nicht aus seinem linearen Speicher heraus.
- **Nicht probiert:** Lua und QuickJS als WASM (die nächsten Kandidaten der Liste),
  und die offizielle WASI-Testsuite als Ganzes.

---

## 8. Commits dieser Runde

```
dc9dd08  Schritt 0 -- Wegentscheidung mit Messung, wasm2c verworfen
cae4c00  der WASM-Deuter -- Modulparser, Stapelmaschine, WASI preview1
783ae97  umlaufendes Rechnen und der data-Durchgang -- ein Rust-Modul laeuft
0268589  path_filestat_get, Labelgrenze und die zu kleine Maschine -- SQLite laeuft durch
3039516  Sprungspeicher, path_remove_directory und EEXIST -- SQLite wiederholbar
dc145e3  Argumente ab dem Modulpfad, Leser aus der Schleife, inline abgeschaltet
```

Nicht gemergt, nicht gepusht.
