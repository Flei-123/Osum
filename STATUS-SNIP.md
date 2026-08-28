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
| PNG aus Osum, 800×600 | **11 400 Oktette**, von einem strengen Leser angenommen: Signatur, jede Chunk-CRC, zlib-Kopf, ADLER-32, nichts hinter IEND |
| Rohdaten desselben Bildes | 1 440 000 Oktette → Faktor **126** |

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

### 3. Der Kern kann nicht in die `mmap`-Zeichenfläche schreiben (OFFEN, blockiert eine Zusage)

**Das ist der Punkt, an dem diese Runde nicht fertig ist, und er steht hier
vorn statt versteckt.**

Gemessen, drei Zeilen aus demselben Lauf:

```
snip: probe 32 527904 527904 527904 527904   buf=1074462720
snip: band  0 0 0 0 0 0
```

* `SN_READ` mit einem Feld **aus dem Programmabbild** als Ziel liefert
  einwandfrei: 32 Oktette, und `527904` ist genau die Farbe, die
  `/bin/desktop` beim Start für diesen Punkt gemeldet hat
  (`desktop: punkt x=400 y=300 c=527904`).
* Derselbe Aufruf mit der **`mmap`-Zeichenfläche von `wlibc`**
  (`0x40080000`) als Ziel liefert nichts. Auch ein Umweg — Zeile in den
  eigenen Puffer holen und mit Wortkopien hinüberschieben — kommt dort nicht
  an: das Zurücklesen gibt 0.

**Folge:** das erzeugte PNG ist formal tadellos (richtige Signatur, richtige
Pruefsummen, richtiger zlib-Rahmen, 800×600, 11 400 Oktette) und
**vollständig schwarz**. Genau deshalb steht in dieser Runde nirgends „die
Datei existiert" als Zusage: ein Formatprüfer sieht so etwas nicht, erst der
Bildpunktvergleich sieht es (`479 945 von 480 000 Bildpunkten verschieden`).

Nicht zu Ende untersucht ist, **warum**: ob `mmap` hier weniger abbildet als
es zusagt, ob die Seiten erst beim Zugriff entstehen und `proc.translate` sie
deshalb nicht findet (ein Anfassen aller 64 Seiten hat nichts geändert), oder
ob die Rückgabe `0x40080000` — dieselbe Zahl wie `sys.BRK_BASE` — auf eine
Überschneidung von Halde und Abbildung deutet. **Das ist der nächste Schritt.**

**Der Weg heraus, ohne den Entwurf aufzugeben:** einen eigenen Streifen als
`static` im Programmabbild führen (81 × 800 × 4 = 259 200 Oktette, passt in die
1 MiB) und ihn mit `WIG_BLIT` ins Fenster schieben — derselbe Aufruf, aber mit
einer Quelle, die nachweislich erreichbar ist. Damit bleibt die wichtigste
Eigenschaft erhalten: **Vorschau und Datei entstehen in derselben Funktion**,
und die Verpixelung kann nicht im Bild und nicht in der Datei landen.

---

## Was noch nicht gemessen ist

Diese Zusagen sind gebaut, aber wegen Befund 3 noch **nicht** belegt, und sie
werden hier nicht als grün gezählt:

* Bildpunktgenauigkeit des Vollbildes gegen den `screendump`
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
