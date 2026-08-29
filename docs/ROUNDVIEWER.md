# Runde VIEWER — das Rundenprotokoll

Zweig `viewer`, von `mergeline` (6b602af). Auftrag: **Bildbetrachter**
(Roadmap E6) mit eigenem JPEG- und PNG-Dekodierer, und der
JPEG-Dekodierer ist zugleich **Schritt F5** der Medien-Roadmap.

---

## 1. Was gebaut wurde, und in welcher Reihenfolge

Die Reihenfolge kommt aus dem Auftrag und aus dem Verhältnis von Aufwand
zu Nutzen — und der erste Schritt war **nachsehen statt schreiben**:

1. **`vendor/firn/lib/std/deflate.fi` und `kernel/user/flate.fi` waren
   schon da.** Runde K11 hat DEFLATE nach RFC 1951 in Firn gebaut, mit
   CRC-32 daneben. PNG braucht genau das. Das hat diese Runde etwa eine
   Woche gespart, und es ist der Grund, warum PNG hier vor JPEG fertig
   war.
2. **PNG** (`imgpng.fi`): Blöcke, die fünf Zeilenfilter, Bittiefen
   1/2/4/8/16, alle fünf Farbarten, `tRNS`, Adam7 — und der Schreiber
   dazu.
3. **Baseline-JPEG** (`imgjpeg.fi`): der teuerste Teil, siehe unten.
4. **BMP** (in `img.fi`): 250 Zeilen, ein halber Tag, deckt jedes
   Testbild und jedes Windows-Überbleibsel ab.
5. **GIF** (`imggif.fi`) inklusive Animation: LZW ist die einzige echte
   Hürde und sie ist klein.
6. **Die Anwendung** (`viewer.fi`) und ihr Bündel.

**Nicht gebaut, wie im Auftrag festgelegt:** WebP, HEIC, SVG. Was sie
kosten würden, steht mit Zahlen in `docs/IMAGES.md`, Abschnitt 3.

---

## 2. Die Entscheidung, die die Runde trägt: Zeilen statt Bilder

Die Schnittstelle ist ein **Ziehmodell**:

```
    img.begin(oktette, laenge, scale)   Kopf lesen, Puffer anlegen
    img.next_row(ziel)                  EINE Zeile RGBA, dann die nächste
```

Der JPEG-Dekodierer hält dafür **drei MCU-Zeilen je Komponente** in
einem Ringpuffer (vorige, laufende, nächste — die dritte, weil der
Dreiecksfilter für die letzte Zeile eines Bandes schon die erste des
nächsten braucht). Damit hängt sein Arbeitsspeicher an der **Breite**
und nicht an der Fläche:

| Bild | Bildpunkte | Arbeitsspeicher |
|---|---|---|
| 4000 × 3000 | 12 Millionen | 1 023 072 Oktette |
| 8000 × 6250 | 50 Millionen | 2 047 376 Oktette |

Vierfache Fläche, doppelter Speicher. **Genau diese Bauart braucht die
Medienrunde wieder**: MJPEG ist eine Folge von JPEG-Bildern, und ein
Abspieler, der je Bild 48 Megaoktett anfordert und wieder freigibt, ist
kein Abspieler. Was F6 aus diesem Modul noch braucht, ist der Aufruf
`imgjpeg.begin` je Bild und sonst nichts.

---

## 3. Warum es bitgenau ist

Ein eigener Dekodierer, der um dreißig Stufen danebenliegt, sieht auf
einem Foto völlig in Ordnung aus. Deshalb ist der Vergleichsmaßstab
**Pillow** (libjpeg-turbo 3.1.4, zlib-ng, giflib): dieselben Dateien
werden auf dem Wirt dekodiert, die rohen RGBA-Oktette kommen auf
dasselbe Plattenabbild, und `/bin/imgtest` vergleicht sie **im laufenden
System** Bildpunkt für Bildpunkt.

Damit dieser Vergleich den Dekodierer misst und nicht die Rundung,
rechnet der Dekodierer **absichtlich wie libjpeg**: `jpeg_idct_islow`
(Ganzzahl, 13 Bit, zwei Durchgänge), der Dreiecksfilter
`h2v1`/`h2v2_fancy_upsample` mit den Rundungssummanden 1, 2, 7 und 8,
und die Festkommatabellen für Y′CbCr → RGB mit libjpegs Konstanten
1,40200 / 1,77200 / 0,34414 / 0,71414.

Dass Ganzzahl hier kein Kompromiss ist, sondern der einzige Weg, steht
in `kernel/user/fas.fi`: der eigene Assembler kennt die SSE-Befehle
nicht, und der Kernel sichert die SSE-Register beim Aufgabenwechsel
nicht. Ring 3 rechnet auf Osum ganzzahlig — und das ist zufällig genau
das, was den Vergleich mit libjpeg erst möglich macht.

---

## 4. Drei Fehler, die nur die Messung gefunden hat

**a) Versatz gegen Adresse.** Der JPEG-Marker-Leser rechnete `body` als
Versatz in die Datei und las ihn als Adresse (`ld8(24)`). Ergebnis: ein
Seitenfehler bei jedem Bild. Dieselbe Verwechslung steckte danach noch
zweimal im Baum — in `imgpng` (der Blockdurchlauf), in `imggif` (die
Blocklängen) und ein drittes Mal in `img.bmp_begin`, wo eine Adresse
gegen eine **Länge** verglichen wurde und die Palette deshalb schwarz
blieb. Alle drei fielen sofort auf, weil der Vergleich gegen Pillow
Zahlen liefert und nicht Eindrücke: `maxabw=255`.

**b) Ein Fehler im festgenagelten Übersetzer.** Der Dreiecksfilter
rechnete falsch, und der Fehler lag nicht im Filter. `firnc`
(a751b3db) legt drei über die Schleifenkante rotierende Veränderliche
(`links = mitte; mitte = rechts; rechts = neu`) auf **zwei**
Stapelplätze und verliert dabei eine Kopie — das *lost-copy problem*
beim Verlassen der SSA-Form. Im Assembler ist es sichtbar, im Messwert
war es ein Farbfehler von bis zu **163 Stufen** bei 4:2:0. Umgangen
(jede Summe frisch aus dem Speicher), aufgeschrieben in
`docs/IMAGES.md` Abschnitt 7 — und die Abnahme **misst den Fehler
weiter** (Abschnitt 9): wird Firn repariert, sagt sie es.

**c) Eine Sortierung ohne Vorzeichen.** `ulib.cmp` gibt 0, 1 oder 2
zurück, kein Vorzeichen; `> 0` war deshalb bei jedem Unterschied wahr
und der Ordner stand rückwärts. Gefunden, weil die Abnahme prüft,
welches Bild als erstes im Fenster steht.

**d) Die Eingabetaste kommt als 10 an, `wlib` prüft auf 13.** Ein Knopf
im Fokus soll sich mit der Eingabetaste drücken lassen — `wlib.on_key`
tut das bei `KEY_ENTER` (13) oder bei 32. Die PS/2-Tastatur dieses
Systems liefert die Eingabetaste aber als **10** (Zeilenvorschub), und
damit passiert nichts. Gemessen an der Anwendung selbst: sie meldet
`viewer: taste k=10 fokus=1`, und der Knopf bleibt still. Die
**Leertaste (32) geht**, und deshalb bedient die Abnahme die Oberfläche
mit Tabulator und Leertaste. Repariert gehört das in `kernel/kbd.fi`
oder in `wlib.decode` — nicht in dieser Runde, weil es jede
wlib-Anwendung betrifft und nicht nur den Betrachter.

Und ein zweiter, kleinerer Fund derselben Sorte: ein **Mausklick über
den QEMU-Monitor setzt den Fokus** (das Bild zeigt den Fokusrahmen an
der neuen Stelle) und zeichnet den Knopf gedrückt und wieder normal,
**löst ihn aber nicht aus**. `wlib.on_up` verlangt dafür
`hit_at(w, x, y) == i` mit den Koordinaten des Loslassen-Ereignisses;
dass die nicht passen, ist die wahrscheinlichste Erklärung, aber sie ist
in dieser Runde nicht bewiesen und steht deshalb hier als offene Frage
und nicht als Befund.

---

## 5. Der Kernel hat zwei Zahlen bekommen

`kernel/proc.fi`: `PRIV_SLOTS` 6 → 40 und `BIG_TOP` `0x40C00000` →
`0x45000000`. Die private Arena eines Prozesses wächst damit von 6 auf
**74 MiB**.

Der Grund ist nicht das Bild — das läuft zeilenweise. Der Grund sind die
zwei Dinge, die **nicht** zeilenweise gehen: eine Datei muss ganz im
Speicher liegen, bevor der erste Marker gelesen wird, und ein PNG
braucht seinen ausgepackten Rohstrom am Stück, weil `flate.inflate`
nicht fortsetzbar ist. Mit 6 MiB war schon ein Handyfoto nicht zu
öffnen.

Die Kacheln entstehen weiterhin erst, wenn jemand sie anfasst
(`proc.pt_for`), und werden mit dem Prozess freigegeben
(`proc.free_space`). Ein Programm, das die Arena nie betritt, belegt
keinen Rahmen mehr als vorher — deshalb ändert die Umstellung an keiner
bestehenden Rahmenzählung etwas.

---

## 6. Die Anwendung

`/bin/viewer`, im Bündel `/apps/viewer.osp` mit dem Anzeigenamen
**„Bilder"** (der Name steht in den Daten und nicht im Code —
`docs/NAMING.md`).

Blättern im Ordner (sortiert, mit Rundlauf), Zoom in Stufen mit
„Einpassen" und „100 %", Drehen links und rechts, **EXIF-Ausrichtung
beim Laden** (sonst steht jedes zweite Handyfoto quer), ein
Miniaturenstreifen aus dem Ordner (JPEG im Achtel dekodiert, also rund
ein Sechzigstel der Arbeit), Diaschau alle drei Sekunden, Zuschneiden
auf den sichtbaren Ausschnitt, Größe ändern über ein Eingabefeld,
Sichern als PNG — und eine Statuszeile mit Name, Format, Maßen,
Bittiefe, Dateigröße und, wenn es so ist, dem Wort
`UNVOLLSTAENDIG` oder `VORSCHAU (zu gross)`.

**Die Grenze steht in der Oberfläche und nicht im Kleingedruckten:** ein
Bild über 8 Megabildpunkten wird angezeigt (die Vorschau entsteht
zeilenweise), aber nicht bearbeitet.

---

## 7. Was diese Runde nicht kann

* **Progressives JPEG.** Benannt (`PROGRESSIV`), nicht falsch gezeigt.
  +600–900 Zeilen, und es bräuchte den Vollbild-Koeffizientenpuffer,
  den dieser Dekodierer absichtlich nicht hat.
* **JPEG schreiben.** Der Betrachter sichert als PNG. Ein
  Baseline-Encoder sind geschätzt 450–600 Zeilen; er ist der erste Punkt
  für die nächste Runde.
* **WebP, HEIC, SVG, TIFF, AVIF.** Erkannt und beim Namen abgelehnt.
* **Zwischenablage, Ziehen und Ablegen, Papierkorb.** Sie hängen an A3
  (Systembus) und D1/D2 und gehören nicht in diese Runde.
* **Mausauswahl zum Zuschneiden.** Der Fensterserver liefert einer
  Anwendung Ereignisse nur über die Widget-Bibliothek; ein freies
  Aufziehen im Bild bräuchte einen Weg dafür. Statt dessen schneidet
  „Zuschneiden" auf den **sichtbaren Ausschnitt** — was man sieht,
  bekommt man.

---

## 8. Vier weitere Fehler — alle gefunden, weil die Oberfläche wirklich bedient wurde

Der Betrachter war nach Abschnitt 7 fertig **im Bericht**. Als die
Abnahme anfing, ihm über den QEMU-Monitor wirklich Tasten zu schicken,
fielen achtzehn Zusagen durch. Keine davon lag im Dekodierer.

**a) Der Miniaturenstreifen dekodierte bei jedem Schritt alles neu.**
`weiter()` rief `minis_bauen()`, und das las alle acht Dateien des
Fensters von der Platte und dekodierte sie im Achtel — bei jedem
Tastendruck, auch die 700-KB-JPEG mit 12 Megabildpunkten. **Gemessen**
(Spur mit der Systemuhr, `viewer: m <k> <uptime>`): ein Schritt weiter
kostete **rund 2,0 s**, davon 1,8 s allein das Lesen der einen großen
Datei (330 ms je 128 KiB). In dieser Zeit holte die Anwendung keine
Ereignisse ab, und die nächste Taste ging in `wlib.key_last` verloren,
weil `step()` bis zu 64 Ereignisse in einem Durchgang abräumt und nur
die letzte Taste stehen bleibt. Von außen sah das aus wie „Tasten
kommen nicht an".

Der Streifen führt jetzt Buch, welches Bild in welchem Kästchen steckt
(`mini_idx`), und lagert beim Blättern die sieben unveränderten
Kästchen über einen zweiten Block um, statt sie neu zu rechnen. **Ein
Schritt weiter kostet jetzt rund 0,05 s.** Danach war keine Taste mehr
verloren — der Fehler „die Bibliothek verschluckt Tasten" hat sich als
Folge der Langsamkeit erwiesen und nicht als eigener Fehler.

**b) Die Anwendung sicherte neben das falsche Bild.** `sichern()` hängt
`.viewer.png` an `pfad`, den Pfad des angezeigten Bildes. `mini_eins()`
benutzte für seine Datei **denselben** Puffer — nach jedem Aufbau des
Streifens stand dort der Pfad der **letzten Miniatur**. Die Datei wurde
also geschrieben (`viewer: gesichert 2747`), nur eben neben
`g-gross.jpg` statt neben `a-rot.png`. Aufgefallen ist es einzig
daran, dass die Abnahme die geschriebene Datei danach **vom Abbild
holt** und Pillow vorlegt. Die Miniaturen haben jetzt ihren eigenen
Puffer (`mpfad`).

**c) `wmhold` hält zwanzig Sekunden, und das ist ein hartes Budget.**
Die Warteschleife in `kmain` läuft `sek` Sekunden TSC-Zeit und fährt
danach herunter — alles, was ein Bildschirmfoto braucht, muss
hineinpassen. Ein Skript von 20,9 s (sechsmal weiterblättern mit je 3 s)
lief genau einen Schritt zu lang: QEMU war weg, bevor `screendump`
verbunden war, und der Abschnitt fiel mit `kein Monitor an ...` durch —
ein Fehlerbild, das nach einem Fehler in der Anwendung aussieht und
keiner ist. Zwei Antworten: die Skripte sind kürzer geworden (1,5 s je
Taste statt 3 s, was seit **a)** reicht), und der Kern hat eine dritte
Haltestufe bekommen (siehe unten).

**d) Kern und Anwendung teilen sich die serielle Leitung — ohne
Absprache.** In einem Lauf stand im Mitschnitt
`...warm=9 us  fwm: go`: die Zeile `wm: hold` war mitten in einer
Kernelmeldung verschwunden, weil die Anwendung dazwischenschrieb. Die
Abnahme wartete auf `^wm: hold`, fand es nie, drehte ihre vollen 300 s
und ließ QEMU in den Zeitablauf laufen. Sie sucht jetzt **ohne
Zeilenanker** und hat einen zweiten Ausweg (hat die Anwendung schon
berichtet, geht es weiter — und sie sagt es). Der eigentliche Fehler
liegt tiefer und ist hiermit benannt, nicht behoben: `serial.puts` aus
Ring 0 und aus Ring 3 brauchen eine gemeinsame Sperre.

### Was der Kern dafür bekommen hat: `wigxl`

`kstate.M_WIGXL` (**Bit 33** von Wort 1) und das Wort `wigxl` auf der
Kommandozeile: **sechzig** Sekunden Stillhalten statt zwanzig. Nur der
eine Fotolauf mit dem 12-MP-Bild bekommt es — die Warteschleife wartet
die volle Zeit ab, und alle neun Läufe damit auszustatten hätte den
Abschnitt um sechs Minuten verlängert, ohne etwas zu messen.

Beim Einbauen ist die Falle zugeschnappt, vor der `kstate.fi` an drei
Stellen warnt: die erste Fassung nahm Bit 17 — das gehört `M_DESK`. Der
Betrachter startete daraufhin gar nicht, statt dessen stand der Starter
im Bild. Zwei Schalter auf einem Bit, genau der Fehler, gegen den der
Modusvektor der Runde K17 gebaut wurde.

### Was danach stand

`tools/viewer/run.sh`, Abschnitt 8, **49 von 49 Zusagen**, darunter die
vier, die die Runde vorher nicht belegen konnte: das 12-MP-Bild steht
mit **4000 × 3000** im Fenster (1 804 336 Oktette Arena, als
**Vorschau** und nicht bearbeitbar), die EXIF-Lage 6 dreht das Foto von
40 × 24 auf 24 × 40, die Diaschau geht von selbst weiter, und Pillow
liest, was die Anwendung geschrieben hat (`PNG 64x48 RGBA`).
