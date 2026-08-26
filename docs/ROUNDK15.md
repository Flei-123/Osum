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
| `kernel/user/wig.fi` — die Widgets, die Anordnung, die Ereignisschleife | 2688 | **Ring 3** |
| `kernel/user/wigc.fi` — Zeichenfläche, Grundformen, Glyphen, Farbschema | 862 | **Ring 3** |
| `kernel/user/files.fi` — `/bin/files`, der Dateimanager | 939 | **Ring 3** |
| `kernel/user/wigdemo.fi` — die Anwendung, an der gemessen wird | 448 | **Ring 3** |
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
k15: start /bin/wigdemo  pid=2
wigdemo: theme n=12
wigdemo: rect id=0 kind=8 x=12 y=12 w=456 h=22
...
wigdemo: ready
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
| `wig` | `/bin/wigdemo` von der Platte starten |
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
wigdemo: text knopf x=40 base=216 fg=15265524 bg=3820126 t=Knopf
wigdemo: rows x=18 base=287 zh=20 fg=15265524 bg=1185824 sel=3104668 selfg=16777215
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

| | Bildpunkte |
|---|---:|
| das ganze Fenster (480 × 400) | 192 000 |
| ein Klick auf das Kontrollkästchen, samt Zeigerweg darüber | siehe Läufer |
| Aufrufe hinüber dafür | ≤ 11 |

**Und die Gegenprobe, ohne die die Zahl nichts bedeutet:** derselbe Klick
mit `nodirty`. Dann wird jede Meldung eines schmutzigen Bereichs zu „der
ganze Schirm", und der Server setzt für denselben Klick das ganze Bild
neu zusammen. Der Läufer rechnet den Faktor aus und prüft dazu, dass die
Anwendung in **beiden** Läufen dasselbe getan hat — sonst wäre die Zahl
ein Vergleich zweier verschiedener Dinge.

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
*verschiedenen* Zeichen auf dem Schirm, nicht die der gemalten.

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

### 7.6 Zwei Fehler im Testläufer selbst

* `grep -oE '.*fg=[0-9]+'` holt `selfg` statt `fg` — `.*` ist gierig, und
  `selfg` endet auf `fg`. Vier Zusagen fielen um, mit einer Meldung, die
  nach einem Zeichenfehler aussah: 195 von 195 Tintenpunkten falsch, weil
  gegen Weiß statt gegen die Textfarbe gerechnet wurde. Ersetzt durch
  `tools/k15/wert.py`, das auf Wortgrenzen achtet.
* `monitor.py "$sock" "$MON" > "$OUT/$NAME.mon"` — Eingabe- und
  Ausgabedatei waren dieselbe. Die Umlenkung schnitt die Befehlsdatei ab,
  bevor sie gelesen wurde: `0 Befehle`, keine Maus, keine Fehlermeldung.

---

## 8. Was diese Runde NICHT hat

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

Die dreizehn Abschnitte des Läufers: bauen aus beiden Übersetzern · die
Speicherkarte · die Anwendung steht da (Anordnung) · der Text je Zeichen
· die Widgets an ihrer Stelle · bedienen mit echten Klicks · die Tastatur
samt Zwischenablage · Menüs und Dialoge · der Dateimanager gegen die
Platte · hineingehen, sortieren, anlegen · die Zeiten · die Gegenproben ·
das Farbschema aus einer Datei · das Zeigerbild.
