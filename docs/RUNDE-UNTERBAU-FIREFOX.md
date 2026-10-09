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

## 3. Was gebaut wurde — je Änderung Abnahme und Gegenprobe

Jede Zeile hat ihre Prüfung in `tools/unterbau/t_*.c`; die **Gegenprobe** ist dasselbe Programm auf dem Kernel von `main` (553ef06c), wo
die Prüfung scheitern muss (`fixed.txt`, Abschnitt 6 von `run.sh`).

### 3.1 Speicher: `mprotect`, `mmap` mit Deskriptor, `MAP_FIXED` — und damit `dlopen` einer fremden Bibliothek

* **`proc.page_protect`** (`kernel/sched/proc.fi`) setzt die Rechte EINER abgebildeten Seite im Seitentabelleneintrag: lesen+schreiben, nur
  lesen, **nichts** (die Seite bleibt, das Benutzerbit geht: `user_ok` — die Prüfung jedes Systemaufruf-Zeigers — sagt nein, der Prozessor
  macht beim Zugriff einen Seitenfehler, `page_drop` gibt den Rahmen weiter zurück), ausführbar. Eine Seite eines geteilten Objekts
  (`PAGE_SHARED`: Fensterpuffer, Fenstertafel), die nicht schreibbar ist, wird nie schreibbar (`-EACCES`) — das Objekt kann mit Absicht
  schreibgeschützt sein. Ein TLB-Verwerfen (`cr3` neu laden) gibt es für den laufenden Prozess; **ein Faden desselben Prozesses auf einem
  anderen Kern behält einen alten Eintrag bis zu seinem nächsten Wechsel** — ein Recht zu ENTZIEHEN wirkt dort nicht sofort (Rechte
  HINZUFÜGEN braucht auf x86 kein Verwerfen). Das ist die Lücke eines fehlenden IPI-Verwerfens und steht in der Restliste.
* **`do_mprotect`** nimmt Seiten-Bereiche an, antwortet `-ENOMEM`, wenn eine Seite nicht abgebildet ist (dann ändert sich nichts), `-EINVAL` für
  unausgerichtete Adressen und unbekannte Bits.
* **`mmap` beachtet `prot`** (`map_anon`): bisher war jede anonyme Abbildung lesbar und schreibbar. Eine `PROT_NONE`-Reservierung wird jetzt
  wirklich zu einer, ein `PROT_READ`-Bereich ist nicht beschreibbar.
* **`MAP_FIXED`** (`map_fixed`): die Seiten gehen genau an die Adresse, Vorhandenes wird ersetzt (und ist danach null). Nur INNERHALB der beiden
  Fenster, aus denen `mmap` vergibt, und nur OBERHALB ihrer Marken — unterhalb gehören die Seiten dem Vergeber, eine feste Abbildung dort
  träfe das nächste gewöhnliche `mmap`.
* **`mmap` einer regulären Datei** (`map_file`): der Kern hat weder Seitenpuffer noch Seitenfehler-Nachladen, also entstehen die Seiten
  JETZT (genullt) und werden mit einem Lesen der Datei gefüllt; was hinter dem Dateiende liegt, bleibt null. `MAP_PRIVATE` ist damit genau
  (eine Kopie, die der Prozess ändern darf). `MAP_SHARED` ist nur ein Schnappschuss und deshalb **nur lesend erlaubt**; schreibend
  antwortet es `-ENODEV` (die alte Antwort für "keine Dateiabbildung"): ein Schreiben würde nie in der Datei oder bei einem anderen Prozess
  ankommen, und eine halbe Wahrheit ist hier schlimmer als die Ablehnung.
* **Ergebnis:** `t_dl` — vorher 4 von 5 Prüfungen rot (`No such device`), jetzt **18 von 18**: Konstruktor, Relokationen, bss, `DT_NEEDED`-Kette,
  TLS in der Bibliothek (pro Faden getrennt), `dladdr`, `dl_iterate_phdr`, Fehlerfall, `dlclose` + zweites `dlopen`. `t_mem`: jede
  `mprotect`-Prüfung (Schreiben auf `PROT_READ` → `SIGSEGV`, `PROT_NONE` lesen/schreiben, `read()` in eine `PROT_NONE`-Seite → `-EFAULT`,
  Reservierung + Teil-Freigabe, W^X-Schaltung mit lauffähigem JIT-Stück, NX auf einer `RW`-Seite) steht auf **ok**.
* **Bewusst nicht gemacht:** Nachladen bei Bedarf (Seitenfehler) — das ist die größte Einzellücke dieses Bereichs (Restliste 5.1).

### 3.2 Fäden und Prozesse

* **Leichen von Fäden** (`reap_dead_threads`): ein beendeter Faden blieb als Zombie in der Aufgabentafel (32 Plätze), bis jemand `wait4` für ihn
  rief — und niemand tut das, `pthread_join` wartet auf ein Futex-Wort. Nach ~30 Fäden im Leben eines Prozesses gab `pthread_create` für immer
  `EAGAIN` (gemessen: `t_threads` `churn_64_threads`, `24_threads_at_once`, `big_stack_create`). Jetzt räumt jedes `clone` und jedes `fork` die
  fertigen Fäden der eigenen Gruppe weg.
* **`clone(CLONE_VM)` ohne `CLONE_THREAD` ist ein Prozess** (`vfork`, was musls `posix_spawn`, `system()` und `popen()` tun). Es wurde als Faden behandelt, das
  `execve` des Kindes ersetzte den Adressraum des ELTERNS, und das Kind starb am Seitenfehler (gemessen: Status `0x8e00` bei jedem
  `posix_spawn`). Jetzt: ein `fork` (Kopie des Raums, der übergebene Stapel als `rsp` des Kindes).
* **`execve` gibt die Umgebung weiter**: der Kern kennt EINEN Umgebungsblock (die Shell füllt ihn mit `SYS_OSUM_SETENV`), und `execve` ignorierte
  `envp`. Jetzt ersetzt `envp` den Block für den einen Programmstart und der alte kommt zurück. Grenzen der Argumentseite: 16 Zeichenketten,
  3584 Oktette (`WAYLAND_DISPLAY`, `XDG_RUNTIME_DIR` kommen damit an; ein Browser-Start mit vollem Umfeld NICHT, Restliste).
* **`FD_CLOEXEC` ist echt**: `F_GETFD`/`F_SETFD`, `O_CLOEXEC` bei `open`, `SOCK_CLOEXEC` bei `socket`/`accept4`, `pipe2`, `dup3`, `F_DUPFD_CLOEXEC`; ein
  Bit je Deskriptor im Wort 24 des Eintrags der Aufgabe in der `TCPU`-Tafel (das Wort, das niemand benutzt), `execve` schließt die
  markierten, `fork`/`clone` kopieren die Maske, `fd_free` löscht das Bit. Vorher blieben ALLE Deskriptoren im Kind offen: das
  Selbstpipe-Paar von `posix_spawn` hielt das Warten des Elternprozesses bis zum Ende des Kindes (gemessen: 1607 ms für ein
  Kind von 1 s) — ein `posix_spawn` eines langlebigen Programms kehrte nie zurück.
* **`wait4` meldet den Tod durch ein Signal nach POSIX** (`WIFSIGNALED`, `WTERMSIG`) — **nur für den Wartenden, der eine libc ist** (er hat seinen Fadenzeiger
  gesetzt, `T_FSBASE != 0`). Die Programme dieses Systems lesen `(status >> 8) & 255` und messen seit Runde 62 `128 + n`; für sie ändert sich nichts.
  `T_SIGLAST` Bit 8 heißt "an diesem Signal gestorben", `T_EXIT` behält die alte Zahl.
* **`read`/`write` auf eine reguläre Datei werden nicht mehr bei 4096 Oktetten gekappt** (`file_io_loop`): ein Programm, das eine Datei "auf
  einmal" liest (`read(fd, buf, st_size)` — Konfigurationsdateien, Schriften, der Kopf eines Laders), hielt die 4096 für die Datei. Pipes, Sockets und
  Terminals behalten ihre kurzen Zählungen (das ist ihr Vertrag).
* **Systemaufrufe mit einem Puffer im noch nicht gewachsenen Stapel** schlugen mit `-EFAULT` fehl (der Stapel wächst nur beim Zugriff von Ring 3);
  `user_ok` legt die Seite jetzt an, wenn sie höchstens 64 KiB unter einer vorhandenen des Stapelbereichs liegt — dieselbe Abstandsregel wie
  beim Seitenfehler.

### 3.3 Signale

* **`tkill`** (200): was `raise()` und `pthread_kill()` von musl rufen. Es fehlte — `raise(sig)` tat nichts (`-ENOSYS`, unbemerkt), während `kill(getpid(), sig)` ging.
* **`siginfo_t` und `ucontext_t` für `SA_SIGINFO`-Handler**: `rsi`/`rdx` waren 0, ein Handler, der `si->si_addr` las, stürzte ab. Jetzt trägt der
  Signalrahmen ein `siginfo_t` (Nummer, Code `SEGV_MAPERR`/`SEGV_ACCERR` aus dem Fehlercode, die Fehleradresse aus `cr2`) und ein `ucontext_t` im Layout von musl (`gregs`,
  gesperrte Maske); `rt_sigreturn` nimmt die Register AUS dem `ucontext` zurück — wer `gregs[REG_RIP]` ändert, setzt woanders fort (Fallen-Handler von JIT und wasm).
* **Ein Fehler-Handler mit `SA_SIGINFO` bleibt eingetragen** (wie unter Linux): der Kern hat ihn nach EINER Zustellung zurückgesetzt, und ein Programm, das Wächterseiten
  durch `siglongjmp` überlebt, starb beim zweiten Fehler. Einfache Handler alter Art behalten das Verhalten "gilt einmal".

### 3.4 Kleine Aufrufe, die ein großes Programm beim Start macht

`getrlimit`/`setrlimit`/`prlimit64` (die echten Tabellengrößen: 16 Deskriptoren, 32 Aufgaben), `sysinfo`, `getrusage`, `sched_getaffinity` (ein Bit je gemeldetem Kern),
`sched_setaffinity`/`sched_*scheduler`/`*param`/`get_priority_*` (die eine Richtlinie, die es gibt), `set_robust_list`, `getpriority`/`setpriority`, `fdatasync`, `pipe2`
(`O_NONBLOCK`, `O_CLOEXEC`), `dup3`, `prctl` (die Wünsche, die ein Sandbox-Programm beim Start äußert und deren Fehlschlag es übergeht: `PR_SET_NO_NEW_PRIVS`, `PR_SET_PDEATHSIG`
(ohne Wirkung, so vermerkt), `PR_GET_SECCOMP`...), `madvise` (`MADV_DONTNEED` nullt private Seiten, die Hinweise werden angenommen),
`mremap` (Verkleinern, Verschieben mit Kopie), `mlock`/`msync` (kein Auslagern, kein Zurückschreiben — "erledigt" ist die ehrliche Antwort), `F_SETFL` (`O_NONBLOCK`/`O_APPEND`)
mit `O_NONBLOCK` bei Rohr-Lesen und -Schreiben, und `read`/`write` auf einem lokalen Socket.

### 3.5 Zeit

* **`futex`-Zeitgrenzen werden eingehalten** (`FUTEX_WAIT` relativ, `FUTEX_WAIT_BITSET` absolut, Monotonuhr oder Echtzeit): `zeit` wurde ignoriert, jedes Warten mit Frist
  dauerte die vollen 10 s — ein `pthread_cond_timedwait` von 50 ms brauchte 9991 ms, und mit ihm jede Frist auf musls Warteaufrufen (`sem_timedwait`, ...).
* **`nanosleep` schläft eine Marke länger**, wie `poll` es schon tat: der Zähler steht beim Lesen mitten in der laufenden Marke, ein Schlaf von N Marken dauerte N-1 bis N;
  `usleep(30000)` maß 24,7 ms. Ein Schlaf darf nie FRÜHER enden.

### 3.6 `/proc`

`/proc/<pid>/maps` zeigt jetzt den GANZEN privaten Bereich (die erste Fassung hörte nach der ersten 2-MiB-Kachel auf: nachgeladene Bibliotheken, die `mmap`-Fenster und die
große Arena fehlten) mit den Rechten wie sie sind (`rwxp`, `---p` für `PROT_NONE`), `[stack]` und `[heap]`; eine eigene Liste der Abbildungen (VMA) gibt es nicht,
also trägt eine Abbildung KEINEN Dateinamen. `status` hat `Threads:`, `VmRSS:`, `VmSize:`; `meminfo` hat `MemAvailable:`.

