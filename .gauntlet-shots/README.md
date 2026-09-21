# Aufnahmen der Runde GLAS

Alle Bilder sind ECHTE Aufnahmen des laufenden Systems: Osum startet in QEMU,
der Bildspeicher wird ueber den QEMU-Monitor als PPM abgezogen und nach PNG
gewandelt. Aufloesung 1280x800 (Bild 20: 1024x768).
Neu erzeugt am 21.09.2026 aus dem Zweig `glas`.

Herkunft:
* 01-12, 18, 19, 21 stammen aus dem Abnahmelauf `bash tools/themestore/run.sh`
  dieses Tages. Ergebnis des Laufs: **188 Zusagen, 0 rot**
  (Log: `/tmp/ts-run.log`, Beweisstuecke: `TS_OUT=/tmp/ts`).
* 13, 14, 20 sind drei zusaetzliche Laeufe mit demselben Verfahren
  (`tools/themestore/build.sh` mit anderen Reglerstellungen).
* 12 ist kein eigener Lauf, sondern ein 2-fach vergroesserter Ausschnitt der
  Leiste aus 04/05/06/07 und zwei Laeufen ueber dem groben Muster uebereinander, damit der Unterschied ohne Zoom
  sichtbar ist.

| Bild | Was es zeigt |
|---|---|
| 01-radius-0-scharfe-ecken.png | Seite "Darstellung" mit `radius=0`: rechte Winkel an Fenster, Knoepfen, Listen, Karten und Leistenknoepfen. Regler "Eckenrundung" steht auf 0. |
| 02-radius-12-mittel.png | Derselbe Stand mit `radius=12`, Zahlenanzeige 12. |
| 03-radius-24-weiche-kacheln.png | Derselbe Stand mit `radius=24`: sehr weiche Kacheln, Zahlenanzeige 24. Der Inhalt sitzt an genau derselben Stelle wie bei 0 (0 von 36 gemeldeten Rechtecken gewandert). |
| 04-taskleiste-100-deckend.png | Gemusterter heller Hintergrund, Leiste voll deckend: der Leistengrund ist EINE Farbe (`var 0`). Im Terminal steht korrekt `KEIN EINZIGES GERÄT!`, der Leistenknopf traegt "Terminal -- sh". |
| 05-taskleiste-70-prozent.png | Leiste bei 70 % Deckung, das Muster schlaegt durch (`var 1597`, 2 Farben im Grund). |
| 06-taskleiste-40-prozent.png | Leiste bei 40 %, staerker durchscheinend (`var 6389`). |
| 07-milchglas-blur16-grobes-muster.png | Milchglas, und diesmal SICHTBAR: dunkles Schema (`midnight`) auf dem GROBEN Muster (`wallpaper=dunkelgrob`, Schachbrett von 24 statt 12, also Felder von rund 160 Bildpunkten auf dem Schirm), Leiste bei 40 %, `taskbar_blur=16`. Der Streifen unter der Leiste ist ein Verlauf aus **36 Farben** (`var 3563`) gegen die **2 Farben** (`var 4102`) desselben Standes ohne Weichzeichner -- Bild 12, die zwei untersten Reihen. BEFUND, der zu dieser Neuaufnahme gefuehrt hat: die alte Aufnahme (`blur=12` ueber dem feinen Muster, hell) war gemessen richtig (`var 788` gegen 1597) und angeschaut fast nichts -- der Weichzeichner verwischte nur die Naehte eines Schachbretts, dessen Felder achtzig Bildpunkte breit sind, und ueber einem hellen Bild hebt `glass_mix` die Deckkraft ausserdem auf 82 an. Zeit je Vollbild: `us=42923`, Spitze 49335 (QEMU/TCG). |
| 08-settings-darstellung-regler.png | Reiter "Darstellung" mit den vier neuen Reglern (Eckenrundung 0-24, Taskleiste %, Fenster %, Milchglas) samt Zahlenanzeige; alles im Fenster, Abschnitt 8 gruen. |
| 09-settings-vorlagen.png | Reiter "Vorlage" (Vorlagenliste), zum Vergleich unveraendert. |
| 10-zug-hin-und-zurueck-keine-schlieren.png | Nach einem Zug des Fensters unter die Leiste UND zurueck: der Leistengrund ist Bildpunkt fuer Bildpunkt der des ungezogenen Laufs (`diff 0`) -- keine Schlieren. Der Name sagt, dass es der Zug MIT Rueckweg ist; die Endlage unter der Leiste zeigt Bild 22. |
| 11-dunkles-bild-leiste-soll40-wirkt82-kontrast.png | Dunkles Hintergrundbild, Regler auf 40 %. Der NAME sagt, was das Bild zeigt: die Lesbarkeitsschranke hebt die wirksame Deckkraft von **soll 40** auf **wirkt 82** (`wm: glas alpha_soll=40 alpha_ist=82`), damit die Leistenschrift 4,5:1 haelt; gemessen gegen den GEMISCHTEN Grund: 12,33:1. Als Beleg fuer DURCHSICHT bei 40 % taugt es deshalb nicht -- dafuer ist Bild 21 da. |
| 12-leiste-vergleich-ausschnitt-2x.png | SECHS Ausschnitte der Leiste uebereinander, 2-fach vergroessert, jede Reihe IM BILD beschriftet mit ihrer Reglerstellung UND der gemessenen Streuung: `100 % deckend -- var 0, 1 Farbe`, `70 % -- var 1597, 2`, `40 % -- var 6389, 2`, `Milchglas (blur=12, 70 %) -- var 788, 13`, `dunkles Schema, 40 %, grobes Muster, ohne Milchglas -- var 4102, 2`, `dasselbe mit Milchglas 16 -- var 3563, 36`. Die letzten zwei Reihen sind das Paar, das den Bildvergleich traegt: harte Kacheln gegen einen Verlauf. Gebaut von `tools/themestore/leistenvergleich.py` aus den Aufnahmen desselben Laufs; die Zahlen kommen aus `glascheck.leiste`/`hell`, und der Lauf haelt Bild und Messung Zahl fuer Zahl gegeneinander. |
| 22-zug-endlage-unter-der-leiste.png | Der zweite Zug-Lauf der Abnahme (ohne Rueckweg): das Fenster steht in seiner Endlage unter der Leiste, Schnittflaeche 16044 Bildpunkte (`wm: schlieren ... unterpx=16044`). `empty 0 cut 0 overlapping 0 linie 0`. |
| 13-fenster-transparenz-55-prozent.png | `window_alpha=55` ueber dem gemusterten Bild: das Einstellungsfenster selbst ist durchsichtig, das Muster schlaegt durch. NEU AUFGENOMMEN nach fix-r3-2: die Lesbarkeitsschranke fuer Fenster ist halb so weit wie die der Leiste (`SCHLEIER_WIN=20`), deshalb laeuft die Ausgabe des Terminals darunter nicht mehr durch die Reiterzeile -- sie bleibt ein Schatten zwischen den Zeilen. Gemessen (`glascheck.py fenster`): 31 Beschriftungen, schlechtestes Paar 5,16:1, die Reiter 6,34:1 (vorher 5,26:1). |
| 14-milchglas-mit-reglerstand.png | Leiste 60 %, Fenster 80 %, Milchglas 12 -- die Reglerstellungen im Bild stimmen mit der Wirkung ueberein, die Leiste ist sichtbar verwischt. |
| 18-regler-zeigt-wirksames-alpha.png | Seite "Darstellung" ueber dem DUNKLEN Bild, Regler der Taskleiste auf 40 %: die Beschriftung lautet "Taskleiste deckend % (wirkt 82)" -- die Untergrenze wird angezeigt statt still zu wirken. |
| 19-zug-unter-die-leiste-neu.png | Zug auf 400,210 OHNE Rueckweg: das Fenster steht bei y=203 und reicht mit der Unterkante unter die Leiste (Schnittflaeche 16044 Bildpunkte, vom Server gerechnet). Der Rumpf ist vollstaendig gemalt, kein Rest steht. |
| 20-schmaler-schirm-1024x768-milchglas.png | ENGER SCHIRM (1024x768, `fbres=`), Leiste 70 % mit Milchglas 8: die Seite "Darstellung" passt auch hier vollstaendig ins Fenster, nichts ueberlappt. |
| 21-dunkelmod-leiste-40-durchsicht-var4218.png | Lauf `dunkelmod` des Abnahmelaufs (`scheme=midnight mode=dark tbalpha=40 wallpaper=dunkel`): dunkles Schema auf dunklem Bild. Hier liegt die Leistenfarbe nahe am Untergrund, der Schleier muss kaum anheben, und bei 40 % scheint das Schachbrett WIRKLICH durch -- gemessen `var 4218` bei zwei Farben im Leistengrund (die deckende Leiste hat `var 0`), und die Schrift haelt dabei ihre 4,5:1. Das ist die Aufnahme, auf der Reglerstellung 40 und Durchsicht zugleich gelten. |

Mechanische Pruefung (`tools/themestore/shotcheck.py`, gegen die Rechtecke,
die die Programme selbst gemeldet haben): fuer alle Laeufe dieses Satzes
`empty 0  cut 0  overlapping 0  ausserhalb 0  verdeckt 0`
(`gekuerzt 0`: seit dem Umbau der Reiterleiste auf ZWEI ZEILEN muss kein
einziger Reitername mehr gekuerzt werden -- vorher waren es neun von elf --,
und die drei gekuerzten Fliesstextzeilen der linken Spalte stehen ganz da,
weil die Spalte von 300 auf 340 Bildpunkte gewachsen ist. `shotcheck.py`
zaehlt beides seither getrennt: `reiterkurz 0  fliesskurz 0`).
