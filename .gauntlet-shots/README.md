# Aufnahmen der Runde GLAS

Alle Bilder sind ECHTE Aufnahmen des laufenden Systems: Osum startet in QEMU,
der Bildspeicher wird ueber den QEMU-Monitor als PPM abgezogen und nach PNG
gewandelt. Aufloesung 1280x800 (Bild 20: 1024x768).
Neu erzeugt am 21.09.2026 aus dem Zweig `glas`.

Herkunft:
* 01-12, 18, 21, 22 stammen aus dem Abnahmelauf `bash tools/themestore/run.sh`
  dieses Tages. Ergebnis des Laufs: **230 Zusagen, 0 rot**
  (Log: `/tmp/ts-run.log`, Beweisstuecke: `TS_OUT=/tmp/ts-shot`).
* 13 ist der Lauf `winal` derselben Abnahme.
* 14, 19, 20 sind drei zusaetzliche Laeufe mit demselben Verfahren
  (`tools/themestore/build.sh` mit anderen Reglerstellungen), jeder
  danach durch `tools/themestore/shotcheck.py` gemessen.
* 12 ist kein eigener Lauf, sondern ein 2-fach vergroesserter Ausschnitt der
  Leiste aus sechs Laeufen uebereinander, damit der Unterschied ohne Zoom
  sichtbar ist.

Kein Bild ist die Kopie eines anderen: alle 19 Dateien haben eine eigene
Pruefsumme.

| Bild | Was es zeigt |
|---|---|
| 01-radius-0-scharfe-ecken.png | Seite "Darstellung" mit `radius=0`: rechte Winkel an Fenster, Knoepfen, Listen, Karten und Leistenknoepfen. Regler "Eckenrundung" steht auf 0. Gemessen: `ecke tiefe=0 weich=0` -- kein einziger Mischton, da ist nichts zu glaetten. |
| 02-radius-12-mittel.png | Derselbe Stand mit `radius=12`, Zahlenanzeige 12, `ecke tiefe=10 weich=8` (acht Zeilen mit Mischton = kantengeglaettet). |
| 03-radius-24-weiche-kacheln.png | Derselbe Stand mit `radius=24`: sehr weiche Kacheln, Zahlenanzeige 24, `ecke tiefe=32 weich=18`. Der Inhalt sitzt an genau derselben Stelle wie bei 0. |
| 04-taskleiste-100-deckend.png | Gemusterter heller Hintergrund, Leiste voll deckend: der Leistengrund ist EINE Farbe (`var 0`). |
| 05-taskleiste-70-prozent.png | Leiste bei 70 % Deckung, das Muster schlaegt durch (`var 1597`, 2 Farben im Grund). |
| 06-taskleiste-40-prozent.png | Leiste bei 40 %, staerker durchscheinend (`var 6389`). |
| 07-milchglas-blur16-grobes-muster.png | Milchglas, und sichtbar: dunkles Schema (`midnight`) auf dem GROBEN Muster, Leiste bei 40 %, `taskbar_blur=16`. Der Streifen unter der Leiste ist ein Verlauf aus **36 Farben** (`var 3563`) gegen die **2 Farben** (`var 4102`) desselben Standes ohne Weichzeichner. Zeit je Vollbild in diesem Lauf: `us=40051`, Spitze 179515 bei `px=35840`, `cache=2/27` aus dem Zwischenspeicher (QEMU/TCG). |
| 08-settings-darstellung-regler.png | Reiter "Darstellung" mit den vier neuen Reglern (Eckenrundung 0-24, Taskleiste %, Fenster %, Milchglas) samt Zahlenanzeige; alles im Fenster, Abschnitt 8 gruen (88 gemeldete Rechtecke, 0 ragen heraus). |
| 09-settings-vorlagen.png | Reiter "Vorlage" (Vorlagenliste), zum Vergleich unveraendert. |
| 10-zug-hin-und-zurueck-keine-schlieren.png | Nach einem Zug des Fensters unter die Leiste UND zurueck: der Leistengrund ist Bildpunkt fuer Bildpunkt der des ungezogenen Laufs (`diff 0`) -- keine Schlieren. |
| 11-dunkles-bild-leiste-soll40-wirkt82-kontrast.png | Dunkles Hintergrundbild, HELLE Leiste, Regler auf 40 %. Der Name sagt, was zu sehen ist: die Lesbarkeitsschranke hebt die wirksame Deckkraft von **soll 40** auf **wirkt 82** (`wm: glas alpha_soll=40 alpha_ist=82`), damit die Leistenschrift 4,5:1 haelt; gemessen gegen den GEMISCHTEN Grund 12,33:1. Als Beleg fuer DURCHSICHT bei 40 % taugt es deshalb nicht -- dafuer ist Bild 21 da. |
| 12-leiste-vergleich-ausschnitt-2x.png | SECHS Ausschnitte der Leiste uebereinander, 2-fach vergroessert, jede Reihe IM BILD beschriftet mit Reglerstellung UND gemessener Streuung: `100 % -- var 0, 1 Farbe`, `70 % -- var 1597, 2`, `40 % -- var 6389, 2`, `Milchglas (blur=12, 70 %) -- var 788, 13`, `dunkles Schema, 40 %, grobes Muster, ohne Milchglas -- var 4102, 2`, `dasselbe mit Milchglas 16 -- var 3563, 36`. Die letzten zwei Reihen sind das Paar, das den Bildvergleich traegt: harte Kacheln gegen einen Verlauf. Die Zahlen im Bild sind die des Laufs, und der Lauf haelt Bild und Messung Zahl fuer Zahl gegeneinander. |
| 13-fenster-transparenz-55-prozent.png | `window_alpha=55` ueber dem gemusterten Bild: das Einstellungsfenster selbst ist durchsichtig, Muster und die Terminalausgabe darunter schlagen durch, die Beschriftungen bleiben lesbar (schlechtestes Paar 5,16:1). |
| 14-milchglas-mit-reglerstand.png | Eigener Lauf: Leiste 60 %, Fenster 80 %, Milchglas 12 (`settings: glas radius=10 tba=60 wa=80 blur=12 ist=63`) -- die Reglerstellungen im Bild stimmen mit der Wirkung ueberein. Weichzeichner `us=37873`, Spitze 47038. `empty 0 cut 0 overlapping 0`. |
| 18-regler-zeigt-wirksames-alpha.png | Seite "Darstellung" ueber dem DUNKLEN Bild, Regler der Taskleiste auf 40 %: die Beschriftung lautet "Taskleiste deckend % (wirkt 83)" -- die Untergrenze wird ANGEZEIGT statt still zu wirken. |
| 19-zug-unter-die-leiste-neu.png | Eigener Zug-Lauf auf 620,260 OHNE Rueckweg, tiefer als der der Abnahme: die Unterkante des Fensters liegt unter der Leiste, Schnittflaeche **21392** Bildpunkte (`wm: schlieren ... unterpx=21392`, gegen 16044 in Bild 22). Die Leiste ist ueber dem Fenster neu gemischt, der zurueckgelassene Schreibtisch ist saubere Musterflaeche -- keine Schliere. `empty 0 cut 0 overlapping 0`. |
| 20-schmaler-schirm-1024x768-milchglas.png | ENGER SCHIRM (1024x768, `fbres=`), Leiste 70 % mit Milchglas 8 (`ist=72`): die Seite "Darstellung" passt auch hier vollstaendig ins Fenster, `empty 0 cut 0 overlapping 0 ausserhalb 0 verdeckt 0`. |
| 21-dunkelmod-leiste-40-durchsicht-var4218.png | Lauf `dunkelmod` (`scheme=midnight mode=dark tbalpha=40 wallpaper=dunkel`): dunkles Schema auf dunklem Bild. Hier liegt die Leistenfarbe nahe am Untergrund, der Schleier muss kaum anheben, und bei 40 % scheint das Schachbrett WIRKLICH durch -- `var 4218` bei 2 Farben im Leistengrund (die deckende Leiste hat `var 0`), und die Schrift haelt dabei 13,73:1. Das ist die Aufnahme, auf der Reglerstellung 40 und Durchsicht zugleich gelten. |
| 22-zug-endlage-unter-der-leiste.png | Der Zug-Lauf der Abnahme (ohne Rueckweg): das Fenster steht in seiner Endlage unter der Leiste, Schnittflaeche 16044 Bildpunkte. `empty 0 cut 0 overlapping 0 linie 0`. |

Mechanische Pruefung (`tools/themestore/shotcheck.py`, gegen die Rechtecke,
die die Programme selbst gemeldet haben): fuer alle Laeufe dieses Satzes
`empty 0  cut 0  overlapping 0  ausserhalb 0  verdeckt 0`
(`gekuerzt 0`: seit dem Umbau der Reiterleiste auf ZWEI ZEILEN muss kein
einziger Reitername mehr gekuerzt werden, und die Fliesstextzeilen der linken
Spalte stehen ganz da. `shotcheck.py` zaehlt beides getrennt:
`reiterkurz 0  fliesskurz 0`).
