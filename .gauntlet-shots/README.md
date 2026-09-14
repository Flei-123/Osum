# Bilder der Runde WMPLUGIN

Alle Bilder stammen aus WIRKLICH gebooteten Kernen (QEMU, `-vga std`,
Foto ueber den QEMU-Monitor mit `tools/gfx/screenshot.py`, PPM nach PNG
mit `tools/gfx/ppm2png.py`). Erzeugt von `tools/wmplug/shots.sh`; die
Bilder 09/10 kommen aus dem Abnahmelauf `tools/wmplug/run.sh`
(139 bestanden, 0 gescheitert).

| Bild | Was es zeigt |
|---|---|
| 01-start-ohne-plugin.png | Schreibtisch mit Leiste, Kommandozeile `... plugaus` -- die Plugintafel ist ZU. Rechts in der Leiste steht NUR die Uhr des Systems. |
| 02-uhr-widget-an.png | Dasselbe Bild mit angemeldetem Ring-3-Plugin `/bin/pluguhr`: rechts in der Leiste steht sein Text `18:33 cpu 100%`. Im Terminal die Anmeldung, die Frist (`frist ticks=50`) und die VERWEIGERUNG `barget verweigert r=-2`. |
| 03-uhr-widget-aus-zur-laufzeit.png | Derselbe Lauf, spaeter: das Plugin hat sich abgemeldet (`ende runden=12`), der Widget-Text in der Leiste ist WEG -- ohne Neustart des Fensterservers. Bildpaar 02/03 ist der Sichtbeweis fuer "an und aus zur Laufzeit". |
| 04-fensterregel-mit-recht.png | Regel-Plugin `/bin/plugregel` MIT Recht: liest `/etc/wmregeln.conf` (2 Regeln), meldet sich an (`rechte=259`), greift auf ein fremdes Fenster zu (`lesefenster id=11`). |
| 05-fensterregel-ohne-recht.png | Derselbe Lauf OHNE Recht -- zum Vergleich daneben legen. |
| 06-breit-1440x900.png | Breiter Schirm (`fbres=1440x900`): Leiste ueber die volle Breite, Widget-Text rechts, Fenster oben links. |
| 07-eng-800x600.png | Vorgabe-Schirm 800x600 mit Widget. |
| 08-sehr-eng-640x480.png | Enger Schirm 640x480 -- hier zeigt sich, ob Leiste und Fenster einander ins Gehege kommen. |
| 09-wmplug-verwaltung.png | `/bin/wmplug list` + `info uhr` im Terminal, mit ZWEI gleichzeitig angemeldeten Plugins (`uhr` 0x807, `regel` 0x301): Fassung `abi=1`, Statuszeile auf zwei Zeilen umgebrochen, Tabellenkopf ueber seinen Werten. Neu aufgenommen von `tools/wmplug/spalten.sh` (24 bestanden, 0 gescheitert); dasselbe Bild liegt als `docs/shots/wmplug/spalten-zwei-plugins.png`. |
| 10-nach-plugin-absturz.png | Nach einem absichtlichen SIGSEGV eines Plugins: der Schreibtisch malt weiter (479819 von 480000 Bildpunkten nicht schwarz, gemessen im Abnahmelauf). |

## Was auf den Bildern AUFFAELLT (nicht behauptet, sondern sichtbar)

- In allen Bildern steht im Terminal `KEIN EINZIGES GERT!` -- das `AE`
  faellt beim Malen weg (Umlaut im Text der USB-Meldung).
- Bild 09 ZEIGTE, dass `wmplug list` die Zeilen am Fensterrand statt am
  Wort brach (`... Frist 50 Ticks  Flaeche` / `0` auf der naechsten
  Zeile) und dass `Leistentext14` Beschriftung und Zahl zusammenklebte.
  BEHOBEN und neu fotografiert: die Statuszeile sind jetzt zwei Zeilen
  von 30 und 27 Zeichen, die Beschriftungen von `info` stehen alle auf
  Spalte 14, und der Tabellenkopf kommt aus denselben Breitenkonstanten
  wie die Datenzeile. Nachgerechnet wird das am BILD, nicht am Quelltext:
  `checkshot.py tgrid` findet `Rechte` ab Spalte 13 und `0x807` ab
  Spalte 14 -- dieselbe Endspalte 18 (tools/wmplug/spalten.sh).
- Bild 03: zwei Schreiber teilen sich eine Zeile
  (`uhrstart: wmplug enable=wmplug: uhr rechte=0x807`).
- Bild 08 (640x480): das Fenster reicht bis an den rechten Schirmrand;
  eng wird es, aber es ueberlappt die Leiste nicht.
