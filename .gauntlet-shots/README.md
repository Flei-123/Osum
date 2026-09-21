# Aufnahmen der Runde GLAS

Alle Bilder sind ECHTE Aufnahmen des laufenden Systems: Osum startet in QEMU,
der Bildspeicher wird ueber den QEMU-Monitor als PPM abgezogen
(`tools/gfx/screenshot.py`) und nach PNG gewandelt. Aufloesung 1280x800.
Erzeugt am 21.09.2026 aus dem Zweig `glas`.

Herkunft:
* 01-11 stammen aus dem Abnahmelauf `bash tools/themestore/run.sh`
  (Ergebnis dieses Laufs: **136 Zusagen, 0 rot**).
* 13-15 sind drei zusaetzliche Laeufe mit demselben Verfahren
  (`tools/themestore/build.sh` mit anderen Reglerstellungen).
* 12 ist kein eigener Lauf, sondern ein 2-fach vergroesserter Ausschnitt
  der Leiste aus 04/05/06/07 nebeneinander, damit der Unterschied ohne
  Zoom sichtbar ist.

Die Zahlen zu diesen Bildern stehen in [`docs/RUNDE-GLAS.md`](../../RUNDE-GLAS.md),
auch die, die nicht erreicht wurden.

| Bild | Was es zeigt |
|---|---|
| 01-radius-0-scharfe-ecken.png | Einstellungen mit `radius=0`: rechte Winkel ueberall, wie frueher `shape=classic`. Ecke: tiefe 0, Mischtoene 0. |
| 02-radius-12-mittel.png | Derselbe Stand mit `radius=12`. Ecke: tiefe 10, 8 Zeilen mit Mischton. |
| 03-radius-24-weiche-kacheln.png | Derselbe Stand mit `radius=24`, Regler zeigt "24". Ecke: tiefe 32, 18 Zeilen mit Mischton. Inhalt sitzt an derselben Stelle wie bei 0 (0 von 36 Rechtecken gewandert). |
| 04-taskleiste-100-deckend.png | Gemusterter Hintergrund, Leiste voll deckend -- der Leistengrund ist EINE Farbe (`var 0`, farben 1). |
| 05-taskleiste-70-prozent.png | Leiste bei 70 % Deckung, das Muster schlaegt durch (`var 1597`, farben 2). Wirksam sind 85 bzw. 100 % -- siehe die Anmerkung unten. |
| 06-taskleiste-40-prozent.png | Leiste bei 40 %, deutlich staerker durchscheinend (`var 6389`, farben 2). Wirksam 71 bzw. 100 %. |
| 07-milchglas-blur12.png | Milchglas (`taskbar_blur=12`, 70 %): der Untergrund unter der Leiste ist weichgezeichnet (`var 788` gegen 1597 ohne), aus zwei Farben sind 13 geworden. |
| 08-settings-darstellung-regler.png | Reiter "Darstellung" mit den vier neuen Reglern (Eckenrundung 0-24, Taskleiste %, Fenster %, Milchglas) samt Zahlenanzeige; alles im Fenster (74 Rechtecke, 0 ragen heraus). |
| 09-settings-vorlagen.png | Reiter "Vorlage" (Vorlagenliste), zum Vergleich unveraendert. |
| 10-fenster-unter-leiste-gezogen-keine-schlieren.png | Nach einem Zug des Fensters unter die Leiste **und zurueck** -- der Leistengrund ist Bildpunkt fuer Bildpunkt der des ungezogenen Laufs (`diff 0`). BEFUND: weil das Fenster zurueckgezogen wurde, ist dieses Bild KEIN Beleg fuer den Fall, in dem es unter der Leiste liegen bleibt -- den zeigt Bild 15. |
| 11-dunkles-bild-leiste-40-kontrast.png | Dunkles Hintergrundbild, Regler auf 40 %. **BEFUND, berichtigt und jetzt GEMESSEN:** die Leiste ist hier NICHT bei 40 % zu sehen. `glass_mix` hebt die Deckkraft ueber den Abstand zur Schluesselfarbe und ueber den Schleier an, und der Server sagt seit dem Nachtrag, wie weit: `wm: glas alpha_soll=40 alpha_ist=82 alpha_max=100 hoch=865797 px=935060` -- im Schnitt **82 %**, an den von Weiss fernsten Bildpunkten 100 %, und 92 % aller gemischten Bildpunkte sind angehoben worden. Im Bild bleibt davon `var 24` bei zwei Gruenden uebrig (gegen `var 6389` bei derselben Einstellung ueber dem hellen Bild): zwei Farben, die sich um eine Helligkeitsstufe unterscheiden, also nichts, was ein Mensch als Durchsicht sieht. Der Kontrast 12,33 : 1 ist deshalb der gegen eine praktisch deckende Leiste. Dieselbe Zahl steht jetzt NEBEN dem Regler ("Taskleiste deckend % (wirkt 82)", Bild 18) -- eine Untergrenze, die man nicht sieht, ist von einem Fehler nicht zu unterscheiden. Siehe RUNDE-GLAS.md, Abschnitt 8.2. |
| 12-leiste-vergleich-ausschnitt-2x.png | Ausschnitt der Leiste aus 04/05/06/07 uebereinander, 2-fach vergroessert: deckend / 70 % / 40 % / Milchglas. |
| 13-fenster-transparenz-55-prozent.png | `window_alpha=55`: das Einstellungsfenster selbst ist durchsichtig, Muster und das Terminal darunter scheinen durch. |
| 14-milchglas-mit-reglerstand.png | Leiste 60 %, Fenster 80 %, Milchglas 12 -- die Reglerstellungen im Bild stimmen mit der Wirkung ueberein. |
| 15-fenster-unter-die-leiste-gezogen.png | Endlage nach einem Zug nach unten (ohne Rueckweg), **der Stand VOR dem Nachtrag**: `shotcheck.py` meldete hier 8 leere Beschriftungen (die anderen Bilder: 0). **BEFUND, aufgeklaert -- es waren drei Sachen und keine davon ein leerer Rumpf:** (1) der Griffpunkt 400,10 lag im oberen Greifrand, der Lauf zog also nie, sondern schob die Oberkante auf die Mindesthoehe (`wm: zieh k=4 ... h=16`) -- der "leere Rumpf" ist ein zusammengeschobenes Fenster; (2) das Programm meldete seine Beschriftungen weiter zu dem Ursprung, an dem es ANGELEGT wurde, weil `win_ort_holen` im Anstrich nicht gerufen wurde -- `wlib.flush_win` fragt die wahre Stelle jetzt vor jedem Anstrich; (3) bei 400,600 haengt das untere Drittel unter dem Bildrand, und was der Schirm nicht zeigt, ist keine leere Beschriftung -- `shotcheck.py` zaehlt das jetzt als `ausserhalb` und benennt es. Nach dem Nachtrag: `empty 0 cut 0 overlapping 0 ausserhalb 0` (Bild 19, Zug auf 400,210, Ueberlappung mit der Leiste 16044 Bildpunkte vom Server und 15960 vom Wirt gerechnet). Siehe RUNDE-GLAS.md, Abschnitt 8.1. |

Mechanische Pruefung (`tools/themestore/shotcheck.py`, gegen die Rechtecke,
die die Programme selbst gemeldet haben):
01-11 sowie 13/14: `empty 0  cut 0  overlapping 0`.
15: `empty 8  cut 0  overlapping 0` -- siehe Befund in der Tabelle. Mit dem
berichtigten `shotcheck.py` (das "nicht auf dem Schirm" von "leer" trennt)
meldet derselbe Stand `empty 0  cut 0  overlapping 0  ausserhalb 13`: keine der
acht Meldungen war ein leerer Rumpf.
18/19: `empty 0  cut 0  overlapping 0  ausserhalb 0`.

## Was die ersten fuenfzehn Bilder NICHT zeigen

Sie sind vor dem Nachtrag entstanden, den die Jury ausgeloest hat. In
jedem von ihnen steht im Terminalfenster `KEIN EINZIGES GERT!` --
`term_putc` hat die zwei Oktette des Ä verschluckt --, und der
Fensterknopf der Leiste traegt keinen Titel, sondern nur sein Symbol.
Beides ist behoben (RUNDE-GLAS.md, Abschnitt 9); die Bilder darunter
sind die Belege dafuer und nach dem Nachtrag aufgenommen.

| Bild | Was es zeigt |
|---|---|
| 16-umlaut-im-terminal.png | Derselbe Stand wie 04, nach dem Nachtrag: im Terminal steht `KEIN EINZIGES GERÄT!`, und der Fensterknopf der Leiste traegt "Terminal -- sh". Nachgerastert mit `tools/look/umlaut.py --gitter=1,1` gegen `tools/ttf/raster.py`: 1 014 Tintenpunkte, 0 falsch. Gemessen mit `shotcheck.py --leiste`: `empty 0 cut 0 overlapping 0`. |
| 17-vorher-nachher-umlaut-und-leiste.png | ABGELEITET, kein eigener Lauf: vier Ausschnitte aus 04 und 16, 2-fach vergroessert und uebereinandergelegt. Oben die Terminalzeile vorher (`GERT!`) und nachher (`GERÄT!`), unten die Leiste vorher (zwei Symbole ohne Wort) und nachher (`Start` und `Terminal -- sh`). |
| 18-regler-zeigt-wirksames-alpha.png | Seite "Darstellung" ueber dem DUNKLEN Bild, Regler der Taskleiste auf 40 %: die Beschriftung des Reglers lautet "Taskleiste deckend % (wirkt 82)", die Zahlenanzeige rechts steht auf 40 %. Beide Zahlen stimmen mit dem Server ueberein (`settings: glas ... tba=40 ist=82` gegen `wm: glas alpha_soll=40 alpha_ist=82`) -- der Schleier ist damit sichtbar statt still. Gemessen: `empty 0 cut 0 overlapping 0 ausserhalb 0`, mit `--leiste` ebenfalls 0/0/0. |
| 19-zug-unter-die-leiste-neu.png | Derselbe Versuch wie Bild 15, nach dem Nachtrag: Griff in die Titelleiste, Zug auf 400,210, KEIN Rueckweg. Das Fenster steht bei y=203 und reicht mit seiner Unterkante unter die Leiste (Schnittflaeche 16044 Bildpunkte, vom Server selbst gerechnet: `wm: schlieren ... unterpx=16044`; im ungezogenen Lauf steht dort 0). Der Rumpf ist vollstaendig gemalt: `empty 0 cut 0 overlapping 0 ausserhalb 0`, und keine einzige `wm: zieh`-Zeile -- gezogen wurde, nicht in der Groesse veraendert. |
