# BEFUND ZIEH (21.09.2026)

Arbeitsbaum `/root/osum-zieh`, Zweig `runde-zieh`, ab dem Merge
`986acdc2`. Alle Zahlen sind an einer laufenden Maschine gemessen
(QEMU/KVM, 1280x800, `scheme=day mode=light shape=osum`, `lang=de`).

Drei Aufträge: die Runde `runde-oberflaeche` nach `main`, den Zweig
`a11y` prüfen, und Justins Zieh-Animation bauen.

---

## TEIL 1 — `runde-oberflaeche` nach `main`

**Konfliktfrei gemergt, Commit `986acdc2`.** Sechs Dateien geändert,
sechs neu.

Die Gegenprobe, die zählt, ist nicht "der Merge lief durch", sondern
ob die Wirkung noch da ist. Gewöhnliches Hochfahren, **ohne** den
Vorführschalter `wmanim`:

| Baum | `anim=` |
|---|---|
| `main` `211f8e1b` | **0** |
| nach dem Merge `986acdc2` | **4** |

    wm: vsync=0  comp=166  pres=0  pxsum=0  pend=0  anim=4  frames=0  ticks=2000

Vier Fenster gehen beim Hochfahren auf, vier angemeldete Bewegungen.
Nachrechenbar mit `bash pruef/anim-ab.sh <arbeitsbaum> <ausgabe>`.

Mitgekommen sind das Minimieren zum eigenen Leistenknopf (`WM_MINRECT`,
2127) und die Regression-Behebung `51d81668`. Die Prüfung, die daran
hängt, ist unten in den Abnahmen: `tools/logind/run.sh` **49/0** mit
`fl=18`.

---

## TEIL 2 — der Zweig `a11y`

**NICHT MITGENOMMEN, und zwar nicht aus Zeitmangel.** Er lässt sich auf
diesen Baum nicht sauber aufsetzen, und der Versuch wäre kein Merge
mehr, sondern eine Neuschreibung.

`a11y` zweigte bei `5cb03208` ab. `main` ist seither **1078 Commits**
weiter und hat den Kernel dazwischen **umstrukturiert** (Runde
O-STRUKTUR, Commit `7af0e12b`): aus dem flachen `kernel/*.fi` wurden
`kernel/ui/`, `kernel/sys/`, `kernel/sched/`, `kernel/lib/` und weitere.

Probemerge auf `986acdc2`, wirklich durchgeführt:

    13 Konflikte
    davon 3 modify/delete auf Dateien, die es auf main NICHT MEHR GIBT:
      kernel/wm.fi        (heute kernel/ui/wm.fi,  4083 gegen 9597 Zeilen)
      kernel/kstate.fi    (heute kernel/lib/kstate.fi)
      kernel/user/leiste.fi (heute kernel/user/taskbar.fi)
    kernel/user/wlib.fi allein: 35 Konfliktblöcke, 1218 Konfliktzeilen

Das allein wäre Arbeit, aber machbar. Der harte Blocker ist ein
anderer:

### Die Systemaufruf-Nummern kollidieren

| Zweig | Nummer | Name |
|---|---|---|
| `a11y` | **1960**..1965 | `AX_PUSH`, `AX_READ`, `AX_EVENT`, `AX_PERM`, `AX_INFO`, `AX_SET` |
| `main` | **1960** | `SYS_OSUM_BUS` |

Beide beanspruchen 1960. Der Kommentar in `a11y` begründet die Wahl
ausdrücklich ("zwischen `SYS_OSUM_WGSET` (1951) und `CAP_BASE` (2000)")
— und genau in diese Lücke hat `main` inzwischen den Systembus gelegt,
mit derselben Begründung, Wort für Wort. Zwei Runden, dieselbe freie
Stelle, kein gemeinsamer Text: ein Textverschmelzer sieht das nicht.

Wer `a11y` will, muss den Baum um sechs Nummern verschieben, alle Rufer
nachziehen und 4958 Zeilen auf eine Verzeichnisstruktur umheben, die es
beim Schreiben noch nicht gab. Das ist eine eigene Runde, und sie
gehört **vor** die nächste Oberflächenrunde, nicht mitten hinein.

**Der Befund der Vorrunde war also richtig, aber aus dem zu schwachen
Grund.** Sie schrieb, `a11y` fasse dieselben drei Dateien an. Das
stimmt — der eigentliche Grund ist aber, dass es diese drei Dateien an
ihrem Ort nicht mehr gibt und die Nummern belegt sind.

---

## TEIL 3 — Justins Zieh-Animation

**GEBAUT.** Drei Wirkungen, jede einzeln schaltbar und in der Stärke
regelbar, wie bestellt.

### Was der Server jetzt kann

| Marke | Bereich | Wirkung |
|---|---|---|
| `FM_LIFT` (9) | 0..120 | das Fenster wird beim Ziehen größer, in Tausendsteln über 1000. **50 = 105 %** |
| `FM_TILT` (10) | 0..100 | der Pivot rückt von der Mitte an die **angefasste Stelle** |
| `FM_SWING` (11) | 0..100 | das **Bild** zieht mit Trägheit nach und pendelt aus |

**Jede Zahl ist Schalter UND Regler: 0 heißt aus.** Dieselbe Regel wie
bei `FM_SHADOW`, und sie spart einen Zustand, der auseinanderlaufen
kann — ein Schalter neben einem Regler kann sich widersprechen, eine
Zahl nicht.

### Keine echte Kippung, und warum nicht

Der Auftrag sagt es schon, und die Messung bestätigt es: eine echte
Kipp-Transformation kann dieser Server nicht. Sie bräuchte je
Zielbildpunkt eine Rücktransformation mit Sinus und Kosinus; der Kernel
rettet in `syscall` kein SSE (siehe `ease_out`, das deshalb ganzzahlig
rechnet), und `paint_win_anim` tastet zeilenweise mit
Nachbarabtastung ab. Eine gedrehte Fläche wäre eine Treppe aus
Rechtecken.

Gebaut ist deshalb die Näherung, die die Vorrunde schon als richtigen
Weg benannt hat: **Versatz und Skalierung um einen verschobenen
Pivot.** Das Fenster wächst, und der Punkt, der dabei stehen bleibt,
ist bei `tilt=100` die Stelle unter dem Zeiger. Genau das ist die
Wahrnehmung "ich habe es an dieser Ecke angefasst".

### Die wahre Lage bleibt unberührt

`W_X`/`W_Y` folgen dem Zeiger **ohne jede Verzögerung**. Nur das Bild
hängt hinterher. Das ist keine Sparmaßnahme, sondern die Bedingung
dafür, dass man ein Fenster noch zielgenau ablegen kann — und
`drag_hover`, die Andockvorschau, rechnet ohnehin mit der wahren Lage.

### Gemessen: die Skalierung

Fenster 360x240, `lift=50`. Das Muster im Fenster hat einen gelben
Block von 140x80, der nicht am Rand klebt und deshalb sauber messbar
ist.

| | Breite | Höhe | gelb breit | gelb hoch |
|---|---|---|---|---|
| in Ruhe | 360 | 240 | 140 | 80 |
| **am Haken** | **378** | **252** | **147** | **84** |
| Sollwert (×1,05) | 378 | 252 | 147 | 84 |

**Alle vier exakt.**

Die Messung brauchte dafür eine eigene Vorkehrung: ein Foto **mitten in
der Bewegung** erwischt zwei Zwischenbilder übereinander. Gemessen als
387 statt 378 Bildpunkte Breite — und 9 ist genau ein Zugschritt. Die
Vorführung lässt das Fenster deshalb bei Tick 100..180 **am Haken
stillstehen**; dort ist die Zahl eindeutig.

### Gemessen: der Pivot

Ein Bildschirmfoto sagt, wo das **Bild** liegt. Die Frage des Pivots
ist gerade, wie weit das Bild gegen die **wahre** Lage versetzt ist —
zwei Unbekannte, eine Gleichung. Die zweite liefert die Zeile
`zieh: t=… x=… y=… sx=… sy=…`, die der Kern je Tick schreibt.

| | Pivot im Fenster | Versatz des Bildes | Bildecke gemessen | aus wahrer Lage |
|---|---|---|---|---|
| `tilt=0` | (180\|120), die Mitte | **(-9\|-6)** | (320\|304) | t=83 (327\|288) |
| `tilt=100` | (38\|0), der Griff | **(-1\|+0)** | (418\|270) | t=93 (417\|248) |

Beide Male geht die Rechnung **bildpunktgenau** auf. Bei `tilt=100`
bleibt der angefasste Punkt praktisch stehen, bei `tilt=0` wandert er
um neun Bildpunkte weg.

### Gemessen: der Nachzug

`swing=35`, Zug mit 9 Bildpunkten je Tick nach rechts:

    t=62  sx=-3    der Versatz baut sich auf, GEGEN die Bewegung
    t=70  sx=-9    ...
    t=98  sx=-15   Gleichgewicht zwischen Aufbau und Abklingen
    t=100 sx=-16   letzter Zugtick
    t=104 sx=-9    das Fenster steht still, der Versatz läuft zurück
    t=112 sx=-3
    t=114 sx=+0    und bleibt null

Größter Nachzug im Lauf: `|sx|=18`, Deckel `SWING_MAX_PX=48` — innerhalb.

### DIE RUCKELMESSUNG — Justins Bedingung

Die vorhandene Zeile `bildzeit:` beantwortet die Frage **nicht**: sie
mittelt über alle Bilder eines Laufs, auch über das Hochfahren, und
dort liegt das Maximum bei rund 50 ms — **auch mit allen drei Marken
auf 0**. Eine Zahl, die ohne die Runde genauso aussieht, misst die
Runde nicht.

Diese Runde zählt deshalb getrennt: Bilder **mit** aufgehobenem Fenster
gegen die Grundlast **desselben Laufs**.

    ziehbild: n=32  mittel=8548 us  max=9139 us  ueber16.7=0
              ohnezug n=162  mittel=1803 us  max=47808 us

| | Wert | vom 60-Hz-Budget (16,7 ms) |
|---|---|---|
| Ziehbild, Mittel | 8 548 us | 51,2 % |
| **Ziehbild, Maximum** | **9 139 us** | **54,7 %** |
| **Bilder über Budget** | **0 von 32** | — |
| Grundlast, Mittel | 1 803 us | 10,8 % |
| Grundlast, Maximum | 47 808 us | 286 % (das Hochfahren) |

**Kein einziges Ziehbild reißt das Budget.** Der Aufschlag durch das
Ziehen ist 8 548 − 1 803 = **6,7 ms**. Dass das teuerste Bild ohne Zug
**fünfmal** so teuer ist wie das teuerste mit Zug, zeigt zugleich, dass
der Ausreißer nicht vom Ziehen kommt.

### Die Gegenprobe

`lift=0 tilt=0 swing=0`, alles andere gleich:

    ziehpx=0  swings=0  ziehbild: n=0

Das Fenster bleibt im Zug **360x240**. Abgeschaltet wird der teure Weg
nie betreten, und die Runde kostet **nichts**.

### Drei Fehler, durch Messen gefunden

1. **Der Nachzug blieb bei −3 stehen.** Ganzzahlig ist
   `-3 * 250 / 1000 = 0` (Firn rundet zur Null), also `sx = -3 - 0 = -3`,
   Tick für Tick. Gemessen an einem Fenster, das am Haken **stillstand**:
   t=105 bis t=190 durchgehend `sx=-3`. Das Bild stand dauerhaft drei
   Bildpunkte neben dem Fenster — keine Trägheit mehr, sondern ein
   Versatz, der nie zurückkommt. Behoben mit `abklingen()`: ist der
   Abzug null, der Wert aber nicht, wird **ein** Bildpunkt abgezogen.
   Danach erreicht jeder Wert die Null in endlich vielen Ticks.
   `swings` fiel von 24 auf 16, `ziehpx` von 10,9 auf 4,2 Millionen.

2. **Ein wiederverwendeter Fensterplatz erbte den Nachzug** des
   Fensters, das vorher dort lag. Geräumt in `create`, an derselben
   Stelle und aus demselben Grund wie der Bündelname (Runde PAINT).

3. **`set_hidden` räumte den Nachzug nicht.** Ein verborgenes Fenster
   wäre beim nächsten Zeigen um bis zu 48 Bildpunkte verschoben
   zurückgekommen. Behoben an derselben Stelle, an der die Runde
   OBERFLAECHE schon `W_ANK` räumt — und aus derselben Lehre, die sie
   aufgeschrieben hat: *was ein Fenster aus dem Bild nimmt, muss jede
   laufende Bewegung daran beenden, nicht nur die, die sie gestartet
   hat.*

### Wo man es einstellt

Einstellungen → Darstellung → **"Fenster ziehen:"**, drei Kästchen mit
je einer Stufenwahl (schwach/mittel/stark). Der Übernehmen-Knopf
schreibt `lift=`, `tilt=` und `swing=` nach `/etc/theme.conf`, und
`theme_reload` holt sie im selben Durchgang wie Schema und Form — ohne
Neustart.

Die Vorgabe steht in `assets/shapes/osum.shape` (`lift=50`,
`tilt=100`, `swing=35`); `classic` setzt alle drei auf 0, weil
`classic` ausdrücklich "die Vergangenheit" ist. `/etc/theme.conf`
sticht die Formdatei — die drei sind eine Vorliebe des Menschen und
sollen den Formwechsel überleben, dieselbe Trennung wie bei `accent=`.

### Das Messmittel

Neuer Schalter **`wmzieh`**: der Kern führt den Zug selbst, über genau
die drei Stellen, die ein Zeiger riefe (`drag_begin`, `move_win`,
`drag_end`).

Das ist kein Selbstzweck. `pruef/ziehprobe.py` hat in vier Fassungen
gemessen, dass der Kern die **gedrückte Taste während einer
Zeigerbewegung gar nicht sieht** (`kl=0`) — auf dem alten Abbild
genauso wie auf dem neuen. Ein echter Zug über QEMU misst deshalb
nichts.

    bash pruef/zieh-ab.sh <arbeitsbaum> <ausgabe> [lift] [tilt] [swing]

`tools/look/shot.sh` hat dafür neu `shots="a b c"` — mehrere Bilder
während des Haltens statt eines am Ende.

---

## Abnahmen

| Abnahme | Stand |
|---|---|
| `tools/install/abnahme.sh` | **35 grün, 0 rot**, RC=0 |
| `tools/clip2/run.sh` | **32 grün, 0 rot**, RC=0 |
| `tools/hotplug/run.sh` | **45 passed, 0 failed**, RC=0 |
| `tools/logind/run.sh` | **49 bestanden, 0 gescheitert**, RC=0 (mit `UITRACE=1`) |
| `tools/check-ui.sh` | **PASSED**, 196 Dateien, 0 Verstöße |
| `tools/paint/scalars.py` | 146 Skalare, **0 Überschneidungen** |

### Ein falscher Alarm, und wie er aufgelöst wurde

Der erste `logind`-Lauf meldete **`FAIL das Startmenue ging nicht auf
(fl=19)`** und 36/1 — also genau die Regression, die die Runde
OBERFLAECHE gefunden und behoben hatte.

**Es war keine.** Der Lauf lief parallel zu einer eigenen
QEMU-Messung auf demselben Wirt. Die Gegenprobe, die das geklärt hat:
`logind` **nacheinander und ohne Nachbarlast** auf zwei Bäumen —
`986acdc2` (der Merge ohne diese Runde) gegen `runde-zieh`.

| Baum | Ergebnis |
|---|---|
| `986acdc2` | `fl=18`, **49/0**, RC=0 |
| `runde-zieh` | `fl=18`, **49/0**, RC=0 |

**Lehre: Abnahmen nie parallel zu eigenen QEMU-Messungen fahren.** Die
Läufer haben feste Wartezeiten (`sleep(4)`, `sleep(12)`); unter Last
reicht die Zeit nicht, ein Fenster ist noch nicht offen, wenn der
Läufer nachsieht — und das sieht exakt wie eine echte Regression aus.
Dieselbe Falle traf die Ruckelmessung: parallel zur
Installations-Abnahme `max=19200 us, ueber16.7=1`, allein
`max=9139 us, ueber16.7=0`.

## Die Pflichtliste

**Keine neue ausgelieferte Datei.** Alle Änderungen liegen in Dateien,
die schon gebaut und ausgeliefert werden; `pruef/zieh-ab.sh` ist ein
Messwerkzeug und gehört nicht ins Abbild. `/etc/shapes/osum` steht
bereits in der Pflichtliste.

Die Gegenprobe trotzdem gemacht, weil sie verlangt war: Eintrag aus dem
**Bauplan** genommen (`build.sh:895`), **Pflichteintrag stehen
gelassen** (`build.sh:1051`).

    == FEHLT IM ABBILD: /etc/shapes/osum
    == 1 Pflichtdatei(en) fehlen im Abbild
    RC=1

Der Bauer bricht also wirklich ab und nennt die Datei beim Namen. Die
Zeile ist danach wortgleich wiederhergestellt (`git diff` auf
`tools/usbimg/build.sh` ist leer).

---

## Vorgefunden, nicht von dieser Runde

`bash tools/build-kernel.sh <ziel> --gui off` ist **kaputt**:

    error: cannot read 'kernel/sched/gfx/fb.fi': No such file or directory

Gegengeprobt auf reinem `main` `211f8e1b` in `/root/osum-merge` —
derselbe Fehler. Es ist ein Nachzügler der Umstrukturierung
(O-STRUKTUR): ein `import` zeigt auf `gfx/fb.fi` relativ zu
`kernel/sched/`. Das Serverbetriebssystem lässt sich damit zurzeit
nicht bauen. **Nicht angefasst**, weil es außerhalb dieses Auftrags
liegt — aber es gehört gemeldet.

Zweitens kennt `settings.fi`, `theme_conf_write` nur `classic` und
`modern`, nicht `osum`. Wer im Einstellungsfenster auf Übernehmen
drückt, schreibt damit die Hausform auf `classic` zurück. Ebenfalls
älter als diese Runde und ebenfalls nicht angefasst.
