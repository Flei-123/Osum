# Runde UNTERBAU — was Firefox und LibreOffice vom Unterbau wollen, und was OrientOS davon hat

Zweig `unterbau`, Grundlage `main` = 553ef06c (09.10.2026). Teil A der Wayland-Fortsetzung: Ziel langfristig **Firefox und LibreOffice auf
OrientOS**. Diese Runde baut keinen Browser; sie misst, was ein Programm dieser Größe unter der Haube braucht, behebt die billigsten
Lücken und schreibt die ehrliche Restliste hin.

@@KURZ@@

---

## 1. Messwerkzeug — `tools/unterbau/`

Jede Behauptung unten steht auf einer Messung, und jede Messung ist ein **echtes kleines C-Programm** (musl, dynamisch gelinkt wie
Firefox: `PT_INTERP` + `libc.so`), das unter OrientOS in QEMU/KVM läuft und je Prüfpunkt eine Zeile `T <test>.<check> PASS|FAIL|GAP <Detail>`
druckt (`PASS` geht, `FAIL` falsche Antwort, `GAP` Aufruf/Datei fehlt). **Ein Boot je Programm**: ein Absturz oder Hänger in einem Test
verdeckt die anderen nicht.

| Programm | prüft |
|---|---|
| `t_dl` | `dlopen` fremder `.so` **aus Dateien** (Konstruktor, Relokationen, bss, `DT_NEEDED`-Kette, TLS in der Bibliothek, `dladdr`, `dl_iterate_phdr`, `dlclose`, Fehlerfall) |
| `t_mem` | `mmap`/`mprotect`/`madvise`/`mremap`/`munmap`/`MAP_FIXED`, Datei-Abbildungen, W^X, Wächterseiten (`SIGSEGV` als Zeuge) |
| `t_threads` | pthreads auf `clone`/`futex`: create/join, Mutex, Condvar, TLS, Schlüssel, Semaphore, Barrier, Once, große Stapel, 64er Wechsel, 24 gleichzeitig |
| `t_proc` | `fork`, `execve` (Argumente, Umgebung, umgeleitete Ein-/Ausgabe), `wait4` (Status, `WNOHANG`, `ECHILD`), `posix_spawn`, `system`, `popen`, Signaltod im Status |
| `t_events` | `pipe2`, `poll`, `select`, `epoll`, `eventfd`, `timerfd`, `signalfd`, `socketpair` + Deskriptorübergabe (`SCM_RIGHTS`), benannte AF_UNIX-Sockets, `inotify`, `ppoll` |
| `t_signals` | `sigaction`, Masken, `raise`/`kill`/`pthread_kill`, `SIGSEGV` mit `si_addr`, `sigaltstack`, `SIGALRM`/`setitimer`, `SIGCHLD`, Standardwirkungen |
| `t_procfs` | `/proc/self/*`, `/proc/cpuinfo`, `/proc/meminfo`, `/sys/devices/system/cpu`, die Pfade, die ein Programm erwartet (`/dev/shm`, `/etc/ssl`, `/dev/urandom` ...), `memfd` |
| `t_malloc` | malloc über Fadengrenzen: Last, Fremd-Freigabe, realloc, große Blöcke, wo das Ende erreicht ist |
| `t_misc` | `sched_getaffinity`, `getrandom`, `prctl`, Uhren, `getrlimit`, `sysinfo`, Dateioperationen (`ftruncate`, `symlink`, `flock` ...), Zeitgeber |
| `t_limits` | die **Tabellengrößen** des Kerns gegen das, was ein Browser braucht |

Dazu `libub1/2/3.so` (die fremden Bibliotheken), `c_child` (das Kindprogramm von `t_proc`) und vier STATISCHE Programme aus
`tools/foreign` (`hello`, `threads`, `forktest`, `locktest`) als Regression des alten Wegs.

**Die Tests selbst sind geprüft:** jedes `t_*.c` läuft zuerst nativ auf dem Linux-Wirt (musl) und besteht dort — ein Test, der auf Linux
fehlschlägt, misst nichts über OrientOS. (Ausnahmen, vom Wirt: zwei `sched_*`-Aufrufe fehlen im Container.)

    /root/jarvis/bin/heavy bash tools/unterbau/run.sh                    # alle Programme, Tabelle, Gate
    ONLY="t_mem t_dl" bash tools/unterbau/run.sh                         # eine Auswahl
    OLDK=<Kernel von main> bash tools/unterbau/run.sh                    # dazu die Gegenproben auf dem alten Kernel

`accept.txt` (jede Prüfung, die heute geht und nicht vom Zeitgeber abhängt — **was heute geht, muss weitergehen**) und `fixed.txt` (jede
Prüfung, die auf dem Kernel von vorher NICHT bestand und jetzt besteht) erzeugt `mkgate.py` aus zwei Läufen. Die Gegenprobe ist damit
dieselbe Binärdatei auf dem alten Kernel: sie muss dort scheitern, sonst misst die Prüfung nichts.

---

## 2. Die offenen Punkte aus `RUNDE-DYNLADER.md` Kap. 10, gegen Firefox bewertet

Zuerst wurde `tools/dynlader/run.sh` über `heavy` gefahren: **36 bestanden, 0 gescheitert** (die Aufgabe nannte 28; seit der Runde sind die
Abschnitte 8 und 9 — Paket, Modularität — dazugekommen).

| Punkt | Für Firefox | Entscheidung |
|---|---|---|
| **`mmap` nur `MAP_ANONYMOUS`** — kein `dlopen("datei")` | **blockiert.** Firefox lädt ~40 Bibliotheken plus `libxul` über den Lader; jede ist ein `open` + `mmap` mit Deskriptor + `MAP_FIXED`. | **behoben** (3.1). `dlopen` einer fremden `.so` läuft. |
| **`mprotect` antwortet 0 ohne Wirkung** | **blockiert für Sicherheit und Funktion:** JIT (W^X), Wächterseiten der Fadenstapel, die der Allokator und die JS-Engine als `PROT_NONE`-Reservierung anlegen, RELRO. Ohne Wirkung ist jede Wächterseite lesbar und ein Stapelüberlauf läuft in den Nachbarn. | **behoben** (3.1) — samt `mmap`, das bis dahin `prot` ignorierte (jede anonyme Abbildung war lesbar und schreibbar). |
| **`INTERP_BASE` fest** | betrifft nur einen **zweiten Interpreter**. Firefox hat einen (musl/glibc-Lader); weitere Bibliotheken lädt dieser selbst per `mmap` an Adressen, die der Kern vergibt. | **nicht nötig**, bleibt. |
| **geteilte Seite bekommt die Rechte des ersten Segments** | nur bei Programmen, bei denen ein RO-Segment und das folgende RW-Segment sich eine Seite teilen. Gemessen: `ld-musl` und `hello_dyn` legen die Segmente auf getrennte Seiten (`0x40aaa8bc` / `0x40aabb20`). Die Binärdatei von Firefox lag nicht vor; GNU ld und lld mit 4-KiB-Seiten trennen sie ebenso. | **bleibt offen**, Risiko klein; Lösung wäre die Vereinigung der Rechte (widerspricht Regel 3 der `elf.fi`) und gehört mit eigener Gegenprobe in eine eigene Runde. |

