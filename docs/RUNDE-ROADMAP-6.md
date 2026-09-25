<!-- SPDX-License-Identifier: GPL-2.0-only -->
# Runde ROADMAP-6 — A-007 (fas/K16) und A-003 (k15 neu eingemessen)

Zweig `runde-roadmap-6`, von `main` 821de79a.

| Punkt | vorher | nachher |
|---|---|---|
| A-007 K16 | 67/2 (sshd, sync, tresor binden nicht mit `fas`; #!-Zeile zerrissen) | **69/0** |
| A-003 k15 | 214/38 | **258/0** |

## A-007 — `fas` kann den SIMD-/Krypto-Satz der Bibliothek

Die Liste kam nicht aus Raten, sondern aus den `.s`-Dateien, die `firnc`
fuer `sshd`, `sync` und `tresor` erzeugt: jeder Befehl, der dort vorkommt
und den `fas` nicht kannte.

* Zahlenmarken `1:` mit `1b` / `1f` (die Bibliothek schreibt ihre
  Krypto-Schleifen so).
* Ein dritter Operand (imm8): `pshufd`, `palignr`, `pclmulqdq`.
* Die Opcode-Karten `0F38` und `0F3A`: `pshufb`, `aesenc`/`aesenclast`/
  `aesdec`/`aesdeclast`/`aesimc`, `sha256rnds2`/`sha256msg1`/`sha256msg2`,
  dazu `paddd`, `pxor` und `cpuid` -- genau die Befehle, die in den drei
  Programmen vorkommen, nicht mehr.
* **Gegenprobe:** 214 Befehle, jeder einzeln von `fas` und von GNU `as`
  uebersetzt und Oktett fuer Oktett verglichen — 214/214 gleich. Falsche
  Formen (`pxor rax,xmm0`, `jnz 7b` ohne Marke, ein dritter Operand, wo
  keiner hingehoert) brechen mit einer Meldung ab statt still Unsinn zu
  schreiben.
* `kernel/user/k16.fi`: das Kindprogramm (`echo` hinter `#!`) und die
  Meldezeile teilten sich die serielle Leitung; die Zeile wird jetzt erst
  NACH dem Warten geschrieben (gleich fuer `open_elf`).

## A-003 — k15 auf das heutige Design eingemessen, und drei echte Fehler

Der rote Faden wie in ROADMAP-2: die meisten roten Zusagen massen eine
Oberflaeche, die es nicht mehr gibt. Jede wurde gegen das Foto dieser
Runde nachgemessen und auf das umgestellt, was das Programm SELBST meldet
(Rechteck, Grundlinie, Bildschirmgroesse), nicht auf eine neue Zahl.

### Echte Fehler (betreffen auch das ausgelieferte System)

1. **Kein Kontextmenue-Eintrag im Dateimanager tat etwas.**
   `explorer.fi` setzte `offen = 0`, sobald kein Menuefenster mehr da war
   — aber ein Klick auf eine Zeile schliesst das Menue UND liefert die
   Wahl im selben `wlib.step`. Die Wahl ging an `menue_wahl(0, …)`.
   "New folder", "Rename", "Delete" …: Menue zu, nichts passiert. Jetzt
   nur noch, wenn `step` kein Ereignis brachte.
2. **Der Starter zeigte Buchstaben statt der Programmsymbole.**
   `wlib.is_image` hielt nur Zeiger unter 0x40200000 fuer Bilder (das
   Abbildfenster von Runde K1). Der Starter hat inzwischen 2,7 MiB Text,
   seine Symboltabelle liegt bei 0x4042f000 — jedes Symbol wurde als
   FARBE gelesen. Grenze jetzt das Ende des privaten Bereichs
   (0x4C600000, `kernel/sched/proc.fi`); eine Farbe ist hoechstens
   0xFFFFFF.
3. **Symbole sassen in den zweizeiligen Zeilen am oberen Rand**, obwohl
   `icon_y` "mittig" meldet. `tile_top` rechnet jetzt fuer Malen und
   Melden dasselbe (einzeilige Zeilen bleiben unveraendert).

Dazu Meldungen, die nicht das meldeten, was gemalt wird:
`selfg=` (widgetdemo, explorer, launcher) meldete das rohe `T_SELFG`
statt `theme_selfg()`; der Starter meldete `zh=20` statt der Hoehe
seiner zweizeiligen Liste (38; auch `tools/design/drive.py` klickt
damit); der Dateimanager meldete das verborgene Symbolfeld als Rechteck
0x276; `explorer: tat` wurde in sechs Stuecken geschrieben und von
`wm: rahmen` zerrissen.

### Neu eingemessen

Fokusring um den aktiven Reiter statt um die Leiste; Menue als
randloses Popup (Rahmen 1 px `T_ACCENT`, Text bei +8/+16); Dialog mittig
auf dem ECHTEN Schirm (1280x800, aus `wm:` gelesen); Kontextmenue des
Dateimanagers mit 14 Zeilen ("New folder" = Zeile 8, Mausweg in Schritten
unter 128); Titeltext bei +12; Textmarke mittig am Zeiger, schwarz mit
weissem Rand; Starter als Panel unten links, Name fett + Beschreibung in
12 px, Reihenfolge aus `launcher: treffer`, Symbole 16x16; Suchwort
`ordner` statt `folder` (seit Runde I18N steht "folder" in der englischen
Beschreibung); Dateitreffer zweizeilig (Name / Ordner). Das Testabbild
fuehrt jetzt `/lib/bold.ttf` wie jedes echte Abbild.
