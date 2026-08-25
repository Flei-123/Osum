# Runde K9 — was jedes Unix-Programm stillschweigend voraussetzt

Osum hatte nach Runde K6 vierunddreissig Systemaufrufe, achtundzwanzig
Programme, eine Shell mit Roehren und Umlenkung, ein Dateisystem, einen
ELF-Lader, NVMe, PCI, APIC, SMP, getrennte Adressraeume und
Capability-Handles. Und trotzdem konnte man einen Prozess in diesem
System nicht ordentlich unterbrechen.

Es gab keine Signale. Es gab kein Terminal — die Shell redete unmittelbar
mit der Tastatur und der seriellen Leitung. Es gab keine Uhr; `ls -l`
zeigte kein Datum, weil es keines gab. Und es gab keinen Zufall, was
mehr ist als eine fehlende Bequemlichkeit: Runde K8 baut im selben Repo
gerade den Netzwerkstapel, und ohne brauchbaren Zufall gibt es weder
sichere TCP-Anfangsfolgenummern (RFC 6528, der Angriff ist von 1985) noch
spaeter TLS.

Diese Runde baut die vier. Was gemessen wurde, steht unten mit Zahlen;
was nicht fertig ist, steht am Ende, mit Namen.

    ./test.sh          zwoelf Abschnitte, 282 Zusagen, 0 Fehler
    tools/unix/run.sh  107 Zusagen dieser Runde

---

## 1. Die Karte — wer welchen Zahlenbereich hat

Drei Runden arbeiten gleichzeitig an diesem Repo (K7 Grafik, K8 Netz, K9
hier), und an einem Tag sind dreimal zwei von ihnen auf dieselbe
Aufrufnummer gekommen. Von dieser Runde an steht die Aufteilung oben in
`kernel/sys.fi`:

    Hat Linux den Aufruf, dann hat er LINUX' NUMMER.
    Hat Linux ihn nicht, dann liegt er ueber 1000, und
        1000..1099   Runden K1 und K6
        1100..1199   RUNDE K9
        1200..1299   Runde K7 (Bildschirm)
        1300..1399   Runde K8 (Netz)
        2000..2099   die native ABI aus OrientOS (kernel/cap.fi)

**Eine Abweichung vom Auftrag, und sie ist bewusst.** Der Auftrag lautete
„nimm den Bereich ab Nummer 80 aufwaerts". Das haette Regel 1 dieses
Projekts gebrochen, die seit Runde K4 in `kernel/sys.fi` steht und von
`tools/posix/run.sh` Abschnitt 1 geprueft wird: *die Nummern sind Linux'
Nummern*, weil Stufe 2 dieses Plans ein statisch gebundenes
Linux-Programm ausfuehren soll und ein solches Programm seine Nummer in
rax legt, ohne jemanden zu fragen. `rt_sigaction` auf 80-irgendwas zu
legen waere eine Uebersetzungstabelle, die jemand pflegen muss.

Der Konflikt, den der Auftrag vermeiden wollte, ist trotzdem
ausgeschlossen, und das ist nachgerechnet: K9 belegt die Linux-Nummern
13, 14, 15, 16, 34, 37, 56, 62, 96, 109, 111, 112, 121, 127, 201, 202,
228, 229, 230, 234 und 318. **Keine davon liegt zwischen 41 und 55** —
das ist der Block der Sockets, den K8 braucht. `tools/unix/run.sh`
Abschnitt 1 prueft genau das als Zusage. Was Osum selbst erfunden hat
(`openpty`, `ttyinfo`, `siginfo`), liegt bei 1100, 1101 und 1102.

---

## 2. Signale (`kernel/signal.fi`, 900 Zeilen)

### Der Aufbau

Ein Signal hat drei Schritte, und die Reihenfolge ist die ganze
Schwierigkeit:

1. **Abschicken** ist billig: ein Bit in `T_SIGPEND` der Zielaufgabe.
   Mehr geschieht beim Absender nicht. Ein Absender, der selbst zustellte,
   muesste in einen fremden Adressraum schreiben, waehrend dessen Besitzer
   laeuft.
2. **Zustellen** geschieht *im Ziel* und an genau zwei Stellen: kurz
   bevor es aus einem Systemaufruf nach Ring 3 zurueckkehrt
   (`signal.check_sys`), und im Zeitgeberunterbrecher
   (`signal.check_trap`). Nur dort steht sein Zusammenhang vollstaendig
   und unbenutzt im Speicher.
3. **Blockieren** ist eine Maske je Aufgabe. Ein blockiertes Signal bleibt
   wartend; es geht nicht verloren.

Die zweite Zustellstelle ist die, die den Unterschied macht. Ein Programm
in einer Endlosschleife macht keine Systemaufrufe — der einzige
Augenblick, in dem der Kernel es in der Hand hat, ist der Zeitgeber. Ohne
diese eine Zeile in `kernel/trap.fi` beendet STRG-C keine Endlosschleife,
und zwar still.

### Der Rahmen auf dem Nutzerstapel, und zwei Fallen

Eine Behandlungsroutine laeuft in Ring 3, auf dem Stapel des Prozesses.
Der Kernel legt darunter:

    [rsp]      die Ruecksprungadresse: `sigreturn_tramp`
    [rsp+8]    Kennwort, alte Maske, Signalnummer
    [rsp+32]   zweiundzwanzig Woerter Zusammenhang (die Form von isr.s)

**Falle 1: der rote Bereich.** System V erlaubt einer Funktion, 128
Oktette *unter* ihrem Stapelzeiger zu benutzen, ohne ihn zu bewegen. Ein
Signalrahmen, der dort hineingelegt wird, ueberschreibt lebende Daten —
eine Zeile Code und der Unterschied zwischen „laeuft" und „laeuft
meistens".

**Falle 2: der Trampolinsprung darf nicht auf dem Stapel liegen.** Seit
Runde K1 traegt jede Stapelseite das No-Execute-Bit. Linux legt seinen
Trampolinsprung traditionell auf den Stapel; ein Kernel, der das Bit
dafuer wieder abnimmt, hat die aelteste Luecke wieder aufgemacht, die es
gibt. Also liegt er in `.utext` (`kernel/isr.s`) — der einen Seite, die
in *jedem* Adressraum fuer Ring 3 lesbar und ausfuehrbar und **nicht**
beschreibbar ist. `tools/kernel/run.sh` prueft seit Runde 59, dass jeder
`syscall`-Befehl des Kernelabbilds dort und nirgends sonst liegt; die
Zusage ist unveraendert, die Zahl ist um eins gewachsen (zwei → drei).

### `sigreturn` und der zweite Rueckweg nach Ring 3

`sysretq` nimmt rip aus rcx und rflags aus r11 — und genau diese beiden
Register zerstoert `syscall` beim Eintritt. Fuer einen Rueckweg aus einem
Systemaufruf ist das richtig. Ein Signal darf aber auch mitten in ein
Programm zugestellt werden, das gar keinen Systemaufruf gemacht hat; dann
sind rcx und r11 echte Registerwerte. Deshalb hat `isr.s` seit dieser
Runde einen zweiten Rueckweg, `user_iret`, der ueber `iretq` geht und
einen vollstaendigen Zusammenhang zurueckgibt.

`sigreturn` folgt dem Zeiger von Ring 3 **nicht blind.** Drei Pruefungen:
der Rahmen liegt vollstaendig im Stapel des Prozesses, das Kennwort steht
darin, und die Adresse ist die, die der Kernel selbst notiert hat
(`T_SIGRET`). Ohne die dritte koennte ein Programm einen eigenen Rahmen
bauen und sich cs und rflags aussuchen — und cs mit zwei Nullbits im
Rueckgabewort ist Ring 0. Selektoren und Flaggen werden ohnehin neu
gesetzt statt uebernommen.

### Eine Behandlungsroutine ist eine Adresse

Stufe 0 von Firn kann die Adresse einer eigenen Funktion nicht nennen
(SPEC 14) — derselbe Grund, aus dem `isr.s` eine Tabelle von Wahlnummern
hat. **Ohne eine Loesung dafuer koennte kein Programm auf dieser Platte
`sigaction` auch nur aufrufen**, egal wie vollstaendig der Kernel darunter
ist. Die Loesung sind neun Zeilen in `kernel/user/crt.s`, neben `_start`:
drei Routinen (mitzaehlen, zweiter Zaehler, und eine, die den Prozess mit
`40 + Nummer` beendet). Ein Firn-Programm kommt mit
`lea rax, [rip + osum_sighandler]` in einem `asm`-Block an ihre Adresse.

### Prozessorausnahmen sind Signale

Bis hierher toetete jede Ausnahme in Ring 3 den Prozess auf der Stelle.
Das ist die halbe Wahrheit: ein Zugriff daneben *ist* toedlich, solange
niemand hinsieht — aber ein Programm darf hinsehen, und ein
Sprachlaufzeitsystem, das seinen Stapel waechst, wenn er anstoesst,
haengt daran. Die Zuordnung ist die von Linux
(`arch/x86/kernel/traps.c`): #DE → SIGFPE, #UD → SIGILL, #PF/#GP/#SS →
SIGSEGV, #AC → SIGBUS.

Zwei Feinheiten, beide aus jedem Unix uebernommen: ein Fehlersignal
laesst sich **nicht blockieren** (sonst waere es eine Schleife aus
derselben Ausnahme fuer immer), und eine eigene Routine dafuer gilt
**einmal** — kehrt sie zurueck, laeuft derselbe Befehl wieder und faellt
wieder.

### Eine Zusage an die Runden vorher

Ein Prozess, der an einem Signal stirbt, hinterlaesst `128 + Signalnummer`
— so rechnet jede Shell. Ein Prozess, der an einer **Ausnahme** stirbt,
hinterliess in diesem Kernel seit Runde 62 `128 + Vektornummer`, und
`tools/osum/run.sh` misst seit damals, dass ein Seitenfehler 142 ergibt.
Beide Zahlen haben ihr Recht, und **beide bleiben**: `signal.fault`
traegt die vektorbasierte in `T_KILLCODE` ein, und wo sie steht, gilt sie.
Auch die Meldezeile von Runde 62 (`user fault: ... -- process killed`)
steht Oktett fuer Oktett noch da — aber nur, wenn der Prozess wirklich
stirbt; faengt er das Signal ab, sagt die Zeile `-> caught SEG`.

### Gemessen

| Zusage | Wert |
|---|---|
| ein Signal an sich selbst landet in der Routine | `caught = 1` |
| sechs Signale, sechsmal gezaehlt | `count = 6` |
| die Routine bekam die richtige Nummer | `last = 10` (SIGUSR1) |
| ein blockiertes Signal wartet | `pending = 1` |
| und kommt beim Freigeben an | `after unblock = 1` |
| ein ueberhoertes kommt nie | `ignore = 0` |
| SIGKILL/Signal 0/Signal 64 bei `sigaction` | `-22` (EINVAL) |
| ein Prozess, den es nicht gibt | `-3` (ESRCH) |
| Kind stirbt an SIGTERM | `143` = 128 + 15 |
| SIGKILL trotz Routine | `137` = 128 + 9 |
| Elternteil bekommt SIGCHLD | `chld = 1` |
| SIGSEGV in einer Routine in Ring 3 | `51` = 40 + 11 |
| ohne Routine: der Code von Runde 62 | `142` = 128 + Vektor 14 |
| SIGFPE aus `div` durch null | `48` = 40 + 8 |

**Gegenprobe `nosig`:** derselbe Code, ein Wort auf der Kommandozeile.
`kill` sagt weiter 0, das Bit wird weiter gesetzt (`pending = 1`) — nur
zugestellt wird nichts. **`caught = 0`, `count = 0`, `after unblock = 0`.**
6 gegen 0. Waere `kill` selbst abgeschaltet, wuerde die Gegenprobe etwas
anderes messen, als sie behauptet.

---

## 3. Anhalten und fortsetzen

`SIGSTOP` macht aus dem Prozess den Zustand `S_STOP` (7) — einen eigenen
Zustand und nicht `S_SLEEP`, denn ein Schlaefer wird vom Zeitgeber
geweckt und ein Angehaltener nicht. `pick` in `sched.fi` waehlt nur
`S_READY`, also faellt eine angehaltene Aufgabe von selbst aus der
Laufliste, ohne dass der Kern der Auswahl eine Zeile mehr braucht.

Gemessen wird nicht der Zustand allein, sondern die **Rechenzeit**: ein
Kind, das rechnet, wird angehalten, und seine Marken stehen still
(`stop frozen = 1`); nach `SIGCONT` laufen sie weiter (`cont moves = 1`).
Ein Prozess, der nur schliefe, taete das nicht.

**Ein Fehler dieser Runde, der es wert ist:** der Selbsttest blieb hinter
`job ttin` stehen. Ein von SIGTTIN angehaltenes Kind bekam ein SIGKILL
und sah es nie — es bekam ja den Prozessor nicht mehr. Wer darauf
wartete, wartete fuer immer. `SIGKILL` holt seither auch einen
Angehaltenen zurueck.

---

## 4. Terminal und Pseudoterminals (`kernel/tty.fi`, 700 Zeilen)

Die Zeilendisziplin sitzt zwischen Geraet und Prozess und hat zwei
Betriebsarten: **kanonisch** (sammelt eine Zeile, Rueckschritt nimmt ein
Zeichen zurueck, STRG-U die Zeile, STRG-D beendet die Eingabe, erst der
Zeilenvorschub gibt alles heraus) und **roh** (jedes Zeichen sofort, kein
Echo, keine Bearbeitung). STRG-C ist kein Zeichen, das jemand liest — es
ist ein SIGINT an die Vordergrund-Prozessgruppe. Das ist die Stelle, an
der Terminals und Signale dasselbe Thema sind, und der Grund, warum beide
in derselben Runde entstehen.

**Das Anzeigegeraet ist austauschbar.** Die Zeilendisziplin weiss nicht,
wohin sie schreibt: sie ruft `tty.emit`, und `emit` sieht in `T_SINK`
nach — `SINK_SERIAL`, `SINK_SCREEN`, `SINK_PEER`. Runde K7 baut im selben
Repo den Rahmenpuffer; sie muss dafuer **eine Zeile** aendern (die
Weiche in `emit`), und an dieser Datei aendert sich keine. K7s
Bildschirmcode wurde nicht angefasst. Auch die Konsolenausgabe der
Prozesse laeuft seit dieser Runde durch `tty.write_out` statt unmittelbar
auf die Leitung — die Weiche liegt also wirklich im Weg und nicht daneben.

**Zwei Schalter stehen auf der Konsole anders als auf einem
Pseudoterminal, und beide aus demselben Grund:** an dieser Leitung
haengen die Messungen der Runden 59 bis K6. `ECHO` ist aus, weil
`kbd.fi` seit Runde 59 jede Taste selbst meldet und die Shell seit Runde
K1 die Zeile schreibt, die sie bekommen hat — ein drittes Echo, und
`grep -c '^key: '` faende keine Zeile mehr. `OPOST` ist aus, weil ONLCR
sonst vor jeden Zeilenvorschub einen Wagenruecklauf setzte und jede
Messung, die eine Zahl am Zeilenende liest, sie mit einem `\r` daran
bekaeme. *Beides ist beim ersten Versuch passiert: 65 von 134 Zusagen in
`tools/posix/run.sh` fielen aus, alle mit „= 3, erwartet 3".* Der
Selbsttest schaltet beides vorruebergehend ein und misst, dass die
Schalter wirken.

Ein **Pseudoterminal** ist ein Paar aus Steuer- und Nutzerseite. Die
Nutzerseite ist ein ganz gewoehnliches Terminal mit Zeilendisziplin und
Echo; eine Shell darauf merkte keinen Unterschied. Gemessen: sechs
Oktette hin, sieben zurueck (das Echo, mit dem Wagenruecklauf von ONLCR),
sechs in der anderen Richtung, ein einzelnes Zeichen im rohen Modus, und
ein Oktett 3, das ein SIGINT wird statt gelesen zu werden.

---

## 5. STRG-C beendet wirklich — ohne einen Menschen davor

Das ist der Test, den ein Mensch bemerkt, und er laeuft ohne Menschen.
Ein Kind setzt sich mit `setpgid(0,0)` in eine eigene Prozessgruppe und
rechnet; die Gruppe wird Vordergrund des Pseudoterminals; ein Oktett 3
geht auf die Steuerseite. Das Kind ist tot, mit **130 = 128 + SIGINT**.

Der Weg ist Zeile fuer Zeile derselbe, den eine gedrueckte Taste nimmt:
`tty.push` sieht VINTR, ISIG steht, `signal.send_pgid` trifft die
Vordergrundgruppe. Dazu:

| | |
|---|---|
| STRG-Z haelt an statt zu beenden | `job tstp = 7` (S_STOP) |
| SIGCONT setzt fort | `job cont = 1` |
| Hintergrundleser bekommt SIGTTIN und steht | `job ttin = 7` |
| `setpgid(0,0)` macht die eigene Gruppe | `job grp = 0` |

Auf der **Konsole** geht derselbe Weg: seit dieser Runde laeuft auch das
Skript der Kommandozeile durch die Zeilendisziplin, und `console_load`
uebersetzt `^C` in ein Oktett 3. Ein `script=...^C...` wirkt damit genau
wie eine Taste.

**Ein Fehler dieser Runde, der die Sache beweist:** das Testprogramm
erbte die Prozessgruppe der Shell, schickte sein STRG-C an diese Gruppe —
und die Shell starb mit 130, waehrend der Test weiterlief und alles gruen
meldete (`osum: sh exit=130`). Genau dafuer gibt es Prozessgruppen. Das
Programm setzt sich jetzt zuerst in seine eigene.

---

## 6. Die Uhr (`kernel/time.fi`)

Zwei Uhren, und der Unterschied ist der Punkt:

**Echtzeit** kommt aus dem CMOS-Baustein, wird **einmal** beim Start
gelesen und danach fortgerechnet. `TIME_BOOT` (Sekunden seit 1970) und
`TIME_TSC0` (Zyklenzaehler) stammen aus demselben Augenblick — kaemen sie
aus zwei, waere der Fehler fuer immer eingebaut. Das Datum entsteht mit
Howard Hinnants `days_from_civil`: keine Schleife ueber Jahre, keine
Tabelle von Monatslaengen, richtig fuer jedes Datum ab 1970.

**Monoton** kommt aus dem Zyklenzaehler, geteilt durch seine **gemessene**
Frequenz. Der Zeitgeber schlaegt hundertmal in der Sekunde; eine Uhr aus
ihm haette zehn Millisekunden Koernung und waere fuer jede Messung
unbrauchbar. Geeicht wird gegen den Zeitgeber, und zwar erst, nachdem
nachgewiesen ist, dass er schlaegt. Gemessen auf der Testmaschine:
**2 201 163 kHz**. Ohne Zyklenzaehler rechnet die Uhr aus Marken weiter,
mit den zehn Millisekunden, die es dann eben hat — eine Uhr, die zugibt,
grob zu sein, ist besser als eine, die eine Zahl erfindet.

**Die Zusage: sie laeuft nie rueckwaerts.** Das ist nicht behauptet,
sondern erzwungen. Vier Kerne duerfen gleichzeitig fragen, und ihre
Zyklenzaehler muessen nicht auf dieselbe Zahl geeicht sein; ein Kern, der
zwei Mikrosekunden hinterherlaeuft, liesse eine Uhr, die einfach rechnet,
rueckwaerts laufen, sobald eine Aufgabe den Kern wechselt. Also steht der
zuletzt herausgegebene Wert in einem Wort, und ein neuer wird nur
herausgegeben, wenn er groesser ist — mit `lock cmpxchg`. `TIME_BACK`
zaehlt mit, wie oft die Klammer greifen musste.

**Die Arithmetik-Falle**, die in diesem Projekt an einem Tag achtmal die
Fehlerursache war: `cycles * 1000000 / khz` haette bei 2,2 GHz nach
wenigen Sekunden 1,8e19 erreicht und waere umgelaufen. Also erst teilen,
dann malnehmen, den Rest getrennt — beide Zwischenwerte bleiben unter
1e13. Und jede Zeile, die mit Zyklen oder Nanosekunden rechnet, benutzt
`+%`, `-%`, `*%`: eine Differenz zweier Zyklenzaehler *meint* Umdeutung.

| Zusage | Wert |
|---|---|
| die monotone Uhr laeuft vorwaerts | `mono runs = 1` |
| **und nie rueckwaerts** | `mono backward = 0` |
| ueber wie viele Messungen geprueft | `mono samples = 20000` |
| das Jahr der Echtzeituhr | `real year = 2026` |
| ein Schlaf von 50 ms dauert (ms) | `42..45` |
| eine Uhr, die es nicht gibt | `-22` (EINVAL) |
| `gettimeofday` und `time` sagen dasselbe | `tod agree = 1` |
| Koernung feiner als eine Zeitgebermarke | `res fine = 1` |

`nanosleep` ist seit dieser Runde **unterbrechbar** (`-EINTR`) — ein
`sleep 30`, das sich von STRG-C nicht stoeren laesst, war genau das, was
zu beheben war. Die 60-Sekunden-Grenze von Runde 62 bleibt.

---

## 7. Der Zufall (`kernel/rand.fi`)

Zwei Haelften, wie ueberall:

**Der Sammler.** Zufall entsteht nicht im Rechenwerk. Er kommt aus
Ereignissen, deren genauen Zeitpunkt niemand vorhersagt: jeder
Zeitgeberschlag und jede Taste ruehren den Zyklenzaehler in einen Topf
von 64 Oktetten (`rand.stir`, gerufen aus `trap.fi` und `kbd.fi`). Dazu,
**wo es sie gibt**, `RDSEED` und `RDRAND` — gefragt ueber CPUID, nicht
angenommen, denn auf einem Prozessor ohne sie ist `rdrand` ein ungueltiger
Befehl und damit ein #UD im Kernel. Auf der Testmaschine (QEMU, TCG,
Standardprozessor) sind sie **nicht** da: `hw=0`, und die gemeldeten
Saaten kommen allein aus dem Flattern. Das ist die ehrlichere Messung von
beiden.

**Der Generator.** ChaCha20 — dieselbe Konstruktion, die Linux seit 4.8
fuer `/dev/urandom` benutzt. Zwanzig Runden aus Addition, Exklusiv-Oder
und Rotation, und genau deshalb in einer Sprache ohne Bibliothek
hinschreibbar und nachlesbar. Alle Additionen sind `+%` mit Maske: die
Chiffre rechnet modulo 2^32, und die gepruefte Addition dieser Sprache
bliebe bei der ersten Uebertragung stehen. Nach 4096 Oktetten wird neu
geschluesselt; beim Saeen laeuft ein Block durch, dessen Ausgang der neue
Schluessel wird („fast key erasure") — wer den Sammler kennt, kennt den
Strom trotzdem nicht.

| Zusage | Wert |
|---|---|
| `getrandom` fuellt, worum gebeten wird | `1024` |
| Chi-Quadrat ueber 256 Faecher, 8192 Ziehungen | `172..218` (ideal 255 ± 23) |
| Bitverteilung in Zehntelprozent | `500..502` (ideal 500) |
| verschiedene Oktette zwischen zwei Puffern von 1024 | `1019..1021` |
| `getrandom(0)` | `0`, kein Fehler |
| Zeiger in den Kernel | `-14` (EFAULT) |
| drei Neustarts, drei verschiedene Saaten | `3 von 3` |

**Gegenprobe `fixedrand`:** der Generator gibt fuer immer `0x5A`.
Chi-Quadrat **2 088 960** statt 190, `random diff = 0` statt 1021. Und
dabei faellt etwas auf, das mit im Bericht stehen soll: **die
Bitverteilung allein haette den festen Strom durchgewinkt** — `0x5A` hat
vier von acht Bits gesetzt, also genau 500. Eine statistische Pruefung
reicht nicht; das Chi-Quadrat ist die, die es merkt.

---

## 8. Was diese Runde sonst noch geaendert hat

* **Der Datenbereich** waechst von 192 auf 256 KiB (`kstate.fi` und
  `boot.s` halten dieselbe Zahl). Drei neue Bereiche: Signalroutinen
  (32 × 32 × 24 Oktette), je Aufgabe ein geretteter Zusammenhang, die
  acht Terminals, der Zufallsgenerator. Die Karte oben in `kstate.fi` ist
  gepflegt — die Runden K4, K5 und K6 haben sich je einmal dieselbe Seite
  genommen, weil sie es nicht war.
* **Der Aufgabendatensatz** war ab Oktett 272 leer und ist es nicht mehr:
  wartende Signale, Maske, Prozessgruppe, Sitzung, beherrschendes
  Terminal, Frist von `alarm`, Fadengruppe.
* **Prozessgruppe und Sitzung werden vererbt** (`proc.create_bare`), und
  Aufgabe 0 hat Gruppe 1. Bliebe dort die Null stehen, haette die ganze
  Maschine die Gruppe null — und `tty.push` haelt genau die Null fuer
  „dieses Terminal hat keinen Vordergrund" und schickte kein SIGINT.
  STRG-C taete dann nichts, und zwar still. *Auch das ist in dieser Runde
  einmal passiert.*
* **Das Loeschen der Signaltabelle** liegt in `sched.fi` und nicht in
  `signal.fi`, obwohl es dorthin gehoerte: `signal.fi` braucht `proc.fi`,
  `proc.fi` braucht `sched.fi`, und ein `import signal` in einem der
  beiden waere ein Ring im Modulgraphen. Was in `sched.fi` steht, ist
  reines Nullen von Speicher ohne Bedeutung; die Bedeutung steht
  vollstaendig in `signal.fi`. Noetig ist es, weil ein Platz, den eine
  tote Aufgabe hinterlaesst, seiner Nachfolgerin sonst
  Behandlungsroutinen in einem Abbild vererbte, das es nicht mehr gibt —
  derselbe Fehler, den Runde K6 bei den Deskriptoren schon einmal hatte.

---

## 9. Was offen bleibt

Ehrlich und mit Namen:

* **Zeitstempel im OFS** (Auftrag Punkt 3, zweite Haelfte). Der Inode ist
  **exakt voll**: 128 Oktette, und `I_TYPE 0`, `I_SIZE 8`, `I_NLINK 16`,
  elf direkte Bloecke `24..111`, `I_INDIRECT 112`, `I_DINDIRECT 120`
  lassen kein Feld frei. Drei Zeitstempel brauchen entweder einen Inode
  von 256 Oktetten (dann aendern sich `INODES_PER_BLOCK`,
  `INODE_BLOCKS` und `DATA_START` — also das **Format auf der Platte**,
  und `tools/osum/mkfs.py` muss Oktett fuer Oktett mitziehen) oder drei
  direkte Bloecke weniger (dann sinkt die groesste Datei von 2 135 552
  auf 2 134 016 Oktette, eine Zahl, die in drei Testlaeufern steht).
  Beides ist machbar, beides ist ein Formatwechsel, und ein Formatwechsel
  gehoert nicht in die letzte Stunde einer Runde. `ls -l` zeigt deshalb
  weiter kein Datum. **Die Uhr darunter ist fertig** — `time.split`
  rechnet aus Sekunden seit 1970 ein Datum zurueck und wartet nur auf
  die Felder.
* **`/proc` als Dateisystem** (Auftrag Punkt 5, erste Haelfte). Nicht
  gebaut. Was `ps` braucht, gibt es weiter ueber `SYS_OSUM_PSTAT` und
  seit dieser Runde ueber `SYS_OSUM_SIGINFO` (Zustand, Rechenzeit und
  wartende Signale eines fremden Prozesses, nach pid). Das ist ein
  Sonderaufruf und kein Dateisystem — `ps` und `top` von aussen
  funktionieren damit nicht.
* **Threads in Ring 3** (`clone` mit gemeinsamem Adressraum, `futex`).
  Nicht gebaut. Die Nummern (56 und 202) und die Felder im
  Aufgabendatensatz (`T_TGID`, `T_SHARED`, `T_FUTEX`, `T_FUTEXVAL`) sind
  reserviert und in der Karte eingetragen, damit K7 und K8 sie nicht
  belegen. `gettid` (186) antwortet heute mit der pid.
* **Auftragssteuerung in der Shell selbst** (`&`, `fg`, `bg`, `jobs`).
  Der Unterbau ist vollstaendig und gemessen — `setpgid`, `getpgid`,
  `setsid`, `TIOCSPGRP`, `TIOCGPGRP`, SIGTSTP, SIGCONT, SIGTTIN, und
  STRG-C an die Vordergrundgruppe. Was fehlt, ist die Auftragstabelle in
  `kernel/user/sh.fi`. `tools/unix/run.sh` misst die vier Bausteine
  einzeln (`job ctlc`, `job tstp`, `job cont`, `job ttin`), aber die
  Shell nutzt sie noch nicht.
* **`siginfo_t` und `ucontext`** werden einer Behandlungsroutine nicht
  uebergeben: rsi und rdx sind null. Zwei Zeiger auf nichts waeren
  schlimmer als zwei ehrliche Nullen. `SA_SIGINFO` wird angenommen und
  hat keine Wirkung.
* **`SA_RESTART`** wird angenommen und hat keine Wirkung: ein
  unterbrochener Systemaufruf gibt immer `-EINTR` und wird nicht neu
  begonnen.
* **Kein `wait4` mit `WUNTRACED`/`WCONTINUED`.** Ein Elternteil erfaehrt
  vom Anhalten seines Kindes ueber SIGCHLD, aber nicht ueber `wait4`.

---

## 10. Die Zahlen des Abnahmelaufs

    1.  der festgenagelte Uebersetzer                     5
    2.  freistehend uebersetzen                          14
    3.  std.core im Kernel                               20
    4.  der Kern laeuft                                 175
    5.  ein Programm von der Platte                     130
    6.  PCI, APIC, NVMe                                  56
    7.  die POSIX-Schicht und die libc                  134
    8.  vier Prozessoren                                 43
    9.  ein Userland                                     91
    10. Handles statt Umgebungsautoritaet                26
    11. Multiboot-Kopf und UEFI-Pfad                     14
    12. was jedes Unix-Programm voraussetzt (K9)        107

Die Abschnitte 1 bis 11 sind unveraendert gruen. Zwei Erwartungen darin
mussten mitziehen, und beide sind Zaehlungen und keine Zusagen: die Zahl
der `syscall`-Befehle in `.utext` ist um eins gewachsen (der
Trampolinsprung), und `tools/kernel/run.sh` sowie `tools/osum/run.sh`
vergleichen die Ausgabe zweier Laeufe Zeile fuer Zeile — deshalb melden
sich die Uhr und der Zufall nur unter dem Wort `unix` auf der
Kommandozeile. Sie sind die einzigen zwei Zeilen im ganzen Kernel, die
sich zwischen zwei Laeufen desselben Abbilds **unterscheiden muessen**.
