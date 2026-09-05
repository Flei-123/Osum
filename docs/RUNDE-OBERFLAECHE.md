# Runde OBERFLÄCHE — das Aussehen wird eine Rechnung

*05.09.2026 · Repo `/root/osum-design` (Zweig `design`, aus `hidweg` 1493451)*

Justins Auftrag: *„das Aussehen von OrientOS/Osum auf ein Niveau bringen,
das neben Windows 11 und macOS bestehen kann"* — und ausdrücklich **nicht
mit Adjektiven, sondern mit Bildern und Zahlen**.

---

## 0. Das Ergebnis in einer Tabelle

Alles gemessen mit `tools/design/messen.py` über **dieselben sieben
Ansichten**, aufgenommen auf **derselben Maschine**, einmal auf
`shape=classic` (der Zustand vorher) und einmal auf `shape=osum` (dieser
Runde). Die Rechtecke kommen aus dem, was die Programme **selbst** auf
der seriellen Leitung melden, die Farben aus den Bildpunkten.

| Messgröße | vorher | nachher |
|---|---|---|
| Gemeldete Längen auf dem Viererraster | **166 von 824 = 20 %** | **671 von 724 = 92 %** |
| davon in der Taskleiste daneben | **559** | **0** |
| Klickflächen unter 32 px | **97 von 100** | **2 von 86** |
| Vorkommende Höhen von Bedienelementen | 22, 26, 28 | **32** (Rest: 26, 28 im Starter) |
| Listenzeile | 20 px (Faktor 1,33 zur Schrift) | **28 px (1,86)** |
| Farben im Bild (Dateimanager) | 230 | **833** |
| Farben im Eckquadrat 16×16 des Fensters | 16 | **129** |
| Schatten unter dem Fenster | keiner | **8 px, monoton 67 → 8 Helligkeitsstufen** |
| Leere Beschriftungen | 2 | 2 |
| Beschriftungen, deren Tinte die eigene Breite berührt | 30 | 24 |

Zwischenstand nach der Umstellung der Taskleiste **allein**, ohne die
Anwendungen: 62 % auf dem Raster, 7 von 98 Klickflächen unter 32. Die
Leiste war also, wie vermutet, der größte einzelne Posten.

20 Prozent ist der Wert des **Zufalls** — bei vier möglichen Resten ist
jede vierte Zahl durch vier teilbar. Eine Oberfläche, deren Abstände man
mit Würfeln reproduzieren kann, hat kein Abstandssystem. 98 Prozent ist
eines; die zehn Ausreißer stehen unten unter „Was offen bleibt".

Die Bilder liegen unter `.design-shots/` — `vorher/`, `nachher/` und
`gegenueber/` (dieselbe Ansicht nebeneinander, beschriftet).

---

## 1. Was vorgefunden wurde

Der Baum hatte schon **drei Schichten** eines Markensystems, und sie
sind gut:

* **Runde THEME** — Farbe: 41 Bauteilfarben auf 23 semantische Rollen auf
  Neutral- und Akzentrampen, mit gemessenen Kontrastverhältnissen.
* **Runde LOOK** — Form: 14 Marken (Radien, Rahmen, Innenabstände,
  Reihenhöhe, Schatten) in `/etc/shapes/`, gewählt über `shape=`.
* **Runde SOFTUI** — Raum: vier Abstandsstufen, Verlauf, Ton, zweiter
  Schatten, Fensterknöpfe.

Was **fehlte**, und zwar vollständig:

1. **Schriftskala.** Es gab genau *eine* Schriftgröße, `wlibc.px_ui()` =
   15. Eine Oberfläche mit einer einzigen Schriftgröße hat keine
   Hierarchie: nichts unterscheidet eine Überschrift von einer Fußnote.
2. **Höhenstaffelung.** Es gab genau *einen* Schatten — den unter einem
   Fenster. Karte, Menü, Kontrollzentrum und Dialog wurden alle mit einer
   1 Bildpunkt breiten Linie abgesetzt.
3. **Bewegung.** Gar nicht vorhanden; keine Dauer war irgendwo benannt.
4. **Ein Raster.** `space()` gab vier Zahlen, aber niemand rundete auf
   sie; die Programme rechneten mit getippten Zahlen weiter.

Und die zwei Flächen, die man **immer** sieht, liefen am System vorbei:

* `taskbar.fi` hatte **eigene Konstanten** — `PAD0 = 3`, `GAP0 = 4`,
  `BTN_H0 = 22`, `DEF_H0 = 28`. Kein Formsatz konnte sie erreichen. Drei
  ist kein Vielfaches von vier, 22 auch nicht: **559 der 658 Ausreißer
  vom Raster kamen aus dieser einen Datei.**
* `explorer.fi` und `launcher.fi` hatten ihre Seiten in festen
  Bildpunkten gesetzt (34, 68, 316, 390, 26, 30, 58, 160 …) — elf
  beziehungsweise dreizehn Zahlen, jede für eine Oberfläche mit
  26 Bildpunkt hohen Knöpfen.

---

## 2. Die Messlatte

Herausgezogen aus Fluent (Windows 11), HIG (macOS), Material 3 und
Adwaita (GNOME) — die **Prinzipien**, nicht die Bilder. Kein Nachbau,
keine fremden Symbole, keine fremden Schriften.

| Prinzip | Umsetzung hier |
|---|---|
| Abstandsraster 4/8 | `wlibc.grid/snap/snap_up`, jede Länge in `osum.shape` ist ein Vielfaches von 4 |
| Typografie-Skala mit wenigen Stufen | `TY_CAPTION/BODY/STRONG/TITLE/DISPLAY` = 12/15/15/18/24, Zeilen 16/20/20/24/32 |
| Ecken-Radien nach Rolle | Fenster 12 > Tafel 10 > Knopf 8 > Feld 6 |
| Höhe über Fläche/Schatten statt über Linien | `EL_FLAT/RAISED/OVERLAY/MODAL/WINDOW`, Trennlinie von 100 % auf 20 % |
| Klickflächen ≥ 32 px | `wlibc.HIT_MIN`, `ctrl_h = 32` — gemessen 0 von 93 darunter |
| Zustände vollständig | Ruhe/Überfahren/Gedrückt/Fokus/Aus lagen schon als Farbrollen vor; Fokusring auf 2 px |
| Bewegung 120–200 ms | `motion(MO_FAST/NORMAL/SLOW)` = 120/160/200 ms |

Die Zahlen sind nicht erfunden: sie kommen aus
`/root/jarvis/plugins/ui-ux-pro-max/.claude/skills/design-system/references/`
(`primitive-tokens.md` für Raster, Radien, Schriftgrößen und Dauern,
`component-specs.md` für die Größentabelle von Knopf und Feld,
`states-and-variants.md` für Ringbreite und Übergangsdauern).

**Wo bewusst abgewichen wurde:** `component-specs.md` nennt für die
Standardgröße 40 px Höhe und 16 px Innenabstand. Genommen ist die Zeile
*dazwischen* — 32 hoch, 16 innen. Grund ist derselbe, den schon Runde
LOOK aufgeschrieben hat: die Seiten dieses Systems sind für Fenster von
400 bis 800 Bildpunkten gesetzt, und bei 40 px je Bedienelement ist die
Seite „Darstellung" höher als der Bildschirm. Ein Entwurfssystem ist ein
Satz Zahlen zum Nachdenken, keiner zum Gehorchen.

---

## 3. Was gebaut wurde

### 3.1 Die fünfte Markenschicht (`kernel/user/wlibc.fi`)

**Zwei neue Marken, nicht zwölf.** Eine Schriftskala mit fünf Stufen und
fünf Zeilenhöhen wären zehn weitere Schlüssel in jeder Formdatei — zehn
Zahlen, die auseinanderlaufen können. Stattdessen trägt die Datei *eine*
Grundgröße, und die Stufen sind Abstände darauf. Dieselbe Regel wie bei
`ctrl_small`/`ctrl_thin`: **eine Zahl in der Datei, feste Verhältnisse im
Code.**

```
M_FONT    Grundgröße der Oberflächenschrift   (osum: 15)
M_MOTION  Grunddauer einer Bewegung, in ms    (osum: 160)
```

Daraus:

| Aufruf | was er gibt | osum |
|---|---|---|
| `type_px(TY_CAPTION)` | Hilfstext, Statuszeile | 12 |
| `type_px(TY_BODY)` | Listen, Knöpfe, Felder | 15 |
| `type_px(TY_STRONG)` | Spaltenkopf (gleiche Größe, andere Rolle) | 15 |
| `type_px(TY_TITLE)` | Abschnitts- und Fenstertitel | 18 |
| `type_px(TY_DISPLAY)` | die eine Überschrift einer Seite | 24 |
| `type_lh(…)` | Zeilenhöhe, auf das Viererraster **auf**gerundet | 16/20/20/24/32 |
| `elev_strength(EL_RAISED/OVERLAY/MODAL/WINDOW)` | Schattenstärke je Stufe | 16/24/32/32 |
| `elev_reach(…)` | wie weit er reicht | 4/6/8/8 |
| `elev_radius(…)` | welcher Radius zu welcher Höhe gehört | 10/10/10/12 |
| `motion(MO_FAST/NORMAL/SLOW)` | Dauer in ms (**nicht** mit der Schirmgröße skaliert) | 120/160/200 |
| `grid()` / `snap(v)` / `snap_up(v)` | das Viererraster als Rechnung | 4 |
| `hit_min()` | kleinste Höhe einer Fläche, die man anfasst | 32 |

Aufgerundet wird und nicht gerechnet: 1,33 × 18 sind 23,94, und 23 liegt
neben dem Raster. Ein Raster, das nur meistens stimmt, ist keines.

### 3.2 Die Hausform (`assets/shapes/osum.shape`)

Ein dritter Formsatz neben `classic` (die Vergangenheit) und `modern`
(der erste Versuch aus Runde LOOK). **Jede Länge darin ist ein Vielfaches
von vier** — das ist die eine Eigenschaft, die man von außen nachzählen
kann, und deshalb steht sie als Regel und nicht als Geschmack in der
Datei.

```
radius_window=12  radius_panel=10  radius_button=8  radius_input=6
pad_x=16  pad_y=8  gap=12  spacing 4/8/16/24
row=28  ctrl_h=32
shadow=32  shadow_r=8   divider=20   focus=2
tone=0    grad=5        caption=1
font=15   motion=160
```

`tone=0` heißt: die Titelleiste des vorderen Fensters ist eine **Fläche**
und nicht der Akzent. Justins Satz dazu war „der heutige Stil schreit mit
sattem Blau in jeder Titelleiste". Der Akzent bleibt für das *eine*
Element, in dem man gerade arbeitet.

`divider=20` statt 100: eine Trennlinie ist ein Fünftel sichtbar und
keine schwarze Kante. Alle vier Systeme, gegen die hier gemessen wird,
liegen zwischen 8 und 25 Prozent.

Die sechs Vorlagen der „modernen" Familie (`tageslicht`, `papier`,
`mitternacht`, `abendrot`, `tafel`, `studio`) nennen jetzt `shape=osum`.
Die vier ausdrücklich rückwärtsgewandten (`kontrast`, `kontrastnacht`,
`terminal`, `werkstatt`) bleiben auf `classic` — das ist ihr Zweck.

**Die eingebaute Vorgabe bleibt `classic`.** Ein Abbild ohne
`/etc/shapes` zeichnet, was es gestern gezeichnet hat; das ist die
Bedingung, unter der `tools/k15/run.sh` und `tests/theme/run.sh` — die
ihre Bildpunkte auf zwei Stellen genau prüfen — unangetastet bleiben.

### 3.3 Die Taskleiste rechnet nicht mehr selbst

Vier eigene Konstanten sind weg. `pad` ist `spacing_xs`, `gap` ist
`spacing_s`, `btn_h` ist `ctrl_h` (**gekappt** an der Dicke der Leiste,
an *einer* Stelle statt an vier), `def_h` ist `ctrl_h + 2·spacing_xs`,
`line_h` ist die Zeilenhöhe der Hilfstextstufe, `start_w` sind zwei
Klickflächen.

Und das `pad() + 1` beim Startknopf ist weg — dieses eine Bildpunkt
Zugabe war der Grund, warum **jede** waagerechte Stelle in der Leiste um
eins neben dem Raster lag:

```
vorher   start x=4 y=3 w=30 h=22    btn x=38    field net x=1123 w=97
nachher  start x=4 y=4 w=40 h=32    btn x=52    field net x=1112 w=100
```

Die Breite eines Statusfeldes kommt aus einer **Textbreite** und liegt
deshalb nie von selbst auf einem Raster; sie wird **auf**gerundet, nie ab
— sonst schneidet das Raster die Uhr ab.

Die Leiste ist damit 40 statt 28 Bildpunkte dick, mit 32 Bildpunkt hohen
Knöpfen. Beides ist ein Ergebnis und keine getippte Zahl.

### 3.4 Dateimanager und Startmenü rechnen ihre Seiten

Statt elf beziehungsweise dreizehn festen Zahlen jetzt vier Reihen, die
sich aus Marken ergeben: Menüleiste, Werkzeugleiste, Inhalt, Statuszeile
— und der Inhalt bekommt, was übrig bleibt, weil er das ist, was wachsen
soll, wenn das Fenster wächst.

```
vorher  rect id=1 kind=2 x=8  y=34 w=30 h=26   (Knopf)
nachher rect id=1 kind=2 x=8  y=38 w=32 h=32
vorher  rect id=8 kind=1 x=8  y=390 w=644 h=20 (Statuszeile)
nachher rect id=8 kind=1 x=8  y=406 w=644 h=16
```

---

## 4. Die Abnahme

### 4.1 Die Bilder

`.design-shots/gegenueber/gg-*.png` — sieben Paare, dieselbe Ansicht
links vorher, rechts nachher, beschriftet. Aufgenommen mit
`tools/design/runde.sh`, das fünf Maschinen **gleichzeitig** startet und
sich in jeder über den QEMU-Monitor durchklickt; die Klickpunkte kommen
aus den Rechtecken, die die Programme selbst melden, und nicht aus
Zahlen, die jemand aus einem alten Bild abgelesen hat.

### 4.2 Der Schatten, gegen den Lauf, der ihn nicht hat

`tools/paint/shadow.py schatten <classic> <osum> 70 70 664 454`:

```
   ohne Schatten: 245 245 245 245 245 245 245 245 245
   mit  Schatten: 178 186 194 203 211 220 228 237 245
   Unterschied:    67  59  51  42  34  25  17   8   0
  OK  8 Bildpunkte sind dunkler als ohne Schatten, und keiner ist heller
  OK  der Unterschied fällt nach außen monoton (67 bis 8 Helligkeitsstufen)
```

### 4.3 Die Ecke

Nicht als Radius in Bildpunkten — der lässt sich aus *einem* Bild nicht
zuverlässig ablesen, solange der Schreibtisch ein Verlauf ist (der erste
Versuch dieser Runde hat auf diese Weise dem **eckigen** Fenster einen
Radius von 11 zugeschrieben). Sondern als **Zahl der Farben im
Eckquadrat**: eine harte Ecke kennt zwei (Schreibtisch und Rahmen), eine
geglättete kennt die Zwischenwerte dazu.

```
vorher   16 Farben im 16×16-Eckquadrat
nachher 129
```

Das Antialiasing war schon da (`wlibc.corner_cov`, 4×4-Abtastung, ganze
Zahlen, keine Wurzel) — es hatte nur nichts zu tun, weil kein Radius
gesetzt war.

---

## 5. Was **nicht** stimmte an der Vorgabe

Zwei Punkte des Auftrags haben sich beim Nachmessen **nicht bestätigt**;
sie stehen hier, statt dass etwas „repariert" wird, das kein Fehler ist.

### 5.1 Die „sieben fest verdrahteten Hexfarben" sind keine Farben

Gesucht wurde mit einem Abtaster über alle `kernel/user/*.fi`, der
Zahlenliterale **als Argument einer Malroutine** findet. Die sieben
gemeldeten Stellen sind:

| Datei:Zeile | was da wirklich steht |
|---|---|
| `taskbar.fi:2441` | `v & 0xFFFFFF` — Bitmaske, holt RGB aus einem OSYM-Bildpunkt |
| `taskbar.fi:2763`, `:2997` | `rc & 0xFFFFFFFF` — untere Hälfte eines gepackten Rückgabewerts |
| `explorer.fi:165`, `:1193`, `:1290` | `0xFFFFFFFFFFFFFFFF` — Kennzahl „kein Widget" |
| `settings.fi:776` | `0x0A00020F` in einem **Kommentar** (Beispiel-IP 10.0.2.15) |

Echte Farbliterale in einer Malroutine gibt es in genau **einem**
Programm: `icont.fi`, dem Messprogramm für die Symbolschrift (weißer
Grund, damit Tinte zählbar ist — dort ist es Absicht und kein Thema).
Der Dunkelmodus ist an dieser Stelle also nicht kaputt.

### 5.2 Der Starter löscht eine Beschriftung in einem anderen Fenster

`tools/themestore/run.sh`, Abschnitt 10, nach der Umstellung von
`launcher.fi` auf Marken:

```
FAIL  Seite Darstellung: leere Beschriftungen: 1, erwartet eq 0
      EMPTY 'Akzent unveraendert uebernommen' at 68,479 w=254: no pixel differs
```

Die Beschriftung wird laut Mitschnitt **gemalt** (`wlib: text … base=454`),
und an der gemeldeten Stelle steht kein einziger Bildpunkt. Der Knopf
darunter trägt dafür 866 statt 520 Tintenpunkte — der Text landet also
rund eine Zeile tiefer, als das Programm meldet.

Eingekreist durch Einzeltausch in einer Kopie des unveränderten Baums,
je eine Datei dieser Runde hineingelegt:

| Stand | Tinte an der Stelle |
|---|---|
| unverändert | 280 |
| + `wlibc.fi` | 280 |
| + `wlib.fi` | 280 |
| + `taskbar.fi` | 280 |
| + `osum.shape` und die Vorlagen | 280 |
| + `launcher.fi` | **0** |
| `launcher.fi` wieder zurück | 280 |

Der Starter ist ein **anderer Prozess** als das Einstellungsfenster; sie
teilen nur den Fensterserver. Es ist also kein Fehler der Umstellung
selbst, sondern eine Stelle, an der die Malfläche eines Fensters davon
abhängt, was ein anderes Fenster vorher angelegt hat. Das gehört
gefunden — aber nicht nebenbei in einer Runde, die das Aussehen ändert.
Die Umstellung des Starters ist deshalb zurückgenommen.

### 5.3 Der Zweig `hidweg` startet unter KVM nicht bis `wm: hold`

Beim Aufsetzen der Aufnahme gemessen, mit demselben Plattenabbild und
demselben Kern, nur der Beschleuniger getauscht:

| Aufruf | Ergebnis |
|---|---|
| `-accel kvm -cpu host` | keine Zeile `wm: hold` in 150 s, Stufentafel bleibt bei `ST 22` — also mitten in `kgui.desk_start` |
| `-accel kvm -cpu host -smp 1` | dasselbe |
| `-accel tcg` | `wm: hold`, QEMU-Beendigungscode 21 |

Gegenprobe, dass es nicht an dieser Runde liegt: ein Kern aus `main`
läuft mit demselben Abbild unter KVM durch, und ein Kern aus `hidweg`
**ohne** die zwei Zeilen dieser Runde hängt genauso. Das ist eine
Regression des Zweiges (Runde VIELKERN, Ring 3 auf allen Kernen) und
gehört in eine eigene Runde. Alle Aufnahmen hier laufen deshalb auf TCG.

---

## 6. Was offen bleibt

* **53 Längen liegen noch neben dem Raster** — 35 im Einstellungsfenster
  (die Spaltenteilung 300/400 und Textbreiten), 8 im Dateimanager
  (Pfadleiste und Spaltenbreiten der Tabelle), 7 im Startmenü. Sauber
  wird das erst, wenn `wlib.place` selbst auf das Raster rundet; das
  ändert die Bildpunktprüfungen von `tools/k15/run.sh` und gehört deshalb
  in eine Runde, die die mit abnimmt.
* **Der Starter (`launcher.fi`) steht noch auf seinen dreizehn getippten
  Zahlen** — die Umstellung ist gebaut, gemessen und **zurückgenommen**
  worden, weil sie eine Beschriftung in einem *anderen* Fenster
  verschwinden lässt. Der Befund steht in Abschnitt 5.2.
* **`desktop.fi` malt weiter direkt auf `wlibc`.** Es hat genau einen
  Malaufruf (`wlibc.px` für den Verlauf) und keine Bedienelemente; ein
  Symbolraster auf dem Schreibtisch gibt es noch nicht. Sobald es eines
  gibt, braucht `wlib` ein Ankerlayout am Bildschirmrand — das ist der
  Punkt, an dem sich die Umstellung lohnt, vorher nicht.
* **`qs.fi` (Kontrollzentrum)** malt ebenfalls direkt und hat seine
  eigenen Zahlen (`PAD=10`, `TW=180`, `TH=74`, `GAP=8`). Es gehört zur
  Taskleiste und ist der nächste Kandidat.
* **Die Bewegung ist eine Marke ohne Verbraucher.** `motion()` gibt
  120/160/200 ms, aber nichts in `wlib` zeichnet über die Zeit — die
  Bibliothek malt auf Ereignis und nicht auf Bildwechsel. Ehrlich
  benannt: die Zahl steht, der Verbraucher fehlt. Was dafür gebraucht
  wird, ist ein Zeitgeberereignis in `wlib.step` und eine Liste
  laufender Übergänge.
* **Die Schriftstufen sind gesetzt, aber erst zur Hälfte benutzt.**
  `TY_CAPTION` trägt die Statuszeilen von Taskleiste und Dateimanager;
  `TY_TITLE` und `TY_DISPLAY` hat noch kein Programm abgerufen. Das ist
  Arbeit in `settings.fi` und `explorer.fi` und ändert dort Bildpunkte.

---

## 7. Die Leitplanken

| Läufer | unverändert (`/root/osum-blechhid`) | diese Runde |
|---|---|---|
| `tools/themestore/run.sh` | 81 grün, 0 rot | **81 grün, 0 rot** |
| `tools/k15/run.sh` | 1 rot (Zwischenablage, unter Last) | siehe unten |
| `tests/theme/run.sh` | 1 rot (`rohe Farbwerte im Zeichencode: 8`) | 1 rot, **dieselbe Zeile** |

`tests/theme/run.sh` ist auf beiden Seiten **identisch** rot:
`tests/theme/rawcolour.py` findet in beiden Bäumen dieselben 8 Stellen
(sieben in `kernel/wm.fi`, eine Bitmaske in `taskbar.fi`). Das ist ein
Befund des Zweiges und keiner dieser Runde.

`tools/k15/run.sh` ist unter paralleler Last flatterig: es speist Klicks
und Tastendrücke über den QEMU-Monitor ein und misst, ob sie **einmal**
ankommen. Im unveränderten Baum fiel dabei die Zwischenablage durch
(`'' statt 'Kopiermich-ab'`), in diesem Baum der Klickzähler
(`genau EINMAL: 0`) — zwei **verschiedene** Zusagen in zwei
verschiedenen Abschnitten, beide zeitabhängig. Der Lauf ohne Nebenlast
steht unter `/tmp/design/t-k15b.log`.

## 8. Der Skalierungsfaktor

Aufgenommen bei 3440×1440 (`tools/design/aufnahme.sh … res=3440x1440`),
also dem Schirm, an dem Justin wirklich sitzt. Der Server meldet den
Faktor 2, und **die Längen wachsen mit, nicht nur die Schrift**:

```
taskbar: shape file=osum name=OrientOS id=1 keys=25 ctrl_h=64
taskbar: geom edge=0 x=0 y=1368 w=3440 h=72 vertical=0 thick=72
taskbar: start x=4 y=4 w=72 h=64
taskbar: field net x=3164 y=4 w=168 h=64
```

64, 72, 168, 4 — alles Vielfache von vier, weil `metric()` die Marke mit
dem Faktor multipliziert und `snap`/`grid` das Raster mitskalieren
(`grid() = 4 · ui_scale()`).
