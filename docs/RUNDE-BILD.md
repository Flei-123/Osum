# Runde BILD -- GIF, "Als JPEG sichern", und endlich ein Laeufer

Zweig `runde-bild`, abgezweigt von `main` 8e772f44.
Alle Zahlen hier sind gemessen, nicht geschaetzt; wie sie zustande
kommen, steht jeweils dabei.

## Worum es ging

Der Bildbetrachter aus Runde ALLTAG konnte PNG, BMP und JPEG lesen und
nichts schreiben. Drei Luecken waren gemessen offen:

1. **GIF** gab es im ganzen Baum nicht -- weder GIF87a noch GIF89a.
2. **Sichern** gab es gar nicht. `image.png_write` lag seit Runde
   ALLTAG da und wurde vom Betrachter nie gerufen; einen
   JPEG-Kodierer gab es nicht.
3. **Einen Laeufer** gab es nicht. `tools/viewer/` existierte nicht,
   es gab also keinen Nachweis, dass der Betrachter tut, was er sagt.

## Was jetzt da ist

### `kernel/user/gif.fi` (neu, 648 Zeilen)

GIF87a und GIF89a lesen: LZW mit dem Sonderfall KwKwK, globale und
lokale Farbtafel, Durchsichtigkeitsindex, **verschachtelt** (vier
Durchgaenge 8/8/4/2 ab Zeile 0/4/2/1), Entsorgungsarten.

Der Speicher kommt vom Rufer, wie bei `image.fi` und `jpeg.fi`. Der
alte Zweig `viewer` hatte dafuer einen eigenen kleinen Haldenverwalter
(`imgmem.take`); den gibt es in diesem Baum nicht und er ist bewusst
nicht wieder hereingekommen.

### `kernel/user/jenc.fi` (neu, 688 Zeilen)

Baseline-JPEG schreiben: 4:4:4, Quantisierungstabellen aus Anhang K in
libjpegs Skalierung, Huffman-Tabellen aus Anhang K, Vorwaerts-DCT
`jpeg_fdct_islow` (Ganzzahl, 13 Bit Konstanten).

### `kernel/user/viewer.fi` (erweitert)

* GIF wird geladen (`art=4`), `viewer -i` sagt bei einer Bildfolge
  zusaetzlich `bilder=N`.
* Zwei Schalter **PNG** und **JPEG** sichern das, was im Puffer liegt.
* Neu `viewer -s <ziel> <quelle>` -- sichern ohne Maus, damit der
  Umlauf messbar ist. Die Endung des Ziels entscheidet das Format.

### `tools/bild/` (neu)

`run.sh` (die Abnahme), `mkbilder.py` (die Testbilder, mit Pillow
gebaut), `pruefen.py` (der Umlauf, mit Zahlen).

## Die Zahlen

### Abnahme

```
BILD: 25 passed, 0 failed
```

### GIF gegen Pillow (giflib): Abweichung 0

Zwoelf Dateien werden auf dem Wirt mit Pillow und im Gast mit dem
eigenen Dekodierer gelesen; verglichen werden Groesse, die Summe jedes
Farbkanals ueber alle Bildpunkte und fuenf einzelne Bildpunkte
(`tools/alltag/bildref.py`). GIF, PNG und BMP sind verlustfrei, die
Schranke ist deshalb **0** und nicht "klein".

| Datei | Groesse | was daran besonders ist | Ergebnis |
|---|---|---|---|
| `g-einfarb.gif` | 32x24 | die kuerzeste LZW-Folge (ein Lauf) | stimmt |
| `g-tafel.gif` | 40x30 | Farbtafel mit 256 Eintraegen | stimmt |
| `g-transp.gif` | 32x32 | durchsichtiger Index | stimmt |
| `g-lace.gif` | 64x48 | **verschachtelt** | stimmt |
| `g-gerade.gif` | 36x28 | ausdruecklich NICHT verschachtelt | stimmt |
| `g-anim.gif` | 48x32 | Bildfolge, 4 Teilbilder | stimmt |
| `g-gross.gif` | 160x120 | erzwingt eine Woerterbuchloeschung | stimmt |
| `g-87a.gif` | 24x16 | die alte Fassung GIF87a | stimmt |
| `b-probe.png` | 48x36 | PNG (keine Regression) | stimmt |
| `b-pal.png` | 32x24 | PNG (keine Regression) | stimmt |
| `b-probe.bmp` | 40x30 | BMP (keine Regression) | stimmt |
| `b-voll.jpg` | 64x48 | JPEG 4:4:4 (keine Regression) | stimmt |

`bildref: 12 von 12 Bildern stimmen mit Pillow ueberein.`

Zusaetzlich wurde die Dekodierlogik VOR dem ersten QEMU-Lauf Zeile fuer
Zeile in Python nachgebaut und gegen Pillow gehalten: **0 abweichende
Bildpunkte in allen acht GIF-Dateien**, maximaler Abstand 0. Das hat
zwei Denkfehler gespart, bevor Rechenzeit dafuer drauf ging.

### Sichern als PNG: verlustfrei, Abweichung 0

Die Datei wird im Gast geschrieben, vom Abbild geholt
(`mkfs.py cat`) und auf dem Wirt mit Pillow gelesen.

| Fall | Maße | Abweichung |
|---|---|---|
| `g-tafel.gif` -> PNG | 40x30 | **0** (1200 Bildpunkte) |
| `g-lace.gif` -> PNG | 64x48 | **0** (3072 Bildpunkte) |
| `b-probe.bmp` -> PNG | 40x30 | **0** (1200 Bildpunkte) |

### Sichern als JPEG: der Kodierer liegt da, wo libjpeg liegt

`file(1)` nennt die geschriebene Datei
`JPEG image data, JFIF standard 1.01, baseline, precision 8` und
Pillow macht sie auf.

**Die ehrliche Messung ist die dritte Spalte.** Gegen das Original zu
messen sagt wenig: ein Bild mit harten Kanten verliert auch bei
libjpeg und Qualitaet 90 sieben Stufen im Mittel. Die Frage ist, ob
der eigene Kodierer da landet, wo libjpeg landet -- gleiche Qualitaet,
gleiches Quellbild.

| Fall | gegen das Original | libjpeg selbst | **gegen libjpeg** | Datei (meine / libjpeg) |
|---|---|---|---|---|
| `b-probe.png` -> JPEG q90 | max 41, mittel 7,21 | max 43, mittel 7,15 | **max 20, mittel 2,43** | 2527 / 2530 Oktette |
| `b-voll.jpg` -> JPEG q90 (Umlauf) | max 26, mittel 4,30 | max 26, mittel 3,85 | **max 18, mittel 2,32** | 3178 / 3178 Oktette |
| `g-tafel.gif` -> JPEG q90 | max 38, mittel 11,00 | max 38, mittel 10,97 | **max 12, mittel 2,56** | 2728 / 2725 Oktette |

Die Dateigroessen liegen bei allen drei Faellen innerhalb von drei
Oktetten an libjpeg, bei einem Fall genau gleich. Das ist der
zusaetzliche Nachweis, dass die Huffman-Tabellen richtig benutzt werden
-- ein Kodierer, der sie falsch benutzt, wird sofort deutlich groesser.

### Kaputte Dateien

Drei Faelle, jeder gibt einen Grund mit Namen und bringt nichts um:
abgeschnitten (halbe Datei), erlogene Kopfgroesse (4000x4000 bei den
Daten eines 40x30-Bildes) und eine Datei, die nur `.gif` heisst.
`kein Absturz beim Lesen`, und die erlogene Groesse wird nicht
geglaubt.

## Zwei Fehler, die diese Runde selbst gemacht und gefunden hat

Beide stehen jetzt als Zusage in `tools/bild/run.sh`, damit sie nicht
wiederkommen:

1. **GIF fehlte in `ist_bildname`.** Der Dekodierer war fertig und
   richtig, aber der Ordnerleser legte `.gif` nie in die Liste -- das
   Fenster sagte "kein Bild". Ein Fehler, den kein Dekodierertest
   findet.
2. **Die Leiste lief ueber.** Die zwei neuen Schalter hiessen zuerst
   "Als PNG" und "Als JPEG" und ueberfuellten die 704 Punkte breite
   Leiste um 80; der Schieberegler behielt 40 statt 152 Punkte
   (`viewer: rect id=22 w=40`). Jetzt heissen sie "PNG" und "JPEG",
   und die Summe geht genau auf:
   40+40+92+60+72+104+52+60+152 = 672, plus acht Luecken von 4 = 704.

## Was NICHT geht, und das steht hier statt verschwiegen zu werden

* **Animierte GIFs bewegen sich nicht.** Gezeigt wird das erste
  Vollbild; der Kopf sagt `1/4`, damit niemand die Datei fuer ein
  Standbild haelt. Fuer die Folge braeuchte es einen zweiten Puffer
  und eine Uhr.
* **Entsorgungsart 3** ("Zustand davor wiederherstellen") wird erkannt
  und wie Art 2 behandelt (Rechteck durchsichtig). Fuer das erste
  Vollbild ohne Folgen -- davor gibt es keinen Zustand.
* **JPEG schreibt nur 4:4:4.** Kein 4:2:0, also rund ein Viertel
  groesser als libjpeg mit Vorgaben -- dafuer scharfe Farbe. Kein
  progressives JPEG, keine Neustartmarken, kein optimiertes Huffman,
  kein EXIF.
* **JPEG hat keinen Alphakanal.** Ein durchsichtiges PNG als JPEG
  gesichert verliert die Deckung; das ist das Format, nicht der
  Kodierer.
* **Der JPEG-Puffer ist 96 KiB** (`KOMPCAP`). Bei 4:4:4 und Qualitaet
  90 sind das rund 300x300 Bildpunkte Foto. Reicht er nicht, wird
  abgelehnt und **nicht halb geschrieben**.
* **Kein Dateiauswahldialog.** Gesichert wird neben die Quelle mit
  getauschter Endung, ohne Ueberschreibschutz.
* Farbtiefe 16, Adam7 und RLE-BMP lehnt `image.fi` weiter ab, wie
  bisher.

## Keine Regression

Die Laeufer waren vor der Arbeit gruen und sind es danach:

| Laeufer | vorher | nachher |
|---|---|---|
| `tools/k17/run.sh` | 158/0 | 158/0 |
| `tools/hv/run.sh` | 162/0 | 162/0 |
| `tools/ebpf/run.sh` | 81/0 | 81/0 |
| `tools/container/run.sh` | 52/0 | 52/0 |
| `tools/netzui/run.sh` | 47/0 | 47/0 |
| `tools/hotplug/run.sh` | 45/0 | 45/0 |
| `tools/struktur/run.sh` | STRUKTUR OK | STRUKTUR OK |
| `tools/check-ui.sh` | PASSED | PASSED |

`python3 tools/kernel/memmap.py` meldet **0 Kollisionen**; diese Runde
hat keine kdata-Seite gebraucht (Ring-3-Programme brauchen keine).

**Struktur:** die beiden neuen Dateien liegen in `kernel/user/`, und
das ist ausdruecklich **nicht** Teil des Schichtenmodells --
`tools/struktur/schichten.txt` sagt in Zeile 11 selbst, dass
`kernel/user/` (jetzt 190 Dateien) eigene Programme mit eigenen
Wurzeln sind. Es waren also keine Eintraege in `ablage.txt` oder
`schichten.txt` faellig, und `STRUKTUR OK` bestaetigt das.

**Abbildgroesse:** die Abnahme baut mit `bloecke=8192`, das Abbild ist
4.194.304 Oktette. Die Falle, in die der alte Zweig gelaufen ist
(`/bin/viewer` in der PROGS-Liste von K15 macht das 16-MiB-Abbild
voll und laesst 35 Zusagen grundlos durchfallen), ist hier nicht
beruehrt: `tools/bild/run.sh` baut seine eigene, schmale Platte mit
fuenf Programmen und fasst die Programmliste von K15 nicht an. K17 ist
mit 158/0 der Beleg.

## Wie man es nachprueft

```sh
bash tools/bild/run.sh          # die Abnahme, ~2 Minuten
```

Ein einzelnes Bild ansehen oder umrechnen:

```sh
viewer -i /b/g-anim.gif             # Art, Maße, Summen, fuenf Bildpunkte
viewer -s /ziel.jpg /b/g-tafel.gif  # sichern, Format aus der Endung
```
