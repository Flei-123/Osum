# STATUS UMLAUT2 -- Zwischenstand

Zweig `umlaut2`, abgezweigt von `mergeline`; `look` und `paint` sind
hineingemergt (50b1993, 3cd8a79). NICHT nach main gemergt.

## 1. Bestandsaufnahme (Commit 6bbbe74)

`tools/i18n/quellen.py` liest den GANZEN Baum und teilt jede deutsche
Zeichenkette in drei Klassen.

| Quelle | Umschriften gefunden | davon SICHTBAR |
|---|---|---|
| `kernel/**/*.fi` (einkompiliert) | 65 | 42 |
| `assets/apps/*.osp/INFO` | 1 (`info=Text schreiben und aendern`) | 1 |
| `locale/de/icons` | 1 (`icon.window.restore.tip`) | 1 |
| `locale/de/messages` | 2 -- beide in KOMMENTAREN | 0 |

NICHT angefasst, mit Begruendung in `docs/ROUNDUMLAUT2.md` Abschnitt 2:
Kommentare, Bezeichner, Dateinamen, Pfade, MITSCHNITT-Zeilen (die
Abnahme greppt nach ihnen) und MARKEN (Unterbefehle/Schalter, die man
ohne Umlauttaste tippen koennen muss). Sechs Marken nehmen jetzt BEIDE
Schreibungen (`opk zurueck` und `opk zurück`), ebenso die `keys=`-
Zeilen der Buendel.

## 2. Korrektur (Commit f786e62)

42 sichtbare Zeichenketten in 14 Kernel-Dateien auf echtes UTF-8
umgestellt; 7 Abnahme-Laeufer mit 13 Erwartungen nachgezogen.

Stand jetzt:

    quellen:  23 Umschriften in kernel/**  --  SICHTBAR=0 MITSCHNITT=15 MARKE=8
    translit: geprueft=211  umschrift=0  eng=0  umlaute=96

## 3. Puffer und Breitenrechnungen

Die Annahme des Auftrags ("ein ü sind zwei Oktette statt einem") ist
gemessen FALSCH: die Umschrift `ue` ist selbst zwei Oktette lang.

* **42 von 42** Zeichenketten haben nach der Ersetzung exakt dieselbe
  Oktettzahl. **0 Puffer** mussten wegen der Oktettzahl wachsen.
* Was sich aendert, ist die ZEICHENzahl. **3 Puffer** um je ein Oktett
  gewachsen (`power.fi`, `vpn.fi`, `tiling.fi`).
* **6 Breitenrechnungen** korrigiert: 4 Beschriftungsspalten
  (`power.fi`, `vpn.fi`, `tiling.fi`, `speicher.fi`) plus 2 Stellen,
  die "vier Zeichen" verlangten und Oktette zaehlten (`settings.fi`,
  `passwd.fi`). Zaehlen jetzt ZEICHEN.

    spalten: 40 Beschriftungen in 6 Spalten, 0 schief
    puffer:  4744 Zeichenketten, 0 passen nicht

## 4. Absicherung (Commit 429529d)

`tools/umlaut/run.sh` = Abschnitt 29 der Abnahme. Prueft alle Quellen
aus Schritt 1, INHALTE statt Kommentare. 9 Gegenproben stellen je eine
Zeile auf Umschrift zurueck und verlangen ROT; eine
GEGEN-Gegenprobe verlangt, dass eine MITSCHNITT-Zeile GRUEN bleibt.
Kein bestehender Test entschaerft.

## 5. Beweis am Bild

Abbild gebaut, QEMU mit `-accel kvm`, Bilder in `docs/shots/umlaut2/`:
`starter.png`, `einstellungen.png`, `speicher.png`.

Gemessen, nicht angeschaut: `tools/look/umlaut.py --kette` rastert den
erwarteten Satz aus derselben Schriftdatei und vergleicht jeden
Tintenpunkt an der vom Fensterserver gemeldeten Stelle.

    UMLAUT2: 43 Zusagen gruen, 0 rot

Spalten am Bild: `Name` x=14, `Größe` x=224, `Anteil` x=324,
`Größte Dateien` x=414 -- genau die Summen aus `lspalten` 210/100/74.

Ein Restbefund, aelter als diese Runde: der Kern-Rasterer und
`tools/ttf/raster.py` weichen beim kleinen `ö` an genau 3 Bildpunkten
ab (an 3 unabhaengigen Stellen je 3). Steht als OBERGRENZE 3 im
Pruefer -- waechst die Zahl, wird der Abschnitt rot.

## 6. Offen

Vollstaendige Abnahme (`test.sh`, alle Abschnitte) laeuft.
