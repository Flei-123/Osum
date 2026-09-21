# RUN.md — OrientOS/Osum starten und nachmessen (Zweig `glas`)

Alle Befehle aus diesem Ordner, alle Pfade relativ. Das Blatt der
vorigen Runde steht unveraendert in **`docs/RUN-WMPLUGIN.md`**.

Diese Runde heisst GLAS: freie Eckenrundung, durchsichtige Taskleiste,
Milchglas. Was sie baulich ist, steht in `PLAN.md`; hier steht nur,
welchen Befehl man tippt.

---

## 1. Bauen

```bash
export FIRNLIB="$PWD/lib"
bash tools/build-kernel.sh /tmp/k.mb      # der Kern, rund 15 s
```

Die Ring-3-Programme baut der Laeufer selbst mit; einzeln geht

```bash
vendor/firn/bin/firnc -c kernel/user/settings.fi -o /tmp/settings.o
```

(Programme mit `profile app` in der ersten Zeile brauchen
`--profile=app`; `kernel/user/wlib.fi` und `wlibc.fi` sind
Bibliotheken und werden nur ueber ein Programm uebersetzt.)

## 2. Einmal booten und zusehen

`tools/themestore/build.sh` baut Kern, Programme und Platte, startet
QEMU, fotografiert den Schreibtisch und legt alles in ein Verzeichnis:

```bash
bash tools/themestore/build.sh /tmp/lauf extra='einst' uitrace=yes keep=yes
```

Danach liegen dort `desktop.png`, `serial.txt` und das Plattenabbild.
Die Schalter dieser Runde:

| Schalter | was er tut |
|---|---|
| `radius=0..24` | die freie Eckenrundung (ohne Angabe entscheidet der Formsatz) |
| `tbalpha=0..100` | Deckkraft der Taskleiste in Prozent (100 = wie frueher) |
| `winalpha=0..100` | Deckkraft gewoehnlicher Fenster |
| `blur=0..16` | Milchglas unter der Leiste, 0 = aus |
| `wallpaper=hell\|dunkel` | ein gemustertes Hintergrundbild — ohne eines beweist Durchsicht nichts |
| `preset=<name>` | eine der zehn Vorlagen aus `assets/themes/` anwenden |
| `extra='einst'` | das Einstellungsfenster mit aufmachen |
| `click='x,y'`, `click='x,y>x,y'` | klicken bzw. ZIEHEN (fuer die Schlierenprobe) |
| `uitrace=yes` | die Programme melden ihre Rechtecke und Radien auf der Leitung |

Beispiel — Milchglas ueber einem hellen Muster:

```bash
bash tools/themestore/build.sh /tmp/glas tbalpha=70 blur=12 \
     wallpaper=hell uitrace=yes keep=yes
```

## 3. Die Abnahme

```bash
bash tools/themestore/run.sh
```

Zwoelf Abschnitte, rund 25 Minuten (QEMU/TCG). Letzter Lauf auf diesem
Rechner:

```
THEMESTORE: 188 passed, 0 failed
```

Die Zahlen, die dieser Lauf nebenbei misst — sie stehen im Mitschnitt,
damit niemand sie erhoffen muss:

| Sache | gemessen |
|---|---|
| Weichzeichner je Vollbild | `us=45511`, Spitze `max=56721` bei `px=35840` |
| und wie oft der Streifen aus dem Zwischenspeicher kam | `cache=2/26` |
| Kontrast der Leistenschrift, helles Muster | 14,43:1 |
| dieselbe Schrift, dunkles Muster | 12,33:1 |
| dunkles Muster mit Milchglas 12 | 12,33:1 aus 13 Kandidaten |
| Schlieren nach dem Zug unter die Leiste | 0 Bildpunkte |

**Wer rundet und wer mischt — "ein Ort je Ring", nicht "genau einer".**
Abschnitt 11e stellt diese Frage dem GANZEN Baum und nicht einer Datei:
er sucht jede Funktion, deren Name auf `round`, `blend`, `mix8` oder
`rrect` passt, und haelt den Fund gegen
[`tools/themestore/raster.liste`](tools/themestore/raster.liste). Dort
steht jeder Ort mit einem Satz Begruendung — `wm.fill_round` und
`wm.blend` fuer den Fensterserver, `fb.blend`/`fb.mix8` fuer das Format
des Schirms, `wlibc.rrect`/`wlibc.blend` fuer Ring 3 (ueber die
Ringgrenze geht kein Systemaufruf je Bildpunkt) und
`vektor.polygon_round` fuer beliebige Formen. Ein Fund ohne Eintrag ist
rot, ein Eintrag ohne Fund auch. Die Zusage lautet also: **genau ein Ort
je Ring und je Format, und jeder ist begruendet** — wer einen weiteren
Mischer baut, schreibt ihn dort hinein oder benutzt einen vorhandenen.

Ein zweiter, kuerzerer Lauf prueft, dass jedes Bedienelement aus der
Bibliothek kommt:

```bash
bash tools/check-ui.sh     # -> CHECK-UI PASSED
```

Mit `TS_OUT=/pfad` bleiben alle Mitschnitte, Bilder und Abbilder
liegen:

```bash
TS_OUT=/tmp/ts bash tools/themestore/run.sh
```

Die Bilder landen in `docs/shots/themestore/` — je eine Aufnahme je
Vorlage plus die sieben der Runde GLAS (`glas-radius-0/12/24`,
`glas-alpha-100/70/40`, `glas-milchglas`). Die durchnummerierten
Aufnahmen der Runde liegen daneben in `docs/shots/glas/`; welche
welche ist, sagt `docs/shots/glas/README.md`, und was die Runde
gebaut und was sie NICHT erreicht hat, steht in `docs/RUNDE-GLAS.md`.

Drei dieser Aufnahmen macht der Lauf inzwischen selbst und legt sie
unter ihrem Namen in `docs/shots/glas/` ab, damit Bild und Lauf nicht
auseinanderlaufen koennen:

* **10 — der Zug hin UND zurueck** (`10-zug-hin-und-zurueck-keine-
  schlieren.png`). Der Name sagt, was der Beleg ist: keine Schliere.
* **22 — die Endlage unter der Leiste**
  (`22-zug-endlage-unter-der-leiste.png`), derselbe Zug ohne
  Rueckweg. Das Fenster bleibt unter der Leiste stehen
  (`unterpx=16044`), und `shotcheck.py` misst dort `empty 0 cut 0
  overlapping 0`.
* **12 — der beschriftete Leistenvergleich**. Er wird von
  `tools/themestore/leistenvergleich.py` aus den vier Aufnahmen
  desselben Laufs gebaut, und jede Zeile traegt IM BILD ihre
  Reglerstellung und ihre gemessene Streuung (`var 0 / 1597 / 6389 /
  788`). Die Zahl kommt aus `glascheck`, und der Lauf haelt die vier
  Zahlen im Bild gegen die vier, die er selbst gemessen hat.

**Zwei Fragen, die seit fix-r3-4 im Bild gestellt werden.**
`shotcheck.py --linien` sucht neben jeder Beschriftung nach einer
durchlaufenden Rahmenlinie — so ist aufgefallen, dass die Statuszeile
„bereit" genau auf der unteren Kante der linken Karte sass, was kein
Vergleich gemeldeter Rechtecke je zeigen konnte (sie ueberlappen
nicht, sie beruehren sich). Und Abschnitt 11i haelt den Strich unter
dem vorderen Leistenknopf gegen die gemessene Breite seiner
Beschriftung: Anfang und Laenge kommen jetzt aus derselben Messung wie
der Text (`taskbar: pille x= w= tx= tw=`).

**Und drei, die seit fix-r3-2 dazugekommen sind.**
`shotcheck.py --knoepfe` fragt fuer JEDEN gemeldeten Knopf
(`wlib: knopf x= y= w= h= r= ax= ay=`), ob im Bild an seinen vier
Kanten ueberhaupt ein Umriss steht — eine Linie oder wenigstens eine
Farbstufe zwischen Flaeche und Umgebung. Der Knopf „Uebernehmen" der
Seite Darstellung hatte keinen: fUi malt flach, Weiss auf `#f8fafc`,
und niemand konnte ihn von einer Beschriftung unterscheiden. Die Zahlen
stehen als `knopf N  ohnekante M` in der Zeile des Pruefers, und der
Lauf haelt eine Gegenprobe dagegen (ein auf dem Wirt flach uebermalter
Knopf MUSS gefunden werden).
`glascheck.py fenster <bild> <serial>` stellt der Fensterschrift
dieselbe Frage, die Abschnitt 11d der Leistenschrift stellt: Kontrast
gegen den Grund, der WIRKLICH unter ihr liegt. Abschnitt 11j faehrt
dafuer `window_alpha=55` ueber einem gemusterten Bild; gemessen wird
das schlechteste Paar (5,16:1), und eine Gegenprobe gegen
`window_alpha=100` belegt, dass dabei wirklich gemischt wurde (39 120
abweichende Bildpunkte). Damit unter einem durchsichtigen Fenster kein
fremder Text durch die Reiterzeile laeuft, ist die Lesbarkeitsschranke
fuer gewoehnliche Fenster halb so weit wie fuer die Leiste
(`SCHLEIER_WIN = 20` gegen `SCHLEIER = 40`, kernel/ui/wm.fi) — der
Selbsttest `wm: glastest 8 / 8` rechnet beide Faelle von Hand nach.
Und Abschnitt 8 misst seit fix-r3-2 **jedes** gemeldete Rechteck ausser
`win` gegen Innenhoehe und Innenbreite: der Namensfilter `^w[a-z][a-z]$`
hat die zwei Karten und die fuenf Bedienelemente mit Sachnamen (`edge`,
`size`, `autohide`, `ontop`, `apply`) still uebersprungen. Die Zahl der
gemessenen Rechtecke (100) steht jetzt als eigene Zusage daneben, damit
ein neuer Filter auffaellt.

## 4. Einstellen im laufenden System

Einstellungen → Reiter **Darstellung**, rechte Spalte unten: vier
Schieberegler (Eckenrundung 0..24, Taskleiste und Fenster deckend in
Prozent, Milchglas 0..16). Jede Bewegung wirkt sofort und wird nach
`/etc/theme.conf` geschrieben, ueberlebt also einen Neustart. Dieselben
vier Zahlen stehen in jeder Vorlage (`assets/themes/*.preset`) und in
`/etc/theme.conf`:

```
radius=16
taskbar_alpha=60
window_alpha=90
taskbar_blur=12
```

**Was einen beim Schieben ueberrascht:** die Lesbarkeit geht vor. Ist
der Untergrund so unruhig, dass die Schrift der Leiste unter 4,5:1
fiele, hebt der Fensterserver das Alpha an, bis sie wieder darueber
liegt — aus `taskbar_alpha=40` kann so ein wirksames 82 werden. Der
Regler verschweigt das nicht, er schreibt die wirksame Zahl daneben
(„Taskleiste deckend % (wirkt 82)"), und der Lauf misst beides
getrennt (`alpha_soll` gegen `alpha_ist`). Wer wirklich durchsehen
will, nimmt ein ruhigeres Hintergrundbild oder Milchglas: der
Weichzeichner beruhigt den Grund und laesst darum mehr Durchsicht zu.

## 5. Voraussetzungen

* `qemu-system-x86_64` — fehlt es, sagt die Abnahme das und beendet
  sich mit 0, statt rot zu werden.
* `python3` mit **Pillow** (Bilder auswerten), `as`, `ld`, `nm`,
  `objcopy`.
* Der Firn-Uebersetzer wird bei Bedarf geholt:
  `bash vendor/firn/fetch-firnc.sh`.

## 6. Wenn etwas rot ist

| Meldung | woran es liegt |
|---|---|
| `FAILED to compile <programm>` | die ersten 25 Zeilen stehen im Lauf; `firnc -c kernel/user/<programm>.fi` sagt dasselbe schneller |
| `wm: kein Bildschirm` | dem Abbild fehlen die Schriften |
| `the module 'std.rt' ... profile 'kernel'` | das Programm traegt `profile app` — mit `--profile=app` uebersetzen |
| Exitcode 124 | `timeout`: der Lauf kam nicht bis `wm: hold` |
| Bilder fehlen | Pillow ist nicht da; die `.ppm` liegen trotzdem im `TS_OUT`-Verzeichnis |
