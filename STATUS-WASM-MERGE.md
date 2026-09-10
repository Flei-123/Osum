# RUNDE WASM-MERGE — SCHLEUSE-2/3 in den Hauptstand

Zweig `wasm-merge`, Arbeitsbaum `/root/osum-wasmmerge`, Basis `merge9 @ 67d487a`.
Merge-Commit `6c14349`. **Noch NICHT in `main`** — wartet auf Freigabe.

---

## 1. Bestandsaufnahme

`schleuse2` steht auf `7ecfa2c`. Gemeinsame Basis mit `merge9` ist
`c0f7151`. Von dort aus:

| Richtung | Commits |
|---|---:|
| `merge9` voraus (was schleuse2 NICHT hat) | 83 |
| `schleuse2` voraus (was hereinkommt) | 40 |

Der Zweig war also 83 Commits alt — der Hauptstand ist seit SCHLEUSE-2
deutlich weitergelaufen (ECHTHARDWARE, VEKTOR, EXPLORER2 …).

Bestätigt: im Hauptstand gab es **keinen** WASM-Teil.

### Was `schleuse2` gegenüber der Basis anfasst — 41 Dateien

**Reiner WASM-Teil (40 Dateien, alle NEU):**

| Bereich | Dateien |
|---|---|
| Laufzeit im System | `kernel/app/wasm.fi` (3355 Z., der Deuter + WASI), `kernel/app/prim.fi` (nativer Maßstab) |
| AOT-Übersetzer | `tools/wasm2firn/wasm2firn.py` (1781 Z.), `flach.py` (434 Z.), `laufzeit.fi.in` (586 Z.), `wasi_ziehen.py`, `TIEFE.md` |
| Differenzprüfung | `tools/wasm2firn/pruefung/` — 10 `.wat` + `run.sh` |
| Abnahmemodule | `wasm-module/` — 6 `.wasm` (inkl. `sqlite.wasm`), `quelle/` mit den Quelltexten, `HERKUNFT.md` mit md5 |
| Befunde | `STATUS-SCHLEUSE.md`, `STATUS-SCHLEUSE2.md`, `beleg-schleuse-*.txt` |

**Geändert (1 Datei):** `tools/install/build.sh`.

### Beifang: KEINER

Das ist der bemerkenswerte Teil der Bestandsaufnahme. `git diff merge9
schleuse2` zeigt zwar 824 Dateien Unterschied — aber das ist fast
ausschließlich **Rückstand**, nicht Beifang: Dateien, die `merge9`
inzwischen hat und `schleuse2` noch nicht kennt (`pruef/`,
`tools/explorer2/`, `tools/fremd/` …). Gegen die **gemeinsame Basis**
gemessen fasst `schleuse2` genau die 41 oben an. Es war nichts
auszusortieren.

---

## 2. Der Merge

`git merge schleuse2` — **konfliktfrei**, 41 Dateien.

Das ist kein Glück, sondern nachgerechnet: `merge9` hat seit der
gemeinsamen Basis **keine** dieser 41 Dateien angefasst
(`git diff --stat c0f7151 merge9 -- <datei>` ist für jede leer). Die
einzige gemeinsame Datei `tools/install/build.sh` war auf der
`merge9`-Seite unverändert. Es gab also nichts „durchzuwinken".

### Die eine bewusste Abweichung von `schleuse2`

`schleuse2` setzt in `tools/install/build.sh` zwei Dinge:

1. `APPS="fetch wasm prim"` — **übernommen**. Ohne das liegt
   `/bin/wasm` in keinem Abbild.
2. `--no-pass=inline` **für alle Apps** — **NICHT so übernommen.**

Zu 2: Die Messung dahinter (dev-fast 4,98 s gegen release-fast
8,21 s gegen release-fast+noinline 4,80 s) gilt dem **WASM-Deuter**,
und aus gutem Grund — er ist eine sehr lange `if/else`-Kette über die
Befehlsnummer, die das Einsetzen aus dem Befehlszwischenspeicher
drängt. Seit SCHLEUSE sind aber `jarvisd`, `konto`, `knetz`, `kjson`
u. a. als Apps dazugekommen; für die ist Einsetzen nützlich. Der
Schalter steht darum jetzt per `case` an `wasm` statt an der Schleife:

```sh
APPFLAGS=""
case "$p" in
    wasm) APPFLAGS="--no-pass=inline" ;;
esac
```

Der Deuter wird also weiter genau so gebaut, wie er gemessen wurde —
die anderen zwölf Apps aber nicht mehr ungefragt mit.

---

## 3. Der Bau

Beide geforderten Fassungen übersetzen auf x86-64, Stufe 0:

| Bau | Ergebnis | Symbole |
|---|---|---|
| `--gui on` | `5 510 620` Oktett | 5865 Symbole, 74266 Zeilen |
| `--gui off` (Server) | `4 102 980` Oktett | 4718 Symbole, 56645 Zeilen |

Beide tragen die Fassungszeile `osum 6c143498` — den Merge-Commit.

---

## 4. Funktionsnachweis

### Differenzprüfung — dasselbe Modul durch Deuter UND AOT

`tools/wasm2firn/pruefung/run.sh`:

```
  OK    arith (13 Faelle)      OK    if2 (7 Faelle)
  OK    cf (8 Faelle)          OK    mem (21 Faelle)
  OK    cf2 (5 Faelle)         OK    po
  OK    i64 (18 Faelle)        OK    schleife (4 Faelle)
  OK    tab (3 Faelle)         OK    turm (15 Faelle)

PRUEFUNG: 10 bestanden, 0 fehlgeschlagen
```

**94 Fälle, Deuter und AOT zeichengleich.**

### Die Module

Jedes einmal durch `wasm2firn` + `firnc`, jedes gegen den Deuter:

| Modul | WASM-Funktionen | Zeilen Firn | wasm2firn | firnc | Ausgabe AOT = Deuter |
|---|---:|---:|---:|---:|---|
| `hallo` | 1 | 1 496 | 0,05 s | 0,43 s | ja |
| `schleife` | 189 | 35 086 | 0,15 s | 1,39 s | ja |
| `prim` | 217 | 43 543 | 0,18 s | 1,47 s | ja |
| `dateitest` | 277 | 53 182 | 0,20 s | 1,87 s | ja¹ |
| **`sqlite`** | **1 340** | **839 086** | **2,29 s** | **33,21 s** | **ja** |

¹ nur `argv[0]` unterscheidet sich — der Deuter sieht den Modulpfad, das
übersetzte Programm seinen eigenen. Das ist richtig so.

### SQLite — der eigentliche Beweis

`sqlite.wasm` (SQLite 3.45.0 Amalgamation, unverändert vom SQLite-Team,
1 340 817 Oktett) durch den AOT-Pfad, Programm 11 112 168 Oktett:

```
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
```

`diff` gegen `beleg-schleuse2-deuter-sqlite.txt` ist **leer** —
zeichengleich mit dem Deuter-Lauf aus SCHLEUSE-2. Echte Fremdsoftware,
CREATE/INSERT/SELECT, unverändert übersetzt.

---

## 5. Messung — und wo meine Zahlen abweichen

`prim.wasm`, Grenze 2 000 000, je 5 Läufe, beste Zeit. Alle Fassungen
liefern **148933** — sonst wäre der Vergleich wertlos.
Maschine: AMD EPYC 7571, 20 Kerne. Alles läuft **nativ auf Linux**,
also auf der echten CPU — kein TCG. (Die Kernel-Selbsttests laufen
darüber hinaus unter `-accel kvm`, siehe Abschnitt 6.)

| | Zeit | gegen nativ C |
|---|---:|---:|
| nativ C (`gcc -O2`) | 624 ms | 1,00× |
| nativ Firn | 659 ms | 1,06× |
| **AOT, `--opt-level=release-safe`** | **1 117 ms** | **1,79×** |
| AOT, `--opt-level=release-fast` | 1 343 ms | 2,15× |
| AOT, `dev-fast` (Standard) | 1 835 ms | 2,94× |
| Deuter | 110 724 ms | 177,4× |

**AOT(bester) gegen Deuter: 99,1× schneller.**

### Ehrlich zu den SCHLEUSE-2-Zahlen

SCHLEUSE-2 sagt „**156×** schneller als der Deuter" und „Faktor
**2,15**". Meine Zahlen:

* **Faktor gegen nativ: bestätigt und besser.** Mit `release-fast`
  messe ich **2,15×** — exakt die Zahl aus SCHLEUSE-2. Mit
  `release-safe` sind es **1,79×**, also besser als dokumentiert.
  Die Aussage „unter 5×, auf dem Stand von `wasm2c`" hält.
* **156× gegen den Deuter: erreiche ich NICHT, ich messe 99×.**
  Die Ursache liegt nicht am AOT, sondern am **Deuter**: SCHLEUSE-2
  maß ihn mit 239 642 ms, ich messe 110 724 ms — er ist auf dieser
  Maschine **gut doppelt so schnell** wie dort. Der AOT-Wert
  (1 533 ms dort, 1 117–1 343 ms hier) liegt dagegen dicht beieinander.
  Der Quotient schrumpft also, **weil der Nenner besser wurde**, nicht
  weil der AOT schlechter ist. Beide Runden maßen auf verschiedener
  Hardware; die Absolutzahlen sind darum nicht vergleichbar, die
  Faktoren nur bedingt.

**Belastbar ist:** AOT liegt bei **1,79–2,15×** gegen nativen C-Code
und ist **rund 100×** schneller als der Deuter. Die Größenordnung der
Aussage von SCHLEUSE-2 stimmt; die genaue Zahl 156 ist
maschinenabhängig und ich kann sie nicht reproduzieren.

### Nebenbefund: die Optimierungsstufe für den AOT ist eine andere als für den Deuter

Gemessen am erzeugten `prim.fi`:

| Stufe | firnc | Laufzeit |
|---|---:|---:|
| `dev-fast` | 1,56 s | 1 768 ms |
| `release-fast --no-pass=inline` | 1,76 s | 1 976 ms |
| `release-fast` | 35,35 s | 1 374 ms |
| `release-safe` | 33,67 s | **1 084 ms** |

Für **erzeugten** Code ist `--no-pass=inline` also **schädlich** (1 976
gegen 1 374 ms) — genau umgekehrt zum Deuter. Das ist ein zusätzliches
Argument dafür, den Schalter nicht pauschal zu setzen (Abschnitt 2).
`release-safe` schlägt hier sogar `release-fast`; der Grund ist nicht
untersucht.

---

## 6. Keine Verschlechterung — Vorher/Nachher

15 Kernabschnitte unter `-accel kvm`, `OSUM_JOBS=6`. Sechs Abschnitte
meldeten Fehler. **Alle sechs sind vorbestehend** — nachgewiesen durch
denselben Lauf auf `67d487a`, dem Stand OHNE meinen Merge, in einem
eigenen Worktree `/root/osum-wasmvor`:

| Abschnitt | NACHHER (mit Merge) | VORHER (ohne Merge) | Urteil |
|---|---|---|---|
| `userland` | 88 ✓ / 3 ✗ | 88 ✓ / **3 ✗ (dieselben)** | vorbestehend |
| `osum` | 6 ✗ | **9 ✗** | vorbestehend, vorher schlechter |
| `posix` | 148 ✓ / 2 ✗ | 148 ✓ / **2 ✗ (dieselben)** | vorbestehend |
| `pci` | 1 ✗ (DMA 1070) | 1 ✗ (**DMA 833**) | vorbestehend, vorher schlechter |
| `server` | 21 ✓ / 2 ✗ | 21 ✓ / **2 ✗ (dieselben)** | vorbestehend |
| `handle` | 1 ✗ (getpid 454 Zyklen) | **80 ✓ / 0 ✗** | Lastwackler¹ |

¹ `handle` fiel nur im parallelen Lauf durch, und zwar an einer
Zyklenmessung (`getpid` 454 statt < 450 Zyklen, also 1 %). Seriell
gelaufen ist er grün. Die Zusage misst Zyklen und ist unter sechs
gleichzeitigen QEMUs nicht stabil.

Grün in beiden Ständen: `freestanding` (41), `core` (46), `unix` (107),
`async` (108), `caps` (67), `guard`, `smp`, `net`, `kernel`.

Die zwei inhaltlichen Vorbefunde, damit sie nicht untergehen — beide
haben mit WASM nichts zu tun:

* `posix`: `SYS_OSUM_DHCPST` steht im Kernel (1302), fehlt in der libc.
* `server`: 15 Stellen außerhalb von `kernel/gfx.fi` greifen noch auf
  die Grafik zu.

**Ergebnis: der Merge verschlechtert nichts.** Er verbessert auch
nichts an diesen Tests — er berührt sie nicht.

---

## 7. Bewertung: wie weit ist der WASM-Pfad wirklich?

### Was steht

Der Pfad **Rust → WebAssembly → Firn → Osum-Programm** funktioniert
Ende zu Ende und ist an echter Fremdsoftware belegt, nicht an
Spielzeug: SQLite 3.45.0, 1 340 Funktionen, unverändert, mit
zeichengleicher Ausgabe. Das Tempo (1,8–2,2× nativ) ist auf dem Stand
von `wasm2c` und für Anwendungscode unproblematisch.

Die Werkzeugkette ist schnell genug für den Alltag: `wasm2firn` braucht
für SQLite 2,3 s, `firnc` 33 s (unoptimiert) bzw. ~35 s
(`release-fast`).

### WASI: 38 von 46 Funktionen

Umgesetzt sind `args_*`, `environ_*`, `clock_*`, `fd_read/write/seek/
tell/close/sync/datasync/advise/renumber/readdir/fdstat_*/filestat_*/
prestat_*`, `path_*` (open, create_directory, remove_directory,
unlink_file, rename, link, symlink, readlink, filestat_get,
filestat_set_times), `poll_oneoff`, `proc_exit`, `proc_raise`,
`sched_yield`, `random_get`.

**Es fehlen acht:**

| fehlt | Folge | Aufwand |
|---|---|---|
| `fd_pread`, `fd_pwrite` | **die wichtigste Lücke.** SQLite braucht sie, sobald die Datenbank größer wird als der Seitenpuffer — dann liefert ein Bench 0 Zeilen, in Deuter und AOT gleichermaßen | **gering.** SCHLEUSE-2 notiert „Osum hat kein pread/pwrite" — das stimmt **nicht mehr**: `kernel/sys.fi` hat `SYS_PREAD64 = 17` und `SYS_PWRITE64 = 18` (Runde LAUFZEIT). Es ist nur noch Verdrahtung im Deuter |
| `fd_allocate`, `fd_filestat_set_size` | kein `ftruncate` | mittel, braucht einen Kernel-Syscall |
| `fd_fdstat_set_rights` | Rechte-Einschränkung je Deskriptor | gering, meist unkritisch |
| `sock_accept`, `sock_recv`, `sock_send`, `sock_shutdown` | **kein Netz aus WASM heraus** | mittel. Der Kernel hat den ganzen Unterbau: `SYS_SOCKET 41`, `BIND 49`, `LISTEN 50`, `ACCEPT 43`, `CONNECT 42`, `SENDTO 44`, `RECVFROM 45`. Es fehlt der Deskriptorweg im Deuter, nicht der Stapel |

### Für Justins Ökosystem — was ein größeres Rust-Programm braucht

| Bedarf | Stand |
|---|---|
| **Dateien** | ✅ da, bis auf `pread`/`pwrite` und `ftruncate` |
| **Zeit** | ✅ `clock_time_get`, `clock_res_get` |
| **Zufall** | ✅ `random_get` |
| **Argumente/Umgebung** | ✅ |
| **Warten auf mehreres** | ✅ `poll_oneoff` |
| **Netz** | ❌ **die vier `sock_*` fehlen.** Der Kernel kann es, WASI erreicht es nicht |
| **Fäden** | ❌ **gar nicht da.** `wasi-threads` ist im Deuter nicht vorgesehen (kein Treffer auf `thread`). Der Kernel hätte `SYS_CLONE 56` und `SYS_FUTEX 202` (Runde FREMDLAND), aber WASM-seitig fehlt das Modell: `wasi-threads` braucht geteilten linearen Speicher (`shared memory`) und Atomics, und beides muss der **Übersetzer** erst können |

### Ehrliche Einschätzung

**Für FreeViewer bzw. einen Messenger-Kern reicht das heute noch nicht** —
aber die Lücke ist kleiner, als sie aussieht, und sie ist ungleich
verteilt:

1. **`fd_pread`/`fd_pwrite`** — kleinste Lücke mit der größten Wirkung.
   Der Syscall ist da, es ist Verdrahtungsarbeit. Danach läuft SQLite
   mit großen Datenbanken. **Das ist der nächste Schritt.**
2. **Die vier `sock_*`** — überschaubar, weil der TCP/IP-Stapel und alle
   Syscalls schon stehen. Ohne sie ist alles Netzbasierte (Messenger!)
   ausgeschlossen. **Danach.**
3. **Fäden** — die einzige echte Baustelle. Das ist keine
   Verdrahtungsarbeit, sondern eine Erweiterung des Übersetzers
   (geteilter Speicher, Atomics) plus ein Fadenmodell in der Laufzeit.
   Umgehbar, solange man einfädig baut — für einen Messenger-Kern mit
   `poll_oneoff` durchaus machbar.

Anders gesagt: Punkte 1 und 2 sind Fleißarbeit auf vorhandenem
Unterbau, Punkt 3 ist eine eigene Runde. Ein einfädiges Rust-Programm,
das Dateien und Netz benutzt, ist nach 1+2 realistisch.

---

## 8. Offene Punkte

* `wasm-merge` ist **nicht** in `main` — wartet auf Freigabe.
* Der Bau des festgenagelten `firnc` scheiterte zunächst, weil die
  Platte zu 98 % voll war (1,3 GB frei). Behoben durch Aufräumen des
  Cargo-Registry-Caches und alter `/tmp`-Reste; danach wurde der
  bereits gebaute `firnc` desselben Commits (`a751b3db`) aus
  `osum-merge9` übernommen. **Die Platte bleibt eng (~3 GB frei)** —
  das trifft jede Runde, nicht nur diese.
* `fd_pread`/`fd_pwrite` sind der nächste sinnvolle Schritt; die
  Bemerkung „Osum hat kein pread/pwrite" in
  `STATUS-SCHLEUSE2.md`/`kernel/app/wasm.fi` ist überholt.
* Die Selbsttests wurden auf 15 Kernabschnitte begrenzt, nicht auf alle
  73. Für die Frage „verschlechtert der Merge etwas?" reicht das, weil
  der Merge nur neue Dateien bringt; eine volle Abnahme steht aus.
