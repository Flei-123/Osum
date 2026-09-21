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

Elf Abschnitte, rund 25 Minuten (QEMU/TCG). Mit `TS_OUT=/pfad` bleiben
alle Mitschnitte, Bilder und Abbilder liegen:

```bash
TS_OUT=/tmp/ts bash tools/themestore/run.sh
```

Die Bilder landen in `docs/shots/themestore/` — je eine Aufnahme je
Vorlage plus die sieben der Runde GLAS (`glas-radius-0/12/24`,
`glas-alpha-100/70/40`, `glas-milchglas`).

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
