# STATUS-MERGE6 — die Zahlen der Runde

*05.09.2026 · Zweig `merge6` (2952fe4), aus `hidweg` 1493451*

Ausführlich: `docs/RUNDE-MERGE6.md`.

## Die Läufer, einzeln gefahren

| Läufer | Ergebnis | Bemerkung |
|---|---|---|
| `tools/themestore/run.sh` | **81 / 0** | Kontraste ≥ 4,5 Text und ≥ 3,0 Bedienelemente, zweimal gerechnet, Gegenprobe fällt |
| `tools/design/messen.py` (7 Ansichten) | **691 von 744 = 92 %** | Design-Runde: 671/724 = 92 %. Nicht abgerutscht. |
| `tools/vielkern/run.sh` | **38 / 2** | beide roten erklärt, keiner ein Regress |
| `tools/posix/run.sh` | **134 / 0** | vorher 133/1 — `SYS_OSUM_CPUSTAT` fehlte in der libc, behoben |
| `tools/werkzeug/run.sh` | **26 / 8** | auf dem Zweig `werkzeug` allein: 37 / 0 |
| `tools/laden/run.sh` | **nicht gefahren** | offene Auflage |

## Die neuen Zusagen dieser Runde

`tools/vielkern/run.sh`, Abschnitte 10–12 (= `test.sh` Abschnitt 40):

```
smp: fsrace kerne=4  runden=20000  blind=0  fehler=0
smp: fsrace kerne=4  runden=20000  blind=1  fehler=31506
einkern gesperrt=13  offen=60
```

0 gegen 31 506 von 80 000 Lesungen. `fsblind` nimmt den **wörtlichen**
Rumpf, den `fs.inode_get` vor VIELKERN 3 hatte.

## `./test.sh`

Gestartet (64 Abschnitte, 10 gleichzeitig) und **innerhalb dieser Runde
nicht zu Ende gelaufen** — das steht hier so, weil eine Zahl, die
niemand gesehen hat, keine Abnahme ist. Was fertig wurde:

| Abschnitt | Ergebnis |
|---|---|
| 1 festgenagelter Übersetzer | **rot** — `vendor/firn/.gebaut` passt nicht zu `COMMIT` (Zustand des Arbeitsbaums, keine Zeile dieser Runde) |
| 2 freestanding | 41 / 0 |
| 3 core | 46 / 0 |
| 4 kernel | 176 / 0 |
| 5 osum | 130 / 0 |
| 6 pci | 97 / 1 — `DMA gegen PIO 1080 statt ≥ 1200`, eine **Durchsatzzahl** unter Wirtslast |
| 7 posix | 133 / 1 → nach der Reparatur **134 / 0** einzeln nachgemessen |
| 8 smp | 59 / 0, dabei `with the lock: 6000 of 6000 · without it: 2115 of 6000` |

## Reife

**`merge6` ersetzt `hidweg` noch nicht.** Ein Ring-3-Programm stirbt in
einem von fünf Läufen mit vier Kernen an `wig.glyph_into` — einer
Glyphenbühne, die der ganzen Maschine gehört:

```
-smp 1   0 Panics, 212 Meldezeilen
-smp 4   1 Panic in 5 Läufen (83 / 78 / 80 / 56 / 0 Meldezeilen)
```

Offen bleiben außerdem: `tools/laden/run.sh` (nie gefahren), die
dreiundvierzig Wege in `kernel/sys.fi` um `NAME_OFF`/`BLOCK_OFF`
(gezählt, nicht gesperrt) und der Umbenennen-Dialog des Dateimanagers
(älter als diese Runde, im Baum `design` Zeile für Zeile derselbe).
