# Runde UNTERBAU — was Firefox und LibreOffice vom Unterbau wollen, und was OrientOS davon hat

Zweig `unterbau`, Grundlage `main` = 553ef06c (09.10.2026). Teil A der Wayland-Fortsetzung: Ziel langfristig **Firefox und LibreOffice auf
OrientOS**. Diese Runde baut keinen Browser; sie misst, was ein Programm dieser Größe unter der Haube braucht, behebt die billigsten
Lücken und schreibt die ehrliche Restliste hin.

## 0. Kurzfassung

* **`tools/dynlader/run.sh` über `heavy`: 36 bestanden, 0 gescheitert** (die Aufgabe nannte 28; seit der Runde kamen Paket-/Modularitätsabschnitte dazu).
* **`dlopen` einer fremden `.so` aus einer Datei läuft** (`t_dl` 18 von 18; vorher `No such device`), und **`mprotect` wirkt wirklich** (Wächterseiten, W^X, `PROT_NONE`; `mmap` beachtet `prot`).
* **Gemessen: 315 Prüfungen in 10 echten C-Programmen. Kernel von `main` vorher: 144 ok / 73 FAIL / 62 GAP (279 erreicht — Abstürze verdecken den Rest). Jetzt: 249 ok / 26 FAIL / 40 GAP.**
* Behoben in dieser Runde (je mit Abnahme und Gegenprobe, Kap. 3): `mprotect`/`mmap`-Rechte, `mmap(fd)`, `MAP_FIXED`, Leichen von Fäden (nach ~30 Fäden ging `pthread_create` nie wieder),
  `posix_spawn`/`system`/`popen` (`vfork`), `execve`-Umgebung, `FD_CLOEXEC`, `siginfo`/`ucontext`, `tkill` (`raise`), `futex`-Fristen, `nanosleep`, `read`/`write` auf Dateien > 4096 Oktette,
  Stapelpuffer in Systemaufrufen, `wait4`-Signalstatus, `select`/`ppoll`/`pselect6`, `socketpair`, `read`/`write` auf lokalen Sockets, `getrlimit`/`sysinfo`/`sched_getaffinity`/`madvise`/`mremap`/`pipe2`/`dup3`/`prctl` u. a., `/proc/*/maps|status|meminfo`.
* **Gates auf dem Stand der Runde** (alle über `heavy`): dynlader 36/0, wm 110/0, k15 259/0, a11y 58/0, alltag 45/0, wayland 45/0, lockseal 43/0, unix 107/0, posix 149/1 (die eine Rote ist **auf `main` schon rot**: drei eigene Systemaufruf-Nummern fehlen in `lib/libc/kcall.fi`), foreign (statisch, `hello`/`threads`/`forktest`/`locktest`) 4/4.
* **Was Firefox NICHT startet, steht in Kap. 5.1: Adressraum ~198 MiB, kein Nachladen bei Bedarf, 16 Deskriptoren je Prozess / 64 offene Dateien / 32 Aufgaben, Rohr 512 Oktette, Stapel ~500 KiB.** Das sind Layoutfragen des Kerns, keine fehlenden Aufrufe — und die größte Arbeit der nächsten Runden.


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

---

## 4. Die Messung

| Programm | Kernel von `main` (ok / FAIL / GAP) | jetzt | Rest |
|---|---|---|---|
| `t_dl` | 1 / 4 / 0 | **18 / 0 / 0** | — |
| `t_mem` | 19 / 11 / 10 | **44 / 1 / 3** | `MAP_SHARED` auf Datei (`ENODEV`), Reservierungen 256 MiB/1 GiB (Adressraum), `pread` > 4096 |
| `t_threads` | 11 / 3 / 0 | **20 / 1 / 0** | Deskriptortabelle je Faden kopiert |
| `t_proc` | 12 / 9 / 0 | **19 / 2 / 0** | `system()`/`popen()`: `/bin/sh` ist die Osum-Shell (kein POSIX-`-c`), mit busybox als `/bin/sh` zu prüfen |
| `t_signals` | 7 / 14 / 2 | **16 / 5 / 2** | `setitimer` (damit `alarm`), `sigsuspend`, `sigaltstack`, `SIGCHLD`-Auto-Abräumen |
| `t_events` | 8 / 5 / 9 | **21 / 1 / 7** | `epoll`, `eventfd`, `timerfd`, `signalfd`, `inotify`, `socketpair(DGRAM)`, `recv` auf lokalem Socket |
| `t_misc` | 42 / 10 / 16 | **61 / 6 / 3** | `ftruncate` auf Dateien, `flock`, `dup3` > 15, `posix_fallocate`, `prctl(PR_GET_NAME)`, `RLIMIT_NOFILE` 16 |
| `t_procfs` | 33 / 9 / 25 | **38 / 4 / 25** | Pfade/Dateien fehlen im Abbild (Kap. 5.3), `cpuinfo`-Felder, `/sys` |
| `t_malloc` | 11 / 0 / 0 | **11 / 0 / 0** | — (siehe 5.4) |
| `t_limits` | 0 / 8 / 0 | **1 / 6 / 0** | die Tabellengrößen, Kap. 5.1 |


Alle Zeilen, die auf BEIDEN Kernen bestehen, sind nicht aufgeführt; der Anhang A hat sie. Wichtig fürs Lesen:

* **`GAP`** heißt: der Aufruf oder die Datei FEHLT (`ENOSYS`, `ENOENT`, `ENODEV`). **`FAIL`** heißt: der Aufruf ist da und antwortet falsch — oder die Tabelle ist
  kleiner, als ein Browser sie braucht (`t_limits`): auch das ist ein Messwert und kein Fehler im Aufruf.
* Der **Fehlschlag auf dem alten Kernel** ist die Gegenprobe: dort bestehen diese Prüfungen nicht, hier schon.

---

## 5. Die Lücken, nach Aufwand und Nutzen — und was Firefox davon wirklich blockiert

Reihenfolge = was zuerst fehlt, damit überhaupt ein Browser-Prozess startet. Aufwand: **S** ein Nachmittag, **M** eine Runde, **L** mehrere Runden / berührt das Kernlayout.
Nutzen: **0** ohne das startet nichts, **1** ohne das geht es nur eingeschränkt, **2** Bequemlichkeit / Leistung.

### 5.1 Strukturgrenzen des Kerns (alle mit Messwert aus `t_limits`)

| Lücke | Messwert | Aufwand | Nutzen |
|---|---|---|---|
| **Adressraum ~198 MiB** je Prozess (`0x40000000`–`0x4C600000`, dazu 2-MiB-Kacheln des Rahmenpuffers); `0x50000000` MUSS der Lader ablehnen (`tools/osum`) | 185 MiB anonymer Speicher in 1-MiB-Stücken, **0 MiB** `PROT_NONE`-Reservierung (256 MiB scheitern). `libxul.so` allein ist über 100 MiB, JS-Engine und Allokator reservieren GiB. | **L** (PDPT/PML4 statt einem PD, anderes Zeiger-Layout, die Gate-Regel von `tools/osum` ändern) | **0** |
| **Kein Nachladen bei Bedarf, kein Seitenpuffer**: `mmap` einer Datei liest sofort alles, `fork` kopiert JEDE Seite, `MAP_SHARED` auf Dateien nicht möglich | `dlopen` einer 10-MiB-Bibliothek kostet 10 MiB Kopie + Lesezeit; ein `fork` von 100 MiB kopiert 100 MiB | **L** (Seitenfehler-Pfad der Datei, Rahmenzähler, Kopie-beim-Schreiben) | **0** |
| **Tabellen**: 32 Aufgaben, **16 Deskriptoren je Prozess**, **64 offene Dateien** für das ganze System, 32 lokale Sockets, 40 Speicherobjekte, **Rohr 512 Oktette**, 31 Signale | 13 Deskriptoren frei; 28 Fäden gleichzeitig; Rohr nimmt 512 Oktette statt 65536 | **L** (`kdata`-Layout: feste Offsets; jede Tabelle wandert mit) | **0** |
| **Stapel ~500 KiB** (`0x40001000`–`0x4007F000`) | 100 Rahmen zu 4 KiB, dann Schluss; Linux: 8 MiB | **M** (Arena umlegen, `BRK_BASE` darüber) | **1** |
| **Dateigröße**: ein `write` von 8 MiB nach `/tmp` bricht nach ~2 MiB mit `ENOSPC` ab (OFS v3-Abbild, 98304 Blöcke) | siehe `t_limits.file_8mib_write` | **M** | **1** |

### 5.2 Fehlende Aufrufe — Ereignisse und IPC (Firefox: Chromium-IPC, glib-Hauptschleife, Netz)

| Lücke | Aufwand | Nutzen |
|---|---|---|
| `epoll_create1/ctl/wait` — baut auf `poll_ready` und derselben Weckfolge wie `poll` auf; je Epoll-Objekt eine kalloc-Tabelle, neue Dateiart | **M** | **0** |
| `eventfd2`, `timerfd_*`, `signalfd4` — kleine Dateiarten mit Zähler/Frist/Signalmaske, in `poll_ready` einzuhängen | **S–M** je | **0** (libevent, glib) |
| `socketpair` für `AF_UNIX/SOCK_DGRAM`, `SOCK_SEQPACKET` (hier gibt es nur Ströme); `recvfrom`/`sendto` auf lokalen Sockets | **S** | **1** |
| `inotify_*` | **M** (nur Dateimonitor) | **2** (Firefox fällt zurück) |
| `AF_INET`-Socket im Testlauf `ENODEV` (nur mit dem Netz-Wort `bus` aufgebaut) — kein Kernproblem, der Testlauf bootet ohne Netz | — | — |
| Signale: **`NSIG = 32`** (keine Echtzeitsignale: musl braucht 32/33 für `pthread_cancel`/`setuid`), **`sigaltstack`**, **`sigsuspend`**, **`setitimer`** (musls `alarm()` ruft `setitimer` — `alarm` geht deshalb NICHT), `SIG_IGN` auf `SIGCHLD` räumt Kinder nicht ab | **S–M** | **0–1** |
| `futex` ohne Warteschlange: ein Wartender fragt alle 10 ms nach, `FUTEX_WAKE` weckt „niemanden" (zählt 0), kein `REQUEUE`/`WAKE_OP`/`PI` | **M** | **1** (Latenz und Leerlauflast mit vielen Fäden) |

### 5.3 Prozesse und Dateien

| Lücke | Aufwand | Nutzen |
|---|---|---|
| **Deskriptortabelle ist je Faden kopiert, nicht geteilt** (`CLONE_FILES` fehlt): ein Faden, der NACH dem Start eines anderen eine Datei öffnet, sieht der andere nicht (`t_threads.fd_table_shared_between_threads`) | **M** (Tabelle je Prozess statt je Aufgabe) | **0** |
| `execve`: höchstens 8 Argumente, 16 Umgebungsvariablen / 3584 Oktette (Kernblock) — ein Browser startet Kinder mit mehr | **M** (Argumentseite umlegen: ABI der Osum-Programme!) | **1** |
| Fäden und Prozesse: `PR_GET_NAME`/`PR_SET_NAME` ohne Namensfeld, `PR_SET_PDEATHSIG` ohne Wirkung | **S** | **2** |
| Dateisystem: `ftruncate` nur auf Speicherobjekten, `symlink`/`readlink`/`utimensat` gehen nicht, `flock`, `statfs`, `posix_fallocate`; `/dev/shm`, `/dev/pts`, `/dev/dri` fehlen (`memfd_create` geht — Firefox nimmt es) | **M** (Dateisystem OFS) | **1** |
| Dateien, die ins Abbild gehören (Paketfrage, nicht Kern): `/etc/ssl/certs`, `/etc/resolv.conf`, `/etc/localtime`, `/usr/share/zoneinfo`, `/usr/share/fonts`, `/etc/fonts/fonts.conf`, `/etc/machine-id` | **S** | **1** |
| `/proc`: `maps` ohne Dateinamen (keine VMA-Liste), `cpuinfo` ohne `model name`/`flags`, `loadavg`, `self/exe`, `self/limits`, `/sys/devices/system/cpu/*`, `/proc/sys/*` | **S** je | **2** |
| `mprotect` entzieht Rechte auf anderen Kernen erst beim nächsten Kontextwechsel (kein IPI-Verwerfen) | **M** | **1** (JIT-Sicherheit) |
| `MAP_SHARED` auf einer regulären Datei: `-ENODEV` (kein Seitenpuffer) | **L** (mit 5.1) | **1** (SQLite-WAL, geteilte Dateien) |
| `malloc` unter Fäden: siehe 5.4 | — | — |

### 5.4 Was die Messung NICHT erklärt hat — die ehrliche Restliste

* **`t_malloc` ist ein ungeklärter Befund.** In den ersten Läufen (OFS-v2-Abbild, frühere Testfassung) schlug `mt_stress_integrity` auf `main` UND auf dem frühen Zweig-Kernel mit Tausenden von `NULL`/Verfälschungen je Faden an,
  ebenso `realloc` von 5 → 9 MiB und 50 000 kleine Blöcke. Im Endlauf (v3-Abbild, Testfassung mit Diagnose-Prüfungen davor) besteht alles — **auch auf `main`**. Was den Unterschied macht (Abbildformat, Reihenfolge der
  Prüfungen, die Speicherlage nach den Diagnose-Läufen), wurde nicht eingegrenzt; die Prüfungen stehen in `accept.txt` und fangen es, falls es wiederkommt. Auf Linux besteht alles.
* **Nicht gemessen** (hier gab es keinen Browser, und die Prüfungen sind Stellvertreter): die Startzeit von `libxul` (Kopie statt Nachladen), Grafik/Audio (kein GPU-Treiber, `dmabuf`), Netz-Sandbox, die
  Last von hundert Fäden (der Kern hat 32 Aufgaben), `fork` großer Prozesse. Der Dynamik-Lader selbst wurde nur mit `hello`, busybox und den `libub*`-Bibliotheken geprüft, nicht mit einer Bibliothek von 100 MiB.
* **Sicherheit:** das Entziehen eines Rechts (`mprotect` auf `PROT_NONE`/`PROT_READ`) wirkt auf einem ANDEREN Kern erst beim nächsten Kontextwechsel (Kap. 3.1); die Tabellengrenzen (Kap. 5.1)
  schützen den Kern vor einem Prozess, der sie ausreizt — sie zu heben heißt, `kdata` neu zu zeichnen und die Gegenproben (`nobigmem`, `norights`, ...) mitzunehmen.
* **Billig und als nächstes zu tun** (jeweils eine kleine Änderung, die diese Runde bewusst nicht mehr angefasst hat, um die Gates auf einem festen Stand zu fahren): `recvfrom`/`sendto` auf lokalen Sockets
  (`recv` auf einem `socketpair`), `pread`/`pwrite` ohne 4096er-Kappung, `setitimer`/`getitimer` (musls `alarm()` ruft `setitimer`), `sigsuspend`, `/proc/self/exe`, `cpuinfo`-Felder.


---

## 6. Nachbauen

    # Wirt braucht: musl-gcc, qemu-system-x86_64, python3 (Pillow nur für report)
    /root/jarvis/bin/heavy bash tools/unterbau/run.sh                       # alle Programme auf dem Kernel dieses Baums
    OLDK=<Kernel von main> /root/jarvis/bin/heavy bash tools/unterbau/run.sh # + Gegenproben (fixed.txt)
    REGEN=1 OLDK=<Kernel von main> ... run.sh                                # accept.txt / fixed.txt neu schreiben

---

## Anhang A — alle Prüfungen, die sich geändert haben oder nicht bestehen

Erzeugt mit `tools/unterbau/report.py` aus zwei Läufen derselben Programme: Kernel von `main` (553ef06c) und Kernel dieses Zweigs.
Eine Zeile mit `-` in der Spalte „main" heißt: dort wurde die Prüfung nie erreicht (ein früherer Absturz oder Hänger).

### `t_dl` -- main: 1 ok / 4 FAIL / 0 GAP, now: 18 ok / 0 FAIL / 0 GAP

| check | main | now | what the run said |
|---|---|---|---|
| open1 | FAIL | ok |  |
| sym_add | - | ok |  |
| call_add | - | ok |  |
| ctor | - | ok |  |
| reloc_ptr | - | ok |  |
| bss_zero_and_rw | - | ok |  |
| data_rw | - | ok |  |
| libc_in_lib | - | ok |  |
| dladdr | - | ok |  |
| iterate_phdr | - | ok |  |
| open2_needed | FAIL | ok |  |
| call_across | - | ok |  |
| open3_tls | FAIL | ok |  |
| tls_main | - | ok |  |
| tls_per_thread | - | ok |  |
| close | - | ok |  |
| reopen | FAIL | ok |  |

### `t_events` -- main: 8 ok / 5 FAIL / 9 GAP, now: 21 ok / 1 FAIL / 7 GAP

| check | main | now | what the run said |
|---|---|---|---|
| pipe_cloexec | FAIL | ok |  |
| pipe_o_nonblock_flag | FAIL | ok |  |
| select_ready_pipe | FAIL | ok |  |
| epoll_create1 | GAP | GAP | errno=38 Function not implemented |
| eventfd | GAP | GAP | errno=38 Function not implemented |
| timerfd_create | GAP | GAP | errno=38 Function not implemented |
| signalfd | GAP | GAP | errno=38 Function not implemented |
| socketpair_stream | GAP | ok |  |
| socketpair_roundtrip | - | ok |  |
| socketpair_recv | - | FAIL | recv -> -1 |
| scm_rights_sendmsg | - | ok |  |
| scm_rights_recvmsg | - | ok |  |
| scm_rights_fd_works | - | ok |  |
| socket_poll_empty | - | ok |  |
| socket_peer_close_seen | - | ok |  |
| socketpair_dgram | GAP | GAP | errno=93 Protocol not supported |
| unix_stream_data | FAIL | ok |  |
| unix_client_exit | FAIL | ok |  |
| tcp_socket | GAP | GAP | errno=19 No such device |
| inotify_init | GAP | GAP | errno=38 Function not implemented |
| ppoll | GAP | ok |  |

### `t_limits` -- main: 0 ok / 8 FAIL / 0 GAP, now: 1 ok / 6 FAIL / 0 GAP

| check | main | now | what the run said |
|---|---|---|---|
| fds_per_process | FAIL | FAIL | 13 descriptors open at once (errno 24); a browser wants >= 256 |
| threads_at_once | FAIL | FAIL | 28 threads alive at once (errno 24); a browser wants >= 64 |
| processes_at_once | FAIL | ok | 28 processes alive at once; a browser wants >= 16 |
| committed_mib | FAIL | FAIL | 185 MiB of anonymous memory in 1 MiB maps; a browser wants >= 256 MiB of address space |
| reserved_mib | FAIL | FAIL | 0 MiB of PROT_NONE reservations; JS engines and allocators reserve GiB |
| stack_depth_4k_frames | FAIL | FAIL | recursion depth 100 x 4 KB (400 KB of stack) before the stack ended; a browser wants 8 MiB |
| pipe_capacity | FAIL | FAIL | 512 bytes fit into a pipe before the writer must wait; Linux: 65536 |
| file_8mib_write | FAIL | - |  |

### `t_malloc` -- main: 11 ok / 0 FAIL / 0 GAP, now: 11 ok / 0 FAIL / 0 GAP

| check | main | now | what the run said |
|---|---|---|---|

### `t_mem` -- main: 19 ok / 11 FAIL / 10 GAP, now: 44 ok / 1 FAIL / 3 GAP

| check | main | now | what the run said |
|---|---|---|---|
| mprotect_ro_write_faults | FAIL | ok |  |
| mprotect_none_read_faults | FAIL | ok |  |
| mprotect_none_write_faults | FAIL | ok |  |
| read_into_none_is_efault | FAIL | ok |  |
| reserve_none_really_none | FAIL | ok |  |
| reserve_guard_holds | FAIL | ok |  |
| jit_rx_runs | FAIL | ok |  |
| jit_rx_write_faults | FAIL | ok |  |
| fixed_address | FAIL | ok |  |
| fixed_replaces_zeroed | - | ok |  |
| tmpfile_write_full | FAIL | ok |  |
| tmpfile_pread_full | FAIL | FAIL | pread returned 4096, content matches as far as it goes |
| mmap_file_private | GAP | ok |  |
| mmap_file_contents | - | ok |  |
| mmap_file_tail_zero | - | ok |  |
| mmap_file_ro_write_faults | - | ok |  |
| mmap_file_offset | GAP | ok |  |
| mmap_file_offset_contents | - | ok |  |
| mmap_private_cow | - | ok |  |
| mmap_file_shared | GAP | GAP | errno=19 No such device |
| madvise_dontneed_call | GAP | ok |  |
| madvise_dontneed_zeroes | - | ok |  |
| madvise_free_call | GAP | ok |  |
| madvise_nohuge_call | GAP | ok |  |
| mremap_grow | GAP | ok |  |
| mremap_grown_usable | - | ok |  |
| mlock_call | GAP | ok |  |
| reserve_256M | GAP | GAP | mmap failed errno=12 |
| reserve_1G | GAP | GAP | mmap failed errno=12 |

### `t_misc` -- main: 42 ok / 10 FAIL / 16 GAP, now: 61 ok / 6 FAIL / 3 GAP

| check | main | now | what the run said |
|---|---|---|---|
| sched_getaffinity | GAP | ok |  |
| affinity_has_a_cpu | - | ok |  |
| sysconf_phys_pages | FAIL | ok |  |
| sched_setaffinity | GAP | ok |  |
| prctl_get_name | FAIL | FAIL | errno=22 Invalid argument |
| prctl_no_new_privs | FAIL | ok |  |
| prctl_pdeathsig | FAIL | ok |  |
| prctl_seccomp_mode_query | FAIL | ok |  |
| getrusage | GAP | ok |  |
| getrlimit_nofile | GAP | ok |  |
| rlimit_nofile_sane | - | FAIL | RLIMIT_NOFILE soft 16 |
| getrlimit_stack | GAP | ok |  |
| getrlimit_as | GAP | ok |  |
| setrlimit_nofile | GAP | ok |  |
| sysinfo | GAP | ok |  |
| fdatasync | GAP | ok |  |
| ftruncate | FAIL | FAIL | errno=22 Invalid argument |
| ftruncate_size | FAIL | FAIL | size 10 |
| flock | GAP | GAP | errno=38 Function not implemented |
| dup3 | FAIL | FAIL | errno=9 Bad file descriptor |
| posix_fallocate | FAIL | FAIL | errno=0 No error information |
| set_robust_list | GAP | ok |  |
| getpriority | GAP | ok |  |
| nice | GAP | ok |  |
| sched_getscheduler | GAP | GAP | errno=38 Function not implemented |
| sched_getparam | GAP | GAP | errno=38 Function not implemented |
| sched_get_priority_max | GAP | ok |  |
| realpath | FAIL | ok |  |

### `t_proc` -- main: 12 ok / 9 FAIL / 0 GAP, now: 19 ok / 2 FAIL / 0 GAP

| check | main | now | what the run said |
|---|---|---|---|
| exec_args_env_stdout | FAIL | ok |  |
| posix_spawn_returns_before_child_ends | FAIL | ok |  |
| wait_wnohang_running | FAIL | ok |  |
| spawn_sleeper_exit_code | FAIL | ok |  |
| posix_spawn_exit_code | FAIL | ok |  |
| system_exit_status | FAIL | FAIL | errno=0 No error information |
| popen | FAIL | FAIL | got '' |
| kill_child_sigkill | FAIL | ok |  |
| child_segv_reported | FAIL | ok |  |

### `t_procfs` -- main: 33 ok / 9 FAIL / 25 GAP, now: 38 ok / 4 FAIL / 25 GAP

| check | main | now | what the run said |
|---|---|---|---|
| self_maps_has_lines | FAIL | ok |  |
| self_maps_names_libc | FAIL | FAIL | libc not named in maps |
| self_maps_stack_or_heap_named | FAIL | ok |  |
| self_status_pid_threads | FAIL | ok |  |
| self_status_vm | FAIL | ok |  |
| self_exe_readlink | GAP | GAP | errno=2 No such file or directory |
| cpuinfo_model_name | FAIL | FAIL | no model name |
| cpuinfo_flags_sse2 | FAIL | FAIL | no flags with sse2 (feature detection by text) |
| meminfo_memavailable | FAIL | ok |  |
| proc_loadavg | GAP | GAP | errno=2 No such file or directory |
| self_limits | GAP | GAP | errno=2 No such file or directory |
| self_cgroup | GAP | GAP | errno=2 No such file or directory |
| random_uuid | GAP | GAP | errno=2 No such file or directory |
| sysctl_overcommit | GAP | GAP | errno=2 No such file or directory |
| sysctl_pid_max | GAP | GAP | errno=2 No such file or directory |
| sys_cpu_online | GAP | GAP | errno=2 No such file or directory |
| sys_cpu_possible | GAP | GAP | errno=2 No such file or directory |
| sys_cpu_cache | GAP | GAP | errno=2 No such file or directory |
| sys_drm | GAP | GAP | errno=2 No such file or directory |
| path_dev_shm | GAP | GAP | stat(/dev/shm): errno 2 |
| path_etc_ssl | GAP | GAP | stat(/etc/ssl): errno 2 |
| path_etc_ssl_certs | GAP | GAP | stat(/etc/ssl/certs): errno 2 |
| path_etc_resolv_conf | GAP | GAP | stat(/etc/resolv.conf): errno 2 |
| path_etc_localtime | GAP | GAP | stat(/etc/localtime): errno 2 |
| path_fontconfig | GAP | GAP | stat(/etc/fonts/fonts.conf): errno 2 |
| path_fonts | GAP | GAP | stat(/usr/share/fonts): errno 2 |
| path_zoneinfo | GAP | GAP | stat(/usr/share/zoneinfo): errno 2 |
| path_dev_pts | GAP | GAP | stat(/dev/pts): errno 2 |
| path_dev_dri | GAP | GAP | stat(/dev/dri): errno 2 |
| path_usr_lib | GAP | GAP | stat(/usr/lib): errno 2 |
| path_machine_id | GAP | GAP | stat(/etc/machine-id): errno 2 |
| shm_create | FAIL | FAIL | errno=1 Operation not permitted |
| statfs_tmp | GAP | GAP | errno=38 Function not implemented |
| statfs_root | GAP | GAP | errno=38 Function not implemented |

### `t_signals` -- main: 7 ok / 14 FAIL / 2 GAP, now: 16 ok / 5 FAIL / 2 GAP

| check | main | now | what the run said |
|---|---|---|---|
| raise_handler_runs | FAIL | ok |  |
| blocked_signal_pending | FAIL | ok |  |
| unblock_delivers | FAIL | ok |  |
| siginfo_delivered | FAIL | ok |  |
| siginfo_si_code_tkill | FAIL | ok |  |
| sigsegv_siginfo_given | FAIL | ok |  |
| sigsegv_si_addr | FAIL | ok |  |
| sigsegv_si_code | FAIL | ok |  |
| sigaltstack | GAP | GAP | errno=38 Function not implemented |
| alarm_fires | FAIL | FAIL | no SIGALRM within 2 s |
| setitimer | GAP | GAP | errno=38 Function not implemented |
| setitimer_fires | FAIL | FAIL | no SIGALRM from setitimer |
| signal_interrupts_nanosleep | FAIL | FAIL | r=0 errno=0 got=0 |
| sigsuspend | FAIL | FAIL | r=-1 errno=38 got=0 |
| sigchld_ign_autoreap | FAIL | FAIL | child not auto-reaped (w=6) |
| sigterm_default_kills | FAIL | ok |  |

### `t_threads` -- main: 11 ok / 3 FAIL / 0 GAP, now: 20 ok / 1 FAIL / 0 GAP

| check | main | now | what the run said |
|---|---|---|---|
| churn_64_threads | FAIL | ok |  |
| 24_threads_at_once | FAIL | ok |  |
| big_stack_create | FAIL | ok |  |
| big_stack_use | - | ok |  |
| barrier | - | ok |  |
| once | - | ok |  |
| cond_timedwait_times_out | - | ok |  |
| sched_yield | - | ok |  |
| fd_table_shared_between_threads | - | FAIL | a descriptor opened after the thread started is not valid in the thread (each task has its own copy) |
| pthread_self_equal | - | ok |  |

Total now: 249 ok, 26 FAIL, 40 GAP (checks that pass on both kernels are not listed)

