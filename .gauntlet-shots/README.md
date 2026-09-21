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
  Leiste aus 04/05/06/07 uebereinander, damit der Unterschied ohne Zoom
  sichtbar ist.

| Bild | Was es zeigt |
|---|---|
| 01-radius-0-scharfe-ecken.png | Seite "Darstellung" mit `radius=0`: rechte Winkel an Fenster, Knoepfen, Listen, Karten und Leistenknoepfen. Regler "Eckenrundung" steht auf 0. |
| 02-radius-12-mittel.png | Derselbe Stand mit `radius=12`, Zahlenanzeige 12. |
| 03-radius-24-weiche-kacheln.png | Derselbe Stand mit `radius=24`: sehr weiche Kacheln, Zahlenanzeige 24. Der Inhalt sitzt an genau derselben Stelle wie bei 0 (0 von 36 gemeldeten Rechtecken gewandert). |
| 04-taskleiste-100-deckend.png | Gemusterter heller Hintergrund, Leiste voll deckend: der Leistengrund ist EINE Farbe (`var 0`). Im Terminal steht korrekt `KEIN EINZIGES GERÄT!`, der Leistenknopf traegt "Terminal -- sh". |
| 05-taskleiste-70-prozent.png | Leiste bei 70 % Deckung, das Muster schlaegt durch (`var 1597`, 2 Farben im Grund). |
| 06-taskleiste-40-prozent.png | Leiste bei 40 %, staerker durchscheinend (`var 6389`). |
| 07-milchglas-blur12.png | Milchglas (`taskbar_blur=12`, 70 %): der Untergrund unter der Leiste ist weichgezeichnet (`var 788` gegen 1597 ohne), aus zwei Farben sind 13 geworden. Zeit je Vollbild: `us=47513`, Spitze 58932 (QEMU/TCG). |
| 08-settings-darstellung-regler.png | Reiter "Darstellung" mit den vier neuen Reglern (Eckenrundung 0-24, Taskleiste %, Fenster %, Milchglas) samt Zahlenanzeige; alles im Fenster, Abschnitt 8 gruen. |
| 09-settings-vorlagen.png | Reiter "Vorlage" (Vorlagenliste), zum Vergleich unveraendert. |
| 10-zug-hin-und-zurueck-keine-schlieren.png | Nach einem Zug des Fensters unter die Leiste UND zurueck: der Leistengrund ist Bildpunkt fuer Bildpunkt der des ungezogenen Laufs (`diff 0`) -- keine Schlieren. Der Name sagt, dass es der Zug MIT Rueckweg ist; die Endlage unter der Leiste zeigt Bild 22. |
| 11-dunkles-bild-leiste-soll40-wirkt82-kontrast.png | Dunkles Hintergrundbild, Regler auf 40 %. Der NAME sagt, was das Bild zeigt: die Lesbarkeitsschranke hebt die wirksame Deckkraft von **soll 40** auf **wirkt 82** (`wm: glas alpha_soll=40 alpha_ist=82`), damit die Leistenschrift 4,5:1 haelt; gemessen gegen den GEMISCHTEN Grund: 12,33:1. Als Beleg fuer DURCHSICHT bei 40 % taugt es deshalb nicht -- dafuer ist Bild 21 da. |
| 12-leiste-vergleich-ausschnitt-2x.png | ABGELEITET: Ausschnitt der Leiste aus 04/05/06/07 uebereinander, 2-fach vergroessert. Jede Zeile ist IM BILD beschriftet -- Reglerstellung und gemessene Streuung: `100 % deckend -- var 0`, `70 % -- var 1597`, `40 % -- var 6389`, `Milchglas (blur=12, 70 %) -- var 788`. Gebaut von `tools/themestore/leistenvergleich.py`, die Zahl gerechnet mit `glascheck`. |
| 22-zug-endlage-unter-der-leiste.png | Der zweite Zug-Lauf der Abnahme (ohne Rueckweg): das Fenster steht in seiner Endlage unter der Leiste, Schnittflaeche 16044 Bildpunkte (`wm: schlieren ... unterpx=16044`). `empty 0 cut 0 overlapping 0 linie 0`. |
| 13-fenster-transparenz-55-prozent.png | `window_alpha=55`: das Einstellungsfenster selbst ist durchsichtig, Muster und das Terminal darunter scheinen durch. Regler zeigt "Fenster deckend % 55%". |
| 14-milchglas-mit-reglerstand.png | Leiste 60 %, Fenster 80 %, Milchglas 12 -- die Reglerstellungen im Bild stimmen mit der Wirkung ueberein, die Leiste ist sichtbar verwischt. |
| 18-regler-zeigt-wirksames-alpha.png | Seite "Darstellung" ueber dem DUNKLEN Bild, Regler der Taskleiste auf 40 %: die Beschriftung lautet "Taskleiste deckend % (wirkt 82)" -- die Untergrenze wird angezeigt statt still zu wirken. |
| 19-zug-unter-die-leiste-neu.png | Zug auf 400,210 OHNE Rueckweg: das Fenster steht bei y=203 und reicht mit der Unterkante unter die Leiste (Schnittflaeche 16044 Bildpunkte, vom Server gerechnet). Der Rumpf ist vollstaendig gemalt, kein Rest steht. |
| 20-schmaler-schirm-1024x768-milchglas.png | ENGER SCHIRM (1024x768, `fbres=`), Leiste 70 % mit Milchglas 8: die Seite "Darstellung" passt auch hier vollstaendig ins Fenster, nichts ueberlappt. |
| 21-dunkelmod-leiste-40-durchsicht-var4218.png | Lauf `dunkelmod` des Abnahmelaufs (`scheme=midnight mode=dark tbalpha=40 wallpaper=dunkel`): dunkles Schema auf dunklem Bild. Hier liegt die Leistenfarbe nahe am Untergrund, der Schleier muss kaum anheben, und bei 40 % scheint das Schachbrett WIRKLICH durch -- gemessen `var 4218` bei zwei Farben im Leistengrund (die deckende Leiste hat `var 0`), und die Schrift haelt dabei ihre 4,5:1. Das ist die Aufnahme, auf der Reglerstellung 40 und Durchsicht zugleich gelten. |

Mechanische Pruefung (`tools/themestore/shotcheck.py`, gegen die Rechtecke,
die die Programme selbst gemeldet haben): fuer alle Laeufe dieses Satzes
`empty 0  cut 0  overlapping 0  ausserhalb 0  verdeckt 0`
(`gekuerzt 9` sind die absichtlich mit "..." verkuerzten Reiterbeschriftungen).
