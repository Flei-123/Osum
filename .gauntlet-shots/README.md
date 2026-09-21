# Aufnahmen der Runde GLAS (neu erzeugt am 21.09.2026)

Alle Bilder sind ECHTE Aufnahmen des laufenden Systems: Osum startet in QEMU,
der Bildspeicher wird ueber den QEMU-Monitor als PPM abgezogen und nach PNG
gewandelt. Aufloesung 1280x800, Bild 20 mit 1024x768, Bild 12 ist ein
zusammengesetzter Ausschnittstreifen.

Herkunft:
* 01-13, 18, 19, 21-23 stammen aus EINEM Abnahmelauf dieses Tages
  (`TS_OUT=/tmp/ts bash tools/themestore/run.sh`, Mitschnitt
  `/tmp/glas-shot-run.log`). Ergebnis des Laufs: **312 Zusagen, 0 rot**.
  Bild und Zahl kommen damit aus demselben Durchgang.
* 14 und 20 sind zwei zusaetzliche Laeufe mit demselben Verfahren
  (`tools/themestore/build.sh` mit anderen Reglerstellungen bzw. mit
  `fbres=1024x768`).
* Kein Bild ist die Kopie eines anderen: alle 20 Dateien haben eine eigene
  Pruefsumme.

Mechanisch geprueft mit `tools/themestore/shotcheck.py` gegen die Rechtecke,
die die Programme selbst gemeldet haben -- fuer JEDE der 20 Aufnahmen:
`empty 0  cut 0  overlapping 0  gekuerzt 0  ausserhalb 0  verdeckt 0`.

| Bild | Was es zeigt |
|---|---|
| 01-radius-0-scharfe-ecken.png | Seite "Darstellung" mit `radius=0`: rechte Winkel an Fenster, Knoepfen, Listen, Karten und Leistenknoepfen. Regler "Eckenrundung" steht auf 0. |
| 02-radius-12-mittel.png | Derselbe Stand mit `radius=12`, Zahlenanzeige 12, kantengeglaettete Rundung. |
| 03-radius-24-weiche-kacheln.png | Derselbe Stand mit `radius=24`: sehr weiche Kacheln, Zahlenanzeige 24 -- der Inhalt sitzt an genau derselben Stelle wie bei 0. |
| 04-taskleiste-100-deckend.png | Gemusterter heller Hintergrund, Leiste voll deckend: der Leistengrund ist EINE Farbe (`var 0`). |
| 05-taskleiste-70-prozent.png | Leiste bei 70 % Deckung, das Muster schlaegt durch (`var 3594`). |
| 06-taskleiste-40-prozent.png | Leiste bei 40 %, deutlich staerker durchscheinend (`var 14376`). |
| 07-milchglas-unter-durchsichtigem-fenster.png | Dunkles Schema, grobes Muster, `window_alpha=25` und `taskbar_blur=16`: der Weichzeichner liegt unter einer FLAECHE (430 160 Bildpunkte je Vollbild) -- im Fenster sind die Schachbrettkanten weiche Verlaeufe, daneben messerscharf. |
| 08-settings-darstellung-regler.png | Reiter "Darstellung" mit den vier neuen Reglern (Eckenrundung 0-24, Taskleiste %, Fenster %, Milchglas) samt Zahlenanzeige; Abschnitt 8 gruen, 0 Widgets ragen heraus. |
| 09-settings-vorlagen.png | Reiter "Vorlagen" zum Vergleich. |
| 10-zug-hin-und-zurueck-keine-schlieren.png | Nach einem Zug des Fensters unter die Leiste UND zurueck: der Leistengrund ist Bildpunkt fuer Bildpunkt der des ungezogenen Laufs (`0` stehengebliebene Bildpunkte). |
| 11-dunkles-bild-leiste-soll40-wirkt82-kontrast.png | Dunkles Hintergrundbild, helle Leiste, Regler auf 40 %: die Lesbarkeitsschranke hebt die wirksame Deckkraft an, damit die Leistenschrift 4,5:1 haelt (gemessen 12,67:1 gegen den GEMISCHTEN Grund). |
| 12-leiste-vergleich-ausschnitt-2x.png | SECHS Leistenausschnitte uebereinander, 2-fach vergroessert, jede Reihe IM BILD beschriftet mit Reglerstellung und gemessener Streuung: `100 % -- var 0`, `70 % -- var 3594`, `40 % -- var 14376`, `Milchglas (blur=12, 70 %) -- var 788`, `dunkel/grob ohne Milchglas -- var 4102`, `dasselbe mit Milchglas 16 -- var 3563`. |
| 13-fenster-transparenz-55-prozent.png | `window_alpha=55` ueber dem gemusterten Bild: das Fenster selbst ist durchsichtig, Muster und Terminalausgabe schlagen durch, die Beschriftungen bleiben lesbar. |
| 14-milchglas-mit-reglerstand.png | Eigener Lauf: Leiste 60 %, Fenster 80 %, Milchglas 12, Radius 10 (`settings: glas radius=10 tba=60 wa=80 blur=12 ist=65`) -- die Zahlenanzeige und die Beschriftung "(wirkt 67)" stimmen mit der Wirkung ueberein. |
| 18-regler-zeigt-wirksames-alpha.png | Seite "Darstellung" ueber dem DUNKLEN Bild, Taskleiste auf 40 %: die Beschriftung nennt die wirksame Deckkraft -- die Untergrenze wirkt nicht still, sie wird angezeigt. |
| 19-zug-unter-die-leiste-neu.png | Zug OHNE Rueckweg, tiefer: die Unterkante des Fensters liegt unter der Leiste, die Leiste ist darueber neu gemischt, der zurueckgelassene Schreibtisch ist saubere Musterflaeche -- keine Schliere. |
| 20-schmaler-schirm-1024x768-milchglas.png | ENGER SCHIRM (1024x768): Leiste 70 % mit Milchglas 8 (`ist=74`), Radius 14 -- die Seite "Darstellung" passt auch hier vollstaendig ins Fenster. |
| 21-dunkelmod-leiste-40-durchsicht.png | Dunkles Schema auf dunklem Bild, Leiste 40 %: hier muss der Schleier kaum anheben, das Schachbrett scheint wirklich durch, und die Schrift haelt trotzdem ihre 4,5:1. |
| 22-zug-endlage-unter-der-leiste.png | Der Zug-Lauf der Abnahme in seiner Endlage unter der Leiste. |
| 23-milchglas-verlauf-feines-muster.png | Milchglas ueber dem FEINEN Muster: aus den zwei Stufen des Musters wird ein Verlauf (`var` sinkt messbar). |
