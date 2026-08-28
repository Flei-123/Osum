# Runde SNIP — Zwischenstand

Zweig `snip` (von `mergeline`), Stand 28.08.2026, 16:45 UTC.
Nicht nach `main` — siehe Abschnitt „Was vor einem Merge passieren muss".

---

## Was steht und gemessen ist

| | Zahl |
|---|---|
| `snap.selftest` im Kern | **9 / 9**, und **acht der neun Zusagen sind Ablehnungen** |
| `wm.selftest` | 30 / 30 (unverändert) |
| `wig.selftest` | 7 / 7 (unverändert) |
| `kstate.K11_OFF`, Überschneidungen | **0** (vorher **6** — siehe unten) |
| PNG aus Osum, 800×600 | **65 930 Oktette**, von einem strengen Leser angenommen: Signatur, jede Chunk-CRC, zlib-Kopf, ADLER-32, nichts hinter IEND |
| Rohdaten desselben Bildes | 1 440 000 Oktette → Faktor **22** |
| Zeilenfilter, adaptiv gewählt | none=0 **sub=39 up=273 paeth=288** — kein einziges `none` |
| nicht-schwarze Bildpunkte | **479 767 von 480 000** |
| Bildpunkt (0,0) im PNG | **(2, 6, 23)** — derselbe Wert wie im `screendump` des Wirtes |

**Der Fahrschein trägt.** Der Kern stellt ihn aus (`snap: ticket 1 pid=5`),
das Standbild wird genommen (`snap: take 1 800x600`), die Anwendung sieht ihn
(`snip: schein 1 bild=800x600`), die Knöpfe werden mit einer echten Maus
getroffen (`snip: knopf 1`, `snip: knopf 14`), und die Datei landet auf der
Platte (`/bild/snip-1.png`, 11 400 Oktette, gültiges PNG).

**Das Tastenkürzel selbst ist gemessen**, mit einer echten Taste über den
QEMU-Monitor: `sendkey shift-meta_l-s` → `hk: super+S` auf der seriellen
Leitung, achtmal hintereinander reproduziert.

---

## Die Sicherheitsentscheidung, im Klartext

**Es gibt in Osum keinen Systemaufruf „gib mir den Bildschirm". Es gibt nur
„gib mir das Standbild, das ein Mensch mit seiner eigenen Hand ausgelöst hat".**

Osum geht den **Wayland-Weg**, weil es in derselben Lage ist: der Fensterserver
liegt im Kern, der Kern ist also gleichzeitig der Kompositor (er besitzt das
Gesamtbild) und der Zeuge des Tastendrucks (er liest ihn selbst vom Baustein).
Deshalb reicht hier ein **Fahrschein**, wo Wayland Bus, Portal und PipeWire
braucht.

1. Ein Fahrschein entsteht **nur** aus Umschalt+Super+S. Genau eine Stelle im
   Kern ruft `snap.ticket` — `kernel/kbd.fi`. Ring 3 hat keinen Aufruf dafür;
   `SN_TAKE` existiert nicht.
2. Er gehört beim Ausstellen **schon** einem bestimmten Prozess (dem vorher
   eingetragenen Dienst, `SN_REG`, euid 0, genau einer). Kein Wettrennen.
3. Er lebt **30 s** und erlaubt höchstens **4** Aufnahmen.
4. Er gibt **kein lebendes Bild**, sondern ein Standbild: der Rahmenpuffer wird
   einmal kopiert. Dauerüberwachung ist damit nicht verboten, sondern **nicht
   ausdrückbar**.
5. Während einer verzögerten Aufnahme malt der Server ein **Zeichen** und räumt
   es **einen Durchgang vor** der Aufnahme ab, damit es nicht selbst auf dem
   Bild steht.

Die vollständige Begründung samt Vergleich mit Windows/macOS/Wayland steht in
**`docs/SCREENCAP.md`**.

Ehrlich dazu: euid 0 darf sich eintragen, und root kann auf dieser Maschine
ohnehin alles. Sobald A3 (Systembus) und der Programm-Sandkasten stehen, wird
aus der Eintragung eine Berechtigung im Paket. Die Naht bleibt dieselbe.

---

## Die Zwischenablage: ein Zwischenstand, keine Zusage

Es gibt in Osum **keine** systemweite Zwischenablage (Roadmap D1, offen, braucht
A3). Die Datei-Ausgabe ist vollständig; für die Ablage legt
`ablage_zwischenstand()` **nur den Pfad** in die Textablage der Runde K15
(4096 Oktette, Text). Ein Bild von 1,9 MiB passt da nicht hinein und soll es
auch nicht. Der Name der Funktion sagt genau das.

---

## Was dabei aufgefallen ist — drei Befunde am Baum

### 1. `AN_PAR` lag auf der Tastatur (behoben)

`kstate.AN_PAR` sind acht Wörter und standen auf `0x80` — genau dort, wo seit den
Runden I18N und NETVIEW `KB_LAYOUT`, `KB_SWITCH`, `KB_SUPER`, `HK_SEQ`,
`HK_KEY` und `HK_NS` liegen. Was das anrichtet, ist ausrechenbar: eine ganz
gewöhnliche Farbfolge `ESC [ 1 ; 31 m` schreibt 1 nach `KB_LAYOUT` und 31 nach
`KB_SWITCH` — **die Tastaturbelegung springt auf Deutsch, weil ein Programm
etwas rot ausgibt.** Eine Folge mit drei Zahlen trifft zusätzlich `KB_SUPER`.

Gefunden, weil diese Runde für `HK_MOD` ein freies Wort suchte und `0xB8` als
`AN_PAR[7]` wiedererkannte — derselbe Hergang wie in Runde PAINT mit `S_TILE`
und `S_DECO`. Der Block zieht auf `0xE0..0x120`, und
**`tools/snip/k11.py`** rechnet den ganzen Block von jetzt an paarweise durch:
vorher 6 Überschneidungen, nachher 0.

### 2. Die Tastatur stellt in der Haltephase nichts mehr zu (offen, nicht meins)

Gemessen mit einer Sonde in `trap.fi` (ein Oktett je IRQ 1):

| Phase | Tastatur-Unterbrechungen |
|---|---|
| Start, bis etwa `desktop: ready` | **8** — `hk: super+S` kommt an |
| Haltephase des Fensterservers | **0** — sechzehn Drücke mit einer Sekunde Abstand, keine einzige |

Das Zeigegerät arbeitet dort weiter (`tools/desktop/run.sh` zieht in genau
dieser Phase die Taskleiste). Der Befund gehört dem Baum und nicht dieser Runde:
`kernel/snap.fi` hat keine Zeile im Unterbrechungsweg, und der Eingriff in
`kbd.fi` ist ein zusätzliches `if` tief unten in `on_code`.

**Zwei Folgen, beide gut:**

* **Die Anwendung bekam Knöpfe.** Ein Bildschirmfoto-Werkzeug, dessen
  Aufnahmearten nur Tastenkürzel sind, ist keines. Knopf und Kürzel laufen durch
  **dieselbe** Funktion `tue`, damit die zwei Wege nicht auseinanderlaufen.
* **Die Messung wurde geteilt.** Das Kürzel wird im Startfenster gedrückt, wo die
  Tastatur nachweislich zustellt; die Anwendung läuft mit dem
  Messhilfsschalter `snipkey`, der **einmal** das tut, was die Taste tut. Er
  steht auf der Kernbefehlszeile, gibt Ring 3 nichts und meldet sich laut im
  Protokoll — dieselbe Bauart wie `pwrhot` in Runde K18.

### 3. Der Kern kann nicht in die `mmap`-Zeichenfläche schreiben (gefunden UND umgangen)

Gemessen, zwei Zeilen aus demselben Lauf:

```
snip: probe 32 527904 527904 527904 527904   buf=1074462720
snip: band  0 0 0 0 0 0
```

* `SN_READ` mit einem Feld **aus dem Programmabbild** als Ziel liefert
  einwandfrei: 32 Oktette, und `527904` ist genau die Farbe, die
  `/bin/desktop` beim Start für diesen Punkt gemeldet hat
  (`desktop: punkt x=400 y=300 c=527904`).
* Derselbe Aufruf mit der **`mmap`-Zeichenfläche von `wlibc`**
  (`0x40080000`) als Ziel liefert nichts — auch nicht über den Umweg
  „in den eigenen Puffer holen und mit Wortkopien hinüberschieben".
  Auch ein Anfassen aller 64 Seiten vorher änderte nichts.

**Was das anrichtete, und warum es die wichtigste Lehre dieser Runde ist:**
das erzeugte PNG war formal **tadellos** — richtige Signatur, richtige
Prüfsummen, richtiger zlib-Rahmen, 800×600, 11 400 Oktette — und
**vollständig schwarz**. Ein Formatprüfer sieht so etwas nicht. Erst der
Bildpunktvergleich sieht es: *479 945 von 480 000 Bildpunkten verschieden*.

Genau deshalb steht in dieser Runde nirgends „die Datei existiert" als
Zusage, und genau deshalb gibt es `tools/snip/pixel.py`.

**Umgangen:** die Anwendung führt ihren Streifen jetzt **selbst**, als
`static` im Programmabbild (24 Zeilen × 800 × 4 = 76 800 Oktette) — dort,
wo `SN_READ` nachweislich ankommt — und schiebt ihn mit `WIG_BLIT` ins
Fenster, demselben Aufruf, den `wlibc.push` benutzt, nur mit einer
erreichbaren Quelle. Ergebnis derselbe Lauf, ein Bild später:

```
800x600, Farbart 2, 65 930 Oktette
filter  none=0 sub=39 up=273 avg=0 paeth=288
479 767 von 480 000 Bildpunkten nicht schwarz
Bildpunkt (0,0) = (2,6,23) -- wie im screendump des Wirtes
```

Die wichtigste Eigenschaft bleibt erhalten: **Vorschau und Datei entstehen
in derselben Funktion** (`band_malen`), die Verpixelung kann also nicht im
Bild und nicht in der Datei landen.

**Offen bleibt die Ursache.** Ob `mmap` hier weniger abbildet als es
zusagt, ob die Rückgabe `0x40080000` — dieselbe Zahl wie `sys.BRK_BASE` —
auf eine Überschneidung von Halde und Abbildung deutet, oder ob
`proc.translate` diese Seiten nicht auflöst: nicht zu Ende untersucht. Es
betrifft **jedes** Programm, dem der Kern in eine `mmap`-Fläche schreiben
soll, und gehört auf die Liste.

**Preis der Umgehung, ehrlich:** die Beschriftung der Knöpfe und der
Text der Textmarke fehlen. `wlibc.text_at` rastert in die `mmap`-Fläche,
und eine eigene Glyphenrasterung über `WIG_GLYPH` in den eigenen Streifen
ist der nächste Schritt (~60 Zeilen mit kleinem Zwischenspeicher). Die
Knöpfe sind da, sie treffen (`snip: knopf 1`, `snip: knopf 14`), sie sind
nur noch nicht beschriftet.

---

## Was noch nicht gemessen ist

Der Weg ist jetzt frei — die Zusagen sind gebaut, der Läufer steht, aber ein
vollständiger grüner Durchlauf von `tools/snip/run.sh` steht noch aus (der
Bauserver trägt gerade fünf fremde Abnahmen; ein Durchlauf dauert dort über
zwanzig Minuten). Nicht als grün gezählt sind deshalb:

* Bildpunktgenauigkeit des Vollbildes gegen den `screendump` (ein Punkt ist
  von Hand geprüft: (0,0) = (2,6,23) in beiden)
* Ausschnitt-Koordinaten auf den Punkt
* Fenster-Modus trifft das richtige Fenster
* Verpixeln macht den Bereich nachweislich unlesbar (Entropie/Kantenmaß)
* Verzögerte Aufnahme: ein Druck, zwei Standbilder, ein Fahrschein
* `snipnofilt`: die adaptive Filterwahl spart Oktette

Die Messwerkzeuge dafür stehen und sind auf dem Wirt geprüft:
`tools/snip/pngcheck.py` (strenger PNG-Leser, nur `zlib` und `struct`),
`tools/snip/pixel.py` (Bildpunktvergleich gegen PPM),
`tools/snip/entropie.py` (Kantenenergie, Entropie, Farbschranke),
`tools/snip/k11.py` (Skalarüberschneidungen).

---

## Was vor einem Merge passieren muss

**Es gibt gerade ZWEI Wege zum Bildschirminhalt.** Die Runde FEEDBACK hat
während dieser Runde `kernel/shot.fi` mit `SYS_OSUM_SHOT` gebaut — auf
derselben Nummer 1840, die beim Anlegen dieser Runde auf allen vierzehn
Zweigen frei war. Gleichzeitig belegten `media1` und `certus` 1840..1842 für die
Tonschicht.

* Diese Runde ist auf **1860** gerückt, und `tools/snip/run.sh` prüft die Nummer
  bei **jedem** Lauf gegen **jeden** Zweig, statt einmal beim Anlegen.
* Die Nummer ist der kleinere Teil. **Ein Sicherheitsmodell mit zwei Türen ist
  keines.** `docs/SCREENCAP.md`, Abschnitt 8, stellt beide gegenüber und
  empfiehlt begründet, was jeweils überlebt: das **Standbild** von SNIP (ein
  Bild, das stückweise aus dem lebenden Rahmenpuffer gelesen wird, kann
  **reißen**, und ein Auswahl-Overlay ist damit gar nicht baubar), der
  **Taskleisten-Pfad** von FEEDBACK (der Portal-Gedanke, besser als „genau ein
  eingetragener Dienst"), **ein** PNG-Kodierer statt zwei.

---

## Neu in diesem Zweig

```
kernel/snap.fi              der Fahrschein, das Standbild, die Fenstertafel
kernel/user/png.fi          PNG mit echtem deflate und adaptiven Filtern
kernel/user/snip.fi         der Dienst mit Overlay, Knopfleiste und Bearbeiter
tools/snip/run.sh           die Abnahme
tools/snip/pngcheck.py      ein strenger PNG-Leser
tools/snip/pixel.py         Bild gegen Rahmenpuffer, Bildpunkt für Bildpunkt
tools/snip/entropie.py      ist der Bereich wirklich unlesbar?
tools/snip/k11.py           Skalarüberschneidungen in kstate.K11_OFF
docs/SCREENCAP.md           die Schnittstelle UND die Begründung
```

geändert: `kernel/kbd.fi` (Umschalt+Super+S, `HK_MOD`), `kernel/wm.fi`
(Fenstertafel einfrieren, Aufnahmezeichen, `snap_step`), `kernel/sys.fi`
(1860), `kernel/kstate.fi` (`SNAP_OFF`, Modusbits, `AN_PAR` verschoben),
`kernel/kmain.fi` (Puffer, Dienststart, Messhilfsschalter),
`kernel/user/flate.fi` (Bänder, Adler-32, CRC-Tabelle).

Kein bestehender Test wurde entschärft.
