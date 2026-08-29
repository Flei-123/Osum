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

## Die Oberfläche, wirklich bedient: 49 von 49

Abschnitt 8 der Abnahme schickt der Anwendung über den QEMU-Monitor
Tabulator, Leertaste und Buchstaben und misst danach, was sie meldet
und was im Bild steht. Beim ersten ernsthaften Durchlauf fielen
**18 Zusagen** durch — keine davon im Dekodierer. Vier Fehler, alle
gemessen und alle behoben (Einzelheiten in `docs/ROUNDVIEWER.md`
Abschnitt 8):

1. **Der Miniaturenstreifen rechnete bei jedem Schritt alles neu** —
   acht Dateien, darunter die 12-MP-JPEG. Ein Schritt weiter kostete
   **2,0 s**; in dieser Zeit holte die Anwendung keine Ereignisse ab und
   die nächste Taste ging verloren. Mit dem Kästchen-Cache
   (`mini_idx` + Umlagern statt Dekodieren) kostet er **0,05 s**, und
   keine Taste geht mehr verloren.
2. **`sichern()` schrieb neben das falsche Bild**, weil die Miniaturen
   denselben Pfadpuffer benutzten. Eigener Puffer (`mpfad`).
3. **`wmhold` hält 20 s, und das ist ein hartes Budget** — ein Skript
   von 20,9 s fiel mit `kein Monitor an ...` durch, was wie ein Fehler
   der Anwendung aussah. Kürzere Skripte, und für den einen Lauf mit dem
   großen Bild eine dritte Haltestufe im Kern.
4. **Kern und Anwendung schreiben ungesperrt auf dieselbe serielle
   Leitung** — einmal war `wm: hold` mitten in einer Kernelmeldung
   zerschnitten und die Abnahme wartete 300 s ins Leere. Sie sucht jetzt
   ohne Zeilenanker; die fehlende Sperre in `serial.puts` ist benannt
   und **nicht** behoben.

| Zusage im Bild | gemessen |
|---|---|
| 12-MP-Bild im Fenster | **4000 × 3000**, 1 804 336 Oktette Arena, als Vorschau |
| EXIF-Lage 6 | aus 40 × 24 wird **24 × 40** |
| Blättern über vier Formate | PNG → JPEG → PNG+Alpha → GIF |
| Zoom „100 %" | Einpassen aus, Zoom 100 |
| Vierteldrehung | aus 64 × 48 wird 48 × 64 |
| Diaschau | geht von selbst auf Bild 2 |
| Sichern | Pillow liest `PNG 64x48 RGBA`, 2 747 Oktette |
| Tastatur `n` / `1` / `r` | blättert, 100 %, dreht |

## Der Kernel hat drei Zahlen bekommen

`kernel/proc.fi`: `PRIV_SLOTS` 6 → 40, `BIG_TOP` `0x40C00000` →
`0x45000000`. Die private Arena eines Prozesses wächst von 6 auf 74 MiB.
Grund: eine Datei muss ganz im Speicher liegen, bevor der erste Marker
gelesen wird, und ein PNG braucht seinen ausgepackten Rohstrom am Stück
(`flate.inflate` ist nicht fortsetzbar). Mit 6 MiB war schon ein
Handyfoto nicht zu öffnen. Die Kacheln entstehen weiterhin erst bei
Bedarf.

Dazu die dritte: `kstate.M_WIGXL` (Wort 1, **Bit 33**) und das Wort
`wigxl` — **60 s** Stillhalten statt der 20 s von `wiglong`. Nur der
Fotolauf mit dem 12-MP-Bild bekommt es; die Warteschleife wartet die
volle Zeit ab. Die erste Fassung hatte Bit **17** genommen, und das
gehört `M_DESK` — der Betrachter startete daraufhin gar nicht.

## Was diese Runde in ANDEREN Abnahmen zerbrochen hatte

Der Betrachter steht seit dieser Runde in der Programmliste von sechs
weiteren Testläufern, und sein Bündel liegt unter `assets/apps`. Beides
hatte Folgen, die keiner der Läufer benannte:

* **`tools/k15/run.sh` fiel mit 35 Zusagen durch.** Die einzige Zeile,
  die es sagte, war `mkfs: the disk is full` — `/bin/viewer` trägt vier
  Dekodierer und zwei Schreiber (rund 450 KiB), und mit 4096 Blöcken
  (16 MiB) ging das Abbild nicht mehr auf. Danach fehlte jede Platte,
  und alles Weitere war Folgeschaden. **Abbild auf 8192 Blöcke.**
* **Fünf weitere Zusagen desselben Läufers** prüften bildpunktgenau,
  dass in Zeile 0 des Starters „Datei-Explorer" steht. Der Starter
  sortiert nach Anzeigenamen, und **„Bilder" kommt vor „Datei-Explorer"**
  — die Zusagen sind eine Zeile weitergerückt (Name, Beschreibung und
  Symbol werden weiterhin Punkt für Punkt geprüft, jetzt für den
  Betrachter in Zeile 0 und den Dateimanager in Zeile 1).
* Dieselbe Bildgröße vorsorglich für `tools/desktop`, `tools/icons`,
  `tools/netview/smoke.sh` und `tools/tresor/gui.sh` — sie tragen den
  Betrachter ebenfalls in ihrer Programmliste.

**Nachgemessen nach der Reparatur:**

| Läufer | Ergebnis |
|---|---|
| `tools/viewer/run.sh` | **109 passed, 0 failed** |
| `tools/k15/run.sh` | **254 passed, 0 failed** (vorher 35 rot) |
| `tools/wm/run.sh` | **103 passed, 0 failed** |
| `tools/icons/run.sh` | 24 ok, **1** rot — `lib/icons.fi` gegen den Lucide-Bauer, **vorbestehend** (diese Runde fasst weder `lib/icons.fi` noch `assets/icons` an) |
| `tools/desktop/run.sh` | **6** rot, alle **vorbestehend**: `WM_MAXNR` erwartet 2113, `kernel/sys.fi` führt 2114 (von dieser Runde nicht angefasst), und die fünf Zusagen um `settings: ... edge=right` sind das in `docs/NETVIEW.md` §11.5 aufgeschriebene Verschneiden der seriellen Leitung zwischen drei Ring-3-Programmen — **dasselbe Grundproblem**, das diese Runde in Abschnitt 8 noch einmal getroffen hat |

Für die beiden roten Läufer wurde **kein** Grundlinienlauf auf
`mergeline` gemacht; die Zuordnung „vorbestehend" stützt sich auf die
Quelltexte (unberührt) und auf `docs/NETVIEW.md`. Das gehört
dazugesagt.

## Zeilenzahlen und Zeiten, zum Nachschlagen

| | |
|---|---|
| Dekodierer und Schreiber zusammen | **4 726** Zeilen |
| Anwendung + Messprogramm | 2 012 Zeilen |
| Abnahme | 1 050 Zeilen |
| 12 MP (4000 × 3000, 4:2:0) dekodieren | **2 340 ms**, 1 023 072 Oktette |
| 50 MP (8000 × 6250, 4:2:0) dekodieren | **9 270 ms**, 2 047 376 Oktette |
| dasselbe 12-MP-Bild als Miniatur (1/8) | **230 ms** |
| ein Schritt weiter in der Anwendung | **~50 ms** (vorher 2 000 ms) |
| größte Abweichung JPEG gegen Pillow | **2** Stufen (nur 4:2:2, Mittel 0,222 ‰) |
| größte Abweichung PNG / BMP / GIF | **0** — bitgenau |
| eigenes JPEG bei Qualität 85 | 3 094 Oktette gegen 3 100 von libjpeg |

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
