# Aufnahmen der Runde GLAS

Alle Bilder sind ECHTE Aufnahmen des laufenden Systems: Osum startet in QEMU,
der Bildspeicher wird ueber den QEMU-Monitor als PPM abgezogen
(`tools/gfx/screenshot.py`) und nach PNG gewandelt. Aufloesung 1280x800.
Erzeugt am 21.09.2026 aus dem Zweig `glas`.

Herkunft:
* 01-11 stammen aus dem Abnahmelauf `bash tools/themestore/run.sh`
  (Ergebnis dieses Laufs: **136 Zusagen, 0 rot**), Beweisstuecke unter
  `/tmp/ts-shot`.
* 13-15 sind drei zusaetzliche Laeufe mit demselben Verfahren
  (`tools/themestore/build.sh` mit anderen Reglerstellungen).
* 12 ist kein eigener Lauf, sondern ein 2-fach vergroesserter Ausschnitt
  der Leiste aus 04/05/06/07 nebeneinander, damit der Unterschied ohne
  Zoom sichtbar ist.

| Bild | Was es zeigt |
|---|---|
| 01-radius-0-scharfe-ecken.png | Einstellungen mit `radius=0`: rechte Winkel ueberall, wie frueher `shape=classic`. |
| 02-radius-12-mittel.png | Derselbe Stand mit `radius=12`. |
| 03-radius-24-weiche-kacheln.png | Derselbe Stand mit `radius=24`, Regler zeigt "24". Inhalt sitzt an derselben Stelle wie bei 0. |
| 04-taskleiste-100-deckend.png | Gemusterter Hintergrund, Leiste voll deckend -- der Leistengrund ist EINE Farbe. |
| 05-taskleiste-70-prozent.png | Leiste bei 70 % Deckung, das Muster schlaegt durch. |
| 06-taskleiste-40-prozent.png | Leiste bei 40 %, deutlich staerker durchscheinend. |
| 07-milchglas-blur12.png | Milchglas (`taskbar_blur=12`, 70 %): der Untergrund unter der Leiste ist weichgezeichnet, keine harten Kachelkanten mehr. |
| 08-settings-darstellung-regler.png | Reiter "Darstellung" mit den vier neuen Reglern (Eckenrundung 0-24, Taskleiste %, Fenster %, Milchglas) samt Zahlenanzeige; alles im Fenster. |
| 09-settings-vorlagen.png | Reiter "Vorlage" (Vorlagenliste), zum Vergleich unveraendert. |
| 10-fenster-unter-leiste-gezogen-keine-schlieren.png | Nach einem Zug des Fensters unter die Leiste und zurueck -- der Leistengrund ist Bildpunkt fuer Bildpunkt der des ungezogenen Laufs (Abnahme: diff 0). |
| 11-dunkles-bild-leiste-40-kontrast.png | Dunkles Hintergrundbild, Leiste bei 40 % -- der Fall, gegen den der Kontrast der Leistenschrift gerechnet wird. |
| 12-leiste-vergleich-ausschnitt-2x.png | Ausschnitt der Leiste aus 04/05/06/07 uebereinander, 2-fach vergroessert: deckend / 70 % / 40 % / Milchglas. |
| 13-fenster-transparenz-55-prozent.png | `window_alpha=55`: das Einstellungsfenster selbst ist durchsichtig, Muster und das Terminal darunter scheinen durch. |
| 14-milchglas-mit-reglerstand.png | Leiste 60 %, Fenster 80 %, Milchglas 12 -- die Reglerstellungen im Bild stimmen mit der Wirkung ueberein. |
| 15-fenster-unter-die-leiste-gezogen.png | Endlage nach einem Zug nach unten (ohne Rueckweg): das Fenster steht halb unter der Leiste. BEFUND: der Rumpf ist an der neuen Stelle leer gezeichnet, `shotcheck.py` meldet hier 8 leere Beschriftungen (die anderen Bilder: 0). |

Mechanische Pruefung (`tools/themestore/shotcheck.py`, gegen die Rechtecke,
die die Programme selbst gemeldet haben):
01-11 sowie 13/14: `empty 0  cut 0  overlapping 0`.
15: `empty 8  cut 0  overlapping 0` -- siehe Befund in der Tabelle.
