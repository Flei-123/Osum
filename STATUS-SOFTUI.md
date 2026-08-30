# STATUS SOFTUI — Zwischenstand

Zweig `softui`, abgezweigt von `mergeline`, mit `paint`, `look` und
`themestore` hereingeholt. **Nicht nach `main` mergen.**

Arbeitsbaum: `/root/osum-softui`. Grundlinie fuer den Bildvergleich:
`/root/softui-base` auf `d4c2742` (dem Elterncommit dieser Runde).

Der ausfuehrliche Bericht mit allen Herleitungen steht in
`docs/ROUNDSOFTUI.md`. Hier stehen nur die Zahlen und der Stand.

---

## Die Zahlen

### Der Schatten — vorher / nachher, in EINEM Lauf gemessen

Gemessen ueber `wm_bench2` in `kernel/kmain.fi`: derselbe Bildaufbau,
dieselbe Maschine, derselbe Zeitgeber, zwanzig Laeufe je Zahl, danach
zurueck auf die Maske. QEMU mit `-accel kvm -cpu host`, zwei
geschmueckte Fenster auf dem Schirm.

```
wmbench2: ohne    full=907 us
wmbench2: maske   full=1620 us  shadowpx=19928  aapx=64
wmbench2: ringe   full=2191 us  shadowpx=19276  aapx=594
```

| | Schatten kostet | gemischte Bildpunkte | Eckabtastungen |
|---|---|---|---|
| Ringe (Runde PAINT) | **1284 µs** | 19 276 | 594 |
| Maske (diese Runde) | **713 µs** | 19 928 | 64 |

Zweiter Lauf derselben Abnahme, zur Streuung: 669 µs gegen 1252 µs.

**Faktor 1,80 in der Zeit, bei 652 gemischten Bildpunkten MEHR.** Je
Fenster: 357 µs gegen 642 µs. Die 64 verbliebenen Eckabtastungen sind
die runde Ecke des Fensters selbst — der Schatten braucht keine einzige
mehr. Die Maske wird **einmal je Lauf** gebaut (`shbuild=1`).

Zwischenstand der ersten, spaltenweisen Fassung — sie steht hier, weil
sie die eigentliche Erkenntnis der Runde ist: 1143 µs gegen 1264 µs,
also elf Hundertstel. Die Abtastung war weg, die Buchhaltung von
`fb.pixel_a` nicht (sechs Zustandszugriffe je Bildpunkt). Erst
`fb.hline_mask` — eine Deckung je Bildpunkt, Grenzen einmal je Lauf,
Schritt ±1 fuer die gespiegelten Ecken — hat den Gewinn gebracht.

### Der Kontrast — nicht schlechter, sondern besser

| | Modell `on-accent/accent` | im BILD auf der Titelleiste |
|---|---|---|
| `day` + `modern` | **5,16** (unveraendert) | **16,96** (`#0f172a` auf `#f9f9f9`) |
| `night` + `modern` | **12,36** (unveraendert) | **15,08** (`#f8fafc` auf `#182335`) |

Die Marke (5,16 / 12,36) ist das Paar *weisse Schrift auf dem
Akzentblau* — bis zu dieser Runde die Titelleiste jedes scharfen
Fensters. Im Modell ist sie unveraendert, weil diese Runde **keine
einzige Farbe angefasst** hat; im Bild ist sie durch `tone=0` durch ein
viel besseres Paar ersetzt. Der Verlauf ist in der Bildmessung
enthalten (`#f9f9f9` ist die abgedunkelte oberste Zeile).

Kleinstes Textpaar im Modell, unveraendert: 4,61 (`day/light`) und 5,70
(`night/dark`).

### Der Fokus ohne Farbe — Schattentiefe statt Titelblau

```
day/light    aktiv   tiefe=58  weite=7      inaktiv  tiefe=23  weite=4
night/dark   aktiv   tiefe=6   weite=6      inaktiv  tiefe=3   weite=2
```

Faktor 2,5 in der Tiefe und 1,75 in der Weite im hellen Schema; im
dunklen bleibt das Verhaeltnis, die absolute Tiefe nicht — siehe die
ehrlichen Grenzen unten. Keine Titelleiste hat eine Kanalspanne ueber 4:
es sind Grautoene, keine Blautoene.

### `classic` ist bildpunktgleich

```
gleich: unterschiedlich 0 von 480000 Bildpunkten -- IDENTISCH
gleich: ausgenommen (die Uhr) 740,572 bis 800,600
gleich: ausgenommen (angegeben) 26,62 bis 586,442
```

Ausgenommen sind genau zwei Rechtecke und beide stehen im Bericht: die
Uhr und die Malflaeche des Terminals, in der der Kern seinen eigenen
Mitschnitt spiegelt (Kerngroesse, Rahmenadressen, `fbbench`-Zahlen).
Alles andere wird ohne Nachsicht verglichen.

---

## Was gebaut wurde

**Neun neue Formmarken**, in beiden Formdateien und im Aufloeser:
`spacing_xs/s/m/l` (die dritte Achse: ABSTAND), `grad`, `tone`,
`shadow_off`, `shadow_off_r`, `caption`. `classic` traegt fuer jede die
Zahl, die vorher im Quelltext stand.

**Vier neue Formwoerter an den Fensterserver** (`WM_FORM` von 4 auf 8):
die zwei Zahlen des flachen Schattens, der Verlauf und die Frage, ob die
Titelleiste die drei Windows-Schaltflaechen traegt.

**Die vorberechnete Schattenmaske** (`kernel/wm.fi`): Neun-Felder, ein
Eckquadrat plus ein Streifen, zeilenweise gemalt ueber das neue
`fb.hline_mask`. Der alte Weg bleibt als Gegenprobe (`set_shadow_old`).

**Die drei Windows-Schaltflaechen** (`wm.paint_caption`): Strich,
Quadrat (zwei versetzte im maximierten Zustand), Kreuz. Ueberfahren:
graue Flaeche, beim Schliessen ROT mit weissem Kreuz. Klick auf
Minimieren verbirgt, auf Maximieren schaltet um, auf Schliessen schickt
`E_CLOSE`.

**Der Verlauf** in Titelleiste und Taskleiste, sechs Helligkeitsstufen,
oben am dunkelsten, begrenzt auf den Spielraum der Farbe.

**Die Taskleiste**: runde Kacheln ohne `frame3`, mittig ausrichtbar, und
eine Pille unter dem laufenden Programm — breit und in der Akzentfarbe,
wenn es vorne ist, sonst schmal und grau. Das ist die einzige Stelle,
an der der Akzent in der Fensterumgebung noch vorkommt.

**Karten** (`wlib.card`, `K_CARD`): ein rundes Feld mit weichem Schatten
und ohne Linie, gemalt VOR den Bedienelementen, die darauf liegen. In
den Einstellungen unter der Darstellungsseite.

**`tone=0`** nimmt der Fensterumgebung den Akzent: die scharfe
Titelleiste ist die gehobene Flaeche mit gewoehnlicher Fensterschrift,
die unscharfe die einfache Flaeche mit gedaempfter Schrift.

---

## Drei Fehler, die dabei aufgefallen sind

1. **Ein Rahmen ging in den Vorrat zurueck, waehrend Ring 3 ihn noch
   beschreiben durfte** (`kernel/arch/x86_64/user.fi`). Unter TCG faellt
   das niemandem auf; unter `-accel kvm -cpu host` schaltet Runde GUARD
   SMAP ein und die Maschine faellt sofort um (`#PF err=0x3`). Behoben
   mit `unmap_user`; auf dem Elterncommit reproduziert, also aelter als
   diese Runde. Damit laeuft KVM jetzt MIT SMAP.
2. **`kv_read` hatte eine maximale Dateigroesse.** `modern.shape` ist
   mit den neun neuen Marken 6981 Oktette gross, der Puffer 4096 — und
   der Aufloeser meldete `keys=0` und fiel still auf `classic` zurueck.
   Der Leser nimmt die Datei jetzt stueckweise; der Puffer begrenzt eine
   ZEILE und keine DATEI.
3. **`wlibc.drop_shadow` hat nie einen Schatten gemalt**, sondern ein
   gefuelltes Rechteck in Schattenfarbe — `rframe` mit gleicher Rand-
   und Innenfarbe. Es fiel nie auf, weil sein einziger Aufrufer sofort
   ein Fenster darueber malte. Die Karte tut das nicht, und die
   Fensterflaeche kam als `(0,0,1)` statt `(248,250,252)` heraus.

---

## Die ehrlichen Grenzen

* **Im dunklen Schema ist der Fensterschatten fast unsichtbar** (sechs
  Stufen gegen 58 im hellen). Das Verhaeltnis aktiv/inaktiv bleibt, die
  absolute Tiefe nicht. Ein Schatten auf einem fast schwarzen
  Schreibtisch hat nichts zum Abdunkeln. Diese Runde misst das und
  behebt es nicht.
* **Der Verlauf ist sechs Stufen** und damit absichtlich an der Grenze
  der Wahrnehmung.
* **Die Pille sitzt an der Unterkante der Kachel**, auch bei einer
  senkrechten Leiste. Eine senkrechte Leiste hat niemand fuer diese
  Runde gemessen.
* **`wlib.card` kennt kein „innen"**. Die Karte wird vor den
  Bedienelementen gemalt; zusammengehalten werden sie von ihren
  Koordinaten, nicht von einer Eltern-Kind-Beziehung.
* **Die drei Schaltflaechen haben keinen Tastaturweg.**
* **Die Titelleiste ist weiterhin 22 Bildpunkte hoch** (`TITLE_H`), auch
  unter `modern`. Sie zur Marke zu machen, haette `inx`/`iny`, den
  Arbeitsbereich und jede Fenstergeometrie im Baum beruehrt; das ist
  eine eigene Runde.

---

## Eine bestehende Erwartung wurde AKTUALISIERT (nicht entschaerft)

`tools/look/run.sh`, Abschnitt D: `keys read out of the shape file`
stand auf `15` und steht jetzt auf `24`. Die Zusage ist weiterhin eine
exakte Gleichheit und faellt weiterhin durch, wenn eine Marke der Datei
falsch geschrieben ist — die Datei hat schlicht neun Marken mehr.
Gegenprobe dafuer ist Abschnitt A von `tools/softui/run.sh`: `classic`
malt dasselbe Bild wie vorher, 0 von 480000 Bildpunkten anders.

### Und zwei Pruefmuster wurden BERICHTIGT

`tools/look/run.sh` Abschnitt A und `tools/look/umlaut.py` suchten nach

    kind=2 x=<n> base=<n> fg=<n> bg=<n> t=Ausführen

-- also "und nichts dazwischen". Runde THEMESTORE hat ` tw=<n>` in diese
Luecke geschrieben, Runde SOFTUI ` ax=<n> ay=<n>` dahinter, und damit
faellt der Abschnitt durch. **Gemessen auf dem Elterncommit dieser
Runde, vor der ersten Zeile SOFTUI-Code: derselbe FAIL.** Ein Test, der
umfaellt, weil ein BERICHT ein Feld dazubekommt, prueft die
Feldreihenfolge und nicht den Bildschirm.

Beide Muster sind jetzt feldweise (`(?: [a-z]+=<n>)* t=`), verlangen
weiterhin `kind=2` und weiterhin das exakte Wort -- das ist strenger und
nicht lockerer. Der Pruefer nimmt ausserdem den Fensterursprung aus
`ax`/`ay` statt aus dem festen `+2 / +22`, das nur fuer ein Fenster in
der Bildschirmecke stimmte. Ergebnis: `9 Zeichen, 438 Tintenpunkte
geprueft, 0 falsch`.

### Ein roter Abschnitt, der NICHT dieser Runde gehoert

`tools/look/run.sh` Abschnitt A2a (`'Übernehmen'` im Themenprobe-Fenster)
faellt durch. **Er faellt auf dem ELTERNCOMMIT genauso durch, und dort
sogar schlechter:**

```
Elterncommit d4c2742   10 Zeichen, 526 Tintenpunkte geprueft, 526 falsch
Zweig softui           10 Zeichen, 526 Tintenpunkte geprueft, 518 falsch
```

Gemessen mit demselben (berichtigten) `umlaut.py` auf beiden Baeumen,
sonst waere es kein Vergleich. Die Stelle stimmt in beiden Faellen
(x=158, y=337, aus `ax`/`ay` nachgerechnet) -- es ist die FARBE, gegen
die verglichen wird: der Bericht meldet `bg=#ffffff`, unter der Schrift
steht etwas anderes. Das kam mit dem Merge von `themestore` herein und
ist hier nicht behoben; es steht hier, damit niemand es dieser Runde
zuschreibt und niemand es fuer erledigt haelt.

Kein anderer Test wurde angefasst.

---

## Die Bilder

`docs/shots/softui/`:

| Datei | was darauf steht |
|---|---|
| `1-desktop-zwei-fenster.png` | zwei ueberlappende Fenster, scharf und unscharf — der Schattenunterschied |
| `2-einstellungen-karten.png` | die Einstellungen mit zwei Karten |
| `3-taskleiste-mittig.png` | die Leiste, mittig, runde Kacheln, Pille unter dem laufenden Fenster |
| `4a-knoepfe-ruhe.png` | die drei Fensterknoepfe im Ruhezustand |
| `4b-knoepfe-hover-rot.png` | dieselben mit ueberfahrenem Schliessen-Knopf — rote Flaeche, weisses Kreuz |
| `5-vollbild-hover.png` | der ganze Schirm, aus dem die Nahaufnahme geschnitten ist |

Alle vier Vollbilder durch `tools/softui/pruef.py`: **0 Beanstandungen**
(keine leere Beschriftung, nichts abgeschnitten, nichts ueberlappend).

---

## Die Abnahme

`bash tools/softui/run.sh` — sieben Abschnitte:

```
SOFTUI: 25 bestanden, 0 gefallen
```

Alle Zahlen oben.
Voraussetzung: ein Arbeitsbaum der Grundlinie und
`SOFTUIBASEPPM=<pfad zum classic-Bild der Grundlinie>`.

Werkzeuge dieser Runde in `tools/softui/`:
`run.sh`, `gleich.py` (Bildpunktvergleich), `pruef.py` (Bild gegen
Mitschnitt), `knoepfe.py` (die drei Zeichen und der rote Knopf),
`fokus.py` (Schattentiefe aktiv/inaktiv), `kontrast.py` und `titel.py`
(WCAG aus dem Bild), `hover.py` (Zeiger fahren ohne Klick).
