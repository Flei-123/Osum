# Runde SERVERBUILD -- Osum ohne Bildschirm

Zweig `serverbuild`, abgezweigt von `mergeline` (4f844b5).

## Die Frage

Osum hatte einen Bildschirm, und es hatte ihn IMMER. Nicht als
Voreinstellung, sondern als Voraussetzung: `kernel/kmain.fi` band `fb`,
`vmode`, `ttf`, `wm`, `tile`, `wig` und `ps2m` ein, `kernel/sys.fi`
ebenfalls, und wer eine dieser Dateien wegnahm, bekam vom Uebersetzer
"module 'fb' was not found". Einen Bauschalter gab es nicht -- ein
`grep -riE 'nogui|headless|console_only'` ueber den ganzen Baum fand
null Treffer.

Dazu kam der Satz, den `kernel/wm.fi` selbst schreibt:

> WO DER SERVER LAEUFT. Im Kernel. Das ist eine Entscheidung und keine
> Bequemlichkeit.

Ein Fensterserver IM Kernel ist nicht danebenliegender Code, den man
weglaesst. Er ist verwoben. Die Frage dieser Runde war deshalb nicht
"kann man die Grafik ausschalten", sondern: **WIE TIEF sitzt sie
wirklich?**

## Die Antwort ist eine Zahl, und sie ist kleiner als erwartet

`tools/server/count.py` wirft die Kommentare weg und zaehlt nur Code:

```
  kmain.fi                   493
  sys.fi                     227
  pwr.fi                      11
  usb.fi                       6
  kbd.fi                       3
  arch/x86_64/trap.fi          3
  serial.fi                    1
  tty.fi                       1
  SUMME 745 Stellen, 329 verschiedene Funktionen, in 8 Dateien
```

745 klingt nach einer Verwebung. Es ist keine. `kmain.fi` und `sys.fi`
GREIFEN nicht auf die Grafik zu -- sie SIND die Oberflaeche: das
Einrichten beim Start und die Aufrufnummern fuer Ring 3. Zieht man die
beiden ab, bleiben

**25 Stellen in 6 Dateien.**

Der ganze uebrige Kernel -- Speicher, Dateisystem, Netz, Zeitplaner,
Signale, Prozesse, USB, NVMe, Hypervisor, Krypto, sechzig Module und
mehr als 50 000 Zeilen -- weiss vom Bildschirm nichts. Die elf Stellen
in `pwr.fi` verdunkeln ihn, die drei in `kbd.fi` geben eine Taste an
den Eingabefokus, die eine in `serial.fi` spiegelt jedes Oktett auf ihn,
die eine in `tty.fi` schreibt in ein Terminalfenster, die sechs in
`usb.fi` bewegen einen Zeiger, die drei in `trap.fi` sind zwei
Unterbrechungen.

Das ist der Grund, warum diese Runde in einem Tag machbar war.

## Was gebaut wurde

### 1. `kernel/gfx.fi` -- die Naht

Ein Modul mit 37 Symbolen. Es ist ab dieser Runde das EINZIGE, das
`fb`, `wm`, `wig`, `font`, `ttf`, `tile`, `vmode`, `ansi` oder `ps2m`
einbindet. Alles andere im Kernel redet ueber `gfx.` mit dem
Bildschirm:

| von | ueber | wie viele |
|---|---|---:|
| `pwr.fi` | `gfx.width/height/pixel/get_pixel/dirty_all/flush/ready` | 11 |
| `usb.fi` | `gfx.mouse_packet/mouse_x/…` | 6 |
| `kbd.fi` | `gfx.wm_ready/wm_on_key/wm_key_tty` | 3 |
| `trap.fi` | `gfx.mouse_irq/wm_poll` | 3 |
| `serial.fi` | `gfx.echo` | 1 |
| `tty.fi` | `gfx.wm_term_out` | 1 |
| `kmain.fi` | `gfx.parse/stage_graphics/stage_surface/stage_hold/mouse_adopt` | 5 |
| `sys.fi` | `gfx.sys_wm/sys_wig/sys_disp/sys_tile` + acht /dev/fb-Griffe | 12 |

Daneben `kernel/gfx-aus.fi`: dieselben 37 Symbole, leere Rumpfe.
`ready` sagt `false`, die vier Aufrufbereiche geben -ENOSYS, `echo` tut
nichts (die serielle Leitung hat das Oktett schon).

**Kein `#ifdef`.** Eine Datei, die in zwei Faellen zwei verschiedene
Programme ist, liest niemand mehr.

### 2. `kernel/kgui.fi` und `kernel/sysgui.fi` -- der Umzug

Die 44 Grafikfunktionen aus `kmain.fi` (2635 Zeilen: `graphics`,
`vmode_stage`, `surface`, `tile_stage`, `desk_start`, `load_font`, die
zwei Dutzend `say_*`, die vier `*_bench`) und die 15 Grafik-Aufrufnummern
aus `sys.fi` (1206 Zeilen: `wm_call`, `wig_call`, `tile_call`,
`disp_call` und ihre Helfer) sind Zeile fuer Zeile umgezogen. Nichts
umgeschrieben.

Was NICHT mitgezogen ist, und der Grund gehoert dazu: `/dev/fb`.
`open_devfb`, `fb_write`, `fb_read`, `do_lseek`, `do_fstat`, `map_fd`
und `do_pwrset` behandeln den Rahmenpuffer als EINEN Fall unter
mehreren -- ein `lseek` auf das Ende einer Datei ist kein Grafikaufruf.
Die sieben fragen ueber acht Weiterleitungen nach, und ohne Bildschirm
sagt die erste `false`: dann gibt `open("/dev/fb")` -ENODEV, genau wie
auf einer Maschine ohne Grafikkarte.

**Ein Modulkreis, und er ist erlaubt.** `sys.fi` bindet `gfx.fi` ein,
`gfx.fi` bindet `sysgui.fi` ein, `sysgui.fi` bindet wieder `sys.fi`
ein. Nachgemessen an einem Zweizeiler: firnc nimmt das an. Was es NICHT
annimmt, ist ein Kreis ueber das WURZELMODUL -- `import kmain` gibt
"module 'kmain' was not found", weil die Wurzel unter ihrem eigenen
Namen keinen Eintrag in der Modultafel hat. Deshalb sind die fuenf
Helfer, die sich `kmain.fi` und `kgui.fi` teilen, nach unten gewandert:
`kernel/kutil.fi`.

### 3. `tools/config` und `--gui off`

```
gui=on      das Verhalten bis einschliesslich MERGE-FINAL (Vorgabe)
gui=off     der Serverbau
```

Reihenfolge: Befehlszeile > Umgebung (`OSUM_GUI`) > `tools/config` >
eingebaut. Bei `gui=off` LOESCHT `tools/build-kernel.sh` elf Dateien
aus dem Uebersetzungsbaum und legt `gfx-aus.fi` an die Stelle von
`gfx.fi`. Derselbe Griff, mit dem `--ohne-tunnel` seit Runde TUNNEL
`wg.fi` durch `wg-aus.fi` ersetzt: nicht abgeschaltet, sondern nicht
vorhanden.

### 4. `kernel/sercon.fi` -- die Leitung wird ein Terminal

Bis hierher war die serielle Leitung eine Einbahnstrasse. `serial.put`
schickte seit Runde 59 jedes Oktett hinaus; einen Empfangsweg gab es
nicht. Getippt wurde auf der PS/2-Tastatur -- oder gar nicht, weshalb
es `script=` auf der Kernel-Befehlszeile gibt: eine Zeichenkette, die
`sys.script_feed` der Shell vorlegt, als haette jemand sie getippt.

Auf einem Server steht keine Tastatur.

- `serial.fi` bekommt `rx_ready`, `rx_take`, `rx_on`, `overrun` -- und
  einen BEWEGLICHEN Torwert. `console=ttyS1` legt Ausgabe UND Eingabe
  auf COM2; zoege nur eine Haelfte um, redete der Kernel in ein Kabel
  und hoerte am anderen.
- `sercon.fi` haengt die FIFO an die Zeilendisziplin von Runde K9.
  Damit gelten Echo, Rueckschritt, STRG-U, STRG-D, roher Modus,
  Vordergrundgruppe und STRG-C-als-SIGINT fuer ein Oktett von der
  Leitung genauso wie fuer eine Taste -- **ohne dass eine zweite
  Zeilenbearbeitung geschrieben wurde**. Das ist der Gewinn daraus,
  dass Runde K9 die Disziplin vom Geraet getrennt hat.
- Vektor 36, GSI 4 (COM1) und GSI 3 (COM2).
- `console=ttyS0` macht das Warten UNBEGRENZT. Bis hierher gab
  `sys.tty_read` nach 400 Ticks eine Null zurueck und meldete damit das
  Ende der Eingabe -- richtig fuer einen Testlauf, der sich selbst
  beenden muss, falsch fuer eine Konsole, an der jemand nachdenkt.
  Ohne das Wort bleibt jede bestehende Messung auf den Tick genau.
- Daneben ein Abfrageweg, damit die Gegenprobe `noserirq` die Konsole
  LANGSAM macht und nicht tot. Eine Gegenprobe, die alles umbringt,
  misst nichts.

## Was gemessen wurde

`tools/server/run.sh`, Abschnitt 30 der Abnahme: **22 Zusagen, 0 rot.**

```
gui=on  2 849 604 Oktette
gui=off 2 109 692 Oktette
Unterschied 739 912 Oktette (25,9 %)
```

Der Oktettunterschied allein waere kein Beweis -- ein Schalter, der nur
eine Verzweigung zur Laufzeit setzt, waere daran nicht zu erkennen.
Also die Symboltafel des gebundenen ELF:

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
| **Summe** | **739** | **0** |
| gfx (die Naht) | 37 | 37 |

Und die Shell, wirklich getippt: `tools/server/console.py` haengt an
einer UNIX-Steckdose, wartet auf `sh: ready`, schickt Zeichen fuer
Zeichen und liest die Antwort.

```
osum$ echo hallo-vom-server
hallo-vom-server
osum$ uname
osum
osum$ ls /bin
./ ../ sh ls cat echo cp mv rm mkdir ... locate edit
osum$ cat /readme.txt
Osum, Serverbau. Kein Bildschirm, eine Leitung.
osum$ df
...
osum$ exit
sh: bye
sercon: port=0x3f8  rx=80  irqs=37  drops=0  overruns=0
```

Gegenproben:

- `echo ABX<BS>C` muss `ABC` ergeben und NICHT `ABXC` -- der
  Rueckschritt wirkt auf der Leitung.
- `echo weg-damit<STRG-U>echo geblieben` fuehrt nur den zweiten Befehl
  aus.
- OHNE `console=ttyS0` darf nichts von der Leitung ankommen. Tut es
  auch nicht: `sercon: off`.
- `noserirq` nimmt den Eintrag im I/O-APIC. Es kommt trotzdem an --
  ueber den Abfrageweg --, und `sercon: irqs=0` sagt es. Im Regellauf
  steht dort 37.

## Was diese Runde ausdruecklich nicht tut

- **Kein Zeichenmodus (VGA-Text).** Die Aufgabe nannte ihn "falls
  vorhanden". Er ist nicht vorhanden: dieser Kernel hat seit Runde K7
  einen LINEAREN Rahmenpuffer und nie einen 0xB8000-Textmodus gehabt,
  und ein Multiboot-Kopf, der Bit 2 setzt, verlangt ausdruecklich
  keinen (siehe Abschnitt 11 der Abnahme, "Cannot use text mode with
  UEFI"). Einen einzufuehren waere neue Grafik in einer Runde, die
  Grafik wegnimmt.
- **Keine Baudrate auf der Befehlszeile.** `serial.init` stellt seit
  Runde 59 38400 ein, jeder Testlaeufer liest mit dieser Zahl zurueck.
  Ein Schalter dafuer waere eine Art, jede bestehende Messung
  stillzulegen.
- **Kein `init` auf der Serverplatte.** `tools/server/build.sh` baut
  `sh` als ersten Prozess, wie `osum` es seit Runde K1 tut. Der Weg
  ueber `/bin/init` und `/bin/login` steht seit Runde K13 und ist eine
  Kommandozeile entfernt, aber er ist in diesem Abschnitt nicht
  gemessen -- und was niemand nachmisst, gilt hier als Behauptung.
