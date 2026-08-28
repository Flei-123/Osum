# Bilder auf Osum — was gelesen wird, was geschrieben wird, und was nicht

Runde VIEWER. Dieses Dokument gehört zu `kernel/user/img.fi` und den vier
Dekodierern daneben. Es sagt drei Dinge: **was geht**, **was nicht geht
und warum**, und **was es kosten würde**, das Fehlende nachzuziehen.

---

## 1. Die Schnittstelle

Ein einziger Weg für alle Formate, und er hält kein ganzes Bild:

```
    img.arena(basis, laenge)          einmal: der Speicher, den es geben darf
    img.sniff(p, n)         -> Format an den ersten Oktetten, nicht an der Endung
    img.begin(p, n, scale)  -> Kopfdaten gelesen, Puffer angelegt
    img.width() / height() / orientation() / frames() / reason()
    img.next_row(ziel)      -> EINE Zeile RGBA, vier Oktette je Bildpunkt
```

`scale` ist 1 oder 8. Bei JPEG heißt 8: nur der Gleichanteil jedes
8×8-Blocks (`jpeg_idct_1x1`), also ein Achtel je Kante und rund ein
Sechzigstel der Arbeit — das ist die Miniaturansicht.

**Warum zeilenweise.** Ein Bild mit 12 Megabildpunkten ist als RGBA 48
Megaoktett, eines mit 50 Megabildpunkten 200. Der JPEG-Dekodierer hält
statt dessen drei MCU-Zeilen je Komponente in einem Ringpuffer; sein
Speicherbedarf hängt an der **Breite** und nicht an der Fläche.
Gemessen (`tools/viewer/run.sh`, Abschnitt 5):

| Bild | Bildpunkte | Arbeitsspeicher |
|---|---|---|
| 4000 × 3000, 4:2:0 | 12 000 000 | 1 023 072 Oktette |
| 8000 × 6250, 4:2:0 | 50 000 000 | 2 047 376 Oktette |

Die Fläche wächst um das Vierfache, der Speicher um das Doppelte — weil
nur die Breite eingeht. **Das ist die Antwort auf „was passiert bei 50
Megabildpunkten": es wird dekodiert.**

---

## 2. Die Grenzen, als Zahlen

| Grenze | Wert | Wo sie steht |
|---|---|---|
| Größte Bildfläche (JPEG, PNG, BMP) | 100 Megabildpunkte | `MAXPIX` in `imgjpeg.fi`, `imgpng.fi`, `img.fi` |
| Größte Kantenlänge | 65 500 (JPEG) / 65 535 (PNG, BMP) | ebenda |
| Leinwand eines GIF | 16 Megabildpunkte | `MAXPIX` in `imggif.fi` |
| Datei, die `imgtest` einliest | 32 MiB | `MAXFILE` in `imgtest.fi` |
| Datei, die die Anwendung einliest | 24 MiB | `MAXFILE` in `viewer.fi` |
| Bild, das die Anwendung AM STÜCK hält (drehen, zuschneiden, sichern) | 32 MiB RGBA = 8 Megabildpunkte | `VOLLGRENZE` in `viewer.fi` |
| Arena eines Prozesses | 74 MiB | `proc.BIG_TOP` − `proc.BIG_FLOOR` |

Was über der letzten Zeile liegt, wird **angezeigt** (die Vorschau
entsteht zeilenweise), aber nicht bearbeitet: die Statuszeile schreibt
dann `VORSCHAU (zu gross)` hin, und die Knöpfe zum Bearbeiten tun nichts.
Ein Betrachter, der in dieser Lage abstürzt, wäre die schlechtere
Antwort; einer, der es verschweigt, auch.

**Der Kernel hat für diese Runde zwei Zahlen bekommen** (`kernel/proc.fi`):
`PRIV_SLOTS` von 6 auf 40 und `BIG_TOP` von `0x40C00000` auf
`0x45000000`. Damit wächst die private Arena eines Prozesses von 6 auf 74
MiB. Die Kacheln entstehen weiterhin erst, wenn jemand sie anfasst, und
werden mit dem Prozess freigegeben — ein Programm, das die Arena nie
betritt, belegt keinen Rahmen mehr als vorher.

---

## 3. Was gelesen wird

| Format | Kann | Kann nicht |
|---|---|---|
| **PNG** | Bittiefen 1/2/4/8/16, Graustufen, RGB, Palette, Graustufen+Alpha, RGBA, `tRNS`, Adam7-Verschränkung, alle fünf Zeilenfilter | 16 Bit werden auf das obere Oktett gekürzt; `iCCP`/`gAMA` werden nicht angewandt |
| **JPEG** | Baseline und „extended sequential" (SOF0/SOF1), 8 Bit, Graustufen und Y′CbCr, 4:4:4, 4:2:2, 4:2:0 und beliebige andere Verhältnisse, Neustartmarken (RST), EXIF-Ausrichtung | **progressiv (SOF2)**, arithmetische Kodierung, 12 Bit, verlustfrei, hierarchisch, CMYK/Adobe (4 Komponenten), Durchgänge mit nur einem Teil der Komponenten |
| **BMP** | 1/4/8/16/24/32 Bit, Paletten, `BI_BITFIELDS`, von unten nach oben und von oben nach unten, `BITMAPCOREHEADER` und `BITMAPINFOHEADER` | RLE4/RLE8 (`BMP-RLE`), eingebettetes PNG/JPEG |
| **GIF** | LZW, globale und lokale Palette, Transparenz, Verschränkung, **Animation** mit allen drei Entsorgungsarten, Zahl der Durchläufe | — |

Und was **erkannt und beim Namen abgelehnt** wird, statt als „kaputte
Datei" zu gelten: **WebP**, **HEIC/HEIF/AVIF**, **SVG**, **TIFF**.
`img.sniff` gibt dafür `F_WEBP`, `F_HEIC`, `F_SVG`, `F_TIFF` zurück und
`img.reason_text` das Wort `NICHT UNTERSTUETZT`.

### Was das Fehlende kosten würde

Aus der eigenen Recherche (`/root/osum-research-raw.md`, Teilaufgabe 5)
und an dieser Runde nachgeprüft: die vier Dekodierer hier sind zusammen
**2 738 Zeilen**, und das deckt sich mit der Schätzung von 1 300–2 500
Zeilen allein für JPEG.

| Fehlt | Aufwand | Bewertung |
|---|---|---|
| **Progressives JPEG** | +600–900 Zeilen, 2–3 Wochen. Zweiter Entropie-Dekodierer mit Spektralauswahl und Näherung über mehrere Durchgänge — **und ein Koeffizientenpuffer für das ganze Bild**, also genau das, was dieser Dekodierer absichtlich nicht hat (12 MP × 3 Komponenten × 2 Oktette = 72 MiB) | Etwa ein Drittel der Fotos im Netz sind progressiv. Der teuerste einzelne Posten dieser Liste, und der einzige, der die zeilenweise Bauart antastet |
| **WebP** | 6 000–8 000 Zeilen, 6–10 Wochen: VP8 (Bool-Dekodierer, Intra-Prädiktion, 4×4-DCT/WHT, Schleifenfilter) **plus** VP8L (Huffman, Farbcache, Rückverweise, vier Transformationen) plus RIFF und Animation | Der ehrliche Schmerzpunkt. Pragmatisch wäre **erst VP8L** (verlustfrei, ~1 500–2 500 Zeilen) — viele gespeicherte Netzbilder sind das |
| **HEIC/HEIF** | 15 000–30 000 Zeilen, 4–8 Monate: ISOBMFF plus **vollständiger HEVC-Intra-Dekodierer** (CABAC, CTU-Quadtree, 35 Intra-Modi, Deblocking, SAO, 10 Bit), dazu das Kachelgitter des iPhone | **Unrealistisch als Eigenbau.** Der Ausweg: HEIC-Dateien tragen meist ein eingebettetes JPEG als Vorschau — ISOBMFF lesen und dieses anzeigen kostet ~300 Zeilen und deckt „ich will das Foto sehen" zu 90 % ab. Muss dann als „Vorschau" gekennzeichnet werden |
| **SVG** | 3 000–5 000 Zeilen für ein brauchbares Teilstück (Referenz NanoSVG: ~3 000 Parser + 1 400 Rasterer, ohne Text und CSS) | Kein Dekodierer, ein **Renderer**: Pfadgrammatik, Bézier-Zerlegung, Scanline-Füllung, Kantenglättung, Strichenden, Verläufe — und Text bräuchte den ganzen Schriftrasterer. Ein Teilstück schafft 70–80 % aller Symbole und Logos |
| **TIFF** | 800–1 500 Zeilen für das Minimum (unkomprimiert, PackBits, LZW, Deflate), 3 000+ für die Wirklichkeit (CCITT G3/G4, JPEG-in-TIFF, Kacheln, CMYK, YCbCr) | Nische. Der Container ist leicht, der Codec-Zoo ist es nicht |
| **AVIF** | 30 000+ Zeilen (AV1-Intra) | **Streichen.** Personenjahre |

---

## 4. Was geschrieben wird

**PNG**, acht Bit, RGB oder RGBA, nicht verschränkt, mit der
Filterwahl der Spezifikation (kleinste Summe der Beträge je Zeile) und
`deflate` aus `kernel/user/flate.fi`. Der Beweis, dass es echtes PNG ist:
`tools/viewer/run.sh` holt die geschriebene Datei mit
`tools/viewer/holen.py` vom Abbild und lässt sie von **Pillow** lesen.

**JPEG**, Baseline, 8 Bit, 4:4:4, Qualität 1–100
(`kernel/user/imgjenc.fi`, 637 Zeilen). Vorwärts-DCT ist
`jpeg_fdct_islow` — dieselbe Ganzzahlrechnung wie die inverse; die
Quantisierungstabellen sind die aus Anhang K mit libjpegs
Skalierungsformel; die Huffman-Tabellen sind ebenfalls die aus Anhang K
(aus einer Datei gezogen, die Pillow geschrieben hat). Kein eigener
Huffman-Erzeuger: er wäre 150 Zeilen für ein paar Prozent Dateigröße.

**Wie gut ist er?** Der Vergleich kann hier nicht „gleich" heißen — ein
JPEG ist verlustbehaftet. Gemessen wird deshalb **„gleich gut"**: derselbe
Ausgangsbildpunkt, dieselbe Qualität, und dann Dateigröße und Fehler
gegen libjpeg:

| Qualität 85, 4:4:4 | Datei | größter Fehler | mittlerer Fehler |
|---|---|---|---|
| **Osum** | 3 094 Oktette | 55 | 5,061 |
| libjpeg (Pillow) | 3 100 Oktette | 60 | 4,935 |

Sechs Oktette kleiner, ein Fehler in derselben Größenordnung. Was fehlt:
**keine Unterabtastung** (4:2:0 würde die Datei um rund ein Viertel
kleiner machen, +150 Zeilen), kein progressives JPEG, keine
Neustartmarken, kein optimiertes Huffman, kein EXIF im Ausgang.

---

## 5. Gemessen gegen Pillow, nicht gegen den Augenschein

Ein Dekodierer, der „gut aussieht", ist nicht geprüft. Jedes Testbild
wird auf dem Wirt mit **Pillow** (libjpeg-turbo 3.1.4, zlib-ng, giflib)
dekodiert; die rohen RGBA-Oktette kommen auf dasselbe Plattenabbild, und
`/bin/imgtest` vergleicht sie im laufenden System Bildpunkt für
Bildpunkt.

**Die Zahlen** (`tools/viewer/run.sh`, Abschnitt 4):

| Gruppe | Größte Abweichung je Kanal | Bemerkung |
|---|---|---|
| PNG (8 Bilder: RGB, RGBA, Palette, tRNS, Grau 1/8/16 Bit, Adam7, 3 MP) | **0** | bitgenau |
| BMP (24, 32, 8, 1 Bit) | **0** | bitgenau |
| GIF (Standbild, Animation, verschränkt) | **0** | bitgenau |
| JPEG 4:4:4, 4:2:0, Graustufen, Neustartmarken, ungerade Maße, 1×1, 1×129, 12 MP, 50 MP | **0** | bitgenau |
| JPEG 4:2:2 | **2** | Mittel 0,222 von 1000 Stufen |

**Warum das überhaupt bitgenau werden kann** — und das ist die
eigentliche Arbeit dieser Runde: der Dekodierer rechnet **absichtlich
genauso wie libjpeg**.

* Die inverse DCT ist `jpeg_idct_islow`: Ganzzahl, 13 Bit Konstanten,
  zwei Durchgänge, `PASS1_BITS = 2`. Nicht die naheliegende
  Gleitkomma-Fassung — dieses System rechnet in Ring 3 ohnehin
  ganzzahlig (der Kernel sichert die SSE-Register beim Wechsel nicht,
  und `kernel/user/fas.fi` sagt, dass der eigene Assembler die Befehle
  gar nicht kennt). Ganzzahl ist hier also kein Kompromiss, sondern der
  einzige Weg — und zufällig auch der genauere.
* Die Hochrechnung der Farbkanäle ist libjpegs Dreiecksfilter
  (`h2v1_fancy_upsample`, `h2v2_fancy_upsample`) mit denselben
  Rundungssummanden 1, 2, 7 und 8 und derselben Randbehandlung.
* Y′CbCr → RGB benutzt libjpegs Festkommatabellen mit 16 Bit und dessen
  Konstanten 1,40200 / 1,77200 / 0,34414 / 0,71414. Wer hier die
  „richtigeren" Werte 0,344136 und 0,714136 nimmt, weicht von der
  Vorlage ab und misst danach seinen eigenen Geschmack.

Die **2 Stufen bei 4:2:2** bleiben als benannte Toleranz stehen: sie
treten nur an waagerecht hochgerechneten Farbkanten auf, der Mittelwert
über alle Kanäle liegt bei 0,0002 Stufen, und für die Abnahme gilt die
Grenze **≤ 2 bei JPEG, = 0 bei PNG, BMP und GIF**.

---

## 6. Kaputte Dateien

Sieben von ihnen liegen im Abbild, und die Zusage ist nicht „richtig
dekodiert", sondern **„ein Grund mit Namen, und der Kernel lebt danach"**:

| Datei | Was ihr fehlt | Antwort |
|---|---|---|
| `kurz.jpg` | nach 55 % abgeschnitten | Bild bis dahin, `teilweise=1` |
| `kurz.png` | nach 45 % abgeschnitten | Zeilen bis dahin, `teilweise=1` |
| `kurz.gif`, `kurz.bmp` | abgeschnitten | `ABGESCHNITTEN` |
| `winzig.jpg` | 1 % der Datei | `ABGESCHNITTEN` |
| `mues.jpg` | 64 Oktette in der Mitte verdreht | Bild, soweit der Entropiestrom trägt |
| `mues.png` | Oktette im Kopf verdreht | `ABGESCHNITTEN` |
| `luege.png` | behauptet im Kopf 30000 × 30000 und trägt 16 Oktette | erkannt, kein Speicher geholt |

`luege.png` ist der wichtigste Fall: ein Dekodierer, der dem Kopf
glaubt, fordert 3,6 Gigaoktett an. Hier entscheidet `MAXPIX` **vor** der
ersten Speicheranforderung.

---

## 7. Ein Fehler im festgenagelten Übersetzer, gefunden in dieser Runde

Die naheliegende Fassung des Dreiecksfilters hält drei Spaltensummen in
drei Veränderlichen und schiebt sie je Durchgang weiter:

```firn
    links = mitte
    mitte = rechts
    if c + 2 < dw { rechts = neue_summe() }
```

`firnc` (Commit `a751b3db`) legt `mitte` und `rechts` dabei auf
**denselben Stapelplatz**. Im Assembler (`--emit=asm`) ist es sichtbar:
der Anfangswert von `rechts` wird nach `[rbp-592]` geschrieben und eine
Zeile später vom Anfangswert von `mitte` überschrieben; im Rumpf liest
`mitte` dieselbe Zelle, in die der neue `rechts` geschrieben wird, und
am Ende des Durchgangs holt sich `links` von dort den **schon
weitergerückten** Wert. Das ist das klassische *lost-copy problem* beim
Verlassen der SSA-Form.

**Die Form ist wählerisch**, und das gehört dazu: dasselbe Muster mit
Konstanten statt Ladebefehlen (`rechts = rechts + 1`) übersetzt firnc
richtig. Nötig für den Fehler sind alle drei Zutaten — `mitte` wird aus
`links` initialisiert, die dritte Summe kommt aus einem Ausdruck mit
Funktionsaufrufen, und ihre Neuberechnung steht in einem `if`. Genau
diese Form steht als `rotationsprobe` in `kernel/user/imgtest.fi`, wird
bei jedem Abnahmelauf ausgeführt und mit dem Sollwert 132172216260
verglichen.

Gemessen hat es sich als Farbfehler von bis zu 163 Stufen bei 4:2:0 —
sichtbar, aber nicht offensichtlich falsch; ohne den Vergleich gegen
Pillow wäre es durchgegangen. **Der Umweg:** jede Spaltensumme wird
frisch aus dem Speicher geholt, sechs Ladebefehle je Spalte statt zwei.
`tools/viewer/run.sh` misst den Fehler in Abschnitt 9 weiter — wird
Firn repariert, meldet der Abschnitt es.
