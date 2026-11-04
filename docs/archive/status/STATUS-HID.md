# RUNDE HID -- ZWISCHENSTAND

Zweig `hid`, abgezweigt von `mergeline2` @ b010f75, Arbeitsbaum
/root/osum-hid. Stand 30.08.2026.

## Was gebaut wurde

| Datei | Zeilen | Was |
|---|---:|---|
| `kernel/hidrep.fi` | 1032 | Der Zerleger fuer HID-Berichtsbeschreibungen |
| `kernel/hidin.fi` | 1503 | DER EINE EINGABEWEG -- PS/2, USB-HID, I2C-HID muenden hier |
| `kernel/i2chid.fi` | 791 | HID ueber I2C: Designware-Regler, Protokoll, ACPI-Ersatzweg |
| `kernel/hidtest.fi` | 247 | ERZEUGT von `tools/hid/descs.py` -- 20 Beschreibungen, 21 Berichte |
| `tools/hid/descs.py` | 1041 | Der ZWEITE Zerleger, in Python, aus der Spezifikation |
| `tools/hid/run.sh` | 355 | Die Abnahme, 57 Zusagen |
| `tools/hid/worte.py` | 93 | Kein Moduswort steckt neu in einem anderen |

Dazu geaendert: `kernel/usb.fi` (die Beschreibung holen, Weiche,
Uebersetzung nach `hidin` verschoben), `kernel/kmain.fi` (Moduswoerter
und drei Stufen), `kernel/kstate.fi` (Moduswort 11),
`tools/kernel/memmap.py` (die neun Seiten + eine Rechenschwaeche),
`test.sh` (Abschnitt 32), `docs/REALHW.md` (Teil H).

Insgesamt 5524 Zeilen eingefuegt, 223 geloescht, 13 Dateien.

## Speicher

| | Oktett |
|---|---:|
| je angeschlossenem Geraet | 6400 (Feldtabelle 4096, Kopfsatz 1024, rohe Beschreibung 1024, Eingabezustand 256) |
| vier Geraeteplaetze | 25600 |
| fest fuer I2C-HID | 8192 |
| `kdata` gesamt | 36864 (neun Seiten, 0x92000..0x9B000) |
| Abbild | +122844 Oktett (+3,9 %), davon 1374 Oktett Testdaten |

## Gemessen

Alle Zahlen aus echten Laeufen, keine geschaetzt.

* **Der Zerleger gegen einen zweiten Zerleger**: 20 Kopfzeilen und 49
  Feldzeilen, Zeile fuer Zeile gleich, kein Unterschied.
* **Latenz**, vom fertigen Bericht bis in die Zeilendisziplin. Median
  aus fuenf Laeufen, QEMU/KVM auf AMD EPYC 7571, 2000 Durchlaeufe je
  Messung, TSC gegen die von `time.fi` kalibrierte Taktzahl (~2,2 GHz):

  | Weg | Zyklen | ns |
  |---|---:|---:|
  | PS/2 (fertiger Abtastcode) | 36 | 16 |
  | USB-HID, Boot-Protokoll | 814 | 369 |
  | USB-HID, generisch | 1885 | 855 |
  | I2C-HID, Softwareanteil (NKRO, 128 Bit) | 6297 | 2857 |
  | Praezisions-Touchpad (34 Felder) | 9310 | 4226 |

  Zwei Verbesserungsrunden dahinter: die Tastenkarte las 512 Oktett je
  Bericht (jetzt vier Woerter), `bits()` ein Oktett je BIT (jetzt
  oktettweise) -- USB generisch von 13344 ns auf 855 ns.

## Abnahme

| Laeufer | Ergebnis |
|---|---|
| `tools/hid/run.sh` (neu) | **57 bestanden, 0 gefallen** |
| `tools/k17/run.sh` (USB) | **RC 0** -- inkl. Oktett-fuer-Oktett USB gegen PS/2 |
| `tools/kernel/run.sh` | **176 bestanden, 0 gefallen** |
| `tools/osum/run.sh` | **130 bestanden, 0 gefallen** |
| `tools/usbimg/run.sh` | **46 bestanden, 0 gescheitert** |
| `tools/server/run.sh` | 22 bestanden, 1 gefallen -- **schon vorher rot**, siehe unten |
| `tools/kernel/memmap.py` | 83 Bereiche, **0 Kollisionen** |
| Bau gui=on / gui=off / --ohne-tunnel / --stufe 1 | alle vier gruen |

### Der eine rote Punkt gehoert NICHT dieser Runde

`tools/server/run.sh` meldet `kgui.fi 41 von 42 Funktionen
zeichengleich -- surface: weicht ab`. Diese Runde hat `kgui.fi`,
`sysgui.fi` und `kutil.fi` NICHT angefasst (`git diff` darauf ist leer).
Nachgestellt auf einem sauberen Arbeitsbaum des Ausgangsstands b010f75,
OHNE eine Zeile dieser Runde: **dieselbe Meldung, wortgleich.** Der
Vergleich laeuft gegen die Grundlinie `5d2550c`, und die passt zum
heutigen `kgui.fi` nicht mehr. Das gehoert der Runde MERGE-2.

## Was NUR aus der Spezifikation stammt

Steht ausfuehrlich in `docs/REALHW.md` Teil H und im Kopf von
`kernel/i2chid.fi`. Kurz: **jeder Designware-Registerzugriff** -- QEMU
hat keinen LPSS-I2C. Der ACPI-Ersatzweg dagegen IST gemessen, gegen eine
gebaute Tabelle UND gegen die echten Tabellen, die QEMU stellt.

Der Zweig `aml` war am 30.08.2026 noch leer (identischer Commit wie
`mergeline2`), deshalb der Ersatzweg. Die drei Stellen, die spaeter auf
AML umzustellen sind, stehen namentlich in `docs/REALHW.md`.

## Zwei eigene Fehler, von den Messungen gefunden

1. `add(a,b)` in `hidin.fi` rechnete `a + b`, sobald b nicht negativ
   war. Ist a negativ, laeuft das ueber, und Firn bricht ab. Die
   Latenzmessung hat den Kern damit umgeworfen -- auf einem echten
   Touchpad waere es bei der ersten Bewegung nach links passiert.
2. Die Gegenprobe hiess `nohidrep`, und darin steckt `nohid` (Runde
   K17). Der Lauf, der beweisen sollte, dass ohne den Zerleger alles
   weiterlaeuft, hatte deshalb gar kein Eingabegeraet mehr. Jetzt
   `hidgen`/`nurboot`, und `tools/hid/worte.py` prueft das mechanisch.

## Beruehrung mit den Nachbarrunden

`mergeline2` ist waehrend dieser Runde von b010f75 auf 54bf135 gelaufen
(MERGE-2 14/15, umlaut2 und themestore). In **keiner** Kernel-Datei gibt
es eine Ueberschneidung mit dieser Runde; die einzige gemeinsame Datei
ist `test.sh`, und dort haengen beide Seiten nur Abschnitte an.
