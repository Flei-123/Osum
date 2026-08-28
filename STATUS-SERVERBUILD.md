# STATUS SERVERBUILD

Zweig `serverbuild`, abgezweigt von `mergeline` (4f844b5). NICHT nach main.

Ziel: Osum soll auch als SERVERBETRIEBSSYSTEM taugen -- ohne Grafik
gebaut, mit einer seriellen Konsole, die ein richtiges Terminal ist.

## Ausgangslage, gemessen

- Kernel gesamt: 72 925 Zeilen in `kernel/*.fi`
- Grafik im Kernel (die vier Dateien der Aufgabe): `fb.fi` 2504,
  `wm.fi` 3908, `wig.fi` 679, `font.fi` ~0 -- zusammen 7091 Zeilen,
  9,7 % des Kernels. Dazu gehoeren im gleichen Sinn `ttf.fi` 1563,
  `tile.fi` 2918, `vmode.fi` 1540, `ansi.fi` ~300, `ps2m.fi` 650.
- Kein Bauschalter: `grep -riE 'nogui|headless|console_only'` -> 0 Treffer.
- GUI-Abbild vor dieser Runde: **2 833 252 Oktett**
  (`tools/build-kernel.sh`, Stufe 0)

## Wie viele Stellen im Kernel greifen auf Grafik zu

Gezaehlt mit einem Werkzeug, das Kommentare wegwirft und nur Code zaehlt
(`fb.` `wm.` `wig.` `font.` `ttf.` `tile.` `vmode.` `ansi.` `ps2m.`):

| Datei | Zugriffe | was das ist |
|---|---:|---|
| `kernel/kmain.fi` | 473 | die Oberflaeche wird beim Start EINGERICHTET |
| `kernel/sys.fi` | 224 | die Oberflaeche wird an Ring 3 WEITERGEGEBEN |
| `kernel/pwr.fi` | 11 | Helligkeit, Verdunkeln, Schirm aus |
| `kernel/kbd.fi` | 3 | eine Taste an den Eingabefokus |
| `kernel/serial.fi` | 1 | jedes Oktett auch auf den Schirm |
| `kernel/tty.fi` | 1 | ein Oktett in ein Terminalfenster |
| **Summe** | **713** | |

Die Zahl, die sagt, wie sauber der Schnitt ist, ist NICHT 713. `kmain.fi`
und `sys.fi` GREIFEN nicht auf die Grafik zu, sie SIND die Oberflaeche --
das Einrichten beim Start und die Aufrufnummern fuer Ring 3. Der ganze
uebrige Kernel (Speicher, Dateisystem, Netz, Zeitplaner, Signale, USB,
Hypervisor, Krypto) beruehrt Grafik an

**16 Stellen in 4 Dateien, mit 11 verschiedenen Funktionen.**

Das ist die Verwebung, von der die Aufgabe spricht, und sie ist duenn.

## Schritte

- [x] 1. Gezaehlt (oben), Grundlinie gebaut (2 833 252 Oktett)
- [x] 2. `kernel/gfx.fi` -- die schmale Naht fuer die 16 Stellen.
      `pwr.fi`, `kbd.fi`, `tty.fi`, `serial.fi` und die zwei Zeilen in
      `kernel_main` rufen nur noch `gfx.*`. Abbild danach:
      **2 833 792 Oktett** (+540, die Weiterleitungen).
- [ ] 3. `kernel/kgui.fi` -- die 38 Grafik-Funktionen aus `kmain.fi`
- [ ] 4. `kernel/sysgui.fi` -- die Grafik-Aufrufnummern aus `sys.fi`
- [ ] 5. `kernel/gfx-aus.fi` + `tools/build-kernel.sh --gui off`
- [ ] 6. Die serielle Konsole: Eingabe, Zeilenbearbeitung, `console=ttyS0`
- [ ] 7. Ein Serverabbild, das bis zur Shell auf der Leitung bootet
- [ ] 8. `tools/server/run.sh` als eigener Abschnitt der Abnahme
- [ ] 9. Die volle Abnahme, GUI-Bau unveraendert gruen

## Zahlen

| | Oktett |
|---|---:|
| GUI-Abbild, Grundlinie (mergeline 4f844b5) | 2 833 252 |
| GUI-Abbild mit der Naht (Schritt 2) | 2 833 792 |
| Serverabbild (gui=off) | -- |
