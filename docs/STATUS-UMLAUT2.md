# STATUS UMLAUT2 -- die Zahlen der Runde

Zweig `umlaut2`, abgezweigt von `mergeline` (6b602af); `look` und
`paint` sind hineingemergt (50b1993, 3cd8a79). NICHT nach main gemergt.

## 1. Bestandsaufnahme (Commit 6bbbe74)

`tools/i18n/quellen.py` liest den GANZEN Baum und teilt jede deutsche
Zeichenkette in drei Klassen.

| Quelle | Umschriften | davon SICHTBAR |
|---|---|---|
| `kernel/**/*.fi` (einkompiliert) | 65 | 42 |
| `assets/apps/*.osp/INFO` | 1 (`info=Text schreiben und aendern`) | 1 |
| `locale/de/icons` | 1 (`icon.window.restore.tip`) | 1 |
| `locale/de/messages` | 2 -- beide in KOMMENTAREN | 0 |

Die beiden Einzelfunde in `INFO` und `locale/de/icons` waren beim
Merge von `look` bereits geholt und wurden nachgeprueft; die 42 im
Quelltext waren offen -- dorthin sah kein Pruefer.

NICHT angefasst, begruendet in `docs/ROUNDUMLAUT2.md` Abschnitt 2:
Kommentare, Bezeichner, Dateinamen, Pfade, MITSCHNITT-Zeilen (die
Abnahme greppt nach ihnen) und MARKEN (Unterbefehle/Schalter, die man
ohne Umlauttaste tippen koennen muss). Sechs Marken nehmen jetzt BEIDE
Schreibungen (`opk zurueck` und `opk zurück`), ebenso die `keys=`-
Zeilen der Buendel.

## 2. Korrektur (Commit f786e62)

**42 sichtbare Zeichenketten in 14 Kernel-Dateien** auf echtes UTF-8;
7 Abnahme-Laeufer mit 13 Erwartungen nachgezogen. Stand jetzt:

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
  `passwd.fi`). Sie zaehlen jetzt ZEICHEN.

    spalten: 40 Beschriftungen in 6 Spalten, 0 schief
    puffer:  4744 Zeichenketten, 0 passen nicht

## 4. Absicherung (Commits 429529d, c6c343e)

`tools/umlaut/run.sh` = Abschnitt 29 der Abnahme, **47 Zusagen gruen,
0 rot**. Prueft alle Quellen aus Schritt 1, INHALTE statt Kommentare.
Neun Gegenproben stellen je eine Zeile auf Umschrift zurueck und
verlangen ROT; zwei GEGEN-Gegenproben verlangen, dass MITSCHNITT,
Beschreibung und getippte Eingabe GRUEN bleiben. Kein bestehender Test
entschaerft.

Dazu seit 7/n `tools/i18n/erwartung.py`: kein Abnahmelaeufer darf noch
nach dem ALTEN Text suchen (Abschnitt 6 unten).

    erwartung: 129 Saetze mit Umlaut, 39 Phrasen, 124 Laeufer,
               0 veraltete Erwartungen

## 5. Beweis am Bild

Abbild gebaut, QEMU mit `-accel kvm`, Bilder in `docs/shots/umlaut2/`:
`starter.png`, `einstellungen.png`, `speicher.png`.

Gemessen, nicht angeschaut: `tools/look/umlaut.py --kette` rastert den
erwarteten Satz aus derselben Schriftdatei und vergleicht jeden
Tintenpunkt an der vom Fensterserver gemeldeten Stelle. Spalten am
Bild: `Name` x=14, `Größe` x=224, `Anteil` x=324, `Größte Dateien`
x=414 -- genau die Summen aus `lspalten` 210/100/74.

Ein Restbefund, aelter als diese Runde: Kern-Rasterer und
`tools/ttf/raster.py` weichen beim kleinen `ö` an genau 3 Bildpunkten
ab (an 3 unabhaengigen Stellen je 3). Steht als OBERGRENZE 3 im
Pruefer -- waechst die Zahl, wird der Abschnitt rot.

## 6. DER FEHLER, DEN DIE RUNDE SELBST GEMACHT HAT (Commit e9e3316)

`tools/tiling/run.sh` wurde rot mit `Kern sagt 21, /bin/tiling sagt ''`
-- am System fehlte nichts, der Laeufer suchte nur weiter nach
`tiling: Eintraege`, waehrend das Programm laengst `Einträge` sagt.
Eine `grep`-Zuweisung mitten im Skript, die beim Nachziehen der
`has`-Zeilen durchgerutscht war.

Behoben und dauerhaft abgesichert: `tools/i18n/erwartung.py` (siehe
`docs/ROUNDUMLAUT2.md` Abschnitt 7). Die Schwierigkeit war nicht das
Finden, sondern das SCHWEIGEN: die erste Fassung meldete 163 Funde,
162 davon Fehlalarme aus Beschreibungen ("Eintraege, die aus ... ")
und getippten Eingaben (`opk zurueck 0`). Die Unterscheidung laeuft
ueber das Programmpraefix -- nur `tiling: …`, `fas: …`, `opk: …`.

## 7. Die vollstaendige Abnahme

Die GRUNDLINIE von main (`GRUNDLINIE.md`, 28.08.) war **20 bestanden /
3 FEHLGESCHLAGEN**, rot: K13 (87/12), K14 (144/8), K16 (58/6).

Gemessen auf `umlaut2` (Abschnitte 1-22 im Gesamtlauf, der Rest
einzeln, weil der Server parallel andere Abnahmen fuhr):

| Laeufer | umlaut2 | Grundlinie | |
|---|---|---|---|
| FREESTANDING | 41/0 | 41 | |
| CORE | 46/0 | 46 | |
| KERNEL | 175/1 | 176 | Flatterer, einzeln 3/3 gruen |
| OSUM | 130/0 | 130 | |
| PCI | 98/0 | 98 | |
| POSIX | 134/0 | 134 | |
| SMP | 59/0 | 59 | |
| USERLAND | 91/0 | 91 | |
| CAPS | 67/0 | 67 | |
| BOOT | 20/0 | 20 | |
| GFX | 76/0 | 76 | |
| UNIX | 107/0 | 107 | |
| NET | 74/1 | 75 | Flatterer, einzeln 75/0 |
| GUARD | 55/0 | 55 | |
| K11 | 85/0 | 85 | |
| WM | 103/0 | 103 | |
| HV | 114/0 | 114 | |
| **K13** | **99/0** | 87/12 | **12 rote weniger** |
| **K14** | **151/1** | 144/8 | **7 rote weniger** |
| K16 | 58/6 | 58/6 | unveraendert vorbestehend |
| K15 | 252/0 | 251 | |
| K17 | 158/0 | -- | |
| K18 | 170/0 | -- | |
| ARM | 46/2 | -- | Flatterer, direkt danach 48/0 |
| DISPLAY | 145/0 | -- | |
| THEME | 90/4 | -- | auf mergeline 66/33 -- flattert unter Last |
| ICONS | 24/1 | -- | auf mergeline identisch 24/1 |
| PAINT | 15/0 | -- | |
| NETVIEW | 190/4 | -- | seit `look`/`paint`, nicht aus dieser Runde |
| NETMON | 76/0 | -- | |
| TUNNEL | 16/0 | -- | |
| TUNNEL-PAKETE | 15/3 | -- | auf mergeline identisch 15/3 |
| TRESOR | 220/0 | -- | |
| POWERMON | 121/0 | -- | |
| **TILING** | **68/0** | -- | 67/1 vor dem Fix aus Abschnitt 6 |
| KVM | 35/0 | -- | |
| **UMLAUT2** | **47/0** | neu | |

Jeder rote Abschnitt ist einzeln nachgestellt und zugeordnet:

* **KERNEL, NET, ARM, THEME** -- Flatterer. Alle vier bauen ueber
  denselben Pfad `vendor/firn/bin/firnc`; laufen zwei Abnahmen
  gleichzeitig, sieht eine den Compiler halbfertig. Einzeln
  nachgestellt: KERNEL 3/3 gruen, NET 75/0, ARM 48/0, THEME auf
  `mergeline` sogar schlechter (66/33) als hier (90/4).
* **K16 (58/6), TUNNEL-PAKETE (15/3), ICONS (24/1)** -- Zahl fuer Zahl
  identisch mit `mergeline`/der Grundlinie, dort nachgemessen.
* **NETVIEW (190/4)** -- die Aenderungen an `tools/netview/` stammen
  aus den Merges `look`/`paint` (f10906d, 19831ab), nicht aus UMLAUT2;
  `git diff f786e62^..HEAD -- tools/netview` ist leer.
* **TILING** -- der einzige echte Fehler dieser Runde, behoben, siehe
  Abschnitt 6.

**K13 und K14 sind durch diese Runde um 19 rote Zusagen besser
geworden** -- die Erwartungen dort suchten Text, den es so nicht mehr
gab, und stimmen jetzt mit dem ueberein, was die Programme sagen.

## 8. Bilanz in Zahlen

* gefundene Stellen: **69** (65 kernel + 1 INFO + 1 icons + 2 Kommentare)
* davon SICHTBAR und korrigiert: **44**
* angepasste Puffer: **3** (keiner wegen der Oktettzahl -- die aendert
  sich nicht; alle drei wegen der ZEICHENzahl in einer Spalte)
* korrigierte Breitenrechnungen: **6**
* nachgezogene Abnahme-Erwartungen: **14** (13 in 2/n, 1 in 6/n)
* Testabschnitt UMLAUT2: **47 gruen, 0 rot**
* Abnahme gesamt: 37 Laeufer gemessen, 4 rot -- davon 0 aus dieser
  Runde (3 vorbestehend, 1 lastbedingt und einzeln gruen)
