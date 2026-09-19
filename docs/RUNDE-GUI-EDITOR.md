# Runde GUI-EDITOR — das mehrzeilige Textfeld und der Editor darauf

Zweig `runde-gui-editor`, Arbeitsbaum `/root/ed-osum`.
Abnahme: `bash tools/guieditor/run.sh` — **18 Zusagen, 0 gescheitert**.

Justins Auftrag, wörtlich: der Editor soll *„ein moderner notepad++
editor oder so"* werden.

---

## Was vorher da war, und was gefehlt hat

`kernel/user/edit.fi` (1475 Zeilen) ist ein **Terminal**-Editor im Stil
von nano: `import ulib`, `import tools`, **kein** `wlib`. Er malt mit
VT100-Fluchtfolgen und fragt seine Größe mit `TIOCGWINSZ` in Zeichen ab.

Ein Fenster-Editor braucht ein mehrzeiliges Textfeld, und das gab es in
`wlib` nicht. Der Kopf der Datei sagte es seit Runde K15 ausdrücklich:

> keine Umbrüche im Textfeld (es ist EINE Zeile), keine Auswahl mit
> Umschalt-Pfeil (die Umschalttaste kommt in diesem System nicht als
> eigenes Ereignis an)

Beide Sätze sind mit dieser Runde nicht mehr wahr.

---

## Teil 1 — `K_TEXTAREA`, das mehrzeilige Textfeld (in `wlib`)

Es steht in der **Bibliothek** und nicht im Programm. Das ist die Regel
dieses Baums (`tools/check-ui.sh` misst sie): ein Editor, der sich sein
Textfeld selbst malt, wäre genau die zweite Umsetzung, die hier nirgends
stehen soll.

### Wie der Text liegt

Als **Zeilentafel**, je Zeile drei Wörter (Zeiger, Länge, Platz). Eine
Datei mit 5000 Zeilen als *ein* Oktettfeld zu halten heißt: ein Zeichen
in Zeile 3 einfügen kopiert alle Oktette dahinter um eins nach hinten —
bei jedem Tastendruck die ganze Datei.

Mit der Zeilentafel kostet ein Zeichen nur den Rest **seiner Zeile**
(60 Oktette statt 200 000). Eine Zeile teilen oder zwei zusammenziehen
verschiebt **Tafeleinträge** (je 3 Wörter), nicht Text.

*Warum kein Lückenpuffer:* für das Tippen gleich gut, für „gib mir
Zeile 312 bis 348" schlechter — er müsste zählen, die Tafel rechnet. Und
genau das fragt der Zeichner bei **jedem** Bild.

### Was sonst drinsteckt

Marke mit Pfeilen, Pos1/Ende (erst an den Text, dann an den Rand),
Bild auf/ab, Strg+Pfeil wortweise, Strg+Pos1/Ende. Auswahl mit Umschalt
**und** mit der Maus samt Ziehen. Strg+C/X/V über `wlibc.clip_put` —
dieselbe Ablage wie der Dateimanager. Strg+Z/Y. Zwei Rollbalken, der
Bildlauf folgt der Marke, die Einrückung wandert auf die neue Zeile.

Der Zeichner malt **nur den sichtbaren Ausschnitt**, und die Schrift ist
die feste (`F_MONO`): damit ist „welche Spalte liegt an Bildpunkt x"
eine Division statt einer Messung Zeichen für Zeichen — und diese Frage
wird bei jeder Mausbewegung gestellt.

### Die Umschalttaste (`kernel/drv/hid/kbd.fi`)

Sie kam nie an — **nicht**, weil der Kern sie nicht sieht, sondern weil
er sie nicht mitschickte. Der xterm-Modifikator `;2` hing nur an den
Tilde-Formen (Entf, Bild auf/ab), nicht an den Buchstabenformen der
Pfeile: `Pfeil links` und `Umschalt+Pfeil links` waren **dieselben drei
Oktette**. Der Pfeil hoch ging sogar als nacktes Oktett 14 an jeder
Fluchtfolge vorbei.

Neu: `mods_of()` liefert 2/5/6 (Umschalt/Strg/beide), die Pfeile gehen
mit Modifikator als `ESC [ 1 ; m D`. **Ohne** Modifikator steht Oktett
für Oktett dasselbe auf der Leitung wie vorher — die Shell und
`/bin/edit` sehen keinen Unterschied. Gemessen: `tools/userland/run.sh`
bleibt bei 91/0, einschließlich „the line editor on a REAL keyboard".

---

## Teil 2 — `/bin/nedit`, der Editor

Reiter (`K_TABS`), Zeilennummernspalte, Statuszeile (Zeile/Spalte/Zahl
der Zeilen, Kodierung, Zeilenende, Änderungszeichen), Syntaxfarben für
Firn und Shell, Suchen/Ersetzen/Gehe-zu, Öffnen/Sichern/Sichern unter,
Frage vor dem Schließen mit ungesicherten Änderungen. Bündel unter
`assets/apps/nedit.osp`.

**`/bin/edit` bleibt.** Er braucht kein Fenster und ist deshalb der, mit
dem man eine Konfigurationsdatei noch reparieren kann, wenn die
Oberfläche gerade nicht hochkommt. Zwei Editoren sind hier kein Doppel,
sondern zwei Arbeitsplätze. Zwei Zusagen der Abnahme halten das fest.

---

## Was gemessen wurde

`/bin/nedit` hat `messen=N`, `rollen=N` und `rollnur=N`: sie speisen die
Tasten durch **genau** den Weg ein, den eine echte Taste nimmt
(`wlib.feed_key` → `on_key` → `ta_key`). Von außen ist das nicht zu
messen — ein Tastendruck über den QEMU-Monitor läuft durch PS/2, Kern,
Fensterserver und Ereignisschlange, und der Anteil des Textfelds geht in
der Gesamtzeit unter. Die Uhr hat 100 Hz, also wird ein Bündel gemessen
und geteilt.

| | 5001 Zeilen (262 KB) | 12 Zeilen |
|---|---|---|
| Tippen | **38 µs/Taste** | 36 µs/Taste |
| Rollen (ohne Anstrich) | **5 µs/Taste** | 0 µs/Taste |
| Rollen (mit Anstrich) | 69 450 µs | 52 400 µs |

Die Zusage ist **nicht** „schnell", sondern **„unabhängig von der
Dateigröße"**: eine feste Schranke wäre eine Aussage über den Wirt, das
Verhältnis ist eine Aussage über den Entwurf. 105 %.

Die dritte Zeile ist der **Voll-Anstrich des Fensters** und nicht das
Textfeld — er kostet bei zwölf Zeilen fast ebensoviel, und `blits=95`
steht in beiden Läufen. Er gehört dem Fensterserver.

---

## Drei Fehler, die nur das Bild gezeigt hat

1. **Die Zeile unter der Marke war ein satter blauer Balken.** `ta_mix`
   mischte drei Viertel Auswahlfarbe in die Feldfarbe; der Text darin
   war schlechter zu lesen als überall sonst. Jetzt sagt
   `ta_misch(a, b, teil)`, wie viel: ein Achtel für die Hinterlegung,
   sechs Achtel für die Syntaxfarbe.

2. **Drei waagerechte graue Linien quer durch das Textfeld**, bei
   y = 266, 470 und 674 — Abstand genau **204**, die Bandhöhe von
   `wlibc.surf_rows()`. `fuib.tafel` schneidet ein Rechteck auf das Band
   zu und malt dann eine **runde Ecke an der neuen Oberkante**. Bei
   jedem anderen Bedienelement fällt das nie auf, weil keines höher ist
   als ein Band; dieses Feld liegt in dreien. Abhilfe: die Füllung ist
   ein **flaches** Rechteck (`fuib.area`), nur der Rahmen rund
   (`fuib.ring`).

3. **Danach fehlten alle Zeilennummern.** Der enge Textschnitt fängt bei
   `x + gut + 1` an und radierte die Spalte links davon weg. Der Schnitt
   wird jetzt je Zeile um den **Text** gelegt und für die Nummer gelöst.

Keiner der drei ist im Quelltext zu sehen.

---

## Bilder

`.editor-shots/` — `ab-reiter.png` (zwei Reiter, Firn und Shell
eingefärbt), `ab-zeig1.png` (Auswahl über zwei Zeilen mit
Umschalt+Pfeil), `ab-zeig2.png` (Suchtreffer ausgewählt),
`ab-zeig3.png` (nach dem Ersetzen: `var TOTAL`, Reiter `*probe.fi`,
unten „geändert"), `06-gross.png` (5001 Zeilen).

## Was nicht erreicht wurde

* **Der Pfad steht nicht im Fenstertitel**, sondern in einer Zeile
  darunter. `wlib.window` nimmt den Titel beim Anlegen, und es gibt
  keinen Weg, ihn danach zu ändern — ein Titel, der beim Reiterwechsel
  stehenbliebe, nennte die falsche Datei. Wer ihn will, baut
  `set_window_title` in die Bibliothek.
* **Der Dateidialog ist ein Textfeld**, kein Durchklicken durch
  Verzeichnisse: `wlib.dlg_open` hat ein Feld, und der Auswahldialog des
  Dateimanagers (`expdlg`) hängt an dessen Modell.
* **Ersetzen ist zwei Fragen nacheinander** (wonach, wodurch), weil ein
  Dialog dieser Bibliothek ein Feld hat. Kein „alle ersetzen".
* **Die Syntaxhervorhebung sieht eine Zeile für sich allein an.** Ein
  Blockkommentar über mehrere Zeilen wird nur in der Zeile erkannt, in
  der er anfängt.
* **Rückgängig ist ein Schnappschuss je Schritt** (16 tief). Bei einer
  sehr großen Datei kostet das Speicher; `ta_push_undo` gibt dann still
  auf, statt den Editor anzuhalten.
* **Die Marke blinkt nicht.** Dafür bräuchte es einen Zeitgeber, der das
  Fenster von selbst schmutzig macht; den hat diese Bibliothek nicht.
