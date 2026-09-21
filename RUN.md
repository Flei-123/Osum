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
