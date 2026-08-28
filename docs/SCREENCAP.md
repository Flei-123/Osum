# Der Bildschirminhalt: wer ihn bekommt und wie

Runde SNIP, Zweig `snip`. Stand 28.08.2026.
Grundlage: `/root/osum-research-raw.md`, Teilaufgabe 4 (Aufnahmearten, Abgriff,
Sicherheitsmodelle von Windows/macOS/Wayland, Bildformate) und der gemessene
Bestand im Repo.

Diese Datei ist die Schnittstellenbeschreibung UND die Begründung. Wer den
Bildschirminhalt in Osum lesen will, liest sie zuerst.

---

## 1. Die Entscheidung, in einem Satz

**Es gibt in Osum keinen Systemaufruf „gib mir den Bildschirm". Es gibt nur
„gib mir das Standbild, das ein Mensch mit seiner eigenen Hand ausgelöst hat" —
und dieses Standbild entsteht erst, nachdem der Kern eine Taste gesehen hat, die
er selbst entgegengenommen hat.**

Eine unbeschränkte Freigabe steht nicht zur Wahl und ist auch nicht als Option
gebaut. Die einzige Stelle, an der die Prüfung ausgeschaltet werden kann, ist das
Wort `snapfrei` auf der **Kernbefehlszeile** — es existiert ausschließlich, damit
`tools/snip/run.sh` belegen kann, dass die Prüfung im Regelbetrieb etwas tut, und
kein ausgeliefertes Abbild trägt es. Aus Ring 3 ist es nicht erreichbar; es gibt
keinen Aufruf, der es setzt.

---

## 2. Warum ein Bildschirm-Lese-Aufruf so gefährlich ist

Der Bildschirminhalt ist die **Summe aller Vertraulichkeit des Systems** und hält
sich an keine Dateirechte: Passwortfelder im geöffneten Zustand, TOTP-Codes,
Banking-TANs, der Klartext Ende-zu-Ende-verschlüsselter Nachrichten,
Wiederherstellungswörter, medizinische Daten. Ein einziger Leseprimitiv umgeht
damit die gesamte Datei- und Prozessisolation — nach der Entschlüsselung ist
alles wieder Bildpunkt.

Verschärfend, alle vier aus der Recherche:

1. **Kontinuierlich statt einmalig.** Fünf Bilder je Sekunde über Stunden sind
   faktisch eine Videoüberwachung des Menschen davor; mit Texterkennung wird
   daraus ein durchsuchbarer Textstrom, und wenige Kilooktette je Sekunde
   Netzverkehr reichen dafür.
2. **Kein Nutzerbezug.** Der Mensch merkt nichts. Es gibt kein Gegenstück zum
   Kameralicht.
3. **Kopplung mit Eingabe.** Wer lesen *und* Eingaben einspeisen kann, hat eine
   vollständige Fernsteuerung. Der klassische X11-Fall — `XGetImage` + `XTEST` +
   `XQueryKeymap` — ist ein Keylogger mit Bild ohne einen einzigen Exploit,
   allein durch Entwurf.
4. **Sandkasten-Bruch.** Ein Programm in einem Container könnte trivial
   ausbrechen, indem es fremde Fenster liest.

---

## 3. Wie es die drei großen Systeme lösen (recherchiert, mit Belegen)

| | Wie der Zugriff geregelt ist | Was daran trägt |
|---|---|---|
| **Windows** | `BitBlt` und DXGI Desktop Duplication brauchen bis heute **keine** Zustimmung klassischer Desktop-Anwendungen. Die Grenze ist die Sitzungstrennung (Session 0 vs. interaktiv) und UIPI/Mandatory Integrity Control; der „secure desktop" (UAC, Anmeldung, Strg+Alt+Entf) ist ein eigenes Desktop-Objekt und nicht erfassbar. Dazu ein **Opt-out der Zielanwendung**: `SetWindowDisplayAffinity(hwnd, WDA_EXCLUDEFROMCAPTURE)`. Der moderne Weg `Windows.Graphics.Capture` erzwingt den Picker und den **gelben Rahmen**. | historisch schwach; nachgebessert über den Picker, nicht über den alten Pfad |
| **macOS** | Berechtigung „Bildschirm- & Systemaudioaufnahme" (**TCC**), je Programm, systemmodaler Prompt beim ersten Zugriff. Gebunden an **Bundle-Kennung + Codesignatur** — wird das Programm verändert oder neu signiert, verfällt das Recht. Sichtbarer **Indikator** in der Menüleiste während der Aufnahme, `SCContentSharingPicker` als nicht fälschbare Auswahl. | Zustimmung + Identität + sichtbares Zeichen |
| **Wayland** | **Das Primitiv existiert nicht.** Ein Client sieht nur seine eigenen Flächen; es gibt kein Kernprotokoll, fremde Bildpunkte zu lesen. Zugriff nur über das **Portal** (`org.freedesktop.portal.Screenshot`/`ScreenCast`, Auswahldialog im Kompositor, Pixel über PipeWire) oder über **ausdrücklich privilegierte Protokolle** (`ext-image-capture-source-v1` + `ext-image-copy-capture-v1`, Freigabe per Allowlist bzw. `wl_security_context`). | Das Problem wird nicht durch Rechteprüfung gelöst, sondern durch **Abwesenheit des Primitivs**. |

---

## 4. Was Osum daraus nimmt, und warum

**Osum geht den Wayland-Weg.** Der Grund ist die eigene Lage und keine Vorliebe:
Der Fensterserver liegt **im Kern** (`kernel/wm.fi`). Der Kern ist damit
gleichzeitig

* der **Kompositor** — die einzige Instanz, die das Gesamtbild besitzt, und
* der **Zeuge des Tastendrucks** — die einzige Instanz, die einen physischen
  Tastendruck bezeugen kann, weil sie ihn selbst vom Baustein liest.

Beides an einem Ort zu haben ist genau der Grund, warum hier ein **Fahrschein**
reicht, wo Wayland einen Systembus, ein Portal und einen PipeWire-Strom braucht.
Osum hat keinen Systembus (Roadmap A3 ist offen) — ein Portal-Dienst als eigener
Prozess wäre also nicht baubar gewesen.

### Das Fahrscheinmodell

1. **Ein Fahrschein entsteht nur aus einer Handlung des Menschen.**
   Genau eine Stelle im ganzen Kern ruft `snap.ticket`: `kernel/kbd.fi`, wenn sie
   **Umschalt+Super+S** gesehen hat. Es gibt keinen Systemaufruf, der einen
   Fahrschein ausstellt — `SN_TAKE` existiert nicht.
2. **Er gehört von Anfang an einem bestimmten Prozess.**
   Der Bildschirmfoto-Dienst trägt sich **vorher** ein (`SN_REG`, euid 0, genau
   einer). Der Fahrschein wird beim Ausstellen an diese pid gebunden. Damit gibt
   es **kein Wettrennen**: kein zweites Programm kann ihn „zuerst abholen".
3. **Er gilt kurz.** 30 Sekunden nach dem Tastendruck ist er tot, auch ungenutzt.
4. **Er gibt kein lebendes Bild, sondern ein Standbild.**
   Beim Einlösen wird der Rahmenpuffer **einmal** in einen Kernpuffer kopiert;
   jeder Lesezugriff danach liest aus dieser Kopie. Ein Programm kann damit nicht
   sehen, was *nach* dem Tastendruck geschieht — die Dauerüberwachung ist nicht
   verboten, sie ist **nicht ausdrückbar**.
5. **Höchstens vier Aufnahmen je Fahrschein.** Die verzögerte Aufnahme verschiebt
   den Augenblick, sie vervielfacht ihn nicht. Vier ist die Zahl der
   Wahlmöglichkeiten (sofort, 3 s, 5 s, 10 s) und keine runde Zahl.
6. **Ein sichtbares Zeichen, solange eine verzögerte Aufnahme wartet.**
   Der Server malt oben rechts eine Marke und räumt sie **einen Durchgang vor**
   der Aufnahme wieder ab — sonst stünde die Aufnahmelampe mit auf dem Bild. Das
   ist die macOS-Lehre gegen Punkt 2 aus Abschnitt 2.

### Was das ehrlich NICHT leistet

* **Kein Rückfragedialog im Kern.** Der Kern legt fest, *wer* gefragt haben muss,
  nicht *dass* gefragt wurde. Der eingetragene Dienst zeigt das Bild vor jeder
  Weitergabe — erzwingen kann der Kern das nicht.
* **euid 0 darf sich eintragen.** Auf einem System ohne Programm-Sandkasten
  (Roadmap A12/Block G) kann root ohnehin alles; die Eintragung gibt ihm nichts,
  was er nicht schon hätte. **Sobald A3 und der Sandkasten stehen, wird aus der
  Eintragung eine Berechtigung im Paket** („darf Bildschirmfotos annehmen") und
  der Fahrschein geht an deren Halter. Die Naht bleibt dieselbe; nur der Satz,
  wer eingetragen werden darf, wechselt.
* **Kein Opt-out der Zielanwendung.** Ein Gegenstück zu
  `WDA_EXCLUDEFROMCAPTURE` — „dieses Fenster erscheint in fremden Aufnahmen
  nicht" — gibt es nicht. Es wäre billig zu bauen (ein Bit je Fenster, das
  `wm.freeze_windows` und die Kopie berücksichtigen), und es gehört auf die
  Liste, sobald es einen Passwortspeicher gibt.
* **Keine Metadaten und das mit Absicht.** Es wird kein EXIF/XMP geschrieben:
  keine Gerätenamen, keine Pfade, keine Zeitzonen.

---

## 5. Die Schnittstelle

`SYS_OSUM_SNAP = 1860`, ein Aufruf mit Auswahlfeld (wie `NETMON` und `PMON`):

```
SNAP(was, a1, a2, a3, a4) -> Zahl
```

| `was` | Bedeutung | Wer darf |
|---|---|---|
| `SN_INFO` 0 | `(feld) -> Zahl` | **jeder** |
| `SN_REG` 1 | sich als Dienst eintragen | euid 0, genau einer |
| `SN_UNREG` 2 | austragen | der Eingetragene |
| `SN_ARM` 3 | `(ms)` — verzögerte Aufnahme | Halter des offenen Fahrscheins |
| `SN_READ` 4 | `(ziel, x\|y<<32, w\|h<<32) -> Oktette` | Halter, und nur mit Standbild |
| `SN_WIN` 5 | `(nr, feld) -> Zahl` — eingefrorenes Fensterrechteck | Halter |
| `SN_HIT` 6 | `(x, y) -> Platz+1` — welches Fenster liegt dort | Halter |
| `SN_DONE` 7 | Fahrschein zurückgeben | Halter |
| `SN_BLIT` 8 | `(handle, dst, src, wh)` — Standbild ins eigene Fenster | Halter, `R_WRITE` am Fenster |

**`SN_INFO` darf jeder** — es sagt, *dass* gerade ein Bildschirmfoto ansteht,
nicht *was* darauf zu sehen ist. Der Mensch hat ein Recht zu erfahren, dass seine
Maschine fotografiert; dieselbe Begründung, mit der `NETVGET` und `NETMON` ihre
Zahlen an jeden herausgeben. Felder u. a.: `SI_SEQ`, `SI_OPEN`, `SI_MINE`,
`SI_FROZEN`, `SI_W`, `SI_H`, `SI_NWIN`, `SI_HANDLER`, `SI_TAKES`, `SI_GRANTS`,
`SI_DENIED`, `SI_TICKETS`, `SI_REFUSED`, `SI_ARMS`, `SI_TTLMS`, `SI_MAXTAKE`,
`SI_MARK`, `SI_FREE`, `SI_SNIPS`, `SI_ATMS`.

**Ohne Fahrschein: null Oktette.** Kein schwarzes Bild, kein Fehlercode mit einem
halben Bild dahinter — null.

**Das Format der Bildpunkte:** vier Oktette je Punkt, `0x00RRGGBB`, wie der
Rahmenpuffer sie hält. Im Standbild liegen die Zeilen **dicht** (`w * 4` Oktette,
ohne Lücke) — die Zeilenlänge des Rahmenpuffers (`pitch`) darf größer sein, und
darauf verlässt sich `tools/snip/pixel.py`.

**Die Fensterrechtecke** werden im selben Augenblick eingefroren wie die
Bildpunkte. Ohne das läge ein Fenster-Ausschnitt neben dem Fenster, sobald sich
zwischen Bild und Frage etwas verschoben hat. Felder: `WF_ID`, `WF_X`, `WF_Y`,
`WF_W`, `WF_H`, `WF_LAYER`, `WF_FLAGS` — das **äußere** Rechteck samt
Titelleiste, von unten nach oben, ohne minimierte und ohne Fenster hinter Reitern.

### Gegenproben auf der Kernbefehlszeile

| Wort | Wirkung |
|---|---|
| `snip` | Runde melden, Selbsttest fahren, `/bin/snip` starten |
| `nosnap` | kein Standbildpuffer — es gibt gar keine Bildschirmfotos |
| `snapfrei` | **die Fahrscheinprüfung aus** (nur zum Messen, siehe Abschnitt 1) |
| `snapnomark` | kein Aufnahmezeichen |
| `snipnofilt` | der PNG-Kodierer nimmt für jede Zeile Filter 0 |

---

## 6. Der Weg der Bildpunkte, und warum das Standbild

Auf allen modernen Systemen zeichnet nicht die Anwendung in einen gemeinsamen
Bildspeicher; jede rendert in ihren eigenen Puffer, und ein Kompositor setzt
zusammen. In Osum ist dieser Kompositor `kernel/wm.fi`, und das Ziel des
Zeichnens ist `fb.draw_at` — der Zweitpuffer, wenn es einen gibt. **Nur der Kern
kennt es**: Ring 3 kommt an den Rahmenpuffer sonst nur über `mmap` auf `/dev/fb`,
und das liefert die Tafel, nicht das zusammengesetzte Bild.

Der **Freeze-Frame** aus der Recherche ist hier zugleich Sicherheits- und
Bauentscheidung. Erst aufnehmen, dann das Standbild im Overlay zeigen:

1. Das Overlay kann sich **unmöglich selbst fotografieren** (sonst Rekursion und
   Selbstverdunklung).
2. Animationen und Videos unter dem Overlay **laufen nicht weg**.
3. Die eigentliche Aufnahme ist danach nur noch ein **Zuschnitt eines Bildes,
   das es schon gibt** — kein zweiter Aufnahmeaufruf, kein Zeitproblem.
4. Und sicherheitsseitig: es gibt keinen Aufruf, der ein *aktuelles* Bild liefert.

Die Alternative (Overlay wirklich durchsichtig, Aufnahme nach dem Loslassen)
verlangt, das Overlay auszublenden, einen Kompositor-Durchgang abzuwarten und
dann zu erfassen — fehleranfällig und flackernd.

---

## 7. Aufnahmearten: was gebaut ist und was fehlt

**Gebaut:** Vollbild · einzelnes Fenster (Rechteck aus der eingefrorenen
Fensterliste, Fenster unter dem Zeiger wird hervorgehoben) · freier Ausschnitt
(aufziehbares Rechteck, abgedunkelter Hintergrund, Größenanzeige in Bildpunkten,
Esc bricht ab) · verzögerte Aufnahme 3/5/10 s.

**Nicht gebaut, und was dafür nötig wäre:**

### Bildlauf-Aufnahme (ganze Seite / ganzer Verlauf)

Drei Wege, und alle drei fehlen hier an der Wurzel:

1. **Blind-Stitching** — wiederholt aufnehmen, ein synthetisches Bildlauf-Ereignis
   schicken, warten, wieder aufnehmen, überlappende Bänder per Phasenkorrelation
   oder normalisierter Kreuzkorrelation ausrichten. Dafür fehlt **das synthetische
   Eingabeereignis**, und das ist mit Absicht so: Eingaben einspeisen zu dürfen ist
   eine *zweite, deutlich sensiblere* Berechtigung als Lesen — Lesen + Einspeisen
   ist eine vollständige Fernsteuerung (Abschnitt 2, Punkt 3). Wer die
   Bildlauf-Aufnahme will, muss zuerst entscheiden, wer Eingaben erzeugen darf.
   Dazu: klebende Kopf- und Fußzeilen erkennen und entdoppeln, verzögertes Laden,
   Parallaxe, wechselnde Schrittweiten.
2. **Semantisch über den Barrierefreiheits-Baum** — man kennt die echte
   Bildlaufposition und kann exakt versetzen. Dafür fehlt der Baum; die Roadmap
   nennt ihn ausdrücklich als Entscheidung, die **jetzt** fallen muss
   („Barrierefreiheits-Baum im Fensterserver-Protokoll. Nachträglich heißt: jedes
   Programm nochmal anfassen").
3. **Anwendungsspezifisch** — sauberster Weg, aber nur für einen Browser.

### Bildschirmvideo

Braucht einen **kontinuierlichen Strom** statt eines Einzelbildes, und damit
genau das, was das Fahrscheinmodell absichtlich nicht anbietet. Realistisch wäre
ein eigener Fahrscheintyp „Strom", mit stehendem Zeichen für die ganze Dauer und
eigener Zustimmung. Technisch fehlt außerdem: ein Kompositor mit Vsync
(Roadmap A13), ein Behälterformat mit Zeitstempeln (F1 — in Runde MEDIA1
entstanden), ein Kodierer, und die Bandbreite. Die Roadmap ist an dem Punkt
unmissverständlich: 1080p60 in Software ist unrealistisch (allein 500 MB/s
Rahmenpuffer-Bandbreite).

---

## 8. ACHTUNG: es gibt gerade ZWEI Wege zum Bildschirminhalt

**Das muss vor einem Merge nach `main` aufgelöst werden.**

Als diese Runde begann, trug der Zweig `feedback` keine eigene Arbeit (nur einen
Merge von `hwnet`) — nachgesehen, nicht angenommen. Drei Stunden später hatte er
`kernel/shot.fi` und `SYS_OSUM_SHOT` auf **derselben Nummer 1840**, dazu
`kernel/app/png.fi` und `/bin/shot`. Gleichzeitig belegten `media1` und `certus`
1840..1842 für die Tonschicht. Diese Runde ist deshalb auf **1860** gerückt und
prüft die Nummer bei jedem Lauf gegen jeden Zweig, statt einmal beim Anlegen.

Die Nummer ist der kleinere Teil. Der größere: **ein Sicherheitsmodell mit zwei
Türen ist keines.** Beide Wege dürfen nicht zusammen nach `main`.

| | `snip`: `kernel/snap.fi` | `feedback`: `kernel/shot.fi` |
|---|---|---|
| Auslöser | Umschalt+Super+S, nur die Tastatur | Super+P, **oder** Taskleiste (`WM_STRUT`-Besitzer), **oder** euid 0 |
| Bindung | an den **vorher** eingetragenen Dienst, beim Ausstellen | an eine pid beim Ausstellen; Selbstausstellung bei Super+P nur mit Eingabefokus |
| Frist | 30 s, höchstens 4 Aufnahmen | 3 s Gnadenfrist, ein Schein ein Bild |
| Bild | **Standbild**, einmal kopiert | **live**, in Stücken aus `fb.draw_at` gelesen |
| Fensterrechtecke | mit eingefroren | keine |
| Ausschnitt | ja, `SN_READ` mit Rechteck | nein, ganzes Bild in Zeilenblöcken |
| Verzögerung | ja (`SN_ARM`) | nein |
| Ins eigene Fenster malen | ja (`SN_BLIT`) | nein |
| Format | `0x00RRGGBB`, 4 Oktette | R,G,B, 3 Oktette |
| Zeichen während der Aufnahme | ja | nein |

**Empfehlung für den Merge, begründet:**

1. **Das Standbild gewinnt.** Ein Bild, das in Stücken aus dem *lebenden*
   Rahmenpuffer gelesen wird, kann **reißen** — Zeilen aus verschiedenen
   Augenblicken in einer Datei. Und ein Auswahl-Overlay ist damit gar nicht
   baubar, weil es sich selbst fotografieren würde.
2. **FEEDBACKs Berechtigungspfad gewinnt zum Teil.** Der Gedanke „die
   Bedienoberfläche darf einen Schein ausstellen, weil sie die Stelle ist, die
   den Menschen fragen *kann*" ist genau das Portal-Argument und besser als
   „genau ein eingetragener Dienst". Konkret: `snap.register` sollte neben
   euid 0 auch den `WM_STRUT`-Besitzer zulassen (`ist_leiste` in `sys.fi` gibt
   es schon) — dann kann die Taskleiste einen Fahrschein für ein anderes
   Programm ausstellen, und aus zwei Modellen wird eines.
3. **`/bin/shot` bleibt und wird umgehängt.** Es braucht nur „ganzes Bild,
   Zeilen holen" — das ist `SN_READ` mit `x=0, w=Breite, h=1` und einer
   Umrechnung von vier auf drei Oktette. Der Rückgabewert bleibt derselbe.
4. **Ein PNG-Kodierer, nicht zwei.** `kernel/app/png.fi` (FEEDBACK, `std.deflate`)
   und `kernel/user/png.fi` (SNIP, `flate` in Bändern) leisten dasselbe. Der
   Bänder-Kodierer kann Bilder schreiben, die **nicht in den Speicher passen**
   (ein Programm hat 1 MiB, ein Vollbild 1,9 MiB) — der andere ist kürzer.
   Wer sie zusammenlegt, prüft zuerst, ob `std.deflate` einen laufenden Zustand
   über mehrere Aufrufe halten kann; wenn nicht, gewinnt der Bänder-Kodierer.

Bis dahin gilt: `snip` baut gegen 1860 und `feedback` gegen 1840, beide laufen,
und **keiner von beiden geht allein nach `main`**.

---

## 9. Die Zwischenablage — was hier NICHT gebaut ist

**Eine systemweite Zwischenablage gibt es in Osum nicht.** Roadmap D1 ist offen
und hängt an A3, dem Systembus: sie braucht ein Besitzermodell, eine Typenliste,
verzögerte Übergabe und geteilten Speicher für große Daten, und nichts davon
existiert.

Was existiert, ist die **Textablage der Runde K15** (`wig.clip_set`, 4096
Oktette, ein Puffer im Kern) — für Text zwischen zwei Eingabefeldern gedacht.
Ein Bild passt da nicht hinein und soll es auch nicht: 800×600 sind 1,9 MiB gegen
4 KiB, und ein Bild in einem Textpuffer wäre eine Zwischenablage, die behauptet,
es gäbe eine.

Deshalb heißt die Funktion in `kernel/user/snip.fi` **`ablage_zwischenstand`**
und tut genau eine Sache: sie legt den **Pfad** der geschriebenen Datei in die
Textablage. Wer die Datei will, findet ihren Namen; wer ein Bild einfügen will,
kann es nicht. Sobald D1 steht, wird aus diesen sechs Zeilen ein
`clip_put(BILD, …)` und der Name fällt weg. Nicht mehr und nicht weniger.

**Die Zwischenablage ist damit ein Zwischenstand und keine Zusage dieser Runde.**

---

## 10. Nachbearbeitung: die Redaktion ist der Punkt

Gebaut: zuschneiden · Rechteck · Pfeil · Freihand · Text · **verpixeln** ·
**Balken** · Rückgängig.

**Verpixeln ist der wichtigste Punkt**, weil man damit überhaupt erst gefahrlos
Bilder weitergibt — und genau deshalb stehen hier zwei Werkzeuge und nicht eines:

* **Mosaik ist nicht zwingend sicher.** Bei bekanntem Zeichensatz und kleinen
  Blockgrößen ist Text rekonstruierbar: alle Kandidaten-Renderings durchprobieren
  und die Blockmittel vergleichen (das ist, was `Unredacter` gegen `pixelation`
  gezeigt hat). **Weichzeichnen ist noch schlechter** — ein Tiefpass ist
  teilweise invertierbar. Deshalb gibt es hier keinen Weichzeichner.
* **Der Balken ist die sichere Form**: volldeckende Fläche in Volltonfarbe, aus
  der sich nichts zurückrechnen lässt. Er liegt auf derselben Leiste und wird
  genauso gemessen. Was der Mensch nimmt, entscheidet er — aber er bekommt beides
  angeboten und nicht nur das hübschere.
* **Die Redaktion trifft die Ausgabepixel.** Vorschau und Datei entstehen in
  *derselben* Funktion (`band_malen`) auf demselben Streifen; der einzige
  Unterschied ist die letzte Zeile (ins Fenster schieben oder an den Kodierer
  geben). Damit kann die Verpixelung nicht „im Bild, aber nicht in der Datei"
  landen. Gemessen wird sie trotzdem **an der Datei**
  (`tools/snip/entropie.py`: Kantenenergie, Entropie und eine harte Schranke für
  die Zahl der übrigen Farben).
* **Die Acropalypse-Falle ist geschlossen** (CVE-2023-21036 / CVE-2023-28303):
  `png.schreibe` legt die Datei mit `O_TRUNC` an. Wer ein zugeschnittenes Bild
  über ein größeres schreibt, ohne zu kürzen, lässt hinter dem `IEND` die Reste
  des Originals stehen — und die sind rekonstruierbar. `tools/snip/pngcheck.py`
  prüft ausdrücklich, dass hinter `IEND` **nichts** steht.

---

## 11. Das Bildformat

**PNG**, Farbart 2 (RGB ohne Deckung), Bittiefe 8, echtes deflate mit festen
Huffman-Bäumen, adaptive Zeilenfilter.

* **Farbart 2 und nicht 6:** das obere Oktett des Rahmenpuffers ist nicht
  Deckung, sondern nichts. Es mitzuschreiben wäre ein Alphakanal, der überall 0
  ist — ein Betrachter, der ihn ernst nimmt, zeigt ein vollständig durchsichtiges
  Bild. Nebenher spart es ein Viertel der Rohdaten.
* **Adaptive Filter statt besserem Packer:** die Recherche nennt die Filterwahl
  bei Bildschirmfotos als die Stelle mit dem besten Verhältnis — oft mehr wert
  als die Feinabstimmung des deflate-Teils, und ~100 Zeilen. Der Packer dieses
  Baums (`flate.fi`, Runde K11) kann feste Bäume; eigene Huffman-Tabellen wären
  +400 bis 800 Zeilen und der klassische Ort für feine Fehler.
* **In Bändern, weil das Bild nicht in den Speicher passt.** Ein Programm hat
  1 MiB (`proc.IMAGE_BASE` bis `IMAGE_END`), ein Vollbild 1,9 MiB. Der Kodierer
  besitzt das Bild deshalb nie: er bekommt eine Funktion gereicht, die ihm eine
  Zeile holt. `flate.band_begin/band/band_end` hält den Bit-Puffer über die
  Bandgrenze — zwei aneinandergehängte `deflate`-Aufrufe wären zwei Ströme und
  kein Leser käme durch.
* **Nicht gebaut:** Palettierung (Farbart 3) — bei reinen Oberflächen-Bildern
  nochmals Faktor 2 bis 4, und der nächste sinnvolle Schritt.

---

## 12. Was gemessen wird

`tools/snip/run.sh` (Abschnitt 27 von `./test.sh`), unter `-accel kvm`:

1. Kein Wort steht an zwei Stellen mit verschiedenem Wert (Aufrufnummer,
   Feldnummern), und 1860 ist auf **jedem** Zweig frei.
2. `kstate.K11_OFF` hat keine zwei Wörter aufeinander (`tools/snip/k11.py`).
3. `snap.selftest` 9/9 — **acht der neun Zusagen sind Ablehnungen**.
4. Das PNG ist gültig gegen einen strengen Leser: jede Chunk-CRC, der zlib-Kopf,
   ADLER-32, die fünf Filter, **nichts hinter IEND** (`tools/snip/pngcheck.py`).
5. Es ist das **richtige** Bild: Bildpunkt für Bildpunkt gegen den
   `screendump` des Wirts (`tools/snip/pixel.py`).
6. Der Ausschnitt steht bildpunktgenau so im Rahmenpuffer.
7. Die verzögerte Aufnahme: **ein** Tastendruck, **zwei** Standbilder, **ein**
   Fahrschein.
8. Verpixeln: Kantenenergie, Entropie und die Farbschranke, vorher gegen nachher.
9. **Die Gegenprobe:** mit `snapfrei` bricht der Selbsttest von 9 auf weniger ein
   — die Prüfung war also da. Ohne dieses Paar wäre „ohne Fahrschein null
   Oktette" eine Behauptung.
10. Umschalt+Super+S gegen die Runde SUPERSEARCH — nicht gelesen, sondern in
    **einem** Kern gebaut: beide Zweige verschmolzen, dann gedrückt.
