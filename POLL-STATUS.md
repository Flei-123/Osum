# RUNDE POLL — Stand, mit gemessenen Zahlen

Zweig `poll`, abgezweigt von `mergeline` (4f844b5). **Nicht nach `main`
gemerged.** Gearbeitet wurde in einem eigenen Arbeitsbaum
(`git worktree`, `/root/mg-osum-poll`), damit der Hauptbaum, in dem
gleichzeitig ein anderer Zweig läuft, unberührt bleibt.

## Der Ausgangspunkt, nachgemessen

```
$ grep -rn 'SYS_POLL\|SYS_SELECT\|SYS_EPOLL' kernel/ lib/   # vor der Runde
(nichts)
```

Vorhanden waren `fork`, `exec`, `pipe`, `dup2`, `wait4` und
`/etc/inittab` mit `respawn`. Ein Prozess konnte auf **genau eine**
Quelle warten. Für `jarvisd` — Netzanschluss **und** Rohr zum
Kindprozess gleichzeitig — reichte das nicht.

## Was gebaut wurde

| Datei | was |
|---|---|
| `kernel/kstate.fi` | `POLLSEQ` (Skalar 1120) — die Weckfolge |
| `kernel/sched.fi` | `S_POLL` (8), `T_POLLSEQ` (504), `poll_seq` / `poll_kick` / `poll_sleep`, `on_tick` weckt S_POLL bei Fristablauf |
| `kernel/sys.fi` | `SYS_POLL = 7`, `POLLIN/PRI/OUT/ERR/HUP/NVAL`, `do_poll`, `poll_scan`, `poll_ready`, `poll_sock`, `get32`/`get16`/`put16` |
| `kernel/inet.fi` | `sock_acceptable` (nicht-zerstörende Lauscher-Prüfung), `sock_hup`, `poll_kick` nach jedem Pumpvorgang |
| `kernel/tty.fi` | `poll_kick` in `lput`/`oput` |
| `kernel/file.fi` | `poll_kick` in `pipe_drop` (die einzige Stelle, an der ein Rohrende zugeht) |
| `kernel/signal.fi` | ein Signal weckt auch `S_POLL` |
| `lib/libc/kcall.fi` | `SYS_POLL = 7` |
| `lib/libc/io.fi` | `poll`, `poll_set`, `poll_fd`, `poll_revents`, `poll_ready`, die Bits, `POLL_FOREVER` |
| `kernel/user/pollt.fi` | das Messprogramm (`/bin/pollt`) |
| `kernel/user/jarvisd.fi` | die Brücke in kleinster Form (`/bin/jarvisd`) |
| `tools/poll/run.sh` | der Testabschnitt, 67 Zusagen |
| `test.sh` | Abschnitt 29 eingehängt |

## Die Syscall-Nummer

`poll` = **7**, Linux' Nummer, in Kernel **und** libc. Sie war frei.
`tools/poll/run.sh` Abschnitt 1 prüft bei jedem Lauf **die ganze Tafel**
in beiden Dateien auf doppelt vergebene Nummern — das ist die Lehre aus
der Runde mit der zweimal vergebenen 1320 (die gehört
`SYS_OSUM_NETMON` und liegt weit weg von hier). Ergebnis: keine
Doppelvergabe, 0 Abweichungen zwischen Kernel und libc.

## Die Wettlaufsituation — und wie sie gelöst ist

Der klassische Fehler:

```
Prozess A                        Prozess B
sieht nach: nichts ist bereit
                                 schreibt in das Rohr
                                 weckt alles, was wartet (nichts)
legt sich schlafen               -> schläft bis zum Zeitablauf
```

Gelöst mit einer **Zählerfolge** statt einer Sperre (weil `poll` Rohre,
Steckdosen und Terminals ansieht und jede dieser Schichten schon eine
eigene Sperre hat):

* A merkt sich `poll_seq` **vor** der Prüfung.
* B erhöht sie **vor** dem Wecken.
* `poll_sleep` legt A nur schlafen, wenn die Zahl unverändert ist —
  geprüft unter derselben Laufsperre, unter der die Aufgabe abgegeben
  wird.

`poll_kick` nimmt die Laufsperre **nicht** (wie `wake_pid`): es wird aus
dem Netzstapel mit gehaltener Netzsperre und aus der Zeilendisziplin
gerufen; eine zweite Sperre in dieser Reihenfolge wäre eine Verklemmung.

## Gemessen (`bash tools/poll/run.sh`, QEMU mit `-accel kvm`)

```
POLL: 67 bestanden, 0 durchgefallen
Laufzeit Abschnitt 3: 9,9 s mit kvm
```

Die Zahlen, auf die es ankommt:

| Messung | Wert | erwartet |
|---|---|---|
| zwei Rohre, eines beschrieben | `poll` meldet **1** | genau 1 |
| das beschriebene Rohr | revents = 1 (POLLIN) | 1 |
| das andere Rohr | revents = 0 | 0 |
| Rohr ohne Schreiber | revents = 16 (POLLHUP) — **ungefragt** | 16 |
| Rohr mit Oktetten + ohne Schreiber | revents = 17 (POLLIN\|POLLHUP) | 17 |
| Schreibseite, Platz da | revents = 4 (POLLOUT) | 4 |
| Schreibseite, kein Leser | revents = 8 (POLLERR) | 8 |
| Deskriptor 77 (nicht offen) | revents = 32 (POLLNVAL), Rückgabe 1 | kein Fehler des Aufrufs |
| gewöhnliche Datei | revents = 5 (POLLIN\|POLLOUT) | immer bereit |
| negativer Deskriptor | revents = 0, zählt nicht | 0 |
| `nfds = 99` | −22 (EINVAL) | −22 |
| Nullzeiger / Zeiger in den Kern | −14 (EFAULT) | −14 |
| **`poll(300 ms)`** | **308 ms** | ≥ 300, ≤ 340 |
| `poll(…, 0)` | 0 ms, Rückgabe 0 | sofort |
| `poll(0 Deskriptoren, 200 ms)` | 207 ms | ≥ 200 |
| **`poll(ohne Frist)`, Kind schreibt nach 1,2 s** | **1199 ms**, Rückgabe 1 | wacht am Ereignis auf |
| `poll(ohne Frist)` + SIGUSR1 nach 300 ms | **−4 (EINTR)**, 3xx ms | −EINTR |

**Toleranz begründet:** der Zeitgeber läuft mit 100 Hz. `poll` rundet
auf die nächste Marke auf **und zählt die angebrochene Marke mit**, weil
`kstate.TICKS` beim Eintritt schon mitten in ihr steht. Die Frist liegt
damit zwischen `timeout` und `timeout + 20 ms`. Der erste Lauf dieser
Runde maß 293 ms für `poll(300)` — also **zu früh**, und das ist das
eine, was POSIX verbietet und was ein Programm nicht selbst nachbessern
kann. Deshalb die eine Marke mehr; danach 308 ms.

### Die Zusage: wer wartet, rechnet nicht

Gemessen über dieselben 1,2 Sekunden Wartezeit, Systemaufrufzähler des
**ganzen Systems**:

```
mit poll (ein Aufruf, blockierend):        9 Systemaufrufe
als Warteschleife (sleep 10 ms, 120x):   123 Systemaufrufe
Verhältnis:                               13x
Zeit in beiden Fällen:                  1199 ms / 1197 ms
```

Die 9 sind: der eine `poll`, die zwei `sysinfo`-Abfragen der Messung
selbst und die paar Aufrufe des Kindprozesses (schlafen, schreiben,
schließen, enden). Ein wartender Prozess in `S_POLL` bekommt den
Prozessor **nicht** — er wird von `poll_kick` aus `pipe_write` geweckt.

### Die Brücke am Draht (Abschnitt 4)

`/bin/jarvisd` lauscht auf 10.0.2.15:9100 (QEMU-Benutzernetz mit
Portweiterleitung — kein Netzwerknamensraum, keine Sonderrechte). Der
Wirt verbindet sich mit `nc` und schickt eine Zeile; parallel dazu
schreibt ein Kindprozess in ein Rohr. **Eine** `poll`-Schleife über
Lauscher, Verbindung und Rohr:

```
jarvisd: socket = 1        angenommene Verbindungen = 1
jarvisd: bind = 0          Zeilen aus dem Netz bedient = 1
jarvisd: listen = 0        Zeilen aus dem Kindrohr bedient = 2
jarvisd: listening         das Ende des Kindes als POLLHUP = 1
                           Kind-Beendigungscode = 5
                           Durchläufe der einen Schleife = 4
beim Wirt angekommen:  "osum: hallo welt"
```

**4 Schleifendurchläufe** für die ganze Sitzung. Eine Warteschleife
hätte in denselben Sekunden Hunderte.

## Ein echter Fehler, der dabei aufflog (seit Runde K9)

`kernel/arch/x86_64/isr.s` schreibt die Antwort eines Systemaufrufs
**nach** `call KERNEL_SYSCALL` in den Rahmen. `sys.entry` rief aber
`signal.check_sys` **davor** — und `check_sys` rettet den ganzen Rahmen
auf den Nutzerstapel, damit `sigreturn` ihn zurückholen kann. In `F_RAX`
stand zu diesem Zeitpunkt noch die **Nummer** des Systemaufrufs.

Folge: jeder Systemaufruf, den ein **abgefangenes** Signal unterbrach,
gab seine eigene Nummer statt seiner Antwort zurück. Gemessen in dieser
Runde: ein `poll` ohne Frist, von SIGUSR1 unterbrochen, lieferte **7**
statt **−4**. Der Kommentar über `entry` behauptete das Gegenteil
("Der Rueckgabewert bleibt unberuehrt").

Warum es niemandem auffiel: die abgefangenen Signale in
`tools/unix/run.sh` treffen einen Prozess, der gerade **rechnet** (dort
geht die Zustellung über `check_irq`), oder einen, der danach ohnehin
stirbt. Ein Helfer, der in `poll` steht und ein SIGTERM sauber
beantworten soll, ist der erste Fall, in dem es zählt.

Behoben mit einer Zeile (`fset(frame, F_RAX, r)` vor der Zustellung).
Dazu die zweite Zeile in `kernel/signal.fi`: ein Signal weckt auch
`S_POLL` — ohne sie wäre ein `poll` ohne Frist die eine Stelle, an der
ein Prozess unerreichbar wird (`T_WAKE` steht auf `POLL_FOREVER`, der
Zeitgeber kommt nie vorbei).

## Kein bestehender Test wurde entschärft

Alle vorher grünen Läufer, nach den Änderungen, auf demselben Rechner:

```
POSIX:  134 bestanden, 0 durchgefallen
UNIX:   107 bestanden, 0 durchgefallen   (zweimal gelaufen)
KERNEL: 176 bestanden, 0 durchgefallen
K11:     85 bestanden, 0 durchgefallen
POLL:    67 bestanden, 0 durchgefallen   (neu)
```

Kein Test wurde gelockert, keine Erwartung heruntergesetzt. Der einzige
Zwischenfall — ein einzelner UNIX-Fehlschlag — trat auf, während auf
demselben Rechner parallel eine zweite volle Testsuite lief
(Lastmittel 8,7); zwei weitere Läufe danach waren 107/0.

## Was für `jarvisd` danach noch fehlt — ehrlich

1. **UDP und ICMP melden nie POLLIN.** `inet.sock_readable` beantwortet
   nur TCP; für UDP gibt es keine Bereitschaftsfunktion im Stapel.
   Für `jarvisd` (TCP) egal, für einen DNS- oder DHCP-Helfer nicht.
2. **Kein `select`, kein `epoll`, kein `ppoll`.** `poll` hat keine
   Signalmaske — zwischen „Signal prüfen" und „schlafen legen" kann ein
   Signal ankommen, das erst beim nächsten Aufwachen gesehen wird. Für
   einen Helfer mit `POLL_FOREVER` ist das der bekannte
   `pselect`-Grund; hier bleibt es offen.
3. **Höchstens 32 Deskriptoren je Aufruf** (`POLL_MAX`), darüber
   −EINVAL. Ein Prozess hat ohnehin nur `file.MAX_FD` offene Dateien.
4. **Kein `O_NONBLOCK` auf Rohren.** Nach einem POLLIN liefert genau
   **ein** `read` sicher Daten; wer in einer Schleife weiterliest,
   blockiert wieder (bis `BLOCK_ROUNDS`). `jarvisd` muss pro POLLIN
   genau einmal lesen — das tut es, aber es ist eine Regel und keine
   Garantie des Kerns.
5. **Die Konsole am Boot-Skript.** `poll` auf `stdin` sieht den
   Zeilenring der Zeilendisziplin. Eingaben aus dem Kommandozeilen-Skript
   werden erst in `tty_read` nachgeschoben (`script_feed`) — ein `poll`
   darauf meldet sie nicht. Echte Tastatur- und serielle Eingabe weckt
   `poll` korrekt (`lput` → `poll_kick`).
6. **Ein `accept` nach POLLIN kann theoretisch leerlaufen**, wenn zwei
   Prozesse denselben Lauscher teilen (das klassische
   Thundering-Herd-Rennen). `sock_acceptable` ist nicht-zerstörend, aber
   `do_accept` blockiert dann bis `NET_ROUNDS`. Mit einem `accept`-Aufrufer
   pro Lauscher — der Normalfall — kommt es nicht vor.
7. **Was `jarvisd` selbst noch braucht**, unabhängig von `poll`:
   ein Protokoll (Rahmenformat, Auftrag/Antwort), `execve` des
   angeforderten Programms mit umgeleiteten Deskriptoren (existiert:
   `fork` + `dup2` + `execve`), ein Dienst-Eintrag in `/etc/inittab`
   mit `respawn` (existiert), und Zugangsschutz — es gibt heute keine
   Authentisierung auf dem Anschluss.
