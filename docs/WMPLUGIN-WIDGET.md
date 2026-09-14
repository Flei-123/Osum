# Modul `widget` — das Leistenwidget, und was daran gemessen ist

Runde WMPLUGIN, Zweig `wmplugin`. Dieses Blatt gehoert dem Modul
`widget`; der Bericht der ganzen Runde steht in `docs/RUNDE-WMPLUGIN.md`
und darf von hier abschreiben. **Jede Zahl unten stammt aus einem
wirklich gebooteten Kernel** (`bash tools/wmplug/widget.sh`, QEMU,
800x600), nicht aus einer Ueberlegung. Der Laeufer endet mit
**30 bestanden, 0 gescheitert**.

## Die Dateien

| Datei | was sie ist |
|-------|-------------|
| `kernel/user/pluguhr.fi` | `/bin/pluguhr` — das Widget, ein **Ring-3-Prozess** |
| `kernel/user/taskbar.fi` | die Leiste holt die Texte und malt sie |
| `kernel/user/plugstart.fi` | **Abkuerzung**, siehe unten |
| `tools/wmplug/widget.sh` | der Laeufer: 30 Zusagen, drei QEMU-Laeufe |
| `docs/shots/wmplug/widget-{an,aus,aus-laufzeit}.png` | die drei Fotos |

## Der Weg eines Zeichens

```
/bin/pluguhr  --WM_PLUG_BAR(2124)-->  Plugintafel im Kern  (31 Oktette)
/bin/taskbar  --WM_PLUG_BARGET(2125)-->  dieselben 31 Oktette
/bin/taskbar  --wlib.draw_board + wlib.draw_text-->  Bild
```

Das Plugin **malt nichts**. Es hat keinen Rahmenpuffer, kein Fenster,
keinen Zeiger in die Leiste — es liefert Text ab. Gemalt wird von einem
Programm, das schon vorher malen durfte, mit genau den zwei Aufrufen,
mit denen die Uhr daneben gemalt wird. `bash tools/check-ui.sh` meldet
weiterhin **PASSED** (nachgesehen nach der Aenderung).

Das ist der Unterschied zu Hyprland: dort ist ein Leistenwidget eine
`.so` im Compositor-Prozess und schreibt in denselben Adressraum wie der
Compositor. Hier kann es das nicht, und zwar nicht, weil es nett ist,
sondern weil es die Adressen nicht hat.

## Die gemessenen Grenzen

* **Die Leiste ist die einzige Leserin.** `/bin/pluguhr` versucht beim
  Start ausdruecklich `WM_PLUG_BARGET` und bekommt
  `pluguhr: barget verweigert r=-2` (`E_RIGHTS`) — geprueft im Kern mit
  `is_taskbar` (wer einen Schirmrand reserviert hat). Ein Plugin kann
  also den Text eines anderen Plugins nicht lesen.
* **Ohne Recht kein Text.** Ohne `R_ACT_BAR` (0x800) gibt
  `WM_PLUG_BAR` `E_RIGHTS`; gemessen im ersten Lauf, als der Name beim
  Anmelden nicht passte: `reg uhr platz=0 rechte=0x1f` und danach
  `pluguhr: KEIN recht R_ACT_BAR r=-2`. Die Leiste zeigte nichts.
* **Die Frist.** Der Kern meldet sie (`PL_FRIST` = 50 Ticks = 0,5 s);
  das Widget fragt danach und holt alle `frist/3` = **166 ms** ab
  (`pluguhr: frist ticks=50 pollms=166`). Der erste Lauf schlief eine
  ganze Sekunde am Stueck und wurde dafuer abgemeldet:
  `wmplug: unreg uhr grund=2` (G_FRIST). Die Grenze ist also keine
  Behauptung — sie hat dieses Modul selbst einmal erwischt.

## Die Fotos, maschinell auseinandergehalten

Die Koordinate ist **nicht getippt**: die Leiste meldet ihren
Widget-Kasten (`taskbar: plug nr=0 x=586 y=2 w=132 h=26`) und ihre
Fensterlage (`taskbar: geom x=0 y=570`); gerechnet wird an Ort und
Stelle.

| Vergleich | Rechnung | Zahl |
|-----------|----------|------|
| `widget-an` gegen `widget-aus` (zwei Laeufe) | verschiedene Punkte im Kasten | **3432 von 3432** |
| dieselbe Mitte (652,585), `checkshot.py punkt` | aus `30 41 59` / an `38 48 60` | verschieden |
| Tinte im Kasten (AN), `checkshot.py flaeche` | gegen die Kastenfarbe | **604** |
| `widget-an` gegen `widget-aus-laufzeit` (EIN Lauf) | verschiedene Punkte | **3432** |
| Tinte im Kasten nach dem Abmelden | gegen die Kastenfarbe | **0** |

(Die Tintenzahl schwankt von Lauf zu Lauf um wenige Punkte, weil die
Uhrzeit im Text steht: `17:10` und `17:46` haben nicht dieselbe Tinte.
Gemessen wurde 581 und 604 in zwei Laeufen; die Zusage lautet ">20",
nicht "genau 604".)

Die letzten beiden Zeilen sind die eigentliche Zusage "**an und aus zur
Laufzeit**": beide Bilder kommen aus **demselben Systemstart**, demselben
`wm`, derselben Leiste. Dazwischen liegt nur
`wmplug: unreg uhr grund=0`. Der Fensterserver wurde nicht neu
gestartet, die Leiste nicht neu gestartet, und auf dem zweiten Bild
steht die Uhr der Leiste unveraendert da, wo sie vorher stand.

## Die Gegenprobe ohne Plugintafel

Derselbe Kernel, dasselbe Abbild, dazu das Wort `plugaus`: der Kern
meldet `tafel= zu`, die Leiste fragt `PL_MAXPLUG` genau einmal, bekommt
einen Fehler und fragt nie wieder. Gemessen: Schreibtisch steht,
`taskbar: geom` wie immer, **kein** `taskbar: plug nr=`.

Nebenbefund, hier festgehalten, weil eine Zusage dieses Laeufers daran
zuerst rot war: **ohne `plugaus` ist die Tafel OFFEN, auch ohne das Wort
`wmplug`** -- in jedem gemessenen Lauf steht
`wmplug: abi=1  tafel= offen  frist=50` auf der Leitung.

## Offene Punkte

* `bash tools/desktop/run.sh` meldet in diesem Arbeitsbaum
  **57 passed, 42 failed**. Die sichtbaren roten Zusagen handeln von
  Aufloesung und Rechtecken (`the bar is at (0, 772, 1280, 28)` --
  der Laeufer startet QEMU ohne `-global VGA.edid=off` und erwartet
  800x600). **Nicht gegengeprueft** gegen den Stand vor dieser Runde:
  an diesem Arbeitsbaum arbeiten gleichzeitig vier Module, ein
  Vergleichslauf haette also nicht diese Aenderung gemessen. Was sich
  ueber diese Aenderung sagen laesst: sie fuegt der Leiste ein Feld
  hinzu, wenn ein Plugin Text schickt, und einen Systemaufruf je
  Sekunde, wenn keines da ist -- an der Aufloesung, an
  `/etc/taskbar.conf` und an den Schirmrand-Reservierungen fasst sie
  nichts an.

## Ausdrueckliche Abkuerzungen dieses Moduls

1. **`kernel/user/plugstart.fi`.** Der Kern startet auf dem
   Schreibtischweg genau ein zusaetzliches Programm (`wigapp=`), der
   Abnahmelauf braucht aber zwei Schritte (Rechte gewaehren, dann
   starten). Dieser Helfer macht beides und faellt weg, sobald der
   Schreibtisch eine Autostart-Liste hat. Er hiess waehrend der Runde
   `_dev_uhrstart.fi`; weil der Abnahmelauf ihn wirklich braucht, ist er
   jetzt ein benanntes Stueck und keine Bauruine mehr -- die Abkuerzung
   bleibt aber eine.
2. **Die senkrechte Leiste bekommt kein Widget-Feld.** Eine Spalte ist
   hier 80 Bildpunkte breit; `17:10 cpu 100%` passt nicht hinein, ohne
   die Uhr darunter zu verdraengen. Steht so im Code, gemessen nicht.
3. **Acht Plaetze**, weil die Plugintafel des Kerns acht hat. Wie viele
   es wirklich sind, fragt die Leiste (`PL_MAXPLUG`); die Acht ist nur
   die Groesse ihres Puffers.
4. **Die CPU-Zahl ist die von Kern 0** (`SYS_CPUSTAT`, zwei Messungen).
   Auf einer Maschine mit mehreren Kernen ist das nicht die Auslastung
   des Systems, sondern die eines Kerns — und unter `wmhold` steht dort
   ehrlich 100 %, weil der Haltepfad wirklich dreht.
