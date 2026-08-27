# Runde SPEICHER — die Frage "was frisst meinen Platz", ohne die Platte zu durchlaufen

Justin hat sich am 27.08.2026 "so ein Tool wie TreeSize, nur besser und
bereits integriert" gewuenscht. Diese Runde baut es: `/bin/speicher` als
Fenster, `/bin/du` auf der Kommandozeile, und darunter ein Index, der die
Groessen mitfuehrt statt sie zu suchen.

## Worin der Unterschied besteht

TreeSize und WizTree beantworten dieselbe Frage. Beide muessen dafuer
beim Start die Platte lesen — WizTree die Master File Table von NTFS am
Stueck, TreeSize Verzeichnis fuer Verzeichnis —, und beide fangen bei
jedem Start von vorn an. Deshalb hat jedes von beiden einen
Fortschrittsbalken.

Osum hatte seit Runde K15 die eine Haelfte dessen, was man braucht, um
darauf zu verzichten: ein **Aenderungsjournal des Dateisystems**
(`kernel/nidx.fi`), Vorbild "Everything" von voidtools. Ein Ring im
Kernelspeicher, beschrieben an genau zwei Stellen — `fs.dir_add` und
`fs.dir_remove` —, aus dem Ring 3 sich eine Namensliste im Speicher
aufbaut und nachfuehrt.

Diese Runde legt die **Groesse** dazu, aufsummiert bis zur Wurzel. Damit
ist die Antwort auf "wie gross ist /daten" ein Feldzugriff und kein
Durchlauf.

## Die Zahlen

Gemessen im Gast, mit derselben Uhr, unmittelbar hintereinander — damit
Last auf dem Wirt beide Zahlen gleich trifft. Abbild `inhalt.img`:
4000 Dateien in 17 Ordnern, davon 308 mit Inhalt, 419.868 Oktette unter
`/daten`, Inode-Tabelle mit 4096 Eintraegen, Abbild zwei Megaoktett.
QEMU ohne KVM, emulierte IDE.

| | |
|---|---|
| Aufbau des Index (einmalig, 4030 Inodes) | **1.365.386 µs** = 1,37 s |
| Abfrage aus dem Index (`/daten`) | **13,4 µs** (zehn Abfragen in 134 µs) |
| Vollstaendiger Verzeichnisdurchlauf (`/daten`) | **220.661.633 µs** = 220,66 s |
| Verhaeltnis Abfrage : Durchlauf | **1 : 16.467.286** |
| Verhaeltnis Aufbau : Durchlauf | **1 : 161,6** |

Die zweite Zeile von unten ist die eigentliche Zusage: eine Antwort in
dreizehn Mikrosekunden statt in dreieinhalb Minuten.

Die letzte Zeile ist die ehrlichere Zahl, und sie steht hier, weil ohne
sie ein Einwand offen bliebe: der Index muss ja auch erst einmal
entstehen. Er entsteht ueber `fs.scan` (Systemaufruf 1807), das die
Inode-Tabelle am Stueck liest — genau der Trick, mit dem WizTree schnell
ist. Schon dieser Aufbau ist **161-mal schneller** als der Durchlauf, und
er passiert **einmal**, nicht bei jeder Frage.

Zum Vergleich dasselbe auf `gross.img` (4000 **leere** Dateien, also nur
Namen und Inodes, kein Inhalt, sonst dieselbe Anordnung):

| | |
|---|---|
| Aufbau des Index (4025 Inodes) | 1.289.430 µs = 1,29 s |
| Abfrage aus dem Index | 16,1 µs |
| Vollstaendiger Durchlauf | 244.519.681 µs = 244,52 s |
| Verhaeltnis | 1 : 15.187.558 |

Dass ein Durchlauf ueber **leere** Dateien genauso lange braucht wie
einer ueber Dateien mit Inhalt, ist der eigentliche Beleg: die Zeit
steckt in den Inode-Zugriffen und nicht im Lesen von Inhalten. Genau
deshalb hilft es TreeSize nichts, dass es die Inhalte gar nicht ansieht —
es muss die Inodes trotzdem anfassen. Der Index muss das nicht, weil er
sie schon angefasst hat.

Die beiden Durchlaufzeiten (220,66 s und 244,52 s) unterscheiden sich um
gut ein Zehntel, obwohl sie dieselbe Arbeit tun. Das ist die Last des
Wirts, auf dem gleichzeitig andere Maschinen liefen — und der Grund,
warum in diesem Logbuch Verhaeltnisse stehen und nicht Absolutwerte als
Zusage.

## Dass die Zahl auch stimmt

Eine sofortige, aber falsche Zahl ist wertlos. Deshalb steht die
Richtigkeit hier vor der Geschwindigkeit, und sie wird **dreifach**
gerechnet:

1. aus dem **Index** (`nidx.total_of_ino`),
2. aus einem **echten Verzeichnisdurchlauf** im selben Lauf
   (`nidx.walk_total`),
3. auf dem **Wirt**, in Python, aus der Liste, aus der das Abbild gebaut
   wurde (`tools/speicher/baum.py` schreibt `soll`).

Der dritte Weg ist der wichtigste. Die ersten beiden stehen in derselben
Datei, lesen dieselben Inodes ueber dieselben Systemaufrufe, und ein
Denkfehler in der Regel, **was** gezaehlt wird ("zaehlt ein Verzeichnis
seine eigene Eintragstabelle mit?"), stuende in beiden gleich falsch
drin. Der Wirt weiss vom Kernel nichts.

`du -p` prueft **jedes** Verzeichnis des Abbilds.
`tools/speicher/pruefen.py` haelt alle drei Zahlen nebeneinander:

```
pruefen: 21 Verzeichnisse aus dem Gast, davon 17 auch gegen die Arithmetik des Wirts
  /                        idx=1101656  lauf=1101656  kb=1357   OK
  /daten                   idx=419868   lauf=419868   kb=686    OK
  /daten/messing           idx=77993    lauf=77993    kb=111    OK
  /daten/nickel/tief       idx=50288    lauf=50288    kb=67     OK
  ... (alle 21)
pruefen: alle 21 Verzeichnisse Oktett fuer Oktett gleich (Index = Durchlauf = Wirt)
```

Fuer `/`, `/bin`, `/lib` und `/etc` gilt nur der Vergleich Index gegen
Durchlauf: dort liegen Programme und Schriften, die `baum.py` nicht
kennt, weil `bauen.sh` sie dazulegt.

Auch die Oberflaeche rechnet sich selbst gegen: `/bin/speicher` macht bei
**jedem** Ortswechsel einen vollstaendigen Durchlauf des angezeigten
Verzeichnisses und schreibt das Ergebnis auf die serielle Leitung
(`speicher: probe idx=… lauf=… ok=…`).

## Das Journal muss Wachstum mitbekommen, nicht nur Namen

Ein Namensindex merkt, dass es einen Namen mehr gibt. Ein Speicherindex
muss zusaetzlich merken, dass eine Datei **gewachsen** ist — und das
passiert viel oefter, als dass eine entsteht. Genau das kann TreeSize
nicht: es hat keine Verbindung zum Dateisystem und muss neu durchlaufen.

Die Aenderung geht deshalb ueber **dieselben zwei Stellen** wie bisher
die Namen, plus **eine dritte** fuer die Groesse — dort, wo `fs.fi` die
Groesse einer Inode fortschreibt. Nicht verstreut ueber `write`,
`truncate` und `create` einzeln.

`du -w` schreibt achtzig Bloecke zu 512 Oktetten in eine neue Datei und
rechnet nach:

```
du: schreib datei=/daten/schreibprobe.bin bloecke=80  okt=40960
du: schreib nachgezogen gezogen=81 lost=0  vorher=1101656  nachher=1142616  erwartet=1142616  ok=1
du: schreib weg        gezogen=2  lost=0  jetzt=1101656   vorher=1101656                     ok=1
du: schreib bauten=1
```

Die Summe bewegt sich um **genau** 40.960 Oktette, das Loeschen bringt
**genau** den alten Stand zurueck, und `bauten=1` heisst: der Index wurde
im ganzen Lauf **einmal** gebaut. Ein Index, der nach jeder Aenderung neu
baut, waere keiner.

**Die Gegenprobe** (`du -W`, dasselbe ohne Nachziehen):

```
du: schreib nachgezogen gezogen=0 lost=0  vorher=1101656  nachher=1101656  erwartet=1142616  ok=0
```

Der Index steht daneben — **also hat vorher wirklich das Journal
gezogen** und nicht ein Zufall.

> Diese Gegenprobe war in ihrer ersten Fassung wertlos, und das gehoert
> ins Logbuch: sie setzte fuer den Lauf ohne Journal `erwartet = vorher`
> und meldete daraufhin `ok=1`. Die Probe senkte ihre eigene Messlatte
> auf das, was ohnehin herauskam, und konnte gar nicht durchfallen.
> Berichtigt in `kernel/user/du.fi`: erwartet wird **die Wahrheit auf der
> Platte**, in beiden Faellen.

Nebenbei ist damit auch die Vergroesserung des Rings belegt. Er fasste
56 Saetze; seit dieser Runde ist **jeder `write`, der eine Datei
waechst, ein Satz**, und achtzig Bloecke ergeben 81 Saetze. Mit 56 waere
er uebergelaufen (`lost > 0`, Neuaufbau noetig), mit 127 nicht — und
`lost=0` in der Zeile oben ist der Beweis. Der Ring liegt dafuer nicht
mehr in der geteilten Seite aus K15, sondern in zwei eigenen
(`kstate.JRNL_OFF = 0x5E000`, `JRNL_MAX = 0x2000`).

## Die Oberflaeche

`/bin/speicher`, gestartet mit `wigspeicher` auf der Kernel-Kommandozeile
(Modusbit `M_WIGSPEICHER`, 1 << 54), auf der Widget-Bibliothek aus K15:

* **links** der Baum — Groesse und Anteil je Eintrag, das Groesste zuerst.
  Ein Ordner traegt die Summe seines ganzen Teilbaums.
* **rechts** die groessten Dateien unter diesem Ort, egal wie tief.
* **unten** die Kacheln — eine Flaeche je Eintrag, so gross wie sein
  Anteil, abwechselnd laengs und quer geschnitten ("slice and dice",
  Shneiderman 1991; die einzige Treemap, die ohne Gleitkomma auskommt).
* **Loeschen** aus dem Programm heraus; danach stimmen die Zahlen sofort
  wieder, weil das Journal den Wegfall meldet.

Der ganze Aufbau der Anzeige — Baum, die 24 groessten Dateien, Kacheln —
braucht **5.882 µs**:

```
speicher: cd /daten ino=15  kinder=8  okt=419868  kb=686  us=5882  gross=24
speicher: zeile i=0 okt=77993 pm=185 dir=1 name=messing
...
speicher: kachel i=0 x=9 y=307 w=130 h=62 farbe=5273279 name=messing
```

Die acht Zeilen summieren sich auf **419.868** — dieselbe Zahl wie `du`
und wie der Wirt. Die Promilleangaben ergeben zusammen 994 ‰ (der Rest
sind die Rundungen nach unten).

**Die Kacheln werden im Bild nachgemessen**, nicht im Quelltext geglaubt
(`tools/speicher/kachelprobe.py`). Das ist die Lehre aus Runde K7B: ein
Programm, das die Flaechen falsch aufteilt, meldet die falschen Flaechen
genauso zuversichtlich.

```
kachelprobe: 8 Kacheln, Versatz des Fensterinhalts 40,60
  messing    gemeldet w=130   im Bild 128
  nickel     gemeldet w=115   im Bild 113
  ...
  blei       gemeldet w=56    im Bild 54
kachelprobe: die Breiten fallen mit dem Anteil: ja
```

Jede Kachel ist im Bild genau zwei Bildpunkte schmaler als gemeldet —
das ist ihr Rahmen, links und rechts einer.

Bildschirmfotos: `docs/bilder/speicher/speicher.png` (und `-ohne-index.png`
als Gegenprobe), erzeugt von `tools/speicher/run.sh`.

## Weg B — noch einmal geprueft, und warum es bei A bleibt

Der Kommentarkopf von `kernel/nidx.fi` nennt zwei Wege und einen
verworfenen:

* **A** — der Kernel merkt sich die Aenderung in einem Ring im
  Arbeitsspeicher. Gewaehlt.
* **B** — ein Journal **auf der Platte**, in OFS. Das treuere
  Gegenstueck zu NTFS, mit einem echten Vorteil: es ueberlebt den
  Neustart, der Index muesste nach dem Hochfahren nicht neu gebaut
  werden.

B war verworfen worden, **weil es ein geaendertes Format auf der Platte
gekostet haette** — `mkfs.py`, jedes bestehende Abbild, jeden Abschnitt
von `test.sh`, der eines baut. Die parallel laufende Runde **OFS3**
aendert das Format ohnehin (mehrblockige Blockbitmap, Inode 128 → 256
Oktette, Zeitstempel, laengere Namen, `rename`, symbolische Verweise).
Damit faellt das teuerste Argument gegen B weg, und die Frage war neu zu
stellen.

**Entscheidung: es bleibt bei A.** Nicht aus Traegheit, sondern weil die
Rechnung nach dem Wegfall dieses einen Arguments immer noch klar
ausfaellt:

* **Was B spart, ist genau ein Aufbau je Hochfahren.** Gemessen:
  **1,37 Sekunden**, einmal, im Hintergrund moeglich.
* **Was B kostet, ist ein Blockschreibvorgang auf dem Pfad jedes
  `write`.** Ein Journal auf der Platte muss geschrieben werden, bevor
  die Aenderung gilt — sonst ueberlebt es den Neustart eben nicht, und
  dann hat man den Aufwand ohne den Nutzen. Der Pfad, der dadurch dauernd
  teurer wuerde, ist der, den **jedes** Programm bei **jedem** Schreiben
  benutzt.
* **B verlagert ein geloestes Problem in ein ungeloestes.** Ein Ring im
  Speicher, der ueberlaeuft, meldet `lost` und der Leser baut neu — das
  steht, ist gemessen, und ist genau das, was Everything tut, wenn das
  USN-Journal umlaeuft. Ein Journal auf der Platte, das vollaeuft,
  waehrend der Schreiber gerade keinen freien Block hat, ist eine
  Verklemmung im Dateisystem. Das ist keine Runde, das ist mehrere.
* **Die Zusage der Runde haengt nicht daran.** Gemessen wird "Antwort aus
  dem Index gegen Antwort aus dem Durchlauf": 13,4 µs gegen 220,66 s. B
  wuerde daran **nichts** aendern — es aendert nur, ob am Anfang 1,37
  Sekunden anfallen.

Ein Index, der beim Hochfahren 1,37 Sekunden braucht, ist ein besserer
Handel als ein Dateisystem, das bei jedem Schreiben einen Block mehr
schreibt.

## Abstimmung mit OFS3

Geprueft wurde, bevor am Inode-Format etwas angefasst wurde — es wurde
dann auch **nichts** daran angefasst; diese Runde legt kein Feld in die
Inode, sondern haelt die Summen in Ring 3 und im Journal.

Die beiden Runden beruehren sich an drei Stellen, und alle drei sind
kollisionsfrei:

| | speicher | ofs3 |
|---|---|---|
| kdata | `JRNL` 0x5E000–0x60000 | `OFS3` 0x5A000–0x5C000 |
| `KDATA_SIZE` | 0x60000 (unveraendert) | 0x70000 (waechst) |
| Syscall-Nummern | keine neue (nur Unter-Code `WX_ROOT = 6`) | 1822, 1823 |
| Modusbits | `M_WIGSPEICHER` = 1 << 54 | keines |

`tools/kernel/karte.py` sagt auf beiden Zweigen 0 Kollisionen (speicher:
52 Bereiche in 0x60000; ofs3: 52 Bereiche in 0x70000). Der Merge sollte
sich auf `kstate.fi` (zwei benachbarte Konstantenbloecke), `sys.fi` und
`karte.py` beschraenken.

## Was NICHT bewiesen ist

Das ist der wichtigste Abschnitt, und er ist absichtlich lang.

1. **Es ist kein Vergleich mit TreeSize oder WizTree.** Gemessen wurde
   Osum gegen Osum — Index gegen Durchlauf. Dass TreeSize durchlaufen
   *muss*, ist eine Aussage ueber seinen Aufbau, keine Messung an seinem
   Programm. Wer "16 Millionen mal schneller als TreeSize" daraus macht,
   liest etwas hinein, das hier nicht steht.
2. **Die Zeiten gelten fuer QEMU ohne KVM.** Jeder Inode-Zugriff ist
   emulierte IDE. Auf echter Hardware waeren beide Zahlen kleiner, und
   der Durchlauf vermutlich staerker als die Abfrage — das Verhaeltnis
   ist also **nicht** auf Blech uebertragbar. Es bleibt gross, aber die
   Zahl 16.467.286 ist eine Zahl **dieses** Aufbaus.
3. **Der Wirt war waehrend der Messung nicht leer.** Es liefen weitere
   Maschinen. Abfrage und Durchlauf wurden hintereinander im selben Gast
   gemessen, Last trifft also beide — aber es sind keine Laborwerte.
4. **Nur 308 von 4000 Dateien haben Inhalt.** Die Blockkarte von OFS ist
   ein Block, also 4096 Bloecke, also zwei Megaoktett; mehr passte nicht.
   Ein Dateisystem mit viertausend **grossen** Dateien ist nicht
   gemessen. (OFS3 hebt genau diese Grenze auf.)
5. **Der Index fasst 4200 Namen.** Darueber sagt er "abgeschnitten", und
   die Statuszeile zeigt es — aber ein Dateisystem, das darueber liegt,
   ist **nicht** gemessen. Es gibt kein Nachladen, keine Auslagerung.
6. **Harte Verweise sind nicht geprueft.** Seit K15 kann ein Inode zwei
   Namen haben (`neu@vorhanden`). Ob seine Groesse dann auf beiden Pfaden
   nach oben gezaehlt wird — und ob das ueberhaupt richtig waere — steht
   in keinem Testlauf dieser Runde. Das Testabbild enthaelt keinen.
   **Das ist die naechstliegende Luecke.**
7. **Gezaehlt wird die Groesse, nicht der belegte Platz.** Eine Datei von
   einem Oktett belegt einen Block zu 512; dieses Werkzeug sagt "1". Das
   ist die Regel von `du --apparent-size` und dieselbe wie in Osum seit
   K11 — TreeSize tut standardmaessig das andere. Ein Verzeichnis zaehlt
   seine eigene Eintragstabelle nicht mit.
8. **Kein Absturzverhalten geprueft.** Der Index lebt im Arbeitsspeicher
   und wird beim Hochfahren neu gebaut; was bei einem Absturz *waehrend*
   einer Aenderung mit den Summen passiert, ist nicht untersucht. Bei Weg
   A ist die Frage klein (nach dem Neustart wird ohnehin neu gebaut) —
   bei Weg B waere sie gross gewesen. Auch das spricht fuer A.
9. **Das Loeschen aus der Oberflaeche ist nicht ueber den Monitor
   bedient worden.** Der Weg steht im Programm und die Journalseite
   davon ist ueber `du -w` gemessen (`du: schreib weg … ok=1`), aber ein
   Lauf, der den Knopf wirklich drueckt und danach das Bild nachmisst,
   fehlt.
10. **Der Merge mit OFS3 ist nicht vollzogen.** Die Kollisionsfreiheit
    ist geprueft, der Merge selbst nicht durchgefuehrt.

## Dateien

| Datei | |
|---|---|
| `kernel/nidx.fi` | das Journal, jetzt mit Groessen; Ring 56 → 127 Saetze |
| `kernel/fs.fi` | die eine Stelle, an der eine Groesse fortgeschrieben wird |
| `kernel/kstate.fi` | `JRNL_OFF` in zwei eigene Seiten; `M_WIGSPEICHER` |
| `kernel/sys.fi` | `WX_ROOT` — die Wurzelinode wird abfragbar |
| `kernel/kmain.fi` | `wigspeicher` startet `/bin/speicher` |
| `kernel/user/nidx.fi` | Summen den Baum hinauf, `total_of_ino`, `walk_total` |
| `kernel/user/speicher.fi` | `/bin/speicher` — Baum, groesste Dateien, Treemap |
| `kernel/user/du.fi` | `-m` messen, `-p` alles pruefen, `-w`/`-W` schreiben |
| `tools/speicher/bauen.sh` | Kernel, Programme, beide Abbilder |
| `tools/speicher/run.sh` | der Laeufer mit den Messungen |
| `tools/speicher/baum.py` | das Abbild mit Inhalt **und** die Wahrheit dazu |
| `tools/speicher/pruefen.py` | die drei Zahlen nebeneinander |
| `tools/speicher/kachelprobe.py` | die Treemap im Bild nachgemessen |
| `tools/gfx/ppm2png.py` | PPM → PNG, nur mit `zlib` |
