# Zwischenstand — Runde INIT

Zweig `init`, abgezweigt von `mergeline` (4f844b5), Arbeitsbaum
`/root/osum-init`. **Nicht nach `main` gemergt.**

Ausführlich: `docs/ROUNDINIT.md` (das Rundenprotokoll) und `docs/INIT.md`
(die Bedienungsanleitung). Testläufer: `tools/init/run.sh`, Abschnitt 29
von `./test.sh`.

---

## 0. Die Ausgangslage, nachgesehen statt geglaubt

Der Auftrag sagte: „`/etc/inittab` ist leer bzw. nicht vorhanden. Es gibt
keine Möglichkeit, Dienste zu starten, zu überwachen und bei Absturz neu
zu starten." Das ist **zur Hälfte richtig**, und die andere Hälfte ist
wichtiger.

**Was WIRKLICH schon da war** (`git show mergeline:kernel/user/init.fi`,
475 Zeilen, Runde K13):

| Behauptet in der Doku | Im Baum von `mergeline` |
|---|---|
| `/sbin/init` als Prozess 1 | **da** — der Kern startet ihn in `kmain.osum` |
| `/etc/inittab` mit `once`/`respawn`/`ctrl`/`off` | **da** — `read_tab()`, Format `name:art:befehl` |
| Waisen einsammeln | **da** — `harvest()`, `wait4(-1, WNOHANG)` |
| Neustart abgestürzter Dienste | **da**, aber nur **gedrosselt** (200 ms), **nicht begrenzt** |
| Herunterfahren über echtes ACPI | **da** — SIGTERM, 2 s, SIGKILL, `reboot(RB_POWEROFF)` |
| `/bin/svc start\|stop\|status\|restart` | **da** — über `/run/svc.cmd` und `/run/svc.state` |

**Was WIRKLICH gefehlt hat:**

1. **`/etc/inittab` lag in keinem Abbild, das dieses Repo baut.** Die
   einzige Stelle im ganzen Baum, die eine anlegt, ist
   `tools/k13/run.sh` — im Temp-Verzeichnis, für die Dauer des Laufs. Ein
   installiertes Osum bootet ohne inittab, `init` sagt `init:
   /etc/inittab fehlt` und gibt 1 zurück. Insofern hatte der Auftrag
   recht: **in der Praxis gab es keine Dienstverwaltung.**
2. **Kein Rückfall-Zähler.** Die 200-ms-Pause ist eine Drosselung, keine
   Grenze.
3. **Kein Runlevel, kein Ziel.** Jede Zeile lief immer.
4. **Keine Protokolldatei je Dienst.**
5. **Keine Abhängigkeit „erst nach Netz".**
6. **Kein `/bin/shutdown`, kein `/bin/reboot`.**
7. **`RB_RESTART` war kein Neustart** — `kernel/sys.fi` schickte ihn in
   `power.shutdown()`, also in den Ausgang des Prüfstands.
8. **`MAX_SVC = 8`.**

**Ausgangsmessung:** `bash tools/k13/run.sh` auf `mergeline` →
**99 Zusagen, 0 Fehler.**

---

## 1. Was diese Runde gebaut hat

| | |
|---|---|
| `/bin/init` | der Kern sucht **zuerst** dort, `/sbin/init` bleibt als zweiter Weg (K13 benutzt ihn) |
| Rückfall-Zähler | **fünf** Fehlstarts hintereinander → `failed`, keine weiteren Versuche |
| Startbremse | mehr als **10 Starts in 5 s** → der nächste wartet **5 s** — gilt für jeden Dienst, ohne nach dem Grund zu fragen |
| Ziele | `/etc/ziel` mit `konsole` oder `grafik`; **fehlt die Datei, gilt `konsole`** |
| Protokoll | `log=/pfad` je Dienst, anhängend, vor `execve` auf 1 und 2 gelegt |
| Netz | Option `netz` — Zustand `waiting`, bis der Stapel läuft **und** eine Adresse hat |
| `/etc/fstab` | `quelle ziel art [ro]`, beim Herunterfahren in umgekehrter Reihenfolge ausgehängt |
| `svc list` | Tafel mit Zustand, PID, Starts, Fehlern, **Laufzeit** und Ziel |
| `svc status` | bleibt **roh** — `tools/k13/run.sh` liest die Spalten; die drei neuen stehen **hinten** |
| `/bin/shutdown`, `/bin/reboot` | über init, mit `-f` als Notweg ohne init |
| echter Neustart | FADT-`RESET_REG` → Anschluss `0xCF9` → 8042 |
| `MAX_SVC` | 8 → **16** |

**Beide inittab-Formate werden gelesen.** `name:art:befehl` (K13) und
`name:ziele:art:befehl:optionen` (diese Runde); das zweite Feld
entscheidet.

---

## 2. Was diese Runde GEFUNDEN hat

Das wichtigste Ergebnis steht nicht in `init.fi`, sondern in
`kernel/sys.fi` — und es kam beim Messen heraus, nicht beim Lesen.

**`do_wait4` fragte `find_child` nach dem ERSTEN Kind des Rufers, ohne
nach dessen Zustand zu fragen.** Lebte das noch, antwortete `wait4` mit
`WNOHANG` eine `0` („nichts Neues") — und der **Zombie dahinter** wurde
nie abgeholt. Eine Shell wartet auf ein Kind und merkt das nie; der
Prozess 1 hat immer mehrere, und das langlebigste steht meist **vor** den
kurzlebigen Diensten. Der Fehler ist seit Runde 62 im Baum.

**Behebung:** zuerst nach einem **Zombie** fragen (`find_zombie_child`),
erst dann, ob es überhaupt ein Kind gibt (das unterscheidet „warte" von
`-ECHILD`). Bei genau einem Kind Zeile für Zeile das alte Verhalten.

**Gegenprobe `waitfirst`** — derselbe Lauf, dasselbe Abbild:

| | behoben | `waitfirst` |
|---|---|---|
| Dienst `sauber` (`/bin/true`, respawn) | 20 Starts, weiter | steht bei **2** Starts, für immer `running` |
| Aufgabentafel | kein Zombie | `11 1 zombie user` bleibt stehen |
| `ctrl`-Zeile endet | `init: herunterfahren`, ACPI, QEMU **0** | init erfährt es nie, QEMU **124** (Zeitlimit) |

Dazu ein zweiter, kleinerer Befund: **`init` selbst las `/run/svc.cmd` in
jedem Durchgang** — vierzig Dateiöffnungen je Sekunde, dauerhaft, auf
einer IDE-Platte. Jetzt alle 200 ms.

Und ein dritter, der die erste Fassung des Rückfall-Zählers verwarf: der
Zähler nahm anfangs nur die Lebensdauer (< 500 ms). Im Testlauf blieb er
bei **null** — `/bin/false` lebte **1,5 Sekunden**, weil `fork` +
`execve` + ELF-Lader so lange brauchen. *Eine Grenze, die unter der
Anlaufzeit eines Prozesses liegt, misst die Platte und nicht den Dienst.*
Seither zählt ein Rückfall nur, wenn der Dienst **mit einem Code ≠ 0**
endet **und** keine zwei Sekunden geschafft hat.

---

## 3. Die Zahlen

Alle Läufe mit `-accel kvm -cpu host`, also auf der echten CPU.

**Die Abschnitte, die der Kernumbau berühren konnte — vorher/nachher:**

| Abschnitt | vorher (`mergeline`) | nachher (Zweig `init`) |
|---|---|---|
| 19 `tools/k13/run.sh` (Benutzer, Rechte, init) | 99 / 0 | **99 / 0** |
| 13 `tools/unix/run.sh` (Signale, `wait`, Terminal, Uhr) | 107 / 0 | **107 / 0** |
| 9 `tools/userland/run.sh` (Shell, 25 Werkzeuge, Rohre) | 91 / 0 | **91 / 0** |
| 16 `tools/k11/run.sh` (Editor, Werkzeuge, Shell-Sprache) | 85 / 0 | **85 / 0** |
| **29 `tools/init/run.sh` (NEU)** | — | **78 / 0** |

`tools/unix`, `tools/userland` und `tools/k11` sind die Abschnitte, die
am meisten `fork`/`wait4` benutzen — sie stehen hier, weil diese Runde
`do_wait4` angefasst hat. Keine Zusage ist verlorengegangen, keine wurde
entschärft.

*Der vollständige `./test.sh` (29 Abschnitte) wurde in dieser Runde
**nicht** zu Ende gefahren: auf demselben Wirt liefen gleichzeitig die
Abnahmen von drei anderen Zweigen (Lastmittel dauerhaft über 20 bei 12
Kernen), und ein Lauf unter dieser Last misst Zeitlimits statt
Eigenschaften. Was oben steht, ist einzeln gemessen.*

**Sonstige Zahlen:**

| Messung | Wert |
|---|---|
| Speicherkarte `tools/kernel/memmap.py` | 64 Bereiche, 0 Kollisionen |
| Modusnamen auf der Kommandozeile | 87 → **88** (`waitfirst`) |
| Kernel Stufe 0 | 2.842.308 Oktette |
| `/bin/init` (firnc0, gestrippt) | 135.616 Oktette |
| Dienste je Tafel | 8 → **16** |
| Rückfall-Zähler | 5 Fehlstarts, Schwelle 2000 ms |
| Startbremse | >10 Starts in 5 s → 5 s Pause |
| `/run/svc.cmd` gelesen | 40×/s → **5×/s** |

---

## 4. Was für einen Dauerbetrieb noch fehlt

Die vollständige, ehrliche Liste steht in `docs/ROUNDINIT.md`,
Abschnitt 7. Die drei wichtigsten:

1. **Keine Protokollrotation** — `log=` wächst, bis die Platte voll ist.
2. **Keine Abhängigkeiten zwischen Diensten** außer `netz`.
3. **Kein Dienst läuft unter einer anderen Kennung** — alles ist root,
   obwohl die Kennungsschicht aus K13 daliegt.
