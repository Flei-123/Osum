# RUNDE FUI-TEXT — die Schrift in Ring 3 setzt fUi

Zweig `fui-schrift`, abgezweigt von `main` = `6190ba0d`.

Justins Entscheidung (24.09.2026) auf die Frage, wer in OrientOS die
Schrift setzt — fUi oder weiter `wlibc.text_at` mit dem Kernel-Rasterer:
**„fUi, einheitlich“.**

## Was jetzt anders ist

Bis hierher kam jede Glyphe, die ein Programm in Ring 3 malte, aus dem
**Kern** (`kernel/gfx/ttf.fi`, über `WIG_GLYPH`/`WIG_KERN`): ein zweiter
TrueType-Leser und ein zweiter Rasterer neben fUis `lib/font/ttf.fi` +
`lib/font/raster.fi`.

Jetzt:

- `kernel/user/fuiglyph.fi` (neu) lädt `/lib/sans.ttf`, `/lib/mono.ttf`,
  `/lib/icons.ttf`, `/lib/bold.ttf` einmal je Prozess und rastert jede
  Glyphe mit **fUis** Schriftmaschine — im selben Umschlag, den der Kern
  lieferte.
- `wlibc` importiert fUi **nicht** (es wird auch in Programme im
  Kernel-Profil gebunden, wo `f64` verboten ist), sondern bekommt die
  Quelle **übergeben**: `wlibc.glyph_source(glyph, kern)`.
  `fuiglyph.install()` ruft das direkt nach `wlibc.start` — in
  `wlib.begin`, `desktop` und `taskbar`. Damit läuft jede Beschriftung,
  jede Listenzeile, jedes Symbol der Symbolschrift aller GUI-Programme
  über fUi.
- Laufweite und Unterschneidung rechnet `fuiglyph` mit der
  **ganzzahligen Formel des Kerns** — die Anordnung bleibt bildpunktgleich,
  nur die **Tinte** ändert sich: exakte Flächendeckung (256 Stufen) statt
  4×4-Abtastung (17 Stufen).
- Rückfall: Fehlen die Schriftdateien oder passt eine Glyphe nicht ins
  Rasterfenster (64 KiB), fragt `wlibc` wie bisher den Kern. Nichts
  verschwindet.

## Die zweite Fassung für die Prüfstände

`tools/ttf/fuiraster.py` ist fUis Rasterer in Python, Zeile für Zeile
(gleiche f64-Operationen in gleicher Reihenfolge). `checkshot.py` wählt
ihn mit dem Präfix `fui:` vor dem Schriftpfad; ohne Präfix gilt weiter die
Tinte des Kerns (Fensterserver-Text: Titel, Terminal im Kern).

Gemessen an einem echten Bildschirmfoto dieses Zweigs, Toleranz 0:

| Text | Tintenpunkte | falsch gegen fUi | falsch gegen Kern |
|---|---|---|---|
| „Start“ (Taskleiste) | 226 | **0** | 182 von 198 |
| „CPU 100%“ (Schreibtisch) | 447 | **0** | 361 von 401 |
| „08:40“ (Schreibtisch) | 290 | **0** | 222 von 258 |

Und auf `main` umgekehrt: „Start“ 0 falsch gegen den Kern.

## Kosten

- Speicher: je GUI-Prozess die vier Schriften (~150 KB), 64 KiB
  Rasterfenster, 16 KiB Punktspeicher.
- Zeit: eine Glyphe wird je Prozess einmal gerastert, danach kommt sie aus
  dem Glyphenspeicher von `wlibc` (unverändert).

## Nachtrag RUNDE FUI-KERNTEXT (26.09.2026): auch der Kern-Text ist fUi

Was hier früher unter „Was NICHT über fUi läuft“ stand -- der Text, den
der **Kern selbst** malt (Fenstertitel, Kern-Terminal, jede Glyphe, die
`WIG_GLYPH` an einen Prozess ohne eigene Schriften gibt) --, läuft jetzt
ebenfalls über fUis Schriftmaschine:

- `kernel/gfx/fuiink.fi` (neu) importiert fUis `lib/font/raster.fi` und
  `lib/font/ttf.fi` -- keine zweite Fassung. Weil `ttf` als Kurzname im
  Kern schon vergeben ist, kopiert `tools/build-kernel.sh` dieselbe Datei
  beim Bau als `gfx/fuittf.fi` in den Baum (Firn erlaubt je Kurzname ein
  Modul).
- f64 im Kern: fUis Funktionen tragen `#[allow_fp]`
  (`vendor/firn/patches/0008-font-allow-fp-im-kern.patch`, dieselbe
  Änderung im Firn-Repo). `fuiink` sichert je Glyphe die Vektorregister
  (`fpu.save`), lädt das Rücksetz-MXCSR, rechnet, stellt zurück. Das geht
  nur, weil `ttf.glyph` die Glyphentafel mit abgeschalteten
  Unterbrechungen hält.
- `ttf.rasterize` fragt zuerst fUi; die 4x4-Abtastung bleibt als
  Rückfall (`nofpu`, kein Arbeitsbereich, Glyphe über 256x256).
- Arbeitsbereich: 162 Rahmen (~648 KiB) aus `kgui.fi`, einmal je Boot.
  Die serielle Zeile `ttf: ink=fui on` bzw. `ttf: ink=kernel` sagt, womit
  der Kern malt.
- Prüfstände: `tools/ttf/raster.py` liefert jetzt fUi-Tinte (über
  `fuiraster.py`), `OSUM_TINTE=kern` oder `kern:` vor dem Schriftpfad
  wählt die alte Tinte. Nachweis: der Terminaltitel im wm-Bild ist mit
  fUi-Tinte 0 von 505 Punkten falsch, mit der alten 390 falsch; auf main
  umgekehrt.

Übrig ist nur die **Textkonsole** (8x16-Bitmaske aus `kernel/gfx/font.fi`)
-- dort wird nichts gerastert, also gibt es auch keine Tinte zu tauschen.

## Was NICHT über fUi läuft (Stand 24.09., überholt -- siehe oben)

- **Text, den der Kern selbst malt** (Fenstertitel, Kern-Terminal,
  Textkonsole): der Kern hat kein `f64`, fUis Rasterer rechnet in `f64`.
  Dafür bräuchte es eine ganzzahlige Fassung von `lib/font/raster.fi`
  oder Titel/Terminal in Ring 3.
- `fuib`s `s_fm` bleibt 0: fUis *Setzer* (`run_draw_wrapped` usw.) wird in
  OrientOS weiter nicht benutzt; die Anordnung macht `wlibc`, die Glyphen
  fUi.
