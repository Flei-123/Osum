# Runde K15 — Widgets und der Dateimanager

**Stand: 26.08.2026.** Runde K10 gab Osum eine Oberfläche: ein Zeigegerät
an IRQ 12, einen Fensterserver mit Bereichsverfolgung, einen
TrueType-Rasterer mit Kantenglättung. Sie endete mit zwei Fenstern auf
dem Schirm — einem Terminal und einem Rechteck, in das ein Programm aus
Ring 3 einen Fleck malen konnte, wenn man es anklickte.

Zwischen diesem Rechteck und einer *Anwendung* fehlte alles. Ein Knopf
weiß, dass er gedrückt aussieht, solange die Taste unten ist. Ein
Textfeld weiß, wo die Einfügemarke steht und was ausgewählt ist. Eine
Liste weiß, welche Zeile gewählt ist und wie weit sie gerollt wurde. Die
Tabulatortaste weiß, wer als nächstes den Fokus bekommt. Nichts davon
gab es.

Diese Runde baut es — **als Bibliothek in Ring 3**, wie die Aufgabe es
verlangt, und nicht im Kernel:

| Datei | Zeilen | wo |
|---|---:|---|
| `kernel/user/wlib.fi` — die Widgets, die Anordnung, die Ereignisschleife | 2688 | **Ring 3** |
| `kernel/user/wlibc.fi` — Zeichenfläche, Grundformen, Glyphen, Farbschema | 862 | **Ring 3** |
| `kernel/user/files.fi` — `/bin/files`, der Dateimanager | 939 | **Ring 3** |
| `kernel/user/widgetdemo.fi` — die Anwendung, an der gemessen wird | 448 | **Ring 3** |
| `kernel/wig.fi` — die Naht: sieben Aufrufe, die kein Widget kennen | 484 | Ring 0 |

**3 550 Zeilen in Ring 3 gegen 484 im Kernel**, und die 484 sind zu
zwei Dritteln Begründung. Was der Kernel dazubekommt, steht unten in
Abschnitt 2 mit je einem Satz, warum es nicht in Ring 3 gehen konnte.

---

## 1. Was auf dem Schirm steht

Nach `gfx wm wig wmhold wiglong` auf der Kommandozeile:

```
wig: selftest 7 / 7
wm: term win=0  cols=56  rows=20  cell=10x19
k15: start /bin/widgetdemo  pid=2
widgetdemo: theme n=12
widgetdemo: rect id=0 kind=8 x=12 y=12 w=456 h=22
...
widgetdemo: ready
wig: blits=5  rows=430  pixels=192000  glyphs=37  clipset=0  clipget=0  shape=0
```

Auf dem Bildschirm liegt dann über dem Terminalfenster aus Runde K10 ein
zweites, 480 × 400, und darin steht **von jeder Art ein Stück**: eine
Menüleiste, zwei Reiter, eine Überschrift, zwei Textfelder, zwei Knöpfe,
ein Kontrollkästchen, ein Auswahlfeld, zwei weitere Knöpfe in einem
Raster und eine Liste mit Bildlaufleiste.

`gfx wm wigfiles wmhold wiglong` startet statt dessen **`/bin/files`**:
660 × 430, Menüleiste, Zurück/Vorwärts/Hinauf, Pfadleiste, links der
Verzeichnisbaum, rechts die Tabelle mit Name, Größe, Zeit und Rechten,
unten die Statuszeile.

### Die Wörter der Kommandozeile

| Wort | Wirkung |
|---|---|
| `wig` | `/bin/widgetdemo` von der Platte starten |
| `wigfiles` | statt dessen `/bin/files` |
| `wiglong` | zwanzig statt fünf Sekunden stillhalten |
| `wignohit` | **Gegenprobe**: die Bibliothek prüft keine Treffer mehr |
| `wignoclip` | **Gegenprobe**: keine Zwischenablage |

Dazu die drei Gegenproben aus Runde K10, die hier weiter gelten:
`nodirty`, `nofocus`, `nomouse`. Ohne das Wort `wig` ändert sich
**nichts**: die Anwendung der Runde K10 (`u_wclick`) läuft wie vorher,
`wm: selftest 17 / 17`, und die Naht meldet `blits=0`.

---

## 2. Was der Kernel dazubekommen hat, und warum jedes Stück

Sieben Aufrufe, **1800 bis 1806**, in dem Hunderterblock, den diese Runde
zugeteilt bekommen hat. Sie liegen bei den POSIX-Nummern und nicht in der
nativen ABI ab 2100, und der Grund ist eine Trennlinie: **ein Fenster ist
Autorität, eine Glyphe ist es nicht.**

| Nr. | Aufruf | Warum nicht in Ring 3 |
|---:|---|---|
| 1800 | `WIG_BLIT(h, xy, wh, quelle, zeilenlänge)` | Der Fensterpuffer liegt im Kernel. Ring 3 malt in **seinen eigenen** Speicher und schiebt das fertige Rechteck mit **einem** Aufruf hinüber. **Braucht ein Handle mit `R_WRITE`.** |
| 1801 | `WIG_GLYPH(schrift, px, zeichen, aus, max)` | Der TrueType-Rasterer ist im Kernel (`kernel/ttf.fi`), sein Arbeitsbereich ein halbes Megabyte aus dem Rahmenverwalter. Ring 3 bekommt das **Deckungsfeld** und mischt selbst — damit gehören Farbe, Beschnitt und Auswahlhintergrund der Bibliothek. |
| 1802 | `WIG_KERN(schrift, px, c1, c2)` | Die Unterschneidung steht in der `kern`-Tabelle der Schrift, die der Kernel gelesen hat. Ohne sie setzt Ring 3 den Text anders als der Server die Titelleiste. |
| 1803/1804 | `WIG_CLIPSET` / `WIG_CLIPGET` | Eine Zwischenablage ist per Definition das, was **zwei Prozesse teilen**. Vier Kilooktett im Kernel, und der Fall ist erledigt. |
| 1805 | `WIG_SCREEN(was)` | Ein Menü, das unten aus dem Bild läuft, klappt nach oben auf — das lässt sich nur entscheiden, wenn man weiß, wo unten ist. |
| 1806 | `WIG_CURSOR(form)` | Der Zeiger wird vom **Server** gemalt, er liegt über allen Fenstern. Wer ihn über einem Textfeld zu einem Balken machen will, muss es dem Server sagen. |

Dazu drei kleine Änderungen an bestehenden Dateien, jede mit ihrem
Grund:

* **`kernel/wm.fi`: die rechte Maustaste.** Runde K10 sah nur die linke
  an — sie brauchte nicht mehr. Ein Kontextmenü gibt es ohne rechte
  Taste nicht. Dieselben zwei Ereignisse, dieselben Ortskoordinaten,
  **kein** Heben und **kein** Fokuswechsel dabei.
* **`kernel/wm.fi`: ein zweites Zeigerbild.** Der Balken ist mechanisch
  aus dem Pfeil-Verfahren entstanden und nicht von Hand gemalt: die
  Füllung ist der Balken, der Umriss ist die Füllung um einen Bildpunkt
  geweitet.
* **`kernel/kbd.fi`: die Tabulatortaste.** Sie hat den Abtastcode 15,
  und an Platz 15 der Übersetzungstabelle stand eine **Null** — die
  Taste kam in diesem System nie an. Bis hierher fiel das nicht auf:
  eine Zeilendisziplin braucht sie nicht, ein Editor auch nicht. Eine
  Oberfläche braucht sie, denn *die Tastaturweiterschaltung ist diese
  Taste*. Gefunden hat es die Messung: der Text landete im vorigen Feld
  und der Fokusring stand still.

### Der Speicher

Drei Seiten `kdata`, **0x46000 bis 0x49000** — der Vorrat, der dieser
Runde zugeteilt wurde, und kein Bit daneben:

```
+0x0000  die Skalare
+0x1000  die Zwischenablage, 4096 Oktette
+0x2000  der Umschlagpuffer -- EINE Bildpunktzeile oder EINE Glyphe
```

`tools/kernel/karte.py` führt den Bereich jetzt als 44. Eintrag und
rechnet ihn gegen alle anderen. Die Gegenprobe zum Prüfer steht im
Läufer: legt man `WIG_OFF` auf `0x1E000`, **muss** er die Kollision mit
dem Fensterserver finden.

---

## 3. Die Zeichenfläche ist ein Streifen — die wichtigste Entscheidung

Ein Prozess hat in diesem System **832 Kilooktett** zwischen `brk` und
`mmap` (`kernel/sys.fi`: `BRK_BASE` 0x40020000, `MMAP_TOP` 0x400F0000).
Ein Fensterpuffer von 640 × 420 Bildpunkten ist **1 075 200 Oktette**.
Er passt nicht. Zwei davon — Fenster und Dialog — erst recht nicht.

Also malt die Bibliothek nicht das Fenster, sondern einen **Streifen**
daraus: 800 Bildpunkte breit (der ganze Schirm) und 81 Zeilen hoch,
259 200 Oktette aus `mmap`. Ein Neuzeichnen läuft über so viele Streifen,
wie der schmutzige Bereich hoch ist, und schiebt jeden mit **einem**
Aufruf hinüber.

Was das kostet: jedes Widget wird je Streifen einmal gezeichnet, den es
berührt — also ein- bis zweimal, nicht sechsmal. Was es spart: den
ganzen Puffer.

**Und es ist der Grund, warum die Bereichsverfolgung hier überhaupt
sichtbar wird.** Eine Einfügemarke ist 2 × 18 Bildpunkte. Sie kostet
einen Streifen von 2 × 18, einen Aufruf und 36 Bildpunkte im Kernel. Wer
statt dessen das Fenster flusht, kostet 192 000.

---

## 4. Wie gemessen wird — und die Warnung aus Runde K7B

Die Aufgabe dieser Runde nennt sie wörtlich, und sie ist ernst genommen:
in Runde K7B stimmte Text „zu 87 Prozent", während *jeder Buchstabe*
fehlte — die 87 Prozent waren schwarzer Hintergrund.

Hier wird deshalb **je Zeichen** gerechnet, nicht je Fläche: die
gesetzten Bildpunkte der Vorlage aus `tools/ttf/raster.py` gegen die
Mischfarbe im Bild, und ein Zeichen mit Umriss, das im Bild **keine
Tinte** hat, lässt die Zusage fallen. Das ist derselbe Prüfer, den Runde
K10 gebaut hat (`tools/gfx/schau.py ttext`).

**Das Neue dieser Runde ist, woher die Stelle kommt.** Ein Testläufer,
der ausrechnet, wo ein Knopftext stehen müsste, baut die Anordnung nach
— und prüft dann seinen eigenen Nachbau. Also sagt die **Anwendung**,
wohin sie schreibt, bevor sie es tut:

```
widgetdemo: text knopf x=40 base=216 fg=15265524 bg=3820126 t=Knopf
widgetdemo: rows x=18 base=287 zh=20 fg=15265524 bg=1185824 sel=3104668 selfg=16777215
```

und der Läufer rechnet im **Bild** nach, ob dort wirklich steht, was
gemeldet wurde. Die Zahlen kommen aus denselben Ausdrücken, mit denen
gemalt wird (`wig.text_x`, `wig.text_base`, `wig.cell_base` …) — jede
Rechnung steht genau einmal.

Und weil ein Foto nicht sieht, ob zwei Knöpfe *übereinander* liegen,
prüft `tools/k15/anordnung.py` die gemeldeten Rechtecke **gegeneinander**:
alle im Fenster, keine zwei überschneiden sich, jedes hat Fläche, die
senkrechte Reihenfolge ist die Anlegereihenfolge. Auch dazu gibt es die
Gegenprobe zum Prüfer selbst: ein Rechteck, das aus dem Fenster ragt,
muss ihm auffallen.

### Bedient wird wirklich

Über den QEMU-Monitor gehen `mouse_move`, `mouse_button` und `sendkey`
in die laufende Maschine (`tools/wm/monitor.py`, aus Runde K10). Der
Zeiger fährt zuerst mit sechs Schritten von −120 in die linke obere Ecke
— dort hält der Anschlag und die Vorgeschichte ist gelöscht — und danach
in Schritten unter 128 an die Stelle, die er meint. Von da an ist der Ort
eine Rechnung und keine Hoffnung.

---

## 5. Die Messungen

*(Die Zahlen dieses Abschnitts stehen im Läufer und werden bei jedem Lauf
neu gemessen; hier steht der Stand vom 26.08.2026, QEMU 7.2.22 unter TCG,
ein Prozessor, 256 MiB, `-vga std`.)*

### 5.1 Was ein Neuzeichnen kostet

Zwanzig Bildschirmfotos, jedes aus einem eigenen Lauf, alle auf derselben
Maschine. Gemessen wird die Zahl der Bildpunkte, die **Ring 3** in sein
Fenster geschoben hat (`wig: pixels`) — nicht eine Zeit, denn unter TCG
ist eine Zeit die Zeit des Wirts.

| Vorgang | Bildpunkte | Aufrufe hinüber |
|---|---:|---:|
| der ganze Aufbau des Fensters (480 × 400) | **192 000** | 5 |
| ein Klick auf das Kontrollkästchen, samt Zeigerweg darüber | **18 184** | **2** |
| **Faktor** | **10,6** | |

**Und die Gegenprobe, ohne die die Zahl nichts bedeutet:** derselbe Klick
mit `nodirty`. Dann wird jede Meldung eines schmutzigen Bereichs zu „der
ganze Schirm", und der Server setzt für denselben Klick das ganze Bild
neu zusammen:

| | mit Bereichsverfolgung | mit `nodirty` |
|---|---:|---:|
| Bildpunkte, die der Server zusammengesetzt hat | **18 966 648** | **40 800 000** |

Der Läufer prüft dazu, dass die Anwendung in **beiden** Läufen dasselbe
getan hat (`haken=1`) — sonst wäre die Zahl ein Vergleich zweier
verschiedener Dinge.

### 5.2 Der Glyphenspeicher in Ring 3

Der Kernel rastert und speichert zwischen; der Speicher **in der
Bibliothek** spart den *Systemaufruf*. Ohne ihn kostet jede Textzeile je
Zeichen einen Aufruf samt Kopie des Deckungsfeldes — bei sechs Streifen
je Neuzeichnen sechsmal. Mit ihm kostet ein Zeichen den Aufruf genau
einmal im ganzen Programmlauf:

```
wig: ... glyphs=37    (die Anwendung mit allen Widgets)
wig: ... glyphs=45    (der Dateimanager mit acht Zeilen Tabelle)
```

37 beziehungsweise 45 verschiedene Zeichen — das ist die Zahl der
*verschiedenen* Zeichen auf dem Schirm, nicht die der gemalten. Die
Anwendung malt in einem Lauf ein Vielfaches davon; der Läufer prüft, dass
die Zahl der Aufrufe unter 90 bleibt.

### 5.3 Eine benannte Toleranz, und die gemessene Zahl dazu

Zwei Zusagen dieses Läufers rechnen nicht mit Toleranz 0, und das gehört
gesagt. Wo sich zwei **Glyphenkästen überlappen** — „ff" in „Oeffnen",
„rw" in „-rw-r--r--" —, mischt die Bibliothek (und `wm.text` genauso)
Zeichen *auf* Zeichen, während der Referenzrasterer jedes auf den reinen
Grund mischt. Gemessen an der Menüzeile „Oeffnen":

| Toleranz | falsche Tintenpunkte von 345 |
|---:|---:|
| 0 | 4 |
| 32 | 2 |
| 64 | 1 |
| 96 | **0** |

Die größte Abweichung ist also kleiner als 96 von 255 Stufen und betrifft
vier Bildpunkte. Dass die Zusage damit trotzdem etwas prüft, steht als
Gegenprobe daneben: ein **anderes Wort** an derselben Stelle fällt auch
bei Toleranz 128 durch — 146 falsche Tintenpunkte und zwei Zeichen ganz
ohne Tinte. Alle übrigen Textzusagen dieser Runde laufen mit **Toleranz
0**.

---

## 6. Der Dateimanager, und drei ehrliche Angaben

`/bin/files` ist die grafische Fassung von `ls` und braucht keine Zeile
mehr Kernel als `ls`: `open` mit `O_DIRECTORY`, `getdents64`, `stat`,
`mkdir`, `unlink`, `spawn`.

Was er kann: hineingehen (Doppelklick), hinauf, zurück und vorwärts,
einen Pfad tippen, nach jeder Spalte sortieren (Kopfzeile anklicken,
noch einmal dreht die Richtung um), Kontextmenü mit Öffnen, Umbenennen,
Löschen und Neuer Ordner, und ein Programm starten.

**Und drei Dinge, die er nicht kann, mit Grund:**

1. **Die Spalte „Zeit" ist leer, bei jeder Datei.** Das Dateisystem hat
   keinen Zeitstempel: ein Inode ist 128 Oktette und trägt Art, Größe,
   Verweiszahl, elf direkte Blöcke, einen einfach und einen doppelt
   indirekten — danach ist er voll (`kernel/fs.fi`). Eine Zeit dort
   unterzubringen hieße, das Format auf der Platte zu ändern, also auch
   `tools/osum/mkfs.py`, also auch jedes bestehende Abbild. Die Spalte
   steht trotzdem da, weil sie sortierbar sein soll, sobald es die Zeit
   gibt — und sie zeigt `--`, weil eine erfundene Zeit schlimmer wäre als
   eine leere. Der Läufer prüft die beiden Striche.
2. **Die Spalte „Rechte" zeigt, was `stat` wirklich meldet:** 0755 für
   ein Verzeichnis, 0644 für eine Datei (`kernel/sys.fi`, `fill_stat`) —
   es gibt keinen Eigentümer und keine Rechte auf der Platte. Die
   Zeichenkette wird **aus den gemeldeten Bits gebaut** und nicht
   hingeschrieben; damit zeigt sie am Tag, an dem es echte Bits gibt, die
   echten.
3. **Umbenennen ist Kopieren und Löschen.** Dieser Kernel hat kein
   `rename`; `kernel/user/mv.fi` sagt es seit Runde K11 in denselben
   Worten.

**Gemessen wird gegen die Platte, nicht gegen das Bild.**
`tools/k15/baum.py` legt den Verzeichnisbaum an *und* schreibt auf, was
darin steht und in welcher Reihenfolge ein Dateimanager es zeigen muss.
Der Läufer hält jede Tabellenzeile Zeichen für Zeichen dagegen. Und was
der Dateimanager **ändert**, wird nicht im Bild geglaubt: nach „Neuer
Ordner" liest `tools/osum/mkfs.py list` das Plattenabbild und sucht den
Eintrag — mit der Gegenprobe, dass er im Abbild ohne die Bedienung nicht
darin steht.

---

## 6b. Der Name, der zweite Name und die Auffindbarkeit

*(Nachtrag zum Auftrag, 26.08.2026.)*

### Er heißt Datei-Explorer, und der Name steht nicht im Quelltext

Justins Entscheidung: **kein Eigenname.** Der Name IST die Beschreibung
— so wie das Programm unter Windows für den Nutzer schlicht
„Datei-Explorer" heißt und die Datei dahinter `explorer.exe`. Kein
Nautilus, kein Finder, kein Kunstwort, das man erst lernen muss.

* Die Datei heißt **`/bin/explorer`**.
* Der angezeigte Name ist **„Datei-Explorer"** — und er steht in
  `/usr/share/apps/explorer.app`, **nicht** im Quelltext. Dasselbe
  Prinzip wie `brands/*.toml` im OrientOS-Repo: austauschbare
  Zeichenketten gehören in Daten. Der Läufer prüft beides — dass die
  Zeichenkette in `kernel/user/explorer.fi` *nicht* vorkommt und dass
  das Programm sie aus der Datei holt.
* Findet sich die Datei nicht, nimmt das Fenster den **Aufrufnamen** und
  behauptet keinen schöneren.

Gemessen wird der ganze Weg: die Datei auf der Platte → Ring 3 →
`WM_CREATE` → die Titelleiste, die der **Fensterserver** malt, je Zeichen
gegen den Referenzrasterer.

### `/bin/files` ist ein zweiter Name, kein zweites Exemplar

Ein Verzeichniseintrag ist eine Inode-Nummer und ein Name (32 Oktette,
`kernel/fs.fi`). **Zwei Einträge mit derselben Nummer sind zwei Namen für
eine Datei** — ein harter Verweis, und er braucht in diesem Format keine
einzige neue Zeile im Kernel. `tools/osum/mkfs.py` hat dafür die
Schreibweise `<neu>@<vorhanden>` bekommen; die Verweiszahl im Inode
(`I_NLINK`) gab es schon und wird jetzt hochgezählt.

**Gemessen, nicht behauptet.** Dasselbe Abbild einmal mit Verweis und
einmal mit zwei Kopien:

| | freie Blöcke | Inodes |
|---|---:|---:|
| zwei Kopien | 3 160 | 4 |
| ein Verweis | **3 610** | **3** |

450 Blöcke und eine Inode gespart — bei einem Programm von 226 256
Oktetten auf einem Abbild von 2 MiB ist das der Unterschied zwischen
„geht" und „geht nicht". Dazu die Zusage, dass beide Namen **Oktett für
Oktett dasselbe** liefern (`mkfs.py cat`).

**Was dieser Kernel dabei noch nicht kann, und es gehört gesagt:**
`unlink` zählt die Verweiszahl nicht herunter, es gibt den Inode frei.
Wer einen der beiden Namen löscht, macht den anderen unbrauchbar. Auf
`/bin`, das nur gelesen wird, fällt das nicht an — ein `rm /bin/files`
wäre trotzdem falsch.

### Das Anwendungsverzeichnis: `/usr/share/apps/*.app`

Osum hatte bis hierher **keinen Ort, an dem steht, welche Programme es
gibt**. `/bin` listet Dateinamen — `sh`, `edit`, `wc`, `explorer` —, und
ein Dateiname ist kein Name: er sagt nicht, was das Programm tut, und man
kann nicht danach suchen, wenn man ihn nicht schon kennt.

Eine Datei je Programm, `schlüssel=wert`, eine Zeile je Feld, `#` für
Anmerkungen:

```
name=Datei-Explorer
info=Dateien und Ordner ansehen
exec=/bin/explorer
icon=4a90d0
keys=datei,dateien,explorer,ordner,verzeichnis,manager,file,files,folder
```

**Warum dieses Format und nicht `.desktop`.** Der *Gedanke* ist der von
Freedesktop und er ist der richtige: eine Textdatei je Programm mit
Anzeigename, Beschreibung, Befehl, Symbol und Schlüsselwörtern, und ein
Verzeichnis voll davon. Was `.desktop` darüber hinaus mitbringt, hat
dieses System nicht:

| in `.desktop` | warum hier nicht |
|---|---|
| `[Desktop Entry]` | es gibt genau eine Gruppe |
| `Name[de]=` | es gibt eine Sprache |
| `Exec=… %f %U` | der Starter übergibt nichts |
| `\s`, `\n`, `\\`, Anführungszeichen | ein Wert ist alles bis zum Zeilenende, roh |
| `Type=`, `Categories=`, `MimeType=`, `StartupNotify=` | Felder für Dinge, die es hier nicht gibt |

Ein `.desktop`-Leser wäre zu neun Zehnteln Leser für Sachen, die nie
vorkommen — und jedes dieser Zehntel eine Stelle, an der er sich anders
verhält als der echte.

**Das Symbol.** Es gibt in diesem System keine Bilddateien und keinen
Leser dafür. `icon=` ist deshalb eine **Farbe**; der Starter malt daraus
ein Plättchen von 14 × 14 und setzt den ersten Buchstaben des
Anzeigenamens mittig darauf. Das ist ein Symbol, das man messen kann —
die Farbe als Zahl von Bildpunkten, der Buchstabe je Zeichen gegen den
Rasterer — und es ist nicht die Behauptung, es gäbe Symbole.

### Der Starter, und die Gegenprobe, um die es geht

Ein Fenster mit einem Suchfeld über dem Anwendungsverzeichnis. Man tippt,
und **während man tippt** wird die Liste kürzer; Eingabetaste,
Doppelklick oder der Knopf starten das Programm. Erreichbar über die
Schaltfläche **„Start"** in der Pfadleiste des Datei-Explorers und über
das Kommandozeilenwort `wigstart`.

Gesucht wird in **drei** Feldern: Anzeigename, Beschreibung **und
Schlüsselwörter**. Das dritte ist der Grund für die ganze Sache:

```
launcher: suche [fol]    treffer=1
launcher: suche [fold]   treffer=1
launcher: suche [folder] treffer=1
launcher: treffer i=0 name=[Datei-Explorer] exec=[/bin/explorer]
```

**„folder" steht weder in „Datei-Explorer" noch in „Dateien und Ordner
ansehen".** Es steht nur in `keys=`. Der Läufer rechnet das zuerst nach —
er durchsucht *alle* `name=`- und `info=`-Zeilen nach `folder`, `files`,
`manager` und `verzeichnis` und fällt, wenn eines davon dort auftaucht;
sonst wäre die Zusage eine über einen Zufall.

Und dann die drei Gegenproben:

| Lauf | getippt | Treffer |
|---|---|---:|
| Regellauf | `folder` | **1** (Datei-Explorer) |
| **`wignokeys`** — dieselben Dateien, dieselbe Suche, **ohne das Feld `keys`** | `folder` | **0** |
| Regellauf | `quaste` (steht in keiner `.app`-Datei) | **0** |
| Regellauf | *(leer)* | **4** — alle |

Die zweite Zeile ist die wichtige: sie zeigt, dass wirklich die
Schlüsselwörter greifen und nicht zufällig der Name. Die dritte zeigt,
dass die Suche überhaupt etwas ablehnt — **eine Suche, die immer etwas
findet, ist keine Suche.** Und alle drei werden im Bild nachgeprüft, je
Zeichen: im Regellauf steht der Datei-Explorer in Zeile 0 der Liste und
in Zeile 1 nichts mehr; mit `wignokeys` steht auch in Zeile 0 nichts.

---

## 6c. Der zweite Nachtrag: das Paket, das Symbol und der Namensindex

*(Zweiter Nachtrag zum Auftrag, 26.08.2026.)*

Drei Festlegungen, und die dritte ist die eigentliche Arbeit.

### 6c.1 Die Dateinamen im Quellbaum

Programme in Ring 3 liegen als `kernel/user/<name>.fi` und werden über
die Liste `PROGS` nach `/bin/<name>` gebaut. Der Dateimanager hieß schon
`explorer.fi`; die **Bibliothek** hieß `wig.fi` und `wigc.fi` — genauso
wie die Kernel-Naht `kernel/wig.fi`, also zwei Dateien mit demselben
Namen in zwei Verzeichnissen. Das ist jetzt aufgeräumt:

| vorher | jetzt | was es ist |
|---|---|---|
| `kernel/user/wig.fi` | **`kernel/user/wlib.fi`** | die Widget-Schicht |
| `kernel/user/wigc.fi` | **`kernel/user/wlibc.fi`** | der Zeichenkern |
| `kernel/wig.fi` | `kernel/wig.fi` | die Naht im Kernel, unverändert |

Beide Bibliotheken haben **kein `u_start`** und stehen **nicht in
`PROGS`** — wie `ulib.fi` und `flate.fi`. Der Läufer prüft weiter, dass
der Kernel die Symbole `wlib__button`, `wlib__step` und `wlibc__text_at`
**nicht** trägt.

### 6c.2 Ein Programm ist ein Verzeichnis

Der erste Nachtrag legte je Programm eine Datei `/usr/share/apps/*.app`
an. Justins Festlegung für den zweiten: **wie bei Apple, ein Bündel** —
alles, was zu einem Programm gehört, an einer Stelle. Installieren heißt
kopieren, entfernen heißt löschen. Die Endung ist **`.prog`** und nicht
`.app`; wer die Form übernimmt, muss nicht auch den Namen nehmen.

```
/apps/explorer.prog/
    INFO            name, info, keys, fassung
    start           die ausfuehrbare Datei
    symbol          das Bild (Format OSYM)
    daten/          alles Weitere
```

`INFO` ist `schlüssel=wert`, eine Zeile je Feld — der Gedanke von
`.desktop`, ohne Gruppenkopf, Sprachvarianten, `%f`, Escapes und die
Felder für Dinge, die es hier nicht gibt. Die Begründung steht ganz in
`kernel/user/appdir.fi`.

**Was gegenüber dem ersten Nachtrag WEGGEFALLEN ist: `exec=`.** Dort
stand ein absoluter Pfad, und ein Bündel mit einem Pfad nach draußen ist
kein Bündel — man könnte es kopieren, und es zeigte weiter auf das alte
Programm. Was läuft, ist **immer** `<bündel>/start`. Das kostet nichts:
`start` ist ein **zweiter Name** auf dieselbe Inode wie die Datei unter
`/bin` (`mkfs.py`, `<neu>@<vorhanden>`), kein zweites Exemplar. Fünf
Bündel für fünf Programme von zusammen 896 KiB kosten dadurch **5 × 1036
Oktette Symbol + 5 INFO-Dateien** und keinen einzigen Block für Code.

Die alten `/bin`-Namen bleiben: `/apps` steht **daneben**, nicht an ihrer
Stelle. Der Läufer prüft, dass `/usr/share/apps` nicht mehr im Abbild
steht — eine Beschreibung an zwei Orten wäre einer zu viel.

### 6c.3 Das Symbol ist jetzt wirklich ein Bild

Im ersten Nachtrag war `icon=` **eine Farbe in sechs Hexziffern**, und
der Starter malte daraus ein Plättchen mit einem Buchstaben darauf. Das
war ehrlich, solange dieses System keine Bilddatei lesen konnte — aber es
war kein Symbol.

Jetzt liegt in jedem Bündel eine Datei `symbol` im Format **OSYM**: vier
Oktette Kennung, Breite, Höhe, dann Breite × Höhe Bildpunkte zu vier
Oktetten (B, G, R, A). Zwölf Oktette Kopf, ein Leser von zwanzig Zeilen
in `wlib.fi`.

**Warum nicht PNG.** PNG braucht einen Deflate-Leser (den gibt es,
`flate.fi`), einen Filterschritt je Zeile, eine Farbtabelle, Interlacing
und CRC32 — mehrere hundert Zeilen für 16 × 16 Bildpunkte, die aus einem
Bündel kommen, das der Bauer dieses Systems selbst schreibt. Die Kennung
steht am Anfang, also steht dieses Format einem PNG-Leser später nicht im
Weg.

**Die Quelle ist Text** (`assets/apps/*.prog/symbol.txt`: eine Palette,
dann sechzehn Zeilen zu sechzehn Zeichen) — ein Oktettklumpen im Baum
wäre in keinem Unterschied lesbar. `tools/k15/symbol.py` macht daraus die
Datei und liest sie unabhängig zurück.

**Gemessen wird Bildpunkt gegen Bildpunkt**, nicht als Fläche: das ist
die Lehre aus Runde K7B, angewandt auf ein Bild. `tools/k15/symbolbild.py`
vergleicht die gezeichneten 14 × 14 mit der zurückgelesenen Datei und
zählt **nur die deckenden** Bildpunkte — über die durchsichtigen sagt ein
Symbol nichts aus.

| Prüfung | Ergebnis |
|---|---|
| Symbol des Dateimanagers, Zeile 0 | **169 von 169 deckenden gleich** |
| dasselbe gegen das Symbol des Editors (Gegenprobe) | **161 von 169 falsch** |
| Symbol des Editors, Zeile 1 | **169 von 169 gleich** |

### 6c.4 Der Namensindex — das ganze Dateisystem, sofort

Justin sagt: die Windows-Suche ist schlecht. Wer die Suche öffnet und
etwas eintippt, soll **das ganze Dateisystem** durchsucht bekommen und
die Antwort **sofort**. Das Vorbild ist **„Everything" von voidtools**,
und sein Trick ist nachlesbar: es durchsucht die Platte nicht, sondern
liest **einmal** die Master File Table von NTFS am Stück und hält daraus
im Speicher eine Liste **nur aus Namen**; danach verfolgt es das
**Änderungsjournal** (USN) und trägt nach.

**Beide Hälften gibt es jetzt in Osum.**

#### Die erste Hälfte: die Tabelle am Stück

`WIG_SCAN` (1807) läuft **einmal** durch die Inode-Tabelle und gibt die
Verzeichniseinträge heraus (`kernel/fs.fi`, `scan`). Kein Pfad wird dabei
aufgelöst — genau das ist der Unterschied zum Baumdurchlauf, der für
jeden Namen die ganze Kette von der Wurzel an noch einmal auflöst,
Bestandteil für Bestandteil, mit einem Verzeichnisdurchlauf je
Bestandteil.

**Ein Unterschied zu NTFS, und er gehört benannt:** dort steht der Name
im Tabelleneintrag (`$FILE_NAME`), hier nicht. In OFS trägt der Inode
keinen Namen — Namen stehen in Verzeichnissen, und genau deshalb kann
eine Datei zwei haben (`/bin/explorer` und `/bin/files`). Der Lauf geht
deshalb über die **Verzeichnisse** der Tabelle und liest ihre Einträge;
das bleibt **ein** Durchgang und bleibt ohne Pfadauflösung, aber es ist
nicht dasselbe wie ein MFT-Lauf, und es soll nicht so aussehen.

#### Die zweite Hälfte: das Journal — und warum dieser Weg

Der Auftrag ließ die Wahl: (A) den Index an den Stellen im Kernel
nachziehen, die Dateien anlegen/löschen/umbenennen, oder (B) ein Journal
in OFS ergänzen. **Gewählt ist A**, und zwar als Ring im Kernelspeicher
(`kernel/nidx.fi`, `WIG_JRNL` 1808), beschrieben an **genau zwei
Stellen**: `fs.dir_add` (ein Name entsteht) und `fs.dir_remove` (ein Name
vergeht). Mehr gibt es nicht — `create_path`, `mkdir`, `unlink_path`,
`link` und das Umbenennen des Dateimanagers gehen alle da durch. Ein Name
ist genau dann neu, wenn ein **Verzeichniseintrag** neu ist, nicht wenn
ein Inode neu ist.

**Was B gekostet hätte:** ein neues Feld im Superblock, also ein
geändertes Format auf der Platte, also `tools/osum/mkfs.py`, also **jedes
bestehende Abbild** und jeden Abschnitt von `test.sh`, der eines baut —
und dazu die Frage, was passiert, wenn das Journal voll ist und der
Schreiber gerade keinen Block mehr frei hat. Für eine Runde, die 1486
bestehende Zusagen nicht senken darf, ist das der falsche Handel.

**Was A kostet, und es steht hier und nicht im Kleingedruckten:** der
Index **überlebt keinen Neustart** — das Journal liegt im Speicher. Und
der Ring fasst **56 Sätze**; läuft er über, zählt `lost` mit, und ein
Leser, der das sieht, **muss neu bauen**. Das ist keine Notlösung, das
ist genau das, was Everything tut, wenn das USN-Journal umläuft.

#### Wofür `fs.fi` angefasst werden musste

Zwei Dinge, beide unvermeidbar, beide mit einer Gegenprobe:

**1. Die Zahl der Inodes kommt aus dem Superblock.** Sie stand seit Runde
62 als Konstante `128` in beiden Umsetzungen — und 128 Inodes sind 128
Dateien. An zwanzig Dateien beweist sich gegen einen Baumdurchlauf
nichts. Die Zahl **stand immer schon im Superblock** (`SB_INODES`), sie
wurde nur nie gelesen; `mount` liest sie jetzt und prüft dabei, dass die
Tabelle dort liegt, wo `inode_block_of` sie sucht, dass sie in den Platz
vor dem ersten Datenblock passt und dass beides auf die Platte passt. Ein
Superblock, der 40 000 Inodes behauptet, wird **nicht** eingehängt.

*Die Bedingung, unter der das gemacht werden durfte:* ein Abbild ohne
`--inodes=` muss **Oktett für Oktett** dasselbe sein wie vorher.
Abschnitt 15d misst das — `data=34`, `inodes=…/128`, zweimal gebaut,
zweimal dieselben Oktette. Was **nicht** beweglich wurde: die Blockkarte
bleibt **ein** Block, also höchstens 4096 Blöcke je Abbild.

**2. `getdents64` war quadratisch.** Es rief je Eintrag
`fs.entry_at(dir, index)`, und das zählt für **jeden** Aufruf von vorn,
wie viele belegte Einträge davor lagen. Bei acht Dateien fällt das nicht
auf; bei 250 Dateien in einem Ordner sind es 31 000 Leseoperationen für
einmal Durchgehen, und der erste Messlauf über 4000 Dateien **lief zehn
Minuten und war nicht fertig**.

Das musste auffallen, denn **die Gegenprobe dieser Runde IST der
Baumdurchlauf**: ein Durchlauf, den ein quadratischer Kernelaufruf
ausbremst, ließe den Namensindex besser aussehen, als er ist. Eine
Gegenprobe, die man gewinnt, weil man dem Gegner ein Bein stellt, ist
keine. `fs.entry_slot` gibt jetzt den Eintrag **am Platz** zurück, und
`d_off` heißt in jedem Unix „wo im Verzeichnis" und nicht „der
wievielte" — was jetzt drinsteht, ist also auch das richtige.

#### Die Zahlen

Ein Abbild mit **4000 leeren Dateien** in einem Baum aus siebzehn Ordnern
(`tools/k15/gross.py`, `--inodes=4096`, Datenbereich ab Block 1026), im
selben Prozess gemessen: erst der Index, dann derselbe Suchbegriff als
rekursiver Baumdurchlauf.

**1. Der Aufbau.**

| | |
|---|---:|
| Namen aus der Inode-Tabelle | **4021** |
| Sätze, die der Kernel geliefert hat | 4021 (keiner verloren) |
| Systemaufrufe dafür | **65** (63 Sätze je Aufruf) |
| Zeit | **820 123 µs** ≈ 0,82 s |
| je Name | 203 µs |
| abgeschnitten | 0 |

Dass es 4021 sein müssen, wird nicht geglaubt: der Läufer zählt die Namen
im fertigen Abbild auf dem Wirt (`mkfs.py list`) und hält die Zahl
dagegen.

**2. Die Suche danach.** Zehn Suchen am Stück gemessen, weil eine
einzelne unter der Körnung der Uhr liegen kann:

| Wort | Treffer | zehn Suchen | eine Suche |
|---|---:|---:|---:|
| `kupfer` | 1 | 69 663 µs | **6966 µs** |
| `07` | 179 | 92 287 µs | 9228 µs |
| `quaste` | 0 | 68 923 µs | 6892 µs |

Der Aufbau ist **117-mal** so teuer wie eine Suche. Er passiert einmal;
die Suche passiert bei jedem Tastendruck.

**3. Die Gegenprobe — dieselbe Frage, der andere Weg.**

| Wort | Index: Treffer / Zeit | Baumdurchlauf: Treffer / Zeit | Namen ungleich | Index schneller um |
|---|---|---|---:|---:|
| `kupfer` | 1 / **6966 µs** | 1 / **1 966 404 µs** | **0** | **282×** |
| `07` | 179 / 9228 µs | 179 / 1 766 744 µs | **0** | 191× |
| `quaste` | 0 / 6892 µs | 0 / 1 804 693 µs | **0** | 261× |

*Die Zeiten für `kupfer` sind die der Abnahme; die für `07` und `quaste`
stammen aus einem Lauf mit denselben Aufrufen kurz davor. Der Läufer
nagelt bei allen drei die **Trefferzahlen** und die **Namensgleichheit**
fest, nicht die Mikrosekunden — die schwanken mit der Last der Maschine
um etwa ein Fünftel, die Größenordnung nicht.*

Der Durchlauf hat dabei jedes Mal **4021 Namen** gesehen — genau so viele,
wie im Index stehen. **Beide Wege liefern nicht nur dieselbe Zahl,
sondern dieselben Namen**: `locate` holt sich die Namen beider Listen,
sortiert sie und vergleicht sie Oktett für Oktett (`ungleich=0`). Zwei
Suchen, die beide „179" sagen, könnten 179 verschiedene Dateien meinen.

Und `07` trifft genau **179**, weil die Liste, aus der das Abbild gebaut
wurde, 179 Namen mit `07` enthält — nachgerechnet auf dem Wirt, nicht in
der Maschine.

**4. Nachziehen ohne Neuaufbau.** `locate -j` legt eine Datei an, benennt
sie um (kopieren und löschen — dieser Kernel hat kein `rename`) und
löscht sie, und holt nach jedem Schritt das Journal ab. Was danach im
Index steht, wird nicht behauptet, sondern **gesucht**:

| Schritt | Journal geholt | Namen im Index | `zwiebel` | `apfel` |
|---|---:|---:|---:|---:|
| angelegt | 1 | 4022 | **1** | 0 |
| umbenannt | 3 | 4022 | 0 | **1** |
| gelöscht | 4 | 4021 | 0 | 0 |

**Genau ein Aufbau im ganzen Lauf.** Ein Index, der nach jeder Änderung
neu baut, ist kein Index, sondern ein Zwischenspeicher mit einer Sekunde
Wartezeit.

**5. Und die Gegenprobe dazu** (`locate -n`): dieselben drei Schritte,
aber das Journal wird **nicht** abgeholt.

| Schritt | Journal geholt | Namen im Index | `zwiebel` | `apfel` |
|---|---:|---:|---:|---:|
| angelegt | **0** | 4021 | 0 | 0 |
| umbenannt | **0** | 4021 | 0 | 0 |
| gelöscht | **0** | 4021 | 0 | 0 |

Der Index merkt **nichts**. Das ist der Beweis, dass oben wirklich das
Journal gewirkt hat und nicht ein Zufall. `lost` blieb in beiden Läufen
**0** — der Ring hat keinen Satz verworfen.

**6. Und ein Wort, das nirgends steht.** `quaste` kommt in keinem der
4021 Namen vor — nachgerechnet auf dem Wirt —, und **beide** Wege finden
**null**, obwohl der Durchlauf dafür alle 4021 Namen angesehen hat. Eine
Suche, die immer etwas findet, ist keine Suche.

#### Die Suche im Fenster: Programme UND Dateien

Der Starter sucht seit diesem Nachtrag in beidem: **erst** die Treffer
aus `/apps` (Anzeigename, Beschreibung, Schlüsselwörter), **darunter** die
Dateitreffer aus dem Namensindex, jeder mit seinem ganzen Pfad — aus den
Elternnummern gebaut, denn der Index hält Namen und keine Pfade.

Getippt wird über den QEMU-Monitor, gemessen wird der Schirm:

| Lauf | getippt | Programme | Dateien |
|---|---|---:|---:|
| Regellauf | `blau` | **0** | **1** — `/daten/bilder/blau.ppm` |
| **`wignoidx`** (ohne Namensindex) | `blau` | 0 | **0** |
| Regellauf | `folder` | **1** — Datei-Explorer | 0 |
| Regellauf | `quaste` | 0 | 0 |

`blau` steht in **keiner** `INFO` — der Läufer rechnet das vorher nach.
Was gefunden wird, kann also nur eine Datei sein. Und der Pfad steht im
Bild, je Zeichen gegen die zweite Rasterung geprüft; mit `wignoidx` steht
er dort nicht.

### 6c.5 Die Fehler des zweiten Nachtrags

**Der Rahmen über dem Bild.** Das Listen-Widget malte um jedes Symbol
denselben Rahmen wie um ein Farbplättchen — und überschrieb damit die
untere und die rechte Kante des Bildes. Im Bild sah man nichts; der
Prüfer sah **25 von 169 deckenden Bildpunkten falsch**, und die Zahl 25
ist genau 13 + 12, also eine Reihe und eine Spalte. Ein Symbol bringt
seinen Rand selbst mit oder hat keinen.

**`wig.init` löschte die Geometrie des Dateisystems.** Der zweite
Nachtrag legt in die erste Seite des K15-Vorrats zwei Wörter für die
Inode-Zahl (0x46080) und das Journal (0x46100). `wig.init` nullte bis
dahin **die ganzen drei Seiten** — und es läuft, wenn die Oberfläche
hochkommt, also lange nach dem ersten `mkdir`. Das Ergebnis wäre ein
`mount`, das geht, und ein `block_alloc`, das ab Block 34 vergibt, wo die
Inode-Tabelle liegt. Jetzt löscht es nur, was ihm gehört.

**Ein Leseaufruf je Verzeichniseintrag.** Der erste Entwurf von
`fs.scan` las je Eintrag 32 Oktette; jetzt liest er 512 und nimmt
sechzehn Einträge daraus. Das darf nur, wer weiß, **welcher Puffer wem
gehört**: der Eintragsblock steht in `buf_zz`, `read_at` arbeitet in
`buf_dt`, `inode_get` in `buf_in`, `file_block` in `buf_ib`. Stünde er in
`buf_dt`, zöge ihn der nächste Leseaufruf unter der Schleife weg — und
der Lauf lieferte Müll, der wie ein Dateiname aussieht.

**Der Baumdurchlauf merkte sich alle Namen.** `absteigen` legte **jeden**
gelesenen Namen in einen Puffer, um danach in die Unterverzeichnisse zu
gehen. In einem Ordner mit 4000 Dateien war der nach sechzig voll — der
Durchlauf stieg dann in kein Unterverzeichnis mehr ab und meldete zu
wenige Treffer. Eine Gegenprobe, die **weniger** findet als der Index,
ließe den Index fälschlich gut aussehen. Gemerkt werden jetzt nur
Unterverzeichnisse.

**`mkfs.py` brauchte 59 Sekunden für das große Abbild.** `dir_find` und
die Suche nach einem freien Platz gingen beide von vorn durch das
Verzeichnis: acht Millionen Eintragsleseoperationen. Mit einem Gedächtnis
je Verzeichnis sind es **0,1 Sekunden**. Der Kernel darf so arbeiten — er
legt selten viertausend Dateien an —, ein Werkzeug auf dem Wirt nicht.

### 6c.6 Was der zweite Nachtrag NICHT hat

* **Der Index überlebt keinen Neustart.** Das Journal liegt im Speicher
  des Kernels. Nach jedem Start baut das suchende Programm neu — 0,94 s
  für 4021 Namen.
* **56 Sätze im Ring, 4200 Namen im Index.** Läuft der Ring über, sagt
  `lost` das und der Leser muss neu bauen. Über 4200 Namen sagt `build`
  „abgeschnitten" statt stillschweigend zu vergessen.
* **Eine Suche über 4021 Namen kostet 6,8 ms.** Das ist ein Zeichen für
  Zeichen laufender Teilzeichenkettenvergleich ohne jeden Index über den
  Anfangsbuchstaben. Für ein Suchfeld reicht es; für 120 000 Namen wie
  beim Vorbild reichte es nicht.
* **Der Index hält Namen, keine Pfade.** Der ganze Pfad wird für die
  angezeigten Treffer aus den Elternnummern gebaut — ein Durchgang je
  Ebene. Das ist billig für zwölf Treffer und wäre teuer für 4000.
* **`unlink` zählt `I_NLINK` weiter nicht herunter.** Ein `rm
  /apps/explorer.prog/start` macht `/bin/explorer` unbrauchbar. Auf `/bin`
  und `/apps`, die nur gelesen werden, fällt das nicht an; falsch ist es
  trotzdem.
* **Die Blockkarte bleibt ein Block** — höchstens 4096 Blöcke, also zwei
  Megaoktett je Abbild. Mehr Inodes gehen; mehr Platz nicht.
* **Der Starter startet keine Datei.** Ein Doppelklick auf einen
  Dateitreffer sagt, welche Datei es ist. Was damit geschehen soll,
  entscheidet nicht der Starter.
* **Ein Bündel kann keinen Argumentsatz mitgeben.** Was läuft, ist
  `<bündel>/start` ohne Argumente.
* **Sechzehn Bündel, 6 KiB Zeichenketten, 16 KiB Symbole.** Was darüber
  hinausgeht, wird übergangen.

---

## 7. Die Fehler dieser Runde

Sie stehen hier, weil sie mehr über den Baum sagen als die grünen Zeilen.

### 7.1 Der Sortiervergleich prüfte auf Gleichheit

`ulib.cmp` gibt **1** für „kleiner", **2** für „größer" und **0** für
„gleich" — nicht −1/0/1 wie `strcmp`. Die erste Fassung des
Dateimanagers verglich auf `== 0`, also auf *Gleichheit*, und sortierte
damit überhaupt nicht: die Tabelle stand in der Reihenfolge, in der das
Verzeichnis auf der Platte liegt.

Im Bild sah man Namen, und sie waren sogar richtig — nur an der falschen
Stelle. Gefunden hat es nicht das Auge, sondern der Vergleich mit
`tools/k15/baum.py`, das die Reihenfolge kennt: die Zeilen 0 bis 3
stimmten, 4 bis 6 nicht, und die Namen dort waren gegeneinander
vertauscht.

### 7.2 Vier Bildpunkte unter der Bildlaufleiste

Die Spaltenbreiten des Dateimanagers waren 200 + 92 + 84 + 96 = 472,
dazu sechs Bildpunkte Einzug — zusammen 478 in einer Tabelle von 476, von
denen die Bildlaufleiste die letzten sechzehn nimmt. Die Spalte „Rechte"
lief also unter die Leiste, und die wird **nach** den Zeilen gemalt: von
373 Tintenpunkten waren vier weg.

*Vier.* Genau die Sorte Fehler, die man im Bild nicht sieht und die ein
Prüfer je Zeichen findet.

### 7.3 Die rechte Maustaste ist Bit 1 und nicht Bit 2

Der PS/2-Baustein legt links auf Bit 0, **rechts auf Bit 1** und die
Mitte auf Bit 2 (`kernel/ps2m.fi`); der QEMU-Monitor nimmt für
`mouse_button` dieselbe Reihenfolge (1 links, 2 rechts, 4 Mitte). Die
erste Fassung prüfte auf 4 — das ist die *mittlere* Taste — und das
Kontextmenü klappte nie auf, ohne dass irgendwo ein Fehler stand.

### 7.4 Ein Rechteck für alles war zu viel

Die erste Fassung der Bereichsverfolgung führte **ein** schmutziges
Rechteck je Fenster und legte jede Meldung hinein — die Vereinigung von
allem. Das ist bequem und es ist gemessen falsch: bewegt sich der Zeiger
von einem Knopf oben zu einer Liste unten, ist die Vereinigung das halbe
Fenster. Gemessen: **ein Klick auf ein Kästchen kostete 82 992 von
192 000 Bildpunkten** — Faktor 2,3 statt Faktor 30.

Jetzt sind es **vier Rechtecke je Fenster** mit einer Flächenregel: zwei
werden nur dann eines, wenn die Vereinigung nicht mehr als ein Drittel
größer ist als beide zusammen. Sind alle vier belegt, wird das Paar
zusammengelegt, das dabei am wenigsten hinzufügt.

### 7.5 Der Selbsttest der Naht rechnete mit 64 × 64

`STAGE_MAX > G_HDR + 64 * 64` ist `4096 > 4144` — falsch, und zwar genau
um den Kopf. Die Zusage lautet jetzt `STAGE_MAX >= G_HDR + 48 * 48`, und
sie ist die *benannte Grenze*: ein Zeichen darf bis 48 × 48 groß sein,
also bis etwa 48 Bildpunkte Schriftgröße. Darüber gibt `glyph_into` eine
Null zurück, statt in die nächste Seite zu schreiben.

### 7.6 Drei Fehler im Testläufer selbst

* `grep -oE '.*fg=[0-9]+'` holt `selfg` statt `fg` — `.*` ist gierig, und
  `selfg` endet auf `fg`. Vier Zusagen fielen um, mit einer Meldung, die
  nach einem Zeichenfehler aussah: 195 von 195 Tintenpunkten falsch, weil
  gegen Weiß statt gegen die Textfarbe gerechnet wurde. Ersetzt durch
  `tools/k15/wert.py`, das auf Wortgrenzen achtet.
* `monitor.py "$sock" "$MON" > "$OUT/$NAME.mon"` — Eingabe- und
  Ausgabedatei waren dieselbe. Die Umlenkung schnitt die Befehlsdatei ab,
  bevor sie gelesen wurde: `0 Befehle`, keine Maus, keine Fehlermeldung.
* **Die serielle Leitung gehört zwei Schreibern.** Der Kernel und die
  Anwendung in Ring 3 schreiben beide darauf, und gelegentlich schiebt
  sich eine Kernelzeile mitten in eine Anwendungszeile:
  `widgetdemo: state ... sel=wm: go`. Ein `sed 's/.*e2=\[//'` darauf liefert
  Unsinn, und zwei Zusagen fielen aus einem Grund, der mit der Sache
  nichts zu tun hat. `tools/k15/felder.py` sucht seither das
  **vollständige** Muster — `e1=[…] e2=[…]` mit beiden schließenden
  Klammern — und nimmt die letzte Zeile, die es enthält. Fehlt eine
  solche Zeile ganz, ist *das* der Befund und nicht ein leerer Text.

---

## 8. Was diese Runde NICHT hat

*(Die Punkte zum Anwendungsverzeichnis und zum Symbol stehen seit dem
zweiten Nachtrag in 6c.6 — dort in ihrer heutigen Fassung.)*

* **Kein Hintergrundbild.** Der Schreibtisch ist eine Farbe, und der
  Fensterserver malt ihn (`wm.compose`, `S_DESK`). Ein Bild dahinter
  hieße entweder ein Bild im Kernel oder ein Fenster, das *unter* alle
  anderen gehört — und einen Weg, ein Fenster nach hinten zu stellen, hat
  der Server nicht. Das Farbschema aus einer Datei ist gebaut und
  gemessen; das Bild ist es nicht.
* **Menüs und Dialoge sind vollwertige Fenster.** Sie bekommen deshalb
  eine Titelleiste und einen Rahmen wie jedes andere Fenster. Ein
  Fenstertyp *ohne* Zierrat wäre die Antwort darauf und ist eine Zeile im
  Server, die diese Runde nicht angefasst hat.
* **Keine Auswahl mit Umschalt-Pfeil.** Die Umschalttaste kommt in
  diesem System nie als eigenes Ereignis an — die Zeilendisziplin liefert
  das *fertige* Zeichen (`kernel/kbd.fi`). Ausgewählt wird deshalb mit
  der Maus und mit STRG-A.
* **Ein Textfeld ist EINE Zeile.** Kein Umbruch, kein Rollen nach
  rechts: ein Text, der breiter ist als das Feld, wird am Rand
  abgeschnitten.
* **Die Anordnung ist eine Anordnung und kein Löser.** Senkrecht,
  waagerecht, Raster; eine Wunschbreite von 0 heißt „nimm, was übrig
  ist". Keine Gewichte, keine Mindestgrößen, kein Ausdehnen in beide
  Richtungen zugleich.
* **Vier Fenster, 96 Widgets, 24 Kästen, vier schmutzige Rechtecke je
  Fenster.** Alles feste Zahlen; was darüber hinausgeht, wird abgelehnt
  und nicht stillschweigend verschluckt.
* **Die Zwischenablage ist systemweit und ohne Handle.** Jeder Prozess
  darf lesen und schreiben. Das *ist* eine Zwischenablage; wer es anders
  will, braucht einen Zwischenablagedienst mit eigenen Handles, und das
  ist eine Runde für sich.
* **Kein Ziehen zwischen Fenstern**, keine Unterfenster im Fenster, keine
  Bildlaufleiste als eigenständig ziehbares Element (ein Klick auf die
  Leiste springt an die Stelle, ein Ziehen des Schiebers gibt es nicht).

---

## 9. Die Abnahme

`bash tools/k15/run.sh` ist Abschnitt 21 von `./test.sh`.

Die Abschnitte des Läufers: bauen aus beiden Übersetzern · die
Speicherkarte · die Anwendung steht da (Anordnung) · der Text je Zeichen
· die Widgets an ihrer Stelle · bedienen mit echten Klicks · die Tastatur
samt Zwischenablage · Menüs und Dialoge · der Dateimanager gegen die
Platte · hineingehen, sortieren, anlegen · die Zeiten · die Gegenproben ·
das Farbschema aus einer Datei · das Zeigerbild · **der Name und der
zweite Name** · **die Bündel unter `/apps` und der Starter** · **die
Suche über die Schlüsselwörter und ihre drei Gegenproben** ·
**der Namensindex gegen den Baumdurchlauf** · **das Journal und die
Gegenprobe ohne Journal** · **der Starter findet Dateien** · **und die
alten Abbilder sind Oktett für Oktett die alten**.

### Die ganze Abnahme, Abschnitt für Abschnitt

| # | Abschnitt | Zusagen | Fehler |
|---:|---|---:|---:|
| 1 | der festgenagelte Übersetzer | 9 | 0 |
| 2 | freistehend übersetzen | 41 | 0 |
| 3 | std.core im Kernel | 46 | 0 |
| 4 | der Kern läuft | 176 | 0 |
| 5 | ein Programm von der Platte | 130 | 0 |
| 6 | PCI, APIC, NVMe | **98** | 0 |
| 7 | die POSIX-Schicht und die libc | 134 | 0 |
| 8 | vier Prozessoren | 59 | 0 |
| 9 | ein Userland | 91 | 0 |
| 10 | Handles statt Umgebungsautorität | 67 | 0 |
| 11 | der Multiboot-Kopf und UEFI | 20 | 0 |
| 12 | der Bildschirm | 76 | 0 |
| 13 | Signale, Terminal, Uhr, Zufall | 107 | 0 |
| 14 | das Netz | 75 | 0 |
| 15 | SMEP, SMAP, Boot-Modul | 55 | 0 |
| 16 | der Editor und der Werkzeugkasten | 85 | 0 |
| 17 | die Oberfläche (Runde K10) | **103** | 0 |
| 18 | ein Wirt für fremde Prozessoren | 114 | 0 |
| **21** | **Widgets, der Dateimanager, der Starter, der Namensindex** | **251** | **0** |
| | **Summe** | **1737** | **0** |

Die achtzehn Abschnitte vor dieser Runde ergeben **1486** — genau die
Zahl, die vorher dastand, keine einzige weniger. Abschnitt 17
(`tools/wm/run.sh`) meldet weiter **103**, obwohl diese Runde
`kernel/wm.fi` angefasst hat; Abschnitt 4 und 13 messen die Tastatur
weiter, obwohl `kernel/kbd.fi` eine Taste dazubekommen hat.

**Nach dem ZWEITEN Nachtrag alle achtzehn noch einmal.** Dieser Nachtrag
hat `kernel/fs.fi` angefasst (die Inode-Zahl aus dem Superblock, der
Tabellenlauf, die zwei Journalhaken), `kernel/sys.fi` (`getdents64` geht
über Plätze statt über laufende Nummern) und `tools/osum/mkfs.py` — also
den Boden, auf dem **jeder** andere Abschnitt steht. Es wäre unredlich,
nur den eigenen zu messen. Alle achtzehn, einzeln, nach dem Umbau:

```
FREESTANDING 41 · CORE 46 · KERNEL 176 · OSUM 130 · PCI 98 · POSIX 134
SMP 59 · USERLAND 91 · CAPS 67 · BOOT 20 · GFX 76 · UNIX 107 · NET 75
GUARD 55 · K11 85 · WM 103 · HV 114     (+ Abschnitt 1: 9)
```

Zusammen **1486** — Zahl für Zahl dieselben wie vorher, 0 Fehler. Mit den
**251** dieser Runde sind es **1737**.

*Eine Zahl, die zwischendurch anders aussah:* NET meldete in einem Lauf
**74 + 1 Fehler** („64240 statt 65536 angekommen") — allein und ohne Last
danach **75 + 0**. Das ist ein TCP-Fenster unter Last und keine Zeile
dieser Runde; es steht hier, weil eine Zahl, die man zweimal messen
musste, dazugehört.

**Wie gemessen wurde, und was daran unschön ist.** Die Summe stammt
nicht aus **einem** Aufruf von `./test.sh`, sondern aus dem Läufer dieser
Runde am Stück (251 Zusagen, 0 Fehler, ein Lauf) plus den achtzehn
anderen Abschnitten, einzeln aufgerufen. Der Grund ist die Maschine:
Abschnitt 21 allein braucht auf ihr etwa eine Stunde und einunddreißig
QEMU-Läufe, und `./test.sh` in einem Stück ist hier schon in der Runde
davor nicht durchgekommen. Das steht hier, weil eine Summe, die aus
mehreren Läufen zusammengesetzt ist, etwas anderes ist als eine aus
einem.

**Einunddreißig QEMU-Läufe**, jeder mit eigenem Plattenabbild.
Sechsundzwanzig davon mit Bildschirmfoto: `ruhe` · `klick` · `haken` ·
`reiter` · `tast` · `noclip` · `tabkey` · `pop` · `popw` · `dlg` ·
`dlgok` · `files` · `fdbl` · `fsort` · `fneu` · `haken_nd` · `nohit` ·
`nomaus` · `nofok` · `ohne` · `theme2` · `beam` · `start` · `suche` ·
`nokeys` · `unsinn` · **`dsuche`** · **`noidx`**. Und fünf ohne Bild, auf
dem großen Abbild mit 4000 Dateien: **`gkupfer`** · **`gviele`** ·
**`gquaste`** · **`gjrnl`** · **`gnojrnl`**.

Die Zusagen der Runden 52 bis K12 sind unverändert da — diese Runde fasst
von ihnen nur `kernel/kbd.fi` (eine Taste, die vorher nicht ankam) und
`kernel/wm.fi` (die rechte Maustaste, ein zweites Zeigerbild) an, und
`tools/wm/run.sh` misst beides weiter Zeile für Zeile.

### Die eine rote Zeile, und warum sie nicht dieser Runde gehört

Im Gesamtlauf schlug **Abschnitt 6 (PCI/NVMe)** mit fünf Zusagen fehl:

```
FAIL  the same file system formats and mounts on the NVMe disk
FAIL  written over DMA, read back over DMA, identical
FAIL  nvme.txt is missing in the listing
FAIL  the file name is not in the image
FAIL  the two kernels behave differently
PCI: 93 passed, 5 failed
```

**Nachgemessen statt behauptet.** Derselbe Läufer allein auf derselben
Maschine, unmittelbar danach:

```
PCI: 98 passed, 0 failed
```

Der Unterschied ist die Last. Auf diesem Rechner liefen während der
Abnahme **drei weitere Runden gleichzeitig** mit eigenen QEMU-Prozessen
(bis zu elf auf zwölf Kernen), und `tools/pci/run.sh` gibt jedem Lauf ein
Zeitlimit. Was dabei ausfiel, war das Formatieren des Dateisystems *auf
der NVMe-Platte* — der Teil des Abschnitts, der am längsten rechnet;
Identify, MSI-X, das Busmaster-Bit und beide Durchsatzmessungen liefen
durch. Dass die Ursache nicht in dieser Runde liegt, ist außerdem an der
Sache zu sehen: der Abschnitt läuft **ohne** das Wort `wm` und damit ohne
eine einzige Zeile dieser Runde, und die Speicherkarte von `kdata` ist
kollisionsfrei (44 Bereiche, `WIG` bei 0x46000 zwischen zwei freien
Lücken).

Das gehört hier hin und nicht in eine Fußnote: eine grüne Abnahme, die
man nur bekommt, wenn die Maschine sonst nichts tut, ist eine Abnahme mit
einer Bedingung — und die Bedingung ist genannt.

*(Nachtrag beim zweiten Nachtrag: bei der Wiederholung aller achtzehn
Abschnitte lief PCI **98 von 98** durch — auf einer Maschine, auf der
diesmal nichts anderes rechnete. Der Absatz darüber bleibt trotzdem
stehen; er beschreibt, was passiert, wenn sie voll ist.)*
