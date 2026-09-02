<!-- SPDX-License-Identifier: GPL-2.0-only -->
# Runde STRUKTUR — die Treiber in Verzeichnisse

Zweig `struktur`, Arbeitsbaum `/root/osum-struktur`, abgezweigt von
`main` (163984d). Anlass: Justins Kritik, dass die Treiber schlecht
abgelegt sind. Sie ist berechtigt.

---

## 1. Der Befund vor der Runde

`kernel/` hatte **83 Dateien flach nebeneinander**, 87 706 Zeilen. Ein
e1000-Treiber lag zwischen der Speicherverwaltung und dem Planer.

Die *Trennung* war dabei schon in Ordnung — nur die *Ablage* nicht:

* `netdev.fi` (595 Z.) ist eine ordentliche Treiberschicht: eine Tabelle
  bildet die PCI-Nummer auf einen Treiber ab, jeder Chip hat eine eigene
  Datei (`virtio.fi` 1022 Z., `e1000.fi` 836 Z.) mit einheitlichen Namen.
* `blk.fi` (813 Z.) ist schlechter: `use_ata`, `use_nvme`, `use_ahci`
  stehen als feste Funktionen nebeneinander, und `read_on`/`write_on`/
  `blocks_on`/`present_on` sind **vier parallele `if`-Ketten** über
  `DEV_*`. Ein fünfter Treiber heißt: vier Ketten anfassen.

### Was Kern ist und was Treiber

Die Zuordnung nach einer engen Regel: **Treiber ist, was mit dem Gerät
redet** — Register, Portadressen, Ringe, Unterbrechungen.

| Klasse | Dateien | Zeilen |
|---|---|---|
| **bus** | pci, acpi | 1 030 |
| **net** | netdev, virtio, e1000 | 2 453 |
| **blk** | blk, nvme, ahci | 2 648 |
| **usb** | usb, xhci | 2 851 |
| **input** | kbd, ps2m | 1 571 |
| **gfx** | gfx, gfx-aus, fb, vmode, font | 5 756 |
| *umgezogen* | **17 Dateien** | **16 309** |

**Nicht** mitgezogen, obwohl es naheliegt: `wm.fi` (5 292 Z.,
Fensterserver), `tile.fi` (Fensterbaum), `ttf.fi` (Schriftrasterer),
`ansi.fi` (Terminalemulation), `kgui.fi`, `sysgui.fi`, `wig.fi`,
`dispsave.fi`. Keine dieser Dateien kennt eine Hardwareadresse. Wären
sie mitgegangen, hieße `drivers/` nach zwei Runden nur noch „alles, was
mit Bildschirm zu tun hat", und die Trennung wäre im ersten Schritt
schon verwässert.

Kern bleibt Kern: `sys.fi` (10 027), `kmain.fi`, `kstate.fi`, `mem.fi`,
`sched.fi`, `proc.fi`, `signal.fi`, `handle.fi`, `async.fi`, `cap.fi`,
`perm.fi`, `time.fi`, `elf.fi` — und die Dateisysteme (`fs`, `fat`,
`vfs`, `procfs`, `devfs`, `part`, …), die weder Kern noch Gerätetreiber
sind und eine eigene Klasse verdienen, wenn jemand Zeit hat.

---

## 2. Warum der Umzug billig war

Nachgelesen im Übersetzer (`compiler/src/modules.rs`, Firn a751b3db),
nicht geraten. Zwei Eigenschaften entscheiden alles:

**Ein `import` sucht (1) neben der importierenden Datei, (2) neben der
Wurzeldatei** (`kernel/kmain.fi`, also `kernel/`). Daraus folgt: ein
Treiber erreicht den Kern weiter mit `import kstate`, egal wie tief er
liegt, und Treiber derselben Klasse erreichen einander weiter mit
`import virtio`. Zu ändern war genau eine Sorte Zeile — ein `import` von
*außerhalb* der Klasse. Das waren 88 Zeilen in 14 Dateien.

**Der Modulname ist der Dateiname ohne Suffix, der Pfad steht nicht
darin** (`package.rs`, dort mit Test: `module_name("/a/b/geo.fi") ==
"geo"`). Daraus folgt zweierlei: das Symbol `_F0.virtio__tx_frame`
bleibt Zeichen für Zeichen dasselbe, und weil ein Modul unter dem
*letzten* Pfadteil angesprochen wird, heißt der Aufruf nach `import
drivers.blk.blk` weiter `blk.read(…)`. **Die paar tausend Aufrufstellen
sind unberührt.** Ohne diese Eigenschaft wäre die Runde nicht machbar
gewesen.

Der Umzug selbst steht als Skript im Repo (`tools/struktur/umzug.sh`):
drei Tabellen statt eines Diffs von tausend Zeilen. Alle 17
Verschiebungen sind `git mv`, git erkennt sie als Umbenennung (`R`), die
Geschichte bleibt.

---

## 3. Die Abnahme: das Abbild ist dasselbe geblieben

`tools/struktur/pruefe.sh`, vier Zusagen, **beide Abbilder grün**
(`--gui on/off`, `--ohne-tunnel`).

Eine **Kontrollprobe vorweg**, ohne die der Rest nichts wert wäre:
derselbe Baum zweimal gebaut ergibt oktettgleiches `.text`. (`.rodata`
ist *nicht* reproduzierbar — `build-kernel.sh` übersetzt aus einem
`mktemp -d`-Verzeichnis, und dessen Name steht in jeder Panikmeldung.
Die Namen sind gleich *lang*, darum ist die Größe reproduzierbar.)

| Probe | Ergebnis |
|---|---|
| Symbole | **identisch** — 3 261 (gui=off) bzw. 3 905, keins hinzu, keins weg |
| `.text`-Größe | **identisch** — 1 397 606 bzw. 1 793 654 Oktette |
| Befehlsfolge | 7 549 bzw. 10 435 Abweichungen, **alle klassifiziert**, Klasse „unerklärt" leer |
| `.rodata` | wächst um 9 456 bzw. 17 228 Oktette, **restlos aufgerechnet**, Rest 0 |

Das Abbild ist **nicht** oktettgleich, und das ist richtig so: die
Panikmeldungen tragen den Quellpfad. Die Abweichungen sind

* **852 / 1 541 Stringlängen als Immediate.** Der Panikaufruf bekommt
  Zeiger *und* Länge; die Länge steht als Konstante im Befehl.
  `mov $0x52,%esi` → `mov $0x60,%esi` ist 82 → 96 Zeichen, und 14 ist
  genau `kernel/kbd.fi` → `kernel/drivers/input/kbd.fi`.
* **32 / 33 Absolutadressen** und **6 663 / 8 859 RIP-Versätze**, weil
  `.rodata` wächst und alles dahinter mitrutscht.

Das `.rodata`-Wachstum ist Datei für Datei nachgerechnet: 133 Panikstellen
in `usb.fi` × 12 Zeichen = 1 596 Oktett, 124 in `xhci.fi` = 1 488, …
Summe **9 456**, gemessenes Wachstum **9 456**, **Rest 0**.

> Zwei geratene Zahlen im Prüfer sind beim zweiten Abbild aufgefallen und
> werden jetzt **gemessen** statt angenommen: wie weit alles hinter
> `.rodata` rutscht (0x2000 gegen 0x5000) und wie weit ein
> Zeichenkettenversatz wandern darf — die geratene Schranke 0x4000 lag um
> **vier Oktette** daneben.

---

## 4. Was der Umzug kaputtgemacht hat

Genau dort, wo der Kopf von `umzug.sh` es vorhergesagt hat: **nicht im
Quelltext** (ein falscher Import ist ein Übersetzungsfehler und fällt
sofort auf), sondern in den **Werkzeugen mit festen Pfaden**.

1. **`tools/kernel/memmap.py` starb** mit `KeyError: 'pci.fi'`. Es sucht
   seine Dateien in einer *Liste* von Verzeichnissen — und der Kommentar
   daneben erzählt, dass Runde ARM denselben Unfall mit `hv.fi` hatte und
   die Liste um einen Eintrag verlängert hat. Ein drittes Mal verlängern
   wäre die falsche Lehre gewesen: die Suche geht jetzt über den ganzen
   Baum. Das ist der schwerste Fund, weil **zehn Testläufer** memmap.py
   aufrufen.
2. **14 Stellen `cp kernel/*.fi ZIEL/`** in zehn Läufern. Sie kopieren
   den Kern, legen eine Konstante auf eine belegte Seite und verlangen vom
   Kartenprüfer eine `KOLLISION`. Ohne die Treiber in der Kopie bekamen sie
   einen KeyError — **eine Gegenprobe, die nicht mehr prüft, was sie
   behauptet.** Jetzt `cp -a kernel/.`.
3. **`tools/arch/inventory.py`, `tools/paint/scalars.py`**: `os.listdir`
   sah nur die Wurzel. scalars.py prüft jetzt **226 statt 209 Dateien** —
   *ein Prüfer, der weniger prüft als gestern, fällt nicht auf, er wird
   nur grüner.*
4. `tools/k17/run.sh` (grep über `kernel/*.fi`), `tools/arch/a64probe.sh`.

Alle behoben und danach einzeln nachgefahren.

---

## 5. `blk.fi` und die Naht zu BLECH — **nicht gedoppelt**

Auftragspunkt 4 (eine `probe()`, die beim Start selbst sucht, NVMe →
AHCI → USB → IDE) ist **von der Runde BLECH bereits gebaut**. Geprüft
auf dem Zweig, nicht geglaubt: `kernel/rootsel.fi` (736 Z., Commit
22d5756) tut genau das, nimmt den *ersten, dessen Wurzel sich wirklich
einhängen lässt*, und benennt zusätzlich den RAID-Modus (Klasse 01:04).
`blech` fasst `blk.fi` und `netdev.fi` **nicht** an (`git diff --stat
main...blech -- kernel/blk.fi kernel/netdev.fi` ist leer).

**Die Naht liegt damit hier:**

| | wer | Zustand |
|---|---|---|
| *Welches Gerät trägt die Wurzel?* | `rootsel.fi` (BLECH) | **gebaut**, nicht in main |
| *Wie liest man von Gerät `dev`?* | `blk.fi` (diese Klasse) | weiterhin vier `if`-Ketten |

Diese Runde hat `blk.fi` deshalb **nur verschoben, nicht umgebaut**. Die
Tabellenform bleibt offen und steht in `docs/TREIBER.md` als Punkt 1 der
offenen Liste. Sie jetzt zu bauen hieße, gegen `rootsel.fi` zu arbeiten,
das noch nicht in main ist — und zwei Runden, die dieselbe Datei in
verschiedene Richtungen ziehen, sind teurer als eine spätere Runde, die
beides zusammen sieht.

---

## 6. `MAX_CARDS` 2 → 7, und zwei echte Fehler

`blech` hat `MAX_CARDS` **nicht** angehoben (auf dem Zweig steht 2), also
war es Sache dieser Runde. Beim Nachrechnen der Schranken fielen zwei
Fehler auf, die **älter sind als diese Runde**:

**(1) Vektor 46 gehört der Maus.** `netdev` gab Karte 1 den Vektor
`VEC_NET + 1` = 46 — und das ist `VEC_MOUSE` (`hw.fi` routet GSI 12
dorthin). In `trap.fi` steht der Mauszweig **vor** dem Netzzweig. Eine
zweite Netzkarte hat also nie eine Unterbrechung gesehen; sie wären an
`gfx.mouse_irq` gegangen. Seit Runde NETMON.

**(2) Der Vektor kam aus der falschen Nummer.** `virtio` rechnete
`VEC_NET + c`, `e1000` rechnete `45 + u` — beides die Kartennummer
*innerhalb* des Treibers. Bei **einer virtio- und einer e1000-Karte** ist
das für beide 0: beide landen auf Vektor 45.

Behoben, indem der Vektor dort vergeben wird, wo die globale
Kartennummer bekannt ist: `netdev.vec_of(c)`. Karte 0 behält 45 (damit
jede Messung von K8 und NETMON dieselbe Zahl liest), Karten 1–6 nehmen
37–42; **34 und 35 bleiben absichtlich frei**, damit der nächste Treiber
einen Vektor findet, ohne die Tabelle anzufassen. Die Treiber bekommen
den Vektor als **Argument** und rechnen ihn nicht mehr aus.

Die neuen Grenzen sind **Schranken, keine Wünsche**:

| Grenze | alt | neu | woher |
|---|---|---|---|
| `netdev.MAX_CARDS` | 2 | **7** | so viele Vektoren gibt es (45 + 37–42) |
| `e1000.MAX_UNITS` | 2 | **6** | `(0x1000 − 0x400) / 0x200`, der Platz in der Seite |
| `virtio.MAX_CARDS` | 2 | **2** | Karte 1 liegt auf `K2_SCALARS+0x1600`, die Seite endet auf 0x2000 |

`isr.s` hat Stummel für `isr0..isr47`; ab 48 stehen in der Tabelle
`vectors` andere Einträge — **48 aufwärts ist kein freier IRQ-Vektor.**
Die 7 ist also die harte Grenze, nicht eine gewählte.

### Warum der Kartenprüfer geschwiegen hat

`memmap.py` ist genau dafür gebaut und hat 2015 die Kollision
`VEC_MOUSE`/`VEC_NVME` gefunden — der Kommentar erzählt es. Er hat
diesmal geschwiegen, weil er **`const VEC_*` liest**: `VEC_NET + 1` ist
eine *Rechnung*, und eine Rechnung steht in keiner Tafel.

memmap.py kennt jetzt `BEREICHS_VEKTOREN` — ein Name belegt *n* Zahlen ab
seinem Wert. **Gegenprobe gefahren:** `VEC_XHCI` auf 39 gelegt meldet
`KOLLISION: Vektor 39 haben zwei Namen: VEC_NET_MORE+2, VEC_XHCI`.
Vorher: Schweigen.

> Die Lehre, und sie steht auch in `kernel/drivers/README.md`:
> **Rechne einen Vektor nicht aus — vergib ihn.**

---

## 7. Die Merge-Reihenfolge

**Justins Empfehlung — erst `blech` und `modul` nach main, dann
`struktur` — ist richtig.** Geprüft mit echten Probemerges, nicht
überlegt:

| Merge | Konflikte |
|---|---|
| `struktur` ← `blech` | 2 Dateien, je 1 Block (`hwdiag.fi`, `tasks.fi`) |
| `struktur` ← `modul` | 1 Datei, 1 Block (`tools/build-kernel.sh`) |
| **`blech` ← `modul`** | **2 Dateien** (`kstate.fi`, `tools/kernel/memmap.py`) — *untereinander, ohne struktur* |

Die Konfliktzahl ist erfreulich klein, weil git die Umbenennungen
erkennt: blechs Änderungen an `nvme.fi` landen von selbst in
`drivers/blk/nvme.fi`. **Das ist aber nicht der Grund für die
Reihenfolge.** Der Grund sind die **neuen Dateien**:

```
blech:  kernel/ehci.fi        kernel/rootsel.fi
modul:  kernel/ps2m-aus.fi   (+ ksym/modul/modtab/modidx — die sind Kern)
rtl:    kernel/r8169.fi
hid:    kernel/hidin.fi  hidrep.fi  i2chid.fi  hidtest.fi
```

Kommt `struktur` **zuerst**, landen diese Dateien trotzdem flach in
`kernel/` — die Struktur wäre am Tag nach dem Merge wieder halb kaputt,
und jede spätere Runde müsste selbst wissen, wohin ihre Datei gehört.
Kommt `struktur` **zuletzt**, sammelt ein Nachlauf-Commit sie in einem
Zug ein. `tools/struktur/umzug.sh` ist dafür gebaut: es ist eine Tabelle,
die man um Zeilen erweitert.

**Empfohlene Reihenfolge, mit der Nachlaufliste:**

1. `blech` → main  *(zuerst: `rootsel.fi` ist die inhaltlich wichtigste
   offene Arbeit — ohne sie findet Osum auf fremdem Blech seine
   Wurzelpartition nicht)*
2. `modul` → main  *(Konflikte `kstate.fi`, `memmap.py` gegen blech
   auflösen — die bestehen ohnehin)*
3. **dann** `struktur` → main, und im selben Zug:

   | Datei | Ziel |
   |---|---|
   | `kernel/ehci.fi` | `kernel/drivers/usb/ehci.fi` |
   | `kernel/rootsel.fi` | `kernel/drivers/blk/rootsel.fi` |
   | `kernel/ps2m-aus.fi` | `kernel/drivers/input/ps2m-aus.fi` |
   | *(später `rtl`)* `r8169.fi` | `kernel/drivers/net/r8169.fi` |
   | *(später `hid`)* `hidin/hidrep/i2chid` | `kernel/drivers/input/` |

   `ksym.fi`, `modul.fi`, `modtab.fi`, `modidx.fi` bleiben in `kernel/` —
   ein Modullader ist kein Treiber.

4. Nach dem Merge **einmal** `python3 tools/kernel/memmap.py` und
   `./tools/build-kernel.sh /tmp/k.bin --gui off`. Der GUI-lose Bau ist
   die empfindlichste Probe: er löscht Dateien über feste Pfade und
   bricht seit dieser Runde ab, wenn einer davon ins Leere zeigt.

> **Hinweis für modul:** dieser Zweig legt `kernel/ps2m-aus.fi` als
> Leerfassung neben `ps2m.fi`. Nach dem Umzug gehört sie neben ihr
> Original — genau wie `gfx-aus.fi` jetzt neben `gfx.fi` in
> `drivers/gfx/` liegt.

---

## 8. Damit die Ordnung hält: `tools/struktur/run.sh`

Ein Verzeichnisbaum ist keine Zusage. Die 17 Dateien an den richtigen
Ort zu legen kostet einen Nachmittag; die nächste Runde legt eine neue
Datei flach nach `kernel/`, und in einem halben Jahr sieht der Baum
wieder aus wie vorher. **Was eine Ordnung hält, ist nicht der Umzug,
sondern die Probe, die den Rückfall meldet.**

`tools/struktur/run.sh` ist die maschinelle Fassung von
`kernel/drivers/README.md` — **20 Zusagen, unter einer Sekunde** (ohne
die Gegenprobe), angemeldet als Abschnitt 34 in `./test.sh`:

| Zusage | fällt, wenn |
|---|---|
| kein Treiber flach in `kernel/` | jemand `kbd.fi` wieder in die Wurzel legt |
| Modulnamen eindeutig | zwei `*.fi` gleichen Namens in der Kerneinheit |
| Regel 1: kein Chipname am Kern vorbei | eine Stelle mehr als der Bestand |
| Regel 2: Pflichtnamen je Chip | ein Treiber schreibt `tx_room_on` anders |
| Regel 3: Vektoren werden vergeben | ein Treiber rechnet wieder `VEC_NET + c` |
| `memmap.py` | Bereichs- oder Vektorkollision |
| `pfade.sh` | ein Werkzeug liest eine Datei, die es nicht gibt |
| `gfx-aus.fi` deckt `gfx.fi` | eine Funktion fehlt in der Leerfassung |
| `GFX_DATEIEN` vollständig | neue Datei in `drivers/gfx/` fehlt in `build-kernel.sh` |

Drei Entscheidungen darin sind wichtiger als der Rest:

**Die Pflichtnamen werden nicht gepflegt, sondern gelesen.** Was
`netdev.fi` auf `virtio.` aufruft, *ist* die Liste — 25 Namen, ohne dass
sie jemand abtippt. Eine handgepflegte Liste ist nach der übernächsten
Runde falsch.

**Der Bestand wird benannt, nicht verschwiegen.** Regel 1 gilt ab heute,
nicht rückwirkend: `nvme.` wird **25 mal** direkt gerufen (21 in
`hw.fi`, 3 in `hwid.fi`, 1 in `trap.fi`), `ahci.` **22 mal**. Beide
Zahlen sind gegen `main` gemessen — diese Runde hat keine einzige Stelle
hinzugefügt. Sie stehen als Obergrenze im Skript: der Bestand **darf
bleiben, aber nicht wachsen**. Es ist auch nicht rein willkürlich, dass
er existiert: `hw.fi` *findet* die Platten, `blk.fi` *liest und
schreibt* sie; die Naht liegt hinter der Erkennung.

**Kommentare, die alte Orte nennen, sind erlaubt.** `pfade.sh` prüft nur
Code-Zeilen. Der erste Entwurf meldete vier tote Pfade — alle vier
standen in Kommentaren, die absichtlich erzählen, wo eine Datei *früher*
lag. Eine Probe, die zwingt, die eigene Umzugsgeschichte zu löschen, ist
falsch gebaut.

### Und die Probe hat Zähne: `tools/struktur/gegenprobe.sh`

„20 passed, 0 failed" ist genau so viel wert wie die Frage, ob das
Skript überhaupt **rot werden kann**. Diese Runde hat den Beweis
geliefert, dass die Frage nötig ist: `memmap.py` prüft Vektorkollisionen
seit Runde K10 — und hat `VEC_MOUSE = 46` gegen `VEC_NET + 1 = 46`
trotzdem übersehen, weil die eine Seite eine *Rechnung* war. Grüner
Schein, echter Fehler.

`gegenprobe.sh` bricht deshalb **jede Zusage genau einmal** — in einem
Wegwerfbaum (`git worktree` unter `/tmp`, der eigene Baum bleibt
unberührt) — und verlangt, dass `run.sh` es meldet und mit 1 endet.
**9 von 9**, einschließlich der Gegenrichtung: am unversehrten Baum muss
sie grün sein, sonst bewiesen die acht Brüche nichts.

Drei Fehler in der Probe selbst hat erst die Gegenprobe sichtbar gemacht:
`kernel/user/` wurde fälschlich als dieselbe Übersetzungseinheit gezählt
(fünf Phantomfehler), `nvme.fi` wurde als „Funktionsname `fi`" gelesen,
und `pfade.sh` meldete die absichtlich toten Pfade der Gegenprobe als
Fehler. *Eine Probe, die nie rot war, ist ungetestet.*

## 9. Was offen bleibt

Ehrlich, damit es niemand für fertig hält — dieselbe Liste steht in
`docs/TREIBER.md`:

1. **`blk.fi` ist keine Tabelle** (Abschnitt 5). Der wichtigste offene
   Punkt dieser Klasse.
2. **`input/` hat keine Naht.** `kbd.fi` und `ps2m.fi` werden direkt
   gerufen. Der Zweig `hid` bringt drei weitere Eingabetreiber — *davor*
   gehört eine `input.fi` nach dem Muster von `netdev.fi` gebaut, nicht
   danach.
3. **`serial.fi` ist ein Treiber und liegt in `kernel/`.** Ein 16550-UART
   gehört nach `drivers/char/`. Nicht gemacht, weil **55 Dateien** ihn
   importieren und er die Ausgabe des Kerns selbst ist — das ist ein
   eigener Schritt, keine Nebenbemerkung.
4. **`batt.fi`, `pwr.fi`** sprechen ACPI und MSRs an, sind also Treiber,
   und liegen noch flach. `drivers/pwr/` wäre folgerichtig.
5. **`netdev.probe` ist ein `if`-Baum, keine Datentabelle.** Für zwei
   Treiber lesbar; ab vier gehört die Zuordnung in ein Feld aus
   `(Hersteller, Gerät, KIND)`.
6. **`drivers/snd/` ist leer.** `ac97.fi` und `audio.fi` liegen auf
   `media1`/`hda`. Wer sie hereinholt, schreibt die `snd.fi`-Naht,
   *bevor* der zweite Treiber (HDA) dazukommt.
