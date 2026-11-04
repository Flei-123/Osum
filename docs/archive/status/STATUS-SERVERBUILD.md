# STATUS SERVERBUILD -- ABGESCHLOSSEN

Zweig `serverbuild`, abgezweigt von `mergeline` (4f844b5). NICHT nach main.

Ziel: Osum soll auch als SERVERBETRIEBSSYSTEM taugen -- ohne Grafik
gebaut, mit einer seriellen Konsole, die ein richtiges Terminal ist.

## Ausgangslage, gemessen

- Kernel gesamt: 72 925 Zeilen in `kernel/*.fi`
- Grafik im Kernel: `fb.fi` 2504, `wm.fi` 3908, `wig.fi` 679,
  `font.fi` -- die vier aus der Aufgabe zusammen 7091 Zeilen, 9,7 %.
  Im selben Sinn Grafik sind `ttf.fi` 1563, `tile.fi` 2918,
  `vmode.fi` 1540, `ansi.fi`, `ps2m.fi` 650; alle neun zusammen
  **14 109 Zeilen, 19,3 % des Kernels**.
- Kein Bauschalter: `grep -riE 'nogui|headless|console_only'` -> 0 Treffer.
- GUI-Abbild vor dieser Runde: **2 833 252 Oktett** (Stufe 0).
- Die serielle Leitung war eine EINBAHNSTRASSE. `serial.put` schickte
  seit Runde 59 hinaus, einen Empfangsweg gab es nicht -- getippt wurde
  auf der PS/2-Tastatur (`kbd.fi`, IRQ 1) oder ueber `script=`.

## Die Zahl, nach der die Aufgabe fragt

`tools/server/count.py` wirft die Kommentare weg und zaehlt nur Code:

| Datei | vorher | nachher |
|---|---:|---:|
| `kernel/kmain.fi` | 493 | 0 |
| `kernel/sys.fi` | 227 | 0 |
| `kernel/pwr.fi` | 11 | 0 |
| `kernel/usb.fi` | 6 | 0 |
| `kernel/kbd.fi` | 3 | 0 |
| `kernel/arch/x86_64/trap.fi` | 3 | 0 |
| `kernel/serial.fi` | 1 | 0 |
| `kernel/tty.fi` | 1 | 0 |
| **Summe** | **745 Stellen in 8 Dateien, 329 verschiedene Funktionen** | **0** |

**Die Zahl, die sagt, wie sauber der Schnitt ist, ist nicht 745.**
`kmain.fi` und `sys.fi` greifen nicht auf die Grafik zu, sie SIND die
Oberflaeche: das Einrichten beim Start und die Aufrufnummern fuer
Ring 3. Der uebrige Kernel -- Speicher, Dateisystem, Netz, Zeitplaner,
Signale, Prozesse, USB, NVMe, Hypervisor, Krypto, sechzig Module --
beruehrt Grafik an **25 Stellen in 6 Dateien**. Darum ging der Schnitt
so glatt.

## Was gebaut wurde

| Datei | Zeilen | was |
|---|---:|---|
| `kernel/gfx.fi` | 270 | DIE NAHT. 37 Symbole. Das einzige Modul, das `fb`, `wm`, `wig`, `font`, `ttf`, `tile`, `vmode`, `ansi`, `ps2m` einbindet. |
| `kernel/gfx-aus.fi` | 181 | dieselben 37 Symbole, leer. `ready` sagt `false`, die vier Aufrufbereiche geben -ENOSYS. |
| `kernel/kgui.fi` | 2635 | die 41 Grafikfunktionen aus `kmain.fi` |
| `kernel/sysgui.fi` | 1206 | die 15 Grafik-Aufrufnummern aus `sys.fi` (wm, wig, tile, disp) |
| `kernel/kutil.fi` | 92 | die fuenf Helfer, die `kmain.fi` und `kgui.fi` sich teilen |
| `kernel/sercon.fi` | 279 | DIE SERIELLE KONSOLE. IRQ 4 auf Vektor 36, FIFO in die Zeilendisziplin, `console=ttyS0` |
| `tools/config` | 38 | die Baukonfiguration: `gui=on\|off`, `tunnel=on\|off` |
| `tools/server/build.sh` | 105 | Kern (gui=off) + Server-Userland + OFS-Platte |
| `tools/server/run.sh` | 286 | Abschnitt 30 der Abnahme |
| `tools/server/console.py` | 138 | ein Mensch an der Leitung: warten, tippen, lesen |
| `tools/server/count.py` | 80 | zaehlt die Grafikzugriffe nach |
| `tools/server/moved.py` | 108 | rechnet nach, dass der Umzug ein Umzug war |

Kein `#ifdef`, keine Verzweigung zur Laufzeit. `--gui off` LOESCHT elf
Dateien aus dem Uebersetzungsbaum und legt `gfx-aus.fi` an die Stelle
von `gfx.fi` -- derselbe Griff, mit dem `--ohne-tunnel` seit Runde
TUNNEL `wg.fi` durch `wg-aus.fi` ersetzt.

**Der Umzug ist ein Umzug, und das ist nachgerechnet**
(`tools/server/moved.py 4f844b5`, laeuft als Zusage im Abschnitt mit):

```
  kgui.fi     41 von 41 Funktionen zeichengleich mit kmain.fi
  kutil.fi     5 von  5 Funktionen zeichengleich mit kmain.fi
  sysgui.fi   15 von 15 Funktionen zeichengleich mit sys.fi
```

Erlaubt ist dabei genau die eine Abweichung, die der Umzug erzwingt
(`neg` -> `sys.neg`, `bnum` -> `kutil.bnum`); jede andere faellt auf.

Was NICHT mitgezogen ist: die 139 KONSTANTEN der Oberflaeche. Sie sind
die ABI -- die Nummern, die Ring 3 schreibt -- und `kernel/sys.fi` ist
die Tafel, an der Ring 3 anklopft. Beim ersten Anlauf zogen sie mit,
und drei Abschnitte der Abnahme sagten sofort, warum das nicht geht
(`tools/display` zaehlt drei Nummern aus 1810..1819 in `sys.fi` nach,
`tools/desktop` sucht `WM_MAXNR` dort, `tools/k15` sucht `WIG_MAXNR`).

## Zahlen

| | Oktett |
|---|---:|
| GUI-Abbild, Grundlinie (mergeline 4f844b5) | 2 833 252 |
| GUI-Abbild nach dieser Runde | 2 849 604 |
| Aufschlag fuer die Naht | +16 352 (+0,58 %) |
| **Serverabbild (gui=off)** | **2 109 692** |
| **Unterschied gui=on zu gui=off** | **739 912 Oktett (25,96 %)** |

Und die Gegenprobe, die aus dem Unterschied einen Beweis macht -- die
Symboltafel des gebundenen ELF. Ein Schalter, der nur zur Laufzeit
verzweigt, waere hier nicht zu unterscheiden:

| Modul | GUI-Abbild | Serverabbild |
|---|---:|---:|
| wm | 174 | 0 |
| tile | 133 | 0 |
| fb | 122 | 0 |
| ttf | 79 | 0 |
| vmode | 75 | 0 |
| kgui | 44 | 0 |
| ps2m | 41 | 0 |
| wig | 26 | 0 |
| ansi | 16 | 0 |
| sysgui | 15 | 0 |
| font | 14 | 0 |
| **Summe Oberflaeche** | **739** | **0** |
| gfx (die Naht) | 37 | 37 |

Serverplatte: 59 Programme, 3 084 376 Oktett, OFS-Abbild 10 485 760
Oktett. Kein `schreibtisch`, kein `leiste`, kein `einstellungen`, kein
`explorer`, kein `launcher`, kein `widgetdemo`, kein `tiling`, kein
`dispctl` -- `tools/server/build.sh` bricht ab, wenn eines davon auf
der Platte landet.

## Die serielle Konsole

- `kernel/serial.fi` hat einen Rueckweg (`rx_ready`, `rx_take`,
  `rx_on`, `overrun`) und einen BEWEGLICHEN Torwert: `console=ttyS1`
  legt Ausgabe UND Eingabe auf COM2.
- `kernel/sercon.fi` haengt die FIFO an die Zeilendisziplin von Runde
  K9 (`tty.push`). Echo, Rueckschritt, STRG-U, STRG-D, roher Modus,
  Vordergrundgruppe und STRG-C-als-SIGINT gelten damit fuer ein Oktett
  von der Leitung genauso wie fuer eine Taste -- ohne dass eine zweite
  Zeilenbearbeitung geschrieben wurde.
- Vektor 36, GSI 4 (COM1) und GSI 3 (COM2), eingetragen in `hw.stage`.
- `console=ttyS0` macht das Warten UNBEGRENZT. Ohne das Wort endet ein
  `read` auf der Konsole weiter nach 400 Ticks -- deshalb aendert sich
  keine bestehende Messung.
- Daneben ein Abfrageweg (`sercon.poll` aus `sys.tty_read`), damit die
  Gegenprobe `noserirq` die Konsole LANGSAM macht und nicht tot.

Gemessen (`tools/server/run.sh`, Abschnitt 30): **23 Zusagen, 0 rot.**
Getippt wird wirklich -- `tools/server/console.py` haengt an einer
UNIX-Steckdose, wartet auf `sh: ready`, schickt Zeichen fuer Zeichen:

```
osum$ echo hallo-vom-server
hallo-vom-server
osum$ uname
osum
osum$ ls /bin
./ ../ sh ls cat echo cp mv rm ... locate edit
osum$ cat /readme.txt
Osum, Serverbau. Kein Bildschirm, eine Leitung.
osum$ df
...
osum$ exit
sh: bye
sercon: port=0x3f8  rx=80  irqs=41  drops=0  overruns=0
```

Gegenproben: `echo ABX<BS>C` ergibt `ABC` und nicht `ABXC`; STRG-U
verwirft die Zeile; OHNE `console=ttyS0` kommt nichts an
(`sercon: off`); `noserirq` nimmt den Vektor -- es kommt trotzdem an,
ueber den Abfrageweg, und `sercon: irqs=0` sagt es.

## Die volle Abnahme

Beides auf DEMSELBEN Wirt, unter hoher Fremdlast (Lastdurchschnitt 17
bis 29 auf 12 Kernen, weil parallel drei weitere Abnahmelaeufe anderer
Runden liefen).

| | Abschnitte gruen | rot | Zusagen |
|---|---:|---:|---:|
| mergeline 4f844b5 (Grundlinie) | 30 | 7 | 3273 |
| serverbuild | 30 | 8 | 3302 |

Rot in BEIDEN, und zwar mit Zeile fuer Zeile derselben Meldung:
`k14` (151/1), `k16` (58/6), `k17` (157/1), `theme` (89/7), `icons`,
`tunnel/pakete`. Das sind sechs Baustellen, die schon auf `mergeline`
offen sind und mit dieser Runde nichts zu tun haben.

Verschieden:

| Abschnitt | mergeline | serverbuild | nachgemessen auf ruhiger Maschine |
|---|---|---|---|
| `caps` | gruen | rot | **serverbuild 2x gruen (67/0)** -- und auf mergeline selbst 1 von 3 Laeufen rot, mit derselben Signatur |
| `arm` | gruen | rot | **serverbuild 2x gruen (48/0)** |
| `netmon` | rot (68/5) | gruen (76/0) | serverbuild 2x gruen (76/0) |

`caps` und `arm` sind LASTFLATTERN, kein Rueckschritt. Der Beweis fuer
`caps` ist, dass die Grundlinie selbst darueber stolpert: die Zusage
"der uebrige Kernel hat sich geaendert" vergleicht zwei serielle
Mitschnitte, und wenn zwei gleichzeitig laufende Schreiber sich MITTEN
IN EINER ZEILE verschraenken (`puser: hello #N` statt `user: hello #N`
plus `proc: hello pid=N`), faellt sie. `serial.put` hat keine Sperre je
Zeile; der Testautor hat die REIHENFOLGE zweier Zeilen abgefangen
(`sort`), nicht die Verschraenkung IN einer. Gemessen, je 3 Laeufe bei
Last ~25-29: serverbuild 1 gruen / 2 rot, mergeline 2 gruen / 1 rot.

**Kein Abschnitt ist wegen dieser Runde rot.** Der neue Abschnitt 30
ist gruen.

## Schritte

- [x] 1. Gezaehlt, Grundlinie gebaut
- [x] 2. `kernel/gfx.fi` -- die Naht fuer die 25 Stellen ausserhalb kmain/sys
- [x] 3. `kernel/kgui.fi` + `kernel/kutil.fi` -- die Oberflaeche aus `kmain.fi`
- [x] 4. `kernel/sysgui.fi` -- die Aufrufnummern aus `sys.fi`
- [x] 5. `kernel/gfx-aus.fi` + `tools/config` + `--gui on|off`
- [x] 6. `kernel/sercon.fi` -- Eingabe, Zeilenbearbeitung, `console=ttyS0`
- [x] 7. `tools/server/build.sh` -- ein Serverabbild bis zur Shell
- [x] 8. `tools/server/run.sh` als Abschnitt 30 von `./test.sh`
- [x] 9. Die volle Abnahme, GUI-Bau unveraendert gruen

## Was diese Runde ausdruecklich nicht tut

- **Kein VGA-Textmodus.** Die Aufgabe nannte ihn "falls vorhanden". Er
  ist nicht vorhanden: dieser Kernel hat seit Runde K7 einen LINEAREN
  Rahmenpuffer und nie einen 0xB8000-Textmodus gehabt, und sein
  Multiboot-Kopf verlangt ausdruecklich keinen (Abschnitt 11 der
  Abnahme). Einen einzufuehren waere neue Grafik in einer Runde, die
  Grafik wegnimmt.
- **Keine Baudrate auf der Befehlszeile.** 38400 steht seit Runde 59 in
  `serial.init`, und jeder Testlaeufer liest mit dieser Zahl zurueck.
- **Kein `init`/`login` auf der Serverplatte.** `tools/server/build.sh`
  startet `sh` wie `osum` es seit Runde K1 tut. Der Weg ueber
  `/bin/init` steht seit Runde K13 und ist eine Kommandozeile entfernt
  -- in diesem Abschnitt aber nicht gemessen.
- **Keine Sperre um `serial.puts`.** Der Wettlauf, der `tools/caps`
  unter Last stolpern laesst, ist AELTER als diese Runde und bleibt
  offen; er ist hier nur zum ersten Mal benannt und mit Zahlen belegt.
