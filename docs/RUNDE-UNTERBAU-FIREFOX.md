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

---

## 4. Die Messung

@@MESSUNG@@

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

@@OFFEN@@

---

## 6. Nachbauen

    # Wirt braucht: musl-gcc, qemu-system-x86_64, python3 (Pillow nur für report)
    /root/jarvis/bin/heavy bash tools/unterbau/run.sh                       # alle Programme auf dem Kernel dieses Baums
    OLDK=<Kernel von main> /root/jarvis/bin/heavy bash tools/unterbau/run.sh # + Gegenproben (fixed.txt)
    REGEN=1 OLDK=<Kernel von main> ... run.sh                                # accept.txt / fixed.txt neu schreiben

