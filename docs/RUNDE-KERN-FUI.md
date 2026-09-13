# RUNDE KERN-FUI: der Fensterserver malt mit fUi

Justin, 10.09.2026:

> "kann man die fUi-Lib nicht ohne Imports machen, also dass sie im
> Kernel auch laufen kann?"

Die Antwort war: **das ist schon halb gebaut und wurde nie
angeschlossen.** `vendor/firn/lib/fui/core.fi` traegt seit dem Tag
`profile kernel` in Zeile 1 und nennt in seinem Kopf woertlich diese
Frage als Grund seiner Existenz. Gebunden hat es niemand --
`grep -rln fui kernel/*.fi` fand vor dieser Runde **nichts**.

Diese Runde schliesst es an.

---

## 1. Kann der Kern fUi ueberhaupt binden?

Zuerst gemessen, nicht vermutet. `import fui.core` in `kernel/wm.fi`,
dann `./tools/build-kernel.sh`:

| Was | Ergebnis |
|---|---|
| `import fui.core` | **uebersetzt**, 19 Symbole `_F0.core__*` im Abbild |
| `import fui.painter` | **32 Fehler**, `module 'ttf' has no element 'Font'` |

Die Grenze ist real und wird vom Uebersetzer erzwungen: `core.fi`,
`layout.fi` und `style.fi` tragen `profile kernel`, die uebrigen 13
fUi-Dateien ziehen `std.rt` und fallen heraus.

**Namenskollision:** `wm.fi` hat eine eigene Funktion `border(state)`
(die Rahmenbreite), `core.fi` hat `border(z, x, y, w, h, st, color)`
(einen Umriss). Sie kollidieren **nicht** -- Firn qualifiziert ueber den
Modulnamen, `border(...)` bleibt wm, `core.border(...)` ist fUi.

**Groesse:** +23 KB Abbild (5 036 768 -> 5 060 040 Oktette).

## 2. Was umgestellt wurde -- und was nicht

Umgestellt sind **die vier Fensterzeichen**. `cap_glyph` malt keine
Form mehr selbst; `cg_mal` ruft `core.cap_minimize`,
`core.cap_maximize`, `core.cap_restore`, `core.cap_close`.

**Nicht umgestellt sind die Flaechen** (`fill_round`, `ring_round`,
`paint_title`), und das ist kein Vergessen, sondern ein Befund:

> `core.round_fill` mischt seine Eckenpunkte mit `get()` gegen das,
> was **im eigenen Puffer** liegt. Der Server mischt gegen den
> **Bildschirm** -- Schreibtisch und tiefere Fenster stehen dort schon.
> Dazu kennt `core.fi` **keinen Beschnitt**: es malt von (0,0) bis
> (w,h), der Server in ein Schmutzrechteck mitten auf dem Schirm.
> Eine Flaeche ueber fUi zu malen hiesse, den ganzen Fensterbereich
> zwischenzupuffern -- bei 3440x1440 mehrere MB je Bild.

Das steht so auch im Kopf von `wm.fi` `fill_round`: *"Genau das ist der
Grund, warum das hier geht und in Ring 3 nicht: die Bibliothek malt in
IHREN Puffer und weiss nicht, was darunter liegt."*

**Text geht nicht**, und das sagt `core.fi` selbst (K1): Rasterung
braucht Fontdatei, Zwischenpuffer und Fliesskomma. Der Titel wird
weiter mit `ttf` gemalt. Das ist die eine Stelle, die geteilt bleibt.

### Wie fUi auf den Schirm kommt

Nicht direkt. Zwei nachgeprueste Gruende:

* **G1 kein Beschnitt** (siehe oben).
* **G2 das Pixelformat ist nicht fest.** `core.put` legt BGRX ab, fest
  verdrahtet. `fb.fi` nimmt die Verschiebungen aus `S_RSHIFT`/
  `S_GSHIFT`/`S_BSHIFT`, die der Grafikmodus liefert. Dazu haelt
  `fb.pixel` das reservierte Band der Messtafel frei (`band_lo`).

Also: fUi rastert in `cg_deck` -- den Zwischenpuffer, den Runde VEKTOR
angelegt und **nie benutzt** hat. Dort ist das Format egal, weil nur die
Deckung zaehlt. Danach traegt `cap_glyph` ihn mit `cap_px` auf den
Schirm: mit Beschnitt, mit Band, ueber den Farbwaehler des Servers.

**Die Form kommt aus fUi, der Weg auf den Schirm bleibt der des
Servers.** `cg_deck` waechst dafuer von 6 400 auf 25 600 Oktette --
`core.fi` schreibt vier Oktette je Punkt, und ihm eine zweite Ablage
beizubringen waere wieder die zweite Umsetzung.

## 3. Die Gegenprobe: malt der Kern dasselbe wie die Anwendung?

Das ist der eigentliche Zweck. Laut `core.fi` ist genau diese Teilung
schon **zweimal** auseinandergelaufen ("erst ein ausgefranstes Kreuz aus
einem Vektorrasterer, dann ein Kreuz, von dem nur eine Diagonale uebrig
war").

`tools/fui/kernvergleich.py` rechnet beide Fassungen nach. Die alte
wm-Fassung gegen fUi, abweichende Bildpunkte:

| uisc | d  | sb | Minimieren | Maximieren | Wiederherst. | Schliessen |
|-----:|---:|---:|-----------:|-----------:|-------------:|-----------:|
| 1 | 10 | 1 | 0 | 0 | 0 | 0 |
| 2 | 20 | 2 | **40** | 0 | 0 | 0 |
| 3 | 30 | 3 | **60** | 0 | 0 | **112** |
| 4 | 40 | 4 | **160** | 0 | 0 | **152** |

**Es war also nicht gleich, und es war nie gleich.** Zwei getrennte
Fehler:

**F1 -- der Minimieren-Strich sass zu tief, auf JEDEM Schirm ab uisc 2.**
Die alte Fassung legte ihn auf `d/2`, ohne die Strichbreite um die
Mittellinie zu verteilen. `core.fi` tut genau das (und sagt im
Kommentar auch warum: *"otherwise it wanders downwards when scaled"*).
Justins Schirm laeuft mit uisc 2 -- der Fehler war **im Betrieb**.

**F2 -- das Kreuz sass ab uisc 3 zu hoch.** Die alte Fassung rechnete
`off = (d - (kn + sb - 1)) / 2` und nahm es fuer **beide** Achsen.
Breite (`kn + sb - 1`) und Hoehe (`kn`) sind aber verschieden.

### Am laufenden System, nicht nur auf dem Papier

Beide Kerne gegen **dieselbe** Platte, 3440x1440, `/bin/settings`
(`tools/design/knopfschuss.sh`). Bezug ist das Quadrat des
Maximieren-Knopfes -- die einzige Form, die das Feld ganz ausfuellt.

**uisc = 2** (Justins Schirm):

| Fassung | Strich y | Quadrat-Mitte | Versatz |
|---|---|---|---|
| alt | 29..30 | 28,5 | **+1,0** |
| neu | 28..29 | 28,5 | **0,0** |

Das Kreuz ist bei uisc 2 in beiden Fassungen **bitgleich** (74 Punkte,
identisches Muster) -- genau wie die Rechnung vorhersagte.

**uisc = 3:**

| Fassung | Versatz Strich | Versatz Kreuz |
|---|---|---|
| alt | +1,5 | **-1,0** |
| neu | +0,5 | **0,0** |

Der Reststand von +0,5 beim Strich ist keine Abweichung, sondern
Paritaet: ein Strich gerader Breite hat in einem Feld ungerader Hoehe
keine ganzzahlige Mitte. fUi rundet ihn konsistent, die alte Fassung
schob ihn um einen ganzen Punkt.

**Abstuerze: 0** in allen vier Laeufen.

> Beim Fotografieren gilt: Kern **und** Plattenabbild aus demselben
> Stand. Ein neuer Kern gegen eine alte `disk.img` zeigt alte Programme.

## 4. Die Regel, damit es nicht zurueckfaellt

`tools/check-ui.sh` prueste bis hierher nur `kernel/user/` -- die
Anwendungsschicht. Im Kern galt die Regel nicht, und **genau dort stand
die zweite Umsetzung**. Jetzt prueft sie auch `kernel/wm.fi`:

* **4a** bindet der Fensterserver `fui.core`?
* **4b** setzt eine **Form**-Funktion (`cg_mal`) rohe Bildpunkte?
* **4c** ist die alte, vertikal falsche Kreuzformel zurueck?

Drei Gegenproben, alle nachgewiesen:

| Eingriff | Regel |
|---|---|
| `import fui.core` auskommentiert | **schlaegt an** (4a) |
| ein Zeichen in `cg_mal` auf `cap_h` zurueckgedreht | **schlaegt an** (4b) |
| unveraendert | **gruen** |

Zwei Loecher fielen beim Bauen der Regel selbst auf und sind zu:

* `core.Target` in der Signatur zaehlte als "ruft fUi" -- die Regel war
  damit blind fuer `cg_mal`. Jetzt zaehlt nur ein **Aufruf**
  (`core.xxx(`), kein Typ.
* Die Bedingung war `roh > 0 && fui == 0`, verlangte also **null**
  core-Aufrufe. Ein **halb** zurueckgedrehtes `cg_mal` rutschte durch --
  und der halbe Zustand ist der wahrscheinlichste. Jetzt genuegt
  `roh > 0`.

`cap_glyph` steht **absichtlich nicht** unter der Regel: es
uebertraegt den fertigen Puffer und **muss** dafuer `cap_px` benutzen
(Beschnitt, Band, Farbreihenfolge). Wer es einträgt, erzwingt einen
Server ohne Beschnitt -- schlimmer als das, was die Regel verhindert.

## 5. Was offen bleibt

* **Flaechen** (`fill_round`/`round_frame`): nicht umgestellt, Grund in
  Abschnitt 2. Ginge nur mit einem Fensterpuffer je Bild.
* **Text**: geht nicht, `core.fi` K1.
* **`layout.fi` und `style.fi`** tragen ebenfalls `profile kernel` und
  sind weiterhin nicht gebunden. Die Titelleiste rechnet ihre
  Knopfpositionen noch selbst. Das waere die naechste Runde.
