# STATUS SERVERBUILD

Zweig `serverbuild`, abgezweigt von `mergeline` (4f844b5). NICHT nach main.

Ziel: Osum soll auch als SERVERBETRIEBSSYSTEM taugen -- ohne Grafik
gebaut, mit einer seriellen Konsole, die ein richtiges Terminal ist.

## Ausgangslage, gemessen

- Kernel gesamt: 72 925 Zeilen in `kernel/*.fi`
- Grafik im Kernel: `fb.fi` 2504, `wm.fi` 3908, `wig.fi` 679,
  `font.fi` (Tabelle) -- die vier aus der Aufgabe zusammen 7091 Zeilen,
  9,7 %. Im selben Sinn Grafik sind `ttf.fi` 1563, `tile.fi` 2918,
  `vmode.fi` 1540, `ansi.fi` und `ps2m.fi` 650; alle neun zusammen
  **14 109 Zeilen, 19,3 % des Kernels**.
- Kein Bauschalter: `grep -riE 'nogui|headless|console_only'` -> 0 Treffer.
- GUI-Abbild vor dieser Runde: **2 833 252 Oktett** (Stufe 0).
- Die serielle Leitung war eine EINBAHNSTRASSE: `serial.put` schickte
  hinaus, es gab kein `serial.rx`. Eingetippt wurde ueber die
  PS/2-Tastatur (`kbd.fi`, IRQ 1) oder ueber `script=` auf der
  Kernel-Befehlszeile.

## Wie viele Stellen im Kernel greifen auf Grafik zu

`tools/server/count.py` wirft die Kommentare weg und zaehlt nur Code
(`fb.` `wm.` `wig.` `font.` `ttf.` `tile.` `vmode.` `ansi.` `ps2m.`):

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
`kmain.fi` und `sys.fi` GREIFEN nicht auf die Grafik zu -- sie SIND die
Oberflaeche: das Einrichten beim Start und die Aufrufnummern fuer
Ring 3. Der uebrige Kernel -- Speicher, Dateisystem, Netz, Zeitplaner,
Signale, USB, Hypervisor, Krypto, 60 Module -- beruehrt Grafik an

**25 Stellen in 6 Dateien.**

Genau darum ging der Schnitt so glatt.

## Was gebaut wurde

| Datei | Zeilen | was |
|---|---:|---|
| `kernel/gfx.fi` | 270 | DIE NAHT. 37 Symbole. Das einzige Modul, das `fb`, `wm`, `wig`, `font`, `ttf`, `tile`, `vmode`, `ansi`, `ps2m` einbindet. |
| `kernel/gfx-aus.fi` | 181 | dieselben 37 Symbole, leer. `ready` sagt `false`, die vier Aufrufbereiche geben -ENOSYS. |
| `kernel/kgui.fi` | 2635 | die 44 Grafikfunktionen aus `kmain.fi`, Zeile fuer Zeile umgezogen. |
| `kernel/sysgui.fi` | 1206 | die 15 Grafik-Aufrufnummern aus `sys.fi` (wm, wig, tile, disp). |
| `kernel/kutil.fi` | 92 | die fuenf Helfer, die `kmain.fi` und `kgui.fi` sich teilen. |
| `kernel/sercon.fi` | 279 | DIE SERIELLE KONSOLE. IRQ 4 auf Vektor 36, FIFO in die Zeilendisziplin, `console=ttyS0`. |
| `tools/config` | 38 | die Baukonfiguration: `gui=on\|off`, `tunnel=on\|off`. |
| `tools/server/build.sh` | 108 | Kern (gui=off) + Server-Userland + OFS-Platte. |
| `tools/server/run.sh` | 266 | der neue Abnahmeabschnitt 30. |
| `tools/server/console.py` | 138 | ein Mensch an der Leitung: warten, tippen, lesen. |
| `tools/server/count.py` | 80 | zaehlt die Grafikzugriffe nach. |

Kein `#ifdef`, keine Verzweigung zur Laufzeit. `--gui off` LOESCHT elf
Dateien aus dem Uebersetzungsbaum und legt `gfx-aus.fi` an die Stelle
von `gfx.fi` -- derselbe Griff, mit dem `--ohne-tunnel` seit Runde
TUNNEL `wg.fi` durch `wg-aus.fi` ersetzt.

## Warum ein Modulkreis erlaubt ist, und was daraus folgt

Nachgemessen, nicht angenommen: `firnc` nimmt gegenseitige `import`s an,
solange keines der beteiligten Module das WURZELMODUL ist. Deshalb darf
`sysgui.fi` sein altes Zuhause `sys.fi` einbinden (fuer `neg`,
`copy_in`, `copy_out`, `do_scan`, `do_jrnl`) -- und deshalb kann
`kgui.fi` das NICHT mit `kmain.fi`: das ist die Wurzel, und unter ihrem
eigenen Namen steht sie nicht in der Modultafel ("module 'kmain' was not
found"). Die fuenf geteilten Helfer sind darum nach unten gewandert,
nach `kernel/kutil.fi`.

## Zahlen

| | Oktett |
|---|---:|
| GUI-Abbild, Grundlinie (mergeline 4f844b5) | 2 833 252 |
| GUI-Abbild nach dieser Runde | 2 849 604 |
| Aufschlag fuer die Naht | +16 352 (+0,58 %) |
| **Serverabbild (gui=off)** | **2 109 692** |
| **Unterschied gui=on zu gui=off** | **739 912 (25,96 %)** |

Und die Gegenprobe, die den Unterschied erst zu einem Beweis macht --
die Symboltafel des gebundenen ELF:

| Modul | Symbole im GUI-Abbild | im Serverabbild |
|---|---:|---:|
| wm | 174 | 0 |
| fb | 122 | 0 |
| tile | 133 | 0 |
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

## Die serielle Konsole

Vorher: Ausgabe ja, Eingabe nein. Nachher:

- `kernel/serial.fi` hat einen Rueckweg (`rx_ready`, `rx_take`,
  `rx_on`, `overrun`) und einen BEWEGLICHEN Torwert -- `console=ttyS1`
  legt Ausgabe UND Eingabe auf COM2, und wenn nur eine Haelfte umzoege,
  redete der Kernel in ein Kabel und hoerte am anderen.
- `kernel/sercon.fi` haengt die FIFO an die Zeilendisziplin von Runde
  K9 (`tty.push`). Damit gelten Echo, Rueckschritt, STRG-U, STRG-D,
  roher Modus, Vordergrundgruppe und STRG-C-als-SIGINT fuer ein Oktett
  von der Leitung genauso wie fuer eine Taste -- ohne dass eine zweite
  Zeilenbearbeitung geschrieben wurde.
- Vektor 36, GSI 4 (COM1) und GSI 3 (COM2), eingetragen in `hw.stage`.
- `console=ttyS0` macht das Warten UNBEGRENZT. Ohne das Wort endet ein
  `read` auf der Konsole weiter nach 400 Ticks -- das ist der Grund,
  warum keine bestehende Messung sich aendert.
- Daneben ein Abfrageweg (`sercon.poll` aus `sys.tty_read`), damit die
  Gegenprobe `noserirq` die Konsole langsam macht und nicht tot.

## Schritte

- [x] 1. Gezaehlt, Grundlinie gebaut
- [x] 2. `kernel/gfx.fi` -- die Naht fuer die 25 Stellen ausserhalb kmain/sys
- [x] 3. `kernel/kgui.fi` + `kernel/kutil.fi` -- die Oberflaeche aus `kmain.fi`
- [x] 4. `kernel/sysgui.fi` -- die Aufrufnummern aus `sys.fi`
- [x] 5. `kernel/gfx-aus.fi` + `tools/config` + `--gui on|off`
- [x] 6. `kernel/sercon.fi` -- Eingabe, Zeilenbearbeitung, `console=ttyS0`
- [x] 7. `tools/server/build.sh` -- ein Serverabbild, das bis zur Shell bootet
- [x] 8. `tools/server/run.sh` als Abschnitt 30 von `./test.sh`
- [ ] 9. Die volle Abnahme, GUI-Bau unveraendert gruen
