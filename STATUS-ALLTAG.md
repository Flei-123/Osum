# STATUS — RUNDE ALLTAG

Zweig `alltag` (Arbeitsbaum `/root/osum-alltag`, Basis `merge6`). **Nicht gepusht, nicht gemergt.**

Abnahme: `bash tools/alltag/run.sh [ordner]` — zehn Abschnitte, jeder mit Gegenprobe.
Mit `ALLTAG_THEMESTORE=1` läuft `tools/themestore/run.sh` am Ende mit.

Sechs kleine Programme, die am ersten Tag fehlen, je als eigenes signiertes `.opk`
im Ladenkatalog: **Sperrbildschirm, Papierkorb, Ausschnittwerkzeug, Bildbetrachter,
ZIP, Taschenrechner.** Jede Oberfläche besteht ausschließlich aus `wlib` — was
fehlte (Bildfläche mit Zoom, Schieberegler, nachträgliche Größe, das Vierer-Raster),
wurde **ins Framework** gebaut und wird von allen benutzt.

## Was der Auftrag verlangte und wo es steht

| Auftrag | Wo | Zustand |
|---|---|---|
| Sperrbildschirm: Leerlauf, Win+L, exklusive Eingabe, Kennwort, sicherer Ausfall | `kernel/user/lock.fi`, `kernel/wm.fi`, `kernel/kstate.fi`, `kernel/sys.fi` (SYS 1850), `kernel/kbd.fi` | grün |
| Papierkorb je Datenträger, Originalpfad + Zeit, Zurück, Leeren, Grenze | `kernel/user/korb.fi`, `papierkorb.fi`, `/etc/papierkorb.conf` | grün, Rückholung byte-gleich |
| Explorer: Entf → Korb, Umschalt+Entf endgültig | `kernel/user/explorer.fi` | grün, beides gemessen |
| Ausschnittwerkzeug: Ausschnitt/Fenster/Vollbild, Verzögerung, PNG + Übergabe | `kernel/user/snip.fi`, `bild.png_datei`, `flate.strom_*` | grün, 99,8 % Bildpunkte wie QEMUs eigenes Foto |
| Bildbetrachter: PNG/JPEG/BMP, Zoom, Drehen, Blättern, Miniaturen | `kernel/user/viewer.fi`, `bild.fi`, `jpeg.fi` | grün, 6 Bilder exakt wie Pillow |
| ZIP packen/entpacken, Kontextmenü im Explorer | `kernel/user/zip.fi` (Deflate aus `flate.fi`) | grün, beide Richtungen gegen Python |
| Taschenrechner: Grund, Prozent, wissenschaftlich, Einheiten, Tastatur | `kernel/user/rechner.fi` | grün, 40 Ausdrücke = Python |
| Alles aus dem Laden installierbar | `tools/laden/apps.tab` + sechs gezeichnete Symbole | grün, 6 signierte Pakete eingespielt |
| Jede Oberfläche nur über wlib | `tools/alltag/run.sh` Abschnitt 10 | **0** direkte Zeichenaufrufe |
| Vierer-Raster ≥ 92 % | `tools/design/messen.py`, je Programm geprüft | **100 %** bei allen fünf Fenstern |

## Das Vierer-Raster steht jetzt in der Bibliothek, nicht in den Programmen

Vor dieser Änderung kam jede Länge aus einer Textbreite (Knopf 78, 90, 112) oder aus
der Schrifthöhe (18) — Zahlen, die kein Raster kennen. Gemessen: Rechner 67 %,
Papierkorb 83 %, Sperrbildschirm 43 %.

`wlib` rundet seit dieser Runde selbst (`r4ab`/`r4auf` in `kernel/user/wlib.fi`):

* die **Ecke** eines Kastens (`new_box`, `box_at`) — aufwärts, damit ein Kasten
  unter einer Reiterleiste nicht in sie hineinrutscht;
* die **Höhe** jedes Bedienelements aufwärts, die **Breite** auf den verfügbaren
  Platz abwärts;
* die **Spaltenbreite** eines Gitterkastens abwärts (der Zahlenblock des Rechners).

Ergebnis, gemessen mit `tools/design/messen.py`:

| Fenster | Raster/4 vorher | nachher | Klickflächen < 32 px |
|---|---|---|---|
| rechner | 67 % | **100 %** (100/100) | 1 → **0** von 23 |
| papierkorb | 83 % | **100 %** (24/24) | 0 |
| viewer | 97 % | **100 %** (36/36) | 0 |
| snip | 92 % | **100 %** (40/40) | 1 → **0** von 8 |
| lock | 43 % | **100 %** (16/16) | 1 → **0** von 2 |

Kein Programm rechnet dafür etwas aus; die Programme sind unverändert geblieben.

**Was das Runden kaputtgemacht hat, und wie es aufgefallen ist:** die Kachelhöhe der
Seite „Vorlagen" war `row + 10` = 34, wurde auf 36 aufgerundet, und die zehnte Kachel
fiel unten aus ihrem Kasten. Sichtbar wurde das nicht im Auge, sondern in der Abnahme
der Runde THEMESTORE: „Werkstatt" wurde gemalt und kam im Bild mit **keinem einzigen
Bildpunkt** an (`shotcheck: empty 1`). `tile_h` ist jetzt `row + 8` = 32 — selbst schon
ein Vielfaches von vier, also rundungsfest, und zehn Kacheln haben wieder Luft.

## Die Zahlen des Laufs

```
== ALLTAG: 47 grün, 0 rot ==   (mit ALLTAG_THEMESTORE=1: themestore 81 grün, 0 rot)
```

* **Rechner:** 40 von 40 Ausdrücken stimmen mit Python (relative Schranke 1e-9);
  Gegenprobe: `2++` gibt einen Fehler und keine Null.
* **ZIP:** packen → entpacken byte-gleich (auch im Unterordner); ein mit Python
  erzeugtes Deflate-ZIP wird entpackt; und Pythons `zipfile` liest das Archiv,
  das der Gast geschrieben hat (609 Oktette) — die Richtung, die ein eigener
  Entpacker nicht prüfen kann.
* **Papierkorb:** Liste kennt den Originalpfad, Rückholung byte-gleich, Leeren
  leert; im Dateimanager legt Entf hinein, Umschalt+Entf löscht endgültig
  (Gegenprobe: dabei entsteht kein `.papierkorb`).
* **Bilder:** 6 von 6 gegen Pillow — PNG (RGBA, Farbtafel, Grau) und BMP exakt in
  Summen und Einzelpunkten, JPEG 4:4:4 exakt, 4:2:0 über die Summen.
* **Ausschnitt:** 998 ‰ der Bildpunkte gleich wie QEMUs eigenes Foto desselben
  Schirms (der Rest ist der Mauszeiger, den der Server nach der Aufnahme malt);
  der Bildbetrachter öffnet das PNG und liest daraus dasselbe wie Pillow.
* **Sperre:** falsches Kennwort → bleibt zu; richtiges → auf; der Sperrer stirbt
  mit Absicht → der Kern startet ihn neu und die **Gegenprobe zeigt: ein Absturz
  sperrt nicht auf**; der Wächter liest `/etc/sperre.conf` und sperrt von selbst.
* **Laden:** 6 signierte Pakete eingespielt, 6 Bündel unter `/apps`, der Starter
  zählt 6; Gegenprobe: ein Paket mit gekipptem Oktett wird abgelehnt (0).
* **Bilder der Programme:** `.alltag-shots/` — je Fenster `shotcheck`
  0 leer / 0 abgeschnitten / 0 überlappend.

## Was diese Runde am Kern geändert hat

* `kstate SP_*`: DASS gesperrt ist, steht im Kern. `wm.darf` filtert Taste, Klick
  **und Bildpunkt** (`compose`), `SYS 1850` sperrt auf und nur der eingetragene
  Sperrer darf es; stirbt er, wird er neu gestartet.
* `SYS_RMDIR` (Linux' 84): `rmdir` hat in diesem System vorher **nie** etwas
  entfernt, `unlink` sagt jedem Verzeichnis EISDIR (POSIX-konform, bleibt so).
* Die private Arena eines Prozesses: 6 → 10 MiB, sonst passt das eigene
  Bildschirmfoto (1280×800 = 4 MiB Bildpunkte) nicht hinein.
* `wlib`: `bild` (Bildfläche mit Zoom/Drehung/Ziehen), `slider`, `setz_groesse`,
  `say_rects` (die Bibliothek meldet ihre Anordnung im Format von
  `tools/design/messen.py`), Eingabetaste (10 → KEY_ENTER 13), Fokus für Dialoge,
  vorgetäuschte Umschalttaste (E0 AA/2A).

## Bekannt und **nicht** von dieser Runde

`./test.sh` Abschnitt 1 ist auf dieser Basis rot, und zwar aus zwei Gründen, die
beide älter sind als dieser Zweig: seit Runde STICK schreibt
`vendor/firn/fetch-firnc.sh` in `.gebaut` **Commit UND Flickenstand**, während
`test.sh` dort nur den Commit erwartet, und `vendor/net/BLOBS` nennt den
**ungeflickten** Stand von `net/stack.fi`, den der Flicken
`0001-rundruf-ohne-arp.patch` verändert. Behoben ist das in `merge6` durch
`66be8ae GLYPHE 18/n: Abschnitt 1 war seit Runde STICK rot -- auf JEDEM Zweig`
— ein Commit, der **nach** dem Abzweig dieses Zweigs entstanden ist. Dieser Zweig
fasst `vendor/firn/fetch-firnc.sh` nicht an; beim Zusammenführen verschwindet es.

**Gefunden und behoben (war von dieser Runde):** `tools/posix/run.sh` Abschnitt 1
hält die Systemaufrufnummern des Kerns gegen die der libc — `SYS_OSUM_SPERRE`
stand nur im Kern (1850) und fehlte in `lib/libc/kcall.fi`. Genau derselbe Fehler
wie bei `SYS_OSUM_CPUSTAT` in MERGE-6, jetzt mit derselben Begründung
danebengeschrieben.

## Nachtrag: `merge6` nachgezogen (Commit „ALLTAG 10/n")

Während dieser Zweig gebaut wurde, ist Runde **GLYPHE** (22 Commits) in `merge6`
gelandet. Der Zweig war damit auf einer alten Basis und maß gegen alte Zahlen.
`git merge merge6` ging **ohne Konflikt** durch; danach:

* `./test.sh` Abschnitt 1 ist **grün** — der oben beschriebene Punkt „bekannt und
  nicht von dieser Runde" hat sich damit von selbst erledigt. Einmal
  `vendor/firn/fetch-firnc.sh` laufen lassen genügt nicht, weil das Skript bei
  aktuellem Übersetzer früh aussteigt und `lib/.roh/` dann fehlt; die Datei kommt
  aus dem Baum, der sie schon hat, oder aus einem Lauf mit gelöschtem `.gebaut`.
* `tools/k15/run.sh`: die Zusage „Zeilen der Naht im Kernel" zählt seit GLYPHE
  Code statt Kommentar und ist wieder grün.

## Drei Fehler, die erst der volle Lauf gezeigt hat

1. **Das Abbild war zu klein — an drei Stellen.** `wlib` ist um Bildfläche,
   Schieberegler und Vierer-Raster gewachsen, und jedes Programm trägt das mit.
   `mkfs` sagte „the disk is full": in `tools/k15/run.sh` beim **zweiten** Abbild
   (Farbschema-Gegenprobe, `disk2.img`) und in `tools/k16/run.sh` bei beiden
   Abbildern. Sichtbar wurde es als scheinbar ganz anderer Fehler: der Assembler
   auf Osum kam mit `BIN=6` zurück — das ist `schreib_elf` fehlgeschlagen, also
   kein Platz. Alle drei stehen jetzt auf 8192 Blöcken (32 MiB, Fassung 2 mit
   mehrblockiger Blockkarte).
2. **`tools/gfx/run.sh`, Abschnitt 11.** Der Schirm hat bei 800×600 und 8×16
   genau 37 Zeilen; die Bilanz am Ende eines Laufs ist über die Runden auf 36
   Zeilen gewachsen, damit stand der Satz der Shell eine Zeile zu hoch. Dieser
   eine Lauf bekommt jetzt den Schirm, den QEMUs EDID nennt (1280×800, 50
   Zeilen); gemessen wird dort die Zeilendisziplin, nicht die eingebaute Vorgabe
   — die steht in Abschnitt 2 und bleibt unangetastet. **GFX: 76 grün, 0 rot.**
3. **SSE2 im eigenen Assembler.** `fas` lehnte die Gleitkommabefehle
   ausdrücklich ab („kein Programm dieses Userlands hat eine f64"). Der
   Taschenrechner hat eine, und die IDCT des JPEG-Decoders auch. Die dreizehn
   Befehle, die `firnc1` dafür erzeugt, sind jetzt kodiert und in
   `tools/k16/run.sh` Oktett für Oktett gegen `as`+`ld` gemessen; dazu die
   Paritätsbedingung (`setp`/`setnp`/`setpe`/`setpo`), ohne die `comisd` nicht
   auswertbar ist.

## Zahlen des Nachlaufs

| Lauf | Ergebnis |
|---|---|
| `tools/alltag/run.sh` | **45 grün, 0 rot** |
| `tools/themestore/run.sh` | **81 grün, 0 rot** |
| `tools/gfx/run.sh` | **76 grün, 0 rot** |

`tools/k15/run.sh` ist auf dieser Basis **nicht** grün — und war es vorher auch
nicht: `merge6` selbst hat dort 30 rote Zusagen im letzten Lauf, dieser Zweig 23,
und die verbleibenden sind auf beiden Zweigen dieselben (Dialogfenster von
`widgetdemo`, Starter/Suche). Diese Runde hat dort nichts hinzugefügt.
