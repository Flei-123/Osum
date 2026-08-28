# STATUS-VIEWER — Zwischenstand der Runde VIEWER

Zweig `viewer`, abgezweigt von `mergeline` (6b602af). **Nicht nach main
mergen.** Auftrag: Bildbetrachter (Roadmap E6) mit eigenem JPEG- und
PNG-Dekodierer — und der JPEG-Dekodierer ist zugleich Schritt **F5** der
Medien-Roadmap, weil MJPEG-Video nichts anderes ist als eine Folge von
JPEG-Bildern.

## Was steht

| # | Stück | Datei | Zeilen | Zustand |
|---|---|---|---|---|
| 1 | Arena-Allokator für Dekodierer | `kernel/user/imgmem.fi` | 158 | fertig |
| 2 | **Baseline-JPEG**, zeilenweise, islow-IDCT | `kernel/user/imgjpeg.fi` | 1 371 | fertig, bitgenau gegen Pillow |
| 3 | **PNG** lesen und schreiben | `kernel/user/imgpng.fi` | 1 000 | fertig, bitgenau |
| 4 | **GIF** mit Animation (LZW) | `kernel/user/imggif.fi` | 528 | fertig, bitgenau |
| 5 | **BMP** + Formaterkennung + eine Schnittstelle | `kernel/user/img.fi` | 700 | fertig, bitgenau |
| 6 | Verkleinern / drehen / zuschneiden | `kernel/user/imgops.fi` | 300 | fertig |
| 7 | Messprogramm gegen Pillow | `kernel/user/imgtest.fi` | 560 | fertig |
| 8 | **Anwendung „Bilder"** | `kernel/user/viewer.fi` | 1 200 | fertig |
| 9 | Bündel | `assets/apps/viewer.osp/` | — | fertig |
| 10 | Abnahme | `tools/viewer/run.sh` | 380 | läuft |
| 11 | Doku | `docs/IMAGES.md` | — | fertig |

## Die Entscheidung, die alles trägt

**Der Dekodierer hält nie ein ganzes Bild.** `img.next_row` liefert eine
Zeile RGBA; der JPEG-Dekodierer hält drei MCU-Zeilen je Komponente in
einem Ringpuffer. Damit hängt der Arbeitsspeicher an der **Breite** und
nicht an der Fläche:

* 12 Megabildpunkte (4000 × 3000): **1 023 072** Oktette
* 50 Megabildpunkte (8000 × 6250): **2 047 376** Oktette

Vierfache Fläche, doppelter Speicher. Genau diese Bauart braucht die
Medienrunde für MJPEG wieder: Bild hinein, Zeilen heraus, konstanter
Speicher, kein Aufruf in den Fensterserver.

## Der Kernel hat zwei Zahlen bekommen

`kernel/proc.fi`: `PRIV_SLOTS` 6 → 40, `BIG_TOP` `0x40C00000` →
`0x45000000`. Die private Arena eines Prozesses wächst damit von 6 auf
74 MiB. Grund: eine Datei muss ganz im Speicher liegen, bevor der erste
Marker gelesen wird (ein 12-MP-JPEG sind 700 KiB bis 5 MiB), und ein PNG
braucht seinen ausgepackten Rohstrom am Stück, weil `flate.inflate` nicht
fortsetzbar ist. Mit 6 MiB war schon ein Handyfoto nicht zu öffnen.

## Gefunden: ein Fehler im festgenagelten Übersetzer

`firnc` (a751b3db) legt drei über die Schleifenkante rotierende
Veränderliche auf zwei Stapelplätze und verliert dabei eine Kopie
(*lost-copy problem*). Belegt im Assembler und im Messwert: bis zu 163
Stufen Farbfehler bei 4:2:0. Umgangen (jede Summe frisch aus dem
Speicher), aufgeschrieben in `docs/IMAGES.md` Abschnitt 7, und die
Abnahme misst den Fehler weiter — wird Firn repariert, meldet sie es.

## Zahlen

Siehe `docs/ROUNDVIEWER.md` (Abschluss) und `docs/IMAGES.md`.
