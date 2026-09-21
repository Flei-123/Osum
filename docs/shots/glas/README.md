# Aufnahmen der Runde GLAS

Alle Bilder sind ECHTE Aufnahmen des laufenden Systems: Osum startet in QEMU,
der Bildspeicher wird ueber den QEMU-Monitor als PPM abgezogen
(`tools/gfx/screenshot.py`) und nach PNG gewandelt. Aufloesung 1280x800.
Erzeugt am 21.09.2026 aus dem Zweig `glas`.

Herkunft:
* 01-11, 19, 21 und 22 stammen aus dem Abnahmelauf
  `bash tools/themestore/run.sh`; sein vollstaendiger Mitschnitt liegt als
  `belege/glas-run.log`, und die Schlusszeile dieser Datei
  (`tail -1 belege/glas-run.log`) ist das Ergebnis des Laufs, aus dem die
  hier liegenden Bilder stammen.
* 13-15 sind drei zusaetzliche Laeufe mit demselben Verfahren
  (`tools/themestore/build.sh` mit anderen Reglerstellungen).
* 12 ist kein eigener Lauf, sondern ein 2-fach vergroesserter Ausschnitt
  der Leiste aus 04/05/06/07 nebeneinander, damit der Unterschied ohne
  Zoom sichtbar ist.

Die Zahlen zu diesen Bildern stehen in [`docs/RUNDE-GLAS.md`](../../RUNDE-GLAS.md),
auch die, die nicht erreicht wurden.

**EIN BELEGPFAD, UND ZWAR DIESER** (fix-r4-2): der vollstaendige
Mitschnitt des Laufs, aus dem die hier liegenden Bilder stammen, ist als
[`belege/glas-run.log`](../../../belege/glas-run.log) eingecheckt. Jede
Zahl in der Tabelle unten ist eine Zeile dieser Datei — nachzuschlagen
mit `grep` und dem Suchwort, das daneben steht. Vorher standen die
Zahlen dreier verschiedener Laeufe nebeneinander (im Bild 08 "74
Rechtecke", im Blatt "100, gefordert >= 88"); beide waren zu ihrer Zeit
richtig und zusammen unbrauchbar.

| Bild | Was es zeigt |
|---|---|
| 01-radius-0-scharfe-ecken.png | Einstellungen mit `radius=0`: rechte Winkel ueberall, wie frueher `shape=classic`. Ecke: tiefe 0, Mischtoene 0. |
| 02-radius-12-mittel.png | Derselbe Stand mit `radius=12`. Ecke: tiefe 10, 8 Zeilen mit Mischton. |
| 03-radius-24-weiche-kacheln.png | Derselbe Stand mit `radius=24`, Regler zeigt "24". Ecke: tiefe 32, 18 Zeilen mit Mischton. Inhalt sitzt an derselben Stelle wie bei 0 (0 von 36 Rechtecken gewandert). |
| 04-taskleiste-100-deckend.png | Gemusterter Hintergrund, Leiste voll deckend -- der Leistengrund ist EINE Farbe (`var 0`, farben 1). |
| 05-taskleiste-70-prozent.png | Leiste bei 70 % Deckung, das Muster schlaegt durch (`var 1597`, farben 2). Wirksam sind 85 bzw. 100 % -- siehe die Anmerkung unten. |
| 06-taskleiste-40-prozent.png | Leiste bei 40 %, deutlich staerker durchscheinend (`var 6389`, farben 2). Wirksam 71 bzw. 100 %. |
| 07-milchglas-unter-durchsichtigem-fenster.png | **Milchglas, und diesmal unter einer FLAECHE statt unter einem Streifen** (fix-r4-4). Dunkles Schema (`midnight`) auf dem GROBEN Muster (`wallpaper=dunkelgrob`, Schachbrett von 24, also Felder von rund 160 Bildpunkten), das Einstellungsfenster mit `window_alpha=25` und `taskbar_blur=16`: der Weichzeichner liegt jetzt auch unter einem durchsichtigen FENSTER (`wm.paint_win`, 430 160 Bildpunkte je Vollbild statt der 35 840 der Leiste), und man sieht ihn ohne Lupe -- innerhalb des Fensters sind die Kanten des Schachbretts weiche Verlaeufe, daneben auf dem Schreibtisch stehen sie messerscharf. Gemessen im Ausschnitt des Fensterrumpfes (x 28..772, y 549..567): **var 655 mit 22 Farben** gegen **var 717 mit 14 Farben** bei sonst gleichem Lauf mit `taskbar_blur=2` -- die Streuung sinkt, und aus der Kante ist ein Verlauf geworden. `shotcheck.py`: `empty 0 cut 0 overlapping 0 ausserhalb 0`. BEFUND, der zu dieser Neuaufnahme gefuehrt hat: die Leiste ist 28 Bildpunkte hoch -- darauf MISST man einen Weichzeichner, man SIEHT ihn nicht. Der Vergleich der Leistenstreifen mit und ohne Milchglas steht weiterhin in Bild 12 (die zwei untersten Reihen), es geht also kein Beleg verloren. |
| 08-settings-darstellung-regler.png | Reiter "Darstellung" mit den vier neuen Reglern (Eckenrundung 0-24, Taskleiste %, Fenster %, Milchglas) samt Zahlenanzeige; alles im Fenster. Die Zahl dazu kommt aus dem Mitschnitt und nicht mehr aus der Erinnerung an einen frueheren Lauf: `grep 'Rechtecke beider Seiten' belege/glas-run.log` sagt **88 gemeldete** und **100 gemessene** Rechtecke (gemessen wird jedes gemeldete ausser `win`, also auch die mit einem Sachnamen), **0 ragen heraus**. Die "74", die hier bis fix-r4-2 stand, war die Zahl EINER Seite aus einem aelteren Lauf. |
| 09-settings-vorlagen.png | Reiter "Vorlagen" (Vorlagenliste), **neu aufgenommen nach fix-r3-3**. Flaeche und Rahmen jeder Vorschaukachel kommen jetzt aus derselben Eckendeckung (`wlibc.rrect`/`wlibc.rring`, gleicher Radius 12, gleiche Kanten) statt aus dem Vektorrasterer unter einem Rahmen: auf dem alten Bild stand deshalb mitten in der Kachel "Mitternacht" ein heller Keil von acht Bildpunkten (x=331..338, Zeilen 229..233) -- eine runde Ecke, die `fuib.tafel` an der Kante des Malbands in die Flaeche gemalt hat. Gemessen mit `glascheck.py kachel`: `innen` vorher 7 bzw. 6 auf zwei Kacheln, jetzt **0 auf allen zehn**, `fremd 0`, `tiefe 7`. Der Name ist Zeichen fuer Zeichen da (`namecheck.py`: gemalt 10, fehlt 0, gekuerzt 0, ohnetinte 0) -- dass "Mitternacht" wie "Mittemacht" aussieht, ist das Schriftbild selbst: der Arm des 'r' reicht bei 15 px in die Schulter des 'n' (Unterschneidung -36/64 px). `shotcheck.py`: `empty 0 cut 0 overlapping 0 gekuerzt 0 ausserhalb 0 knopf 6 ohnekante 0`. |
| 10-zug-hin-und-zurueck-keine-schlieren.png | Nach einem Zug des Fensters unter die Leiste **und zurueck** -- der Leistengrund ist Bildpunkt fuer Bildpunkt der des ungezogenen Laufs (`diff 0`). Der NAME sagt jetzt, was das Bild ist: ein Beleg fuer die Schlierenfreiheit und ausdruecklich KEINER fuer den Fall, in dem das Fenster unter der Leiste liegen bleibt -- den zeigt Bild 22, das derselbe Abnahmelauf aufnimmt. |
| 11-dunkles-bild-leiste-soll40-wirkt82-kontrast.png | Dunkles Hintergrundbild, Regler auf 40 %. Der NAME sagt, was das Bild zeigt: die Lesbarkeitsschranke hebt die wirksame Deckkraft von **soll 40** auf **wirkt 82** (`wm: glas alpha_soll=40 alpha_ist=82`), damit die Leistenschrift 4,5:1 haelt; gemessen gegen den GEMISCHTEN Grund: 12,33:1. Als Beleg fuer DURCHSICHT bei 40 % taugt es deshalb nicht -- dafuer ist Bild 21 da. |
| 12-leiste-vergleich-ausschnitt-2x.png | SECHS Ausschnitte der Leiste uebereinander, 2-fach vergroessert, jede Reihe IM BILD beschriftet mit ihrer Reglerstellung UND der gemessenen Streuung: `100 % deckend -- var 0, 1 Farbe`, `70 % -- var 1597, 2`, `40 % -- var 6389, 2`, `Milchglas (blur=12, 70 %) -- var 788, 13`, `dunkles Schema, 40 %, grobes Muster, ohne Milchglas -- var 4102, 2`, `dasselbe mit Milchglas 16 -- var 3563, 36`. Die letzten zwei Reihen sind das Paar, das den Bildvergleich traegt: harte Kacheln gegen einen Verlauf. Gebaut von `tools/themestore/leistenvergleich.py` aus den Aufnahmen desselben Laufs; die Zahlen kommen aus `glascheck.leiste`/`hell`, und der Lauf haelt Bild und Messung Zahl fuer Zahl gegeneinander. |
| 22-zug-endlage-unter-der-leiste.png | Derselbe Versuch, aber WEIT: `click=400,10>600,600` (Abschnitt 11f3). Ohne die Klemmung haenge das Fenster zu drei Vierteln unter dem Bildrand -- das war Bild 15 der Runde. Hier steht es in seiner Endlage vollstaendig auf dem Arbeitsbereich (`wm: geklemmt ... x=220 y=182 vory=593`), um 200 Bildpunkte nach rechts versetzt gegenueber Bild 19, und zeigt damit dieselbe Regel in beiden Richtungen. Gemessen: `empty 0 cut 0 overlapping 0 ausserhalb 0 verdeckt 0`, vier von vier Reglerzeilen ganz ueber der Leiste. |
| 13-fenster-transparenz-55-prozent.png | `window_alpha=55` ueber dem gemusterten Bild: das Einstellungsfenster selbst ist durchsichtig, das Muster schlaegt durch. NEU AUFGENOMMEN nach fix-r4-2: die Deckung sitzt jetzt unter der SCHRIFT und nicht mehr ueber der Flaeche (`SCHLEIER_WIN` ist 0, dafuer traegt jede Textzeile ihre eigene deckende Platte, `wlibc.platte`). Die Reiterzeile ist als Ganzes deckend -- **4341 Kanten gegen 4341** im Lauf mit `window_alpha=100`, und das Band ist Bildpunkt fuer Bildpunkt dasselbe (`diff 0`) --, waehrend der Rumpf desselben Bildes sich in **5132** von 41 000 abgetasteten Bildpunkten vom deckenden Lauf unterscheidet. Gemessen (`glascheck.py fenster`): 31 Beschriftungen, schlechtestes Paar 5,16:1 (die ausgewaehlte Listenzeile auf der Akzentfarbe, kein Fall von Transparenz). |
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
| 19-zug-unter-die-leiste-neu.png | Der Zug OHNE Rueckweg aus dem Abnahmelauf (Abschnitt 11f2/11f3, `click=400,10>400,210`). Das Fenster wird unter die Leiste gezogen -- die Schnittflaeche rechnet der Server selbst (`grep 'wm: schlieren' belege/glas-run.log`, `unterpx=16044`; im ungezogenen Lauf steht dort 0) --, beim LOSLASSEN holt `wm.drag_klemmen` die Endlage aber auf die Arbeitsflaeche zurueck: `wm: geklemmt id=12 x=20 y=182 vory=203 w=764 h=590`. Deshalb steht das Fenster hier bei y=182 und nicht mehr bei y=203, und der Reglerblock der Seite ist vollstaendig zu sehen. Gemessen: **31 Beschriftungen**, `empty 0 cut 0 overlapping 0 ausserhalb 0 verdeckt 0`, vier von vier Reglerzeilen ganz ueber der Leiste, und keine einzige `wm: zieh`-Zeile -- gezogen wurde, nicht in der Groesse veraendert. |
| 21-dunkelmod-leiste-40-durchsicht-var4218.png | Lauf `dunkelmod` des Abnahmelaufs (`scheme=midnight mode=dark tbalpha=40 wallpaper=dunkel`): dunkles Schema auf dunklem Bild. Hier liegt die Leistenfarbe nahe am Untergrund, der Schleier muss kaum anheben, und bei 40 % scheint das Schachbrett WIRKLICH durch -- gemessen `var 4218` bei zwei Farben im Leistengrund (die deckende Leiste hat `var 0`), und die Schrift haelt dabei ihre 4,5:1. Das ist die Aufnahme, auf der Reglerstellung 40 und Durchsicht zugleich gelten. |
