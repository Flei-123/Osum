# Runde O-CONTAINER: Container im Stil von LXC

Zweig `container`. Gebaut, gemessen, nicht nach `main` verschmolzen.

Osum soll als Serverbetriebssystem laufen und mehrere voneinander
getrennte Systemumgebungen auf EINEM Kern anbieten -- das, was ein
Mensch von Proxmox und LXC kennt. Keine Hardwarevirtualisierung: die
gibt es in Osum nicht und sie war nicht Teil des Auftrags.

---

## 1. Was ein Container hier IST

Der Satz, um den sich die ganze Runde dreht:

> **Ein Container ist eine Zahl im Aufgabensatz, und alles, was diese
> Zahl bedeutet, steht in EINEM Datensatz.**

`sched.T_CTR` ist die Zahl. `0` ist der Wirt -- und das ist der Wert, auf
dem jeder Aufgabensatz steht, den nie jemand angefasst hat. Jeder Prozess,
den es vor dieser Runde gab, ist damit im Wirt und merkt von der Runde
nichts.

### Die Handle-Sicht gegen die Linux-Namensraum-Sicht

Der Auftrag nennt `kernel/cap.fi` als Ausgangspunkt, und das ist richtig
gelesen. Dort stehen drei Saetze im Kopf der Datei:

1. Eine frische Handle-Tabelle ist LEER -- nichts wird geerbt.
2. Ein Handle ist Slot + Generation.
3. Rechte koennen NUR KLEINER werden (`restrict` ist eine Schnittmenge).

Diese Runde baut **den dritten Satz fuer Dinge, die kein Handle sind**:

| Eigenschaft | Einbahnstrasse | wo geprueft |
|---|---|---|
| die Wurzel | nur TIEFER, nie hoeher | `ctr.may_reroot` |
| die Speichergrenze | nur KLEINER, nie groesser | `ctr.may_limit` |
| die Zugehoerigkeit | nur HINEIN, nie hinaus | es gibt kein `CTRLEAVE` |

Das ist derselbe Gedanke wie `cap.rights_restrict`, und er ist aus
demselben Grund richtig: **eine Schranke, die der Eingesperrte selbst
oeffnen kann, ist keine.**

Der Unterschied zu Linux in einer Tabelle:

| | Linux | hier |
|---|---|---|
| Zugehoerigkeit | 7 Namensraeume (mnt, pid, net, ipc, uts, user, cgroup), jeder mit eigener Lebensdauer und eigenem Erbe | EIN Feld, `sched.T_CTR` |
| Grenzen | cgroups -- eine zweite, voellig getrennte Hierarchie | dieselben 256 Oktette wie alles andere |
| Wurzel | `chroot`/`pivot_root`: der Prozess haengt an einem anderen Wurzel-Inode | eine Zeichenkette, die bei JEDEM Pfad vorn steht |
| Ausbruch aus der Wurzel | klassisch: offener Deskriptor auf ein Verzeichnis draussen, `fchdir`, dann `..` | unmoeglich -- siehe unten, es wird GEFALTET |
| Anzahl der Stellen, die stimmen muessen | zwei Dutzend, einzeln entstanden, einzeln umgehbar | eine je Zusage |

**Warum Linux' `chroot` ausbrechbar ist und dieser Weg nicht.** `chroot`
verlaesst sich darauf, dass die Pfadaufloesung an der neuen Wurzel
haengenbleibt. Das haelt, solange niemand einen offenen Deskriptor auf ein
Verzeichnis ausserhalb behaelt -- der klassische Ausbruch ist `fchdir`
dorthin und dann `..` bis zur echten Wurzel.

Hier ist die Wurzel **keine Eigenschaft eines Inodes**, sondern eine
Zeichenkette, die in `uio.resolve` bei jedem Pfad vorn steht. Und die
Reihenfolge ist die eigentliche Zusage:

```
    ZUERST FALTEN, DANN VORANSTELLEN.
```

`ctr.fold` laeuft die Glieder ab und wirft bei `..` das letzte weg -- und
wenn nichts mehr da ist, bleibt es bei `/`. Aus `/../../../etc/passwd`
wird so `/etc/passwd`, und ERST DANN kommt `/c/eins` davor. Der Ausbruch
ist nicht *abgelehnt* worden, er ist **unmoeglich geworden**: ein `..` an
der Wurzel des Containers zeigt auf die Wurzel des Containers, genau wie
`..` in `/` auf `/` zeigt.

Wer stattdessen nach der Zeichenfolge `..` sucht und den Pfad ablehnt, hat
eine Schranke gebaut, die `/a/b/../../..` nicht faengt.

---

## 2. Was gebaut ist -- die fuenf Stufen

| Stufe | Zustand | wo |
|---|---|---|
| 1. Eigene Wurzel je Container | **fertig, gemessen** | `ctr.jail` / `ctr.fold`, angewandt in `uio.resolve` |
| 2. Ressourcengrenzen (Speicher + CPU) | **fertig, gemessen** | `ctr.mem_charge` in `proc.map_page`; `sched.budget_for` |
| 3. Eigene Prozesssicht | **fertig, gemessen** | `ctr.visible` in `sys.do_pstat`, `signal.do_kill`, `uio.kill_pid` |
| 4. Netz je Container | **Anfangswert gesetzt, auf `netview` aufgesetzt** | `ctr.netview_of` -> `netview.set_view` in `do_ctrenter` |
| 5. Das Werkzeug `ctr` | **fertig** | `kernel/user/ctr.fi` |

### Stufe 1 -- die Wurzel

Eine Zeichenkette je Container (`X_ROOT`, 96 Oktette). Angewandt an
**genau einer Stelle**: `uio.resolve`. Das ist die Funktion, durch die
jeder Pfad aus Ring 3 laeuft, bevor ein Dateisystem ihn sieht --
`open`, `stat`, `execve`, `unlink`, `mkdir`, `chdir` und jeder andere
Aufruf. Es gibt **keine Liste von Aufrufen, die gepflegt werden muesste**;
es gibt diese Funktion.

Beide Wege durch `resolve` sind eingesperrt: der absolute Pfad (dort steht
die Zeile vor dem `return`) und der mit dem Arbeitsverzeichnis
vervollstaendigte.

### Stufe 2 -- die Grenzen

**Speicher.** Gezaehlt wird in RAHMEN (4096 Oktette), weil das die Einheit
ist, in der dieser Kern Speicher vergibt. Die Kasse sitzt in
`proc.map_page` -- der EINEN Stelle, an der dieser Kern einem Prozess eine
Seite gibt. Der ELF-Lader, `brk`, `mmap`, der wachsende Stapel und `fork`
gehen alle dort durch. *Eine Grenze, die an vier Stellen geprueft wird,
ist an der fuenften offen.*

Gefragt wird **vor** `mem.frame_alloc`, nicht danach: wer erst nimmt und
dann prueft, muss im Fehlerfall zurueckgeben -- und genau dieser
Rueckgabepfad ist der, den niemand testet. Ist der Speicher der MASCHINE
alle (nicht der des Containers), wird die Buchung zurueckgenommen.

Die Gegenbuchung steht in `proc.free_space`, wo die Aufgabe noch ihre
Containernummer traegt und `freed` genau die Zahl der zurueckgegebenen
Rahmen ist.

**CPU.** Ein Anteil 1..100, der auf die LAENGE der Zeitscheibe wirkt
(`sched.budget_for`), nicht auf die Auswahl des naechsten Prozesses.
Bewusst: dieser Kern hat einen Rundlauf, und eine zweite Rangordnung
daneben waere ein zweiter Verteiler mit eigenen Hungerfaellen. Ein Anteil
von 1 ergibt mindestens Budget 1 -- ein Container mit kleinem Anteil soll
langsam sein, nicht tot.

`sched.fi` kann `ctr.fi` nicht importieren (`ctr` importiert `sched`, das
waere ein Ring). Uebernommen sind deshalb nur die drei Zahlen, die das
Feld beschreiben; sie stehen dort beieinander und sind so benannt wie in
`ctr.fi`.

### Stufe 3 -- die Prozesssicht

Eine Regel mit genau einer Ausnahme (`ctr.visible`):

* **Der Wirt sieht alle.** Keine Nachlaessigkeit, sondern die Bauart von
  Proxmox: der Wirt fuehrt die Container, also muss er ihre Prozesse sehen
  und beenden koennen.
* **Ein Container sieht nur sich selbst.** Nicht den Wirt, nicht die
  Geschwister.

Angewandt an **drei** Tueren, und alle drei waren noetig:

1. `sys.do_pstat` -- was `ps` und `top` sehen. Eine unsichtbare Aufgabe
   meldet sich als freier Platz (0 auf jedes Feld). Der Container sieht
   eine Maschine, auf der ausser ihm nichts laeuft; er sieht **keine
   Luecke**, aus der er auf die Nachbarn schliessen koennte.
2. `signal.do_kill` -- alle vier Zielarten (eine pid, die eigene Gruppe,
   eine fremde Gruppe, "an alle").
3. `uio.kill_pid` -- der zweite Weg, auf dem in diesem Kern ein Prozess
   stirbt. *Waere die Schranke nur an einer der beiden Stellen, waere die
   Grenze so dicht wie die offenere von beiden.*

Abgewiesen wird mit **-ESRCH und nicht -EPERM**: die Nummer soll dem
Container nicht verraten, dass es den Prozess gibt. Dasselbe tut Linux'
pid-Namensraum, aus demselben Grund.

### Stufe 4 -- das Netz

Auf `netview` **aufgesetzt, nicht danebengebaut**. Der Container traegt
einen Anfangswert (`X_NETV`); `do_ctrenter` schreibt ihn beim Eintritt
nach `sched.T_NETV`. Danach gilt ausschliesslich das Feld, das es schon
gab, und `netview.decide` bleibt die einzige Entscheidungstuer. Es gibt
**keine zweite**.

Das ist die ehrliche Beschreibung des Standes: der Container kann seinen
Prozessen `faked` oder `none` mitgeben, und das wirkt. Eine eigene
Adresse je Container gibt es nicht -- siehe Abschnitt 6.

### Stufe 5 -- das Werkzeug

```
ctr list                      was es gibt
ctr create <name> <wurzel>    anlegen -> Nummer
ctr set <nr> mem <rahmen>     Speichergrenze (NUR KLEINER)
ctr set <nr> cpu <1..100>     Anteil an der Rechenzeit
ctr set <nr> procs <n>        hoechste Prozesszahl
ctr set <nr> net <sicht>      real|filtered|faked|none
ctr start|stop <nr>           Zustand
ctr exec <nr> <befehl> ...    darin ausfuehren
ctr destroy <nr>              abraeumen (nur wenn leer)
ctr show [nr]                 die Zahlen
```

Das Abbildformat ist ein **Verzeichnisbaum** -- die erste Runde, wie im
Auftrag vorgesehen. `/c/eins` mit `/c/eins/bin` und `/c/eins/etc` darin
ist ein Container. Ein Tar-Abbild waere die Kuer und ist nicht gebaut.

**Wie `ctr exec` wirklich funktioniert**, denn das ist die einzige Stelle,
an der das Programm mehr tut als einen Aufruf weiterreichen: `SYS_CTRENTER`
geht hinein, und es gibt keinen Weg zurueck. Wuerde `ctr` also eintreten
und danach den Befehl starten, waere ES selbst fuer immer drin -- `ctr
exec 1 /bin/sh` gefolgt von `ctr list` waere unmoeglich. Gebaut ist
deshalb: `fork`, im KIND eintreten und `execve`, im ELTERNTEIL warten.
Dieselben drei Zeilen wie `netview faked <prog>`, mit `enter` an der
Stelle, an der dort `view_set` steht.

---

## 3. Die Zahlen aus `tools/container/run.sh`

```
CONTAINER: 52 passed, 0 failed
```

Jede Zusage hat ihre Gegenprobe. Das ist bei einer Einsperrung besonders
noetig, denn `cat /etc/wirt-geheim` zeigt AUCH dann nichts, wenn es die
Datei gar nicht gibt, `cat` fehlt oder der Kern beim Start
stehengeblieben ist.

| Zusage | Gegenprobe | gemessen |
|---|---|---|
| Container liest `/etc/wirt-geheim` nicht | **derselbe Befehl im WIRT liest ihn** (`WIRT-GEHEIM-7731`) | beides gruen |
| Ausbruch mit `..`, absolut und gemischt scheitert | Container liest im selben Lauf seine EIGENE `/etc/eigen` (`CONTAINER-EIGEN-4242`) -- der Pfad wird UMGEBOGEN, nicht verworfen | beides gruen |
| Speichergrenze greift bei 96 von 64 Rahmen | derselbe Aufruf UNTER der Grenze (32 Rahmen) geht durch | beides gruen |
| " | derselbe Aufruf OHNE Grenze geht durch | `stress: ok 6` |
| " | der WIRT nimmt sich danach 96 Rahmen | `stress: ok 6` |
| `kill` ueber die Grenze scheitert | es steht ausdruecklich `abgewehrt 1` da und NICHT `getroffen 1` | beides gruen |
| Container sieht weniger Prozesse | **Wirt sieht 4, Container sieht 1** -- und die 1 ist nicht 0, also lebt `pstat` | beides gruen |
| Grenze laesst sich nicht oeffnen | 64 -> 32 wird angenommen, 32 -> 4096 und 32 -> 0 nicht; sie steht am Ende auf 32 | gruen |
| Wurzel laesst sich nicht anheben | `/` und `/c` werden abgelehnt, sie steht weiter auf `/c/eins` | gruen |

Der Kern meldet selbst (`ctr.report`):

```
ctr: count=1   ctr: created=1   ctr: destroyed=0   ctr: escapes=2
ctr[1] lim=32 use=.. peak=.. deny=1 cpu=.. ticks=.. procs=..
```

`escapes` zaehlt abgewehrte Ausbruchsversuche -- *"kein Ausbruch gelungen"
ist erst dann etwas wert, wenn daneben steht, wie viele versucht wurden.*

### Ein Fehler, den der Testlaeufer selbst gefunden hat

Der erste Lauf war **42 passed, 1 failed**, und der Fehlschlag lag im
TEST, nicht im Kern: die Gegenprobe stand auf `stress 40`. 40 Bloecke sind
640 Rahmen -- und der `brk`-Bereich eines Prozesses ist in diesem Kern
`0x40080000..0x400F0000`, also 448 KiB = **112 Rahmen = 7 Bloecke**
(`sys.BRK_BASE`, `sys.MMAP_TOP`). `stress 40` scheitert deshalb AUCH IM
WIRT, an der Adressraumgrenze und nicht an einer Containergrenze.

Die Zusage *"der Wirt bekommt 640 Rahmen"* war gruen und mass nichts.
Beide Proben stehen jetzt auf 6 Bloecke = 96 Rahmen: unter der
Architekturgrenze von 112 und ueber den 64 Rahmen des Containers. Das ist
genau der Fall, den der Auftrag verbietet -- ein Test, der nichts findet
und trotzdem OK meldet.

---

## 4. Die gemessenen Kosten

| | vorher | nachher | Unterschied |
|---|---|---|---|
| Kernabbild | 6 111 524 Oktette | 6 116 760 Oktette | **+5 236 Oktette (+0,086 %)** |
| `kdata` | 129 Bereiche | 130 Bereiche | +1 Seite (`CTR_OFF`, 0x12C000) |
| Aufgabensatz | 648 Oktette belegt | 656 belegt (`T_CTR`) | von 1024 vorhandenen |

**Laufzeit.** Eine Maschine ohne Container zahlt fuer diese Runde:

* je Pfad aus Ring 3: **ein Vergleich** (`ctr.jail_needed` liest
  `T_CTR`, sieht 0 und kehrt um);
* je Seitenzuteilung: **ein Vergleich** (`mem_charge` mit `i == 0` kehrt
  sofort zurueck -- der Wirt zahlt nicht);
* je Aufgabenwechsel: **ein Vergleich** (`budget_for` sieht Anteil 0 und
  gibt die Prioritaet unveraendert zurueck);
* je `pstat`/`kill`: **ein Vergleich** (`visible` sieht Wirt, gibt true).

Kein Schloss, keine Liste, keine Suche. Die Zahl steht im Aufgabensatz,
der beim Wechsel ohnehin angefasst wird.

**Speicher je Container:** 256 Oktette. Acht Container plus drei Zaehler
sind 2072 Oktette -- eine halbe Seite.

Acht und nicht achtzig, weil `kstate.MAX_TASKS` 32 ist: *eine Maschine,
die 32 Aufgaben fuehrt, fuehrt keine 64 Container, und ein Feld, das
groesser ist als das, was es verwalten kann, ist eine Luege ueber die
Groesse des Systems.*

---

## 5. Welche Dateien wie geaendert wurden

Der Auftrag verlangt das ausdruecklich, weil `struktur2` parallel
`kernel/` in Schichten umordnet und dabei Dateien verschiebt. Die
Aenderungen sind deshalb **so eng und so lokal wie moeglich** gehalten:
in den bestehenden Dateien steht fast nirgends mehr als ein Aufruf.

**Neu (5 Dateien, kein bestehender Ablageort veraendert):**

| Datei | Zeilen | was |
|---|---|---|
| `kernel/sched/ctr.fi` | 800 | der ganze Mechanismus |
| `kernel/user/ctr.fi` | 395 | das Werkzeug |
| `kernel/user/stress.fi` | 82 | Messsonde: Speicher anfordern, jede Seite beruehren |
| `kernel/user/ctrkill.fi` | 68 | Messsonde: ueber die Grenze schiessen, Prozesse zaehlen |
| `tools/container/run.sh` | 390 | der Testlaeufer |

**Geaendert (8 Dateien):**

| Datei | Art der Aenderung |
|---|---|
| `kernel/kstate.fi` | `CTR_OFF = 0x12C000`, `CTR_MAX`, beide exportiert. Neuer, bis dahin unbenutzter Bereich hinter `WACH` -- **nichts aus einer bestehenden Seite herausgeschnitten** (der Kopf von `netview.fi` schreibt auf, was das kostet). |
| `kernel/sched.fi` | `T_CTR = 656` (Aufgabensatz hat 1024). Dazu `ctr_share_of`, `ctr_tick`, `budget_for` -- drei Funktionen, weil ein `import ctr` hier ein Ring waere. Zwei bestehende Zeilen in `schedule_locked` rufen jetzt `budget_for` statt `tget(T_PRIO)`. |
| `kernel/uio.fi` | `import ctr`; `resolve` bekommt an seinen zwei `return`-Wegen `jailed(...)`; neue Funktion `jailed`; in `kill_pid` fuenf Zeilen Schranke. |
| `kernel/proc.fi` | `import ctr`; in `map_page` die Kasse vor `frame_alloc` und die Ruecknahme bei Fehlschlag; in `free_space` eine Zeile Gegenbuchung. |
| `kernel/signal.fi` | `import ctr`; in `do_kill` eine Schranke fuer die einzelne pid und eine im "an alle"-Zweig; neue Funktion `send_pgid_from` (statt `send_pgid` eine Signatur zu aendern, die Aufrufer ausserhalb von `kill` hat). |
| `kernel/sys.fi` | `import ctr`; vier Konstantenbloecke und vier Handler (`do_ctrget/set/new/enter` + `ctr_admin`); vier Zeilen Verteilung; `do_pstat` bekommt `me` und eine Schranke; **die Obergrenze des Netzblocks von `SYS_OSUM_SHARE` auf `SYS_OSUM_CTRENTER` gezogen**; fuenf `ctr.inherit` neben den bestehenden `netview.inherit`. |
| `kernel/elf.fi` | `import ctr`; eine Zeile `ctr.inherit` neben `uio.adopt` in `spawn`. |
| `kernel/user/ulib.fi` | Konstanten (`SYS_BRK`, `SYS_FORK`, `SYS_EXECVE`, die vier `SYS_CTR*`, die `CG_*`/`CS_*`-Felder) und ihr Export. Keine Funktion geaendert. |

### Eine Falle, die zugeschnappt ist

Die Aufrufe 1330..1333 waren nach dem ersten Bau **still mit -ENOSYS**
beantwortet worden: in `sys.fi` steht

```firn
if number >= SYS_OSUM_NETGET && number <= SYS_OSUM_SHARE {
    return net_call(...)
}
```

und `SYS_OSUM_SHARE` ist 1322. Genau daneben steht seit der Verschmelzung
von NETVIEW und NETMON ein Vermerk, der vor diesem Fehler warnt. Er ist
trotzdem wieder passiert, beim ersten Lauf des Testlaeufers aufgefallen
und steht jetzt ein zweites Mal dort: **wer einen Block erweitert, muss
die Grenze nachziehen.**

---

## 6. Was zu einem echten LXC-Ersatz noch fehlt

Ehrlich und vollstaendig:

1. **Ein eigenes Netz je Container.** Stufe 4 gibt dem Container die
   `netview`-Sicht mit, und das wirkt -- aber es ist *keine eigene
   Adresse*. Ein LXC-Container hat ein `veth`-Paar, eine eigene IP, eine
   eigene Routingtabelle und eine Bruecke im Wirt. Dafuer braucht es ein
   virtuelles Geraet in `netdev.fi` und eine zweite Adresse in `inet.fi`;
   beides ruehrt an die Dateien, an denen `netzplus` und `ebpf` gerade
   arbeiten, und gehoert deshalb in eine eigene Runde.
2. **Eigene pids.** Der Container SIEHT nur seine Prozesse, aber sie
   tragen die pids des Wirts. Ein LXC-Container hat eine eigene
   pid 1. Fuer `ps` reicht die Sicht; fuer ein `init` im Container nicht.
3. **Eigene Benutzer.** `T_UID` ist global. Benutzer 0 im Container ist
   Benutzer 0 des Wirts -- deshalb muss `ctr_admin` verlangen, dass der
   Aufrufer im WIRT laeuft, und nicht nur euid 0. Linux' `user_namespaces`
   bilden Kennungen aufeinander ab; das fehlt.
4. **Eine Einhaengetafel je Container.** Die Wurzel ist eine Zeichenkette
   im gemeinsamen Dateisystem, kein eigener Mount-Namensraum. Ein
   Container kann nichts eigenes einhaengen.
5. **Ein Tar-Abbild.** Der Verzeichnisbaum ist die erste Runde; ein
   entpackbares Abbild mit Schichten waere die Kuer.
6. **Grenzen fuer alles Uebrige.** Speicher und CPU stehen, Prozesszahl
   ist gebaut aber nicht gemessen. Offene Dateien, Sockets, Platten-E/A
   haben keine.
7. **Ein Kernfehler ist weiter ein Ausbruch.** Alle Container laufen auf
   DIESEM Kern -- so wie LXC-Container auf dem Kern des Wirts laufen. Das
   ist dieselbe Grenze wie dort und wird hier genannt, statt verschwiegen
   zu werden. Wer echte Isolation gegen Kernfehler will, braucht
   Hardwarevirtualisierung, und die gibt es in Osum nicht.
8. **`procs`-Grenze und `cpu`-Anteil sind nicht im Testlaeufer.** Beide
   sind gebaut und der Kern meldet ihre Zahlen (`ctr[..] cpu= ticks=`),
   aber `tools/container/run.sh` misst sie nicht. *Lieber zwei Stufen
   wasserdicht als fuenf halbe* -- gemessen sind Wurzel, Speicher und
   Sicht.

---

## 7. Regression

| Laeufer | Sollwert | gemessen |
|---|---|---|
| `tools/container/run.sh` | neu | **52 passed, 0 failed** |
| `tools/k17/run.sh` | 158 passed, 0 failed | **158 passed, 0 failed** |
| `tools/hotplug/run.sh` | 45 / 0 | **45 passed, 0 failed** |
| `tools/install/abnahme.sh` | 35 gruen / 0 rot | **35 gruen, 0 rot** |

### Zwei Dinge, die dabei passiert sind, und beide gehoeren in den Bericht

**1. `memmap.py` kannte `CTR_OFF` nicht.** Der erste k17-Lauf war
**156 / 2**, und die zwei roten Zusagen waren echt: die Speicherkarte
meldete `kstate.fi:CTR_OFF steht in keiner Karte` und damit
`1 Kollisionen`. Das ist keine Ueberschneidung gewesen, sondern ein
Bereich, den die Karte nicht kannte -- `tools/kernel/memmap.py` fuehrt
eine eigene Liste, und wer eine Seite nimmt, traegt sich dort ein. Eine
Zeile nachgetragen (`("CONTAINER", "kstate.fi", "CTR_OFF", "CTR_MAX")`),
danach 130 Bereiche und **0 Kollisionen**.

**2. Die Abnahme war beim ersten Lauf 15 gruen / 18 rot -- und es lag
NICHT an dieser Runde.** Das musste bewiesen und nicht behauptet werden,
also wurde ein zweiter Arbeitsbaum auf **demselben Ausgangscommit**
(`7e68da55`) ausgecheckt und dieselbe Abnahme dort gefahren:

| | Ausgangscommit `7e68da55` | dieser Zweig |
|---|---|---|
| `tools/install/abnahme.sh` | 35 gruen, 0 rot | 35 gruen, 0 rot |

Der erste Lauf war an `installer: step=5` stehengeblieben, und von dort
fielen alle spaeteren Abschnitte um (keine `limine.conf`, kein Start von
der Platte, kein Geraeteschluessel). Ursache war das **Zeitlimit von
900 Sekunden** um den QEMU-Lauf: die Maschine trug zu dem Zeitpunkt
Fremdlast um 30, und das Kopieren der Wurzel plus das Schreiben des
Bootladers auf die FAT-Partition brauchten laenger als das Limit.
Nachgewiesen im zweiten Lauf, indem die CPU-Zeit des QEMU-Prozesses
mitgelesen wurde (484 s -> 509 s in 25 Sekunden Wanduhr): die Maschine
rechnete, sie hing nicht. Der Lauf kam danach bis `installer: fertig`
und auf 35 / 0.
