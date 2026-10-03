# PDFVIEW — der PDF-Betrachter von OrientOS

Stand 02.10.2026 (Roadmap r55, Zweig `daily-driver`). Ein **eigenes, natives
fUi-Programm** (`kernel/user/pdfview.fi` auf dem Szenenbaum, `fuiscene`) —
**nicht** über Certus/Browser.

```
pdfview [datei.pdf]                das Fenster
pdfview --info datei.pdf           ohne Fenster: Seitenzahl oder Fehlernummer
pdfview --render datei seite pct   ohne Fenster: Seite malen, Größe + Prüfsumme melden
```

Bedienung: PgDn / Leertaste / → nächste Seite, PgUp / ← vorige, ↑ ↓ Home End
scrollen, `+` `-` zoomen, `b` Seitenbreite, `s` ganze Seite; mit der Maus ziehen
verschiebt die Seite; Knöpfe für Zurück / Weiter / − / + / Breite / Seite; ein
Pfadfeld mit „Öffnen". Im Programmstart-Menü als „PDF-Betrachter" (Bündel
`assets/apps/pdfview.osp`).

## Aufbau

| Schicht | Datei | Aufgabe |
|---|---|---|
| Lesen | `lib/pdfread/pdfread.fi` | Dateistruktur, Seitenbaum, Filter, Inhaltsstrom → SVG-Text; Bilder: Orte, Dekodierung, Einblenden |
| Zusammensetzen | `lib/pdfread/pdfpage.fi` | Seite = weiß + Bilder + Vektorschicht (lib/svg) → `0xFFRRGGBB`-Punkte |
| Daten | `lib/pdfread/pdftab.fi` (erzeugt von `tools/pdf/gentab.py`) | Breiten der 14 Standardschriften, Basiskodierungen, Adobes Glyphenliste |
| Fenster | `kernel/user/pdfview.fi` + `fuiscene.image` (Bildknoten des Szenenbaums: zeigt die Seite, Ziehen verschiebt) | Werkzeugleiste, Seitenfläche, Tasten (`fuiscene.last_key`, `image_pan`) |

Die Vektorschicht und der Text werden vom **selben SVG-Maler** gezeichnet, den die
Systemsymbole benutzen (`lib/svg`, `svg.svgimage`). Der Leser schreibt ein SVG in
Gerätekoordinaten; Text wird **Zeichen für Zeichen** an die Stelle gesetzt, die die
PDF-Datei vorgibt (Breiten aus `/Widths`, `/W` bzw. den Metriken der Standardschriften).

## Was er kann

* **Dateistruktur:** klassische xref-Tabellen, xref-Ströme, Objektströme, Hybriddateien,
  inkrementelle Änderungen (`/Prev`); eine beschädigte Datei (kein Trailer, falsches
  `startxref`, abgeschnitten) wird durch Suchen nach `N G obj` neu aufgebaut.
* **Filter:** Flate (mit PNG- und TIFF-Prädiktoren), ASCIIHex, ASCII85, RunLength, LZW,
  DCT (JPEG, über `lib/jpeg`).
* **Seiten:** MediaBox/CropBox/Resources/Rotate samt Vererbung, Inhaltsströme als Liste,
  Form-XObjects (verschachtelt bis 8).
* **Grafik:** Pfade (Füllung, Strich, gerade-ungerade Regel, Beschneidung), Linienbreite,
  -ende, -verbindung, Strichelung, Deckkraft (ExtGState `ca`/`CA`), Matrizen,
  Farben Gray/RGB/CMYK, ICCBased nach Komponentenzahl, Separation als Tönung, Indexed (Bilder).
* **Text:** einfache und Type0-Schriften (Identity), Unicode aus `/ToUnicode`, `/Encoding`
  (WinAnsi, MacRoman, Standard, `/Differences` mit Adobes Namensliste), Zeichen-/Wortabstand,
  Zeilenabstand, horizontale Skalierung, Rise, gedrehte und geschrägte Matrizen.
* **Bilder:** JPEG, rohe Abtastwerte mit 1/2/4/8/16 Bit in Gray/RGB/CMYK/Indexed,
  Bildmasken, weiche Masken (`/SMask`), beliebige Drehung/Skalierung.
* **Verschlüsselung:** Dateien, die ohne Passwort aufgehen (leeres Benutzerkennwort — Rechnungen, Kontoauszüge, mit Eigentümerkennwort gegen Kopieren/Drucken): **RC4 40/128 Bit und AES-128** werden entschlüsselt (Streams). Braucht die Datei ein Kennwort oder ist sie AES-256 (V5, braucht SHA-512), wird das gemeldet („Verschlüsselte PDF-Dateien: nicht möglich"). Strings in Wörterbüchern werden nicht entschlüsselt.

## Was er NICHT kann (ehrlich)

* **Schrift: drei Schnitte, keine Serifen.** Das System hat eine normale, eine fette und eine
  Festbreitenschrift; daraus macht der Betrachter: fett (Name enthält Bold/Black/Heavy/Demi, `/FontWeight`
  ≥ 600, ForceBold), Festbreite (Courier/Mono/Consolas/…, FixedPitch) und kursiv (Oblique/Italic,
  `/ItalicAngle`: die aufrechte Schrift um 12° geschert). **Serifenschriften (Times & Co.) werden in der
  Systemschrift ohne Serifen gezeigt**; Glyphenformen sind überhaupt die des Systems, die **Positionen**
  stimmen (aus der Datei). Eingebettete Schriften werden nicht benutzt, Ligaturen/Kerning der Datei nur
  über die Breiten.
* **Schattierungen (`sh`) und Muster (Pattern)** werden nicht gezeichnet (Muster: mittelgrau).
* **Bilder liegen immer unter der Vektorschicht,** egal in welcher Reihenfolge die Datei
  sie zeichnet (eine weiße Fläche, die *über* ein Bild gezeichnet wird, würde das Bild
  zeigen). JPX, CCITT und JBIG2 werden als graues Rechteck gezeigt. `/Mask` (Farbschlüssel)
  fehlt. Bilder über 12 Mio. Punkte werden beim Einlesen herunterskaliert, JPEGs über 16 Mio.
  Punkte nicht gezeigt.
* **Inline-Bilder** (`BI … EI`) werden übersprungen.
* **Keine Textauswahl, keine Suche, keine Lesezeichen/Links, keine Formulare, keine Ebenen.**
* **Kein Mausrad** (fuiapp liefert keine Radereignisse): Scrollen mit Tasten oder Ziehen.
* Fenstergröße fest (900 × 700).

## Wie es geprüft wird — `tools/pdf/run.sh`

Acht Abschnitte, alle gegen etwas **Äußeres**:

1. Bau der Host-Treiber (`pdfdump`, `pdfpng` — derselbe Code wie im Programm).
2. Korpus aus **reportlab, pypdf und einem Rohschreiber** (xref-/Objektströme, A85/Hex/RL/LZW,
   gedrehte Seiten, Bilder, Unicode-Schriften, Formulare, beschädigt, verschlüsselt).
3. **Gegen poppler:** je Seite die Zeichenmenge gleich `pdftotext`, das Bild von `pdftoppm`
   um weniger als 3 Graustufen im Mittel entfernt.
4. Beschädigte Dateien: verschlüsselt → Fehler 2, Müll/leer → Fehler 1, abgeschnitten oder
   falsches `startxref` → wiederaufgebaut, die Seite ist da.
5. **Fuzz:** 800 zufällige Verderbungen, nie Absturz, nie Hängen.
6. Tempo: 40 Seiten < 5 s, 150 Seiten mit 9000 Zeilen < 15 s (Host).
7. **Im Gast** (QEMU, OrientOS-Bau): `pdfview --render` meldet die Prüfsumme der gemalten
   Seite — sie muss der des Wirts **Bit für Bit** gleichen.
8. **Das Fenster:** Bild, dann PgDn und `-` über den QEMU-Monitor: „Seite 2 von 2", Zoom sinkt.

Gefundene und behobene Fehler beim Bauen: **`lib/svg` wendet ein `transform` auf `<text>` zweimal an** (`times_text` wendet den Zustand erneut an) — gedrehte/geschrägte Glyphen stehen deshalb in einem `<g transform>`, der Text bei 0,0 darin (gedrehter Text stand vorher falsch); LZW-Tabelle bei beschädigtem Strom (Überlauf),
`as u32`-Überläufe bei ToUnicode-/CID-Werten (jetzt geklemmt), Datei ohne Trailer (Katalog-Suche).
