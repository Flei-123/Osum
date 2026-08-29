# STATUS-VIEWER — Stand der Runde VIEWER

Zweig `viewer`, abgezweigt von `mergeline` (6b602af). **Nicht nach main
mergen.** Auftrag: Bildbetrachter (Roadmap E6) mit eigenem JPEG- und
PNG-Dekodierer — und der JPEG-Dekodierer ist zugleich Schritt **F5** der
Medien-Roadmap, weil MJPEG-Video nichts anderes ist als eine Folge von
JPEG-Bildern.

## Was steht

| # | Stück | Datei | Zeilen | Zustand |
|---|---|---|---|---|
| 1 | Arena-Allokator für Dekodierer | `kernel/user/imgmem.fi` | 159 | fertig |
| 2 | **Baseline-JPEG lesen**, zeilenweise, islow-IDCT | `kernel/user/imgjpeg.fi` | 1 419 | bitgenau gegen Pillow |
| 3 | **PNG lesen und schreiben** | `kernel/user/imgpng.fi` | 971 | bitgenau |
| 4 | **GIF mit Animation** (LZW) | `kernel/user/imggif.fi` | 546 | bitgenau |
| 5 | **BMP** + Formaterkennung + die eine Schnittstelle | `kernel/user/img.fi` | 713 | bitgenau |
| 6 | **JPEG schreiben** (islow-FDCT, Anhang K) | `kernel/user/imgjenc.fi` | 637 | gemessen gegen libjpeg |
| 7 | Verkleinern / drehen / spiegeln / zuschneiden | `kernel/user/imgops.fi` | 281 | fertig |
| 8 | Messprogramm gegen Pillow | `kernel/user/imgtest.fi` | 592 | fertig |
| 9 | **Anwendung „Bilder"** | `kernel/user/viewer.fi` | 1 420 | fertig |
| 10 | Bündel | `assets/apps/viewer.osp/` | — | fertig |
| 11 | Abnahme | `tools/viewer/run.sh` + 3 Helfer | 1 050 | fertig, Abschnitt 29 in `./test.sh` |
| 12 | Doku | `docs/IMAGES.md`, `docs/ROUNDVIEWER.md` | — | fertig |

Zusammen **4 726 Zeilen Dekodierer und Schreiber** (imgmem, imgjpeg,
imgpng, imggif, img, imgjenc, imgops) plus 2 012 Zeilen Anwendung und
Messprogramm und 1 050 Zeilen Abnahme.

## Die Entscheidung, die alles trägt

**Der Dekodierer hält nie ein ganzes Bild.** `img.next_row` liefert eine
Zeile RGBA; der JPEG-Dekodierer hält drei MCU-Zeilen je Komponente in
einem Ringpuffer. Damit hängt der Arbeitsspeicher an der **Breite** und
nicht an der Fläche:

* 12 Megabildpunkte (4000 × 3000): **1 023 072** Oktette, **2 290 ms**
* 50 Megabildpunkte (8000 × 6250): **2 047 376** Oktette, **8 800 ms**
* dasselbe 12-MP-Bild als Miniatur (1/8, nur der Gleichanteil): **230 ms**

Vierfache Fläche, doppelter Speicher. Genau diese Bauart braucht die
Medienrunde für MJPEG wieder.

## Gemessen gegen Pillow (libjpeg-turbo, zlib-ng, giflib)

27 Bilder, Bildpunkt für Bildpunkt, **im laufenden System** verglichen:

* **PNG, BMP, GIF: Abweichung 0** — bitgenau, alle Bittiefen, Palette,
  Alpha, Adam7, Animation.
* **JPEG: Abweichung 0** bei 4:4:4, 4:2:0, Graustufen, Neustartmarken,
  ungeraden Maßen, 1×1, 1×129, 12 MP und 50 MP. **Nur 4:2:2 weicht um
  bis zu 2 Stufen ab** (Mittel 0,222 von 1000).
* **Geschrieben:** fünf PNG-Dateien und zwei JPEG-Dateien werden vom
  Abbild geholt und von Pillow gelesen; Zuschneiden und Drehen sind
  bitgenau dasselbe wie bei Pillow. Das eigene JPEG ist bei Qualität 85
  **3 094 Oktette** groß gegen **3 100** von libjpeg, bei gleichem
  Fehler.

## Der Kernel hat zwei Zahlen bekommen

`kernel/proc.fi`: `PRIV_SLOTS` 6 → 40, `BIG_TOP` `0x40C00000` →
`0x45000000`. Die private Arena eines Prozesses wächst von 6 auf 74 MiB.
Grund: eine Datei muss ganz im Speicher liegen, bevor der erste Marker
gelesen wird, und ein PNG braucht seinen ausgepackten Rohstrom am Stück
(`flate.inflate` ist nicht fortsetzbar). Mit 6 MiB war schon ein
Handyfoto nicht zu öffnen. Die Kacheln entstehen weiterhin erst bei
Bedarf.

## Vier Fehler, die nur die Messung gefunden hat

1. **Versatz gegen Adresse** — dreimal im Baum (JPEG-Marker, PNG-Blöcke,
   GIF-Blocklängen) und einmal als Vergleich einer Adresse mit einer
   Länge (BMP-Palette blieb schwarz).
2. **Ein Fehler im festgenagelten Übersetzer**: `firnc` (a751b3db) legt
   drei über die Schleifenkante rotierende Veränderliche auf zwei
   Stapelplätze. Umgangen, aufgeschrieben in `docs/IMAGES.md`
   Abschnitt 7 — und die Abnahme **misst ihn weiter**
   (`IMGROT wert=132220264264` statt `132172216260`).
3. **`ulib.cmp` hat kein Vorzeichen** (0/1/2) — die Ordnerliste stand
   rückwärts.
4. **Die Eingabetaste kommt als 10 an, `wlib` prüft auf 13** — ein Knopf
   im Fokus reagiert deshalb systemweit nicht auf die Eingabetaste. Die
   Leertaste geht; die Abnahme bedient die Oberfläche damit.

## Was diese Runde nicht kann

Progressives JPEG (benannt, nicht falsch gezeigt), WebP, HEIC, SVG,
TIFF (erkannt und beim Namen abgelehnt), Unterabtastung beim Schreiben,
Zwischenablage und Ziehen-und-Ablegen (hängen an A3/D1/D2), freies
Aufziehen eines Ausschnitts mit der Maus. Alles mit Zahlen in
`docs/IMAGES.md`.
