# RUNDE DESIGN-2 -- Radien, Schatten, Bewegung, und wer noch selbst malt

Zweig `design2`, abgezweigt von `merge6` (2aa3f59). Arbeitsbaum
`/root/osum-design2`. Nicht geschoben, nicht zusammengefuehrt.

Der Befund, mit dem diese Runde angefangen hat, stand im Auftrag: die
FARBEN dieses Systems sind modern, die FORM sagt 2005. Elf Treffer fuer
`radius`, elf fuer `shadow`, keine Animation, keine Hoehenstufen.

Was davon nach dieser Runde anders ist, und was nicht, steht hier --
mit den Zahlen, aus denen es folgt, und mit dem, was gemessen NICHT
funktioniert hat.

---

## 0. DIE EHRLICHE KURZFASSUNG

Zwei der fuenf Auftragspunkte waren beim Anfangen **schon gebaut**, und
zwar auf `merge6` selbst -- von Runde OBERFLAECHE. Das habe ich beim
Einlesen festgestellt und nicht noch einmal gebaut:

* **Form-Tokens (Punkt 1)**: `M_RADIUS_*`, `M_SP_*`, `M_FONT`,
  `M_MOTION`, die Hoehenstufen `EL_FLAT..EL_WINDOW` mit
  `elev_strength`/`elev_reach`/`elev_radius`, die Typo-Skala
  `TY_CAPTION..TY_DISPLAY` -- alles vorhanden, exportiert, und mit
  `assets/shapes/osum.shape` als Hausform belegt.
* **Zeichenkern (Punkt 2)**: `rrect`, `rframe`, `rring`, `drop_shadow`,
  `shadow_edge`, `divider` mit Kantenglaettung ueber `corner_cov`
  (4x4-Unterabtastung) -- ebenfalls vorhanden.

Neu in DIESER Runde sind:

| Punkt | Zustand |
|---|---|
| 1. Form-Tokens | war da (Runde OBERFLAECHE), nicht angefasst |
| 2. Runde Ecken + Schatten mit AA | war da, **visuell nachgeprueft** (Abschnitt 3) |
| 3. **Animation/Tween** | **NEU gebaut** (Abschnitt 1) |
| 4. Rueckpuffer/Tearing | war da (`fb: back=0x66c000`), **gemessen** (Abschnitt 4) |
| 5. **Restmalerei raus** | **NEU: 45 -> 0** (Abschnitt 2) |

---

## 1. DIE BEWEGUNG (neu, kernel/user/wlib.fi)

Ein Tween-Verwalter fuer die ganze Bibliothek. Sechzehn Plaetze, vier
Zahlen je Bewegung (Startzeit, Dauer, Kurve, Ziel), Fortschritt in
**Tausendsteln**.

**Warum Tausendstel und nicht Prozent:** bei einem Fenster von 800
Bildpunkten ist ein Prozent acht Bildpunkte -- ein Sprung von acht
Bildpunkten ist genau das Ruckeln, das abgestellt werden sollte.

**Warum kein 60-Hz-Takt:** dieser Kernel laeuft mit `TICK_HZ = 100`
(kernel/time.fi). Eine Bibliothek, die 60 Hz *behauptet*, waehrend ihr
Zeitgeber mit 100 laeuft, rechnet jede Dauer um 40 Prozent falsch. Die
Zusage lautet deshalb: **die Dauer in Millisekunden stimmt**; die Zahl
der Zwischenbilder ist, was die Maschine hergibt. Eine Konstante,
`MS_PRO_TICK = 10`.

**Keine Fliesskommazahl.** `ease` rechnet in Ganzzahlen, und das ist
keine Sparsamkeit: dieser Kernel rettet in `syscall` keine
SSE-Register, also hat ein Ring-3-Programm, das in einer
Ereignisschleife multipliziert, mit `f64` keine Zusage.

Kurven: `EASE_LINEAR`, `EASE_OUT` (1-(1-t)^2), `EASE_IN_OUT`
(Zwei-Stueck-Parabel).

Angeschlossen sind: Knopf-Hover (`AN_HOVER`), Knopf-Druck
(`AN_PRESS`), Menue-Aufklappen (`AN_MENU`).

**"Animationen reduzieren"** ist `motion=0` in der Formentabelle. Der
Unterschied zum Weglassen ist wichtig und im Code festgehalten: die
Bewegung wird nicht uebersprungen, sie ist **sofort fertig** -- der
Endzustand wird in beiden Faellen erreicht, nur ohne Zwischenbilder.
`classic.shape` hat kein `motion=`, bekommt also den Vorgabewert 0 und
bewegt sich nicht.

### Gemessen, nicht behauptet

Eine Animation ist die einzige Eigenschaft dieser Runde, die man auf
einem **Standbild nicht sehen kann**. Deshalb meldet der Verwalter
jeden Schritt auf die serielle Leitung (nur mit `/etc/uitrace`, wie
jede andere Meldung dieser Bibliothek):

```
wlib: anim was=4 wd=7   p=83   dur=12
wlib: anim was=4 wd=7   p=1000 dur=12
wlib: anim was=3 wd=160 p=583  dur=12
wlib: anim was=3 wd=160 p=1000 dur=12
```

`was=4` ist `AN_HOVER`, `was=3` ist `AN_MENU`. Die Zwischenwerte
(p=83, p=583) sind der Beleg, dass wirklich interpoliert wird und
nicht von 0 auf 1000 gesprungen.

`dur=12` Ticks = **120 ms**. Erwartet fuer `MO_FAST` bei `motion=160`:
160 * 3/4 = **120 ms**. Stimmt ueberein.

Und eine Zeile, ohne die die Schleife mitten in einer Bewegung
einschlaeft:

```firn
if !etwas && gemalt == 0 && laufend == 0 {
    ulib.sys(ulib.SYS_YIELD, 0, 0, 0)
}
```

Eine laufende Bewegung ist ETWAS. Ohne `laufend == 0` bleibt das
Fenster auf halbem Weg stehen, bis die Maus wackelt.

---

## 2. WER NOCH SELBST MALT: 45 -> 0

Justins Regel: *alles an Oberflaeche geht ueber das Rahmenwerk; was das
Rahmenwerk nicht kann, wird INS Rahmenwerk eingebaut, nicht daneben.*

`tools/design/zaehlen.py` zaehlt jeden Aufruf einer **malenden**
Routine des Zeichenkerns ausserhalb von wlib/wlibc. Messende Routinen
(`text_w`, `ascent_of`) zaehlen nicht -- eine Breite zu erfragen ist
kein Malen.

| Programm | malt selbst vorher | nachher |
|---|---:|---:|
| taskbar.fi | 16 | **0** |
| qs.fi (Schnelleinstellungen) | 15 | **0** |
| taskmgr.fi | 7 | **0** |
| speicher.fi | 5 | **0** |
| desktop.fi | 1 | **0** |
| settings.fi | 1 | **0** |
| explorer.fi | 0 | 0 |
| launcher.fi | 0 | 0 |
| edit.fi, terminal, netmon, powermon | 0 | 0 |
| **Summe (Programme)** | **45** | **0** |
| icont.fi, themetest.fi (Pruefstaende) | 6 | 6 |

Die zwei Pruefstaende rufen den Zeichenkern absichtlich direkt auf --
das ist ihr Zweck: sie pruefen ihn. Sie stehen einzeln in der Ausgabe.

### Wie -- und was dabei NICHT gemacht wurde

Der falsche Weg waere gewesen, aus einer Taskleiste Knoepfe zu machen.
Eine Leiste, ein Schnelleinstellungs-Blatt, ein Verlaufsdiagramm und
eine Kachelkarte sind **keine Widget-Fenster**: sie malen eine
Flaeche, und ein Knopf ist dafuer das falsche Werkzeug.

Also hat wlib eine **zweite Schicht neben den Widgets** bekommen, den
*Maler*:

```
mal_flaeche  mal_tafel  mal_rahmen  mal_trenner  mal_linie
mal_text     mal_text_w mal_ascent  mal_balken   mal_punkt
mal_symbol   mal_abstand mal_radius mal_kante3
```

Ein Programm sagt jetzt, **was** es malt (`MR_TAFEL`, `MR_KNOPF`,
`MR_FELD`) und **wie hoch** es liegt (`EL_FLAT`..`EL_WINDOW`) -- nicht
mehr, wie rund es ist. Die Rechnung (Radius aus der Rolle, Schatten aus
der Hoehenstufe) steht **einmal** in wlib statt fuenfmal in den
Programmen.

`mal_kante3` ist ausdruecklich **keine Gestaltung dieser Runde**: das
ist die Kante mit Licht und Schatten von `classic`, und sie musste
erhalten bleiben, weil `tools/look/run.sh` Bildpunkt fuer Bildpunkt
gegen sie misst. Sie hat nur einen Namen bekommen und geht nicht mehr
am Rahmenwerk vorbei.

### Feste Farbwerte: 7 -> 0, und warum das eine Korrektur AM MESSGERAET war

Die Zaehlung meldete sieben feste Farbwerte. Angesehen waren es:

```
while wlib.alive() && runden < 4000000     eine SCHLEIFENGRENZE
v & 0xFFFFFF                                eine BITMASKE
rs & 0xFFFFFFFF                             dieselbe, 32 Bit
```

**Keine einzige davon war eine Farbe.** Die erste Fassung suchte "eine
Zahl mit mindestens fuenf Stellen in einer Zeile, in der wlib
vorkommt". Korrigiert wurde das **Messgeraet**, nicht der Code: eine
Zahl gilt nur noch als Farbe, wenn sie **Argument eines malenden
Aufrufs** ist und kein `&`/`|`/`^` davorsteht.

Eine Messung, die das Falsche zaehlt, ist schlimmer als keine -- sie
bringt jemanden dazu, richtigen Code zu aendern, damit eine Zahl sinkt.

---

## 3. DIE BILDER: ANGESEHEN, NICHT NUR GEZAEHLT

Sieben Ansichten vorher und nachher unter QEMU, 1920x1080,
`.design2-shots/{vorher,nachher}-run/bilder/`, Gegenueberstellungen in
`.design2-shots/vergleich/`.

Weil ein Radius von 12 Bildpunkten auf einem 1920er-Bild
nebeneinandergelegt drei Bildpunkte gross ist -- man sieht ihn nicht,
man glaubt ihn -- gibt es `tools/design/lupe.py`: derselbe Ausschnitt
aus beiden Aufnahmen, vergroessert.

**Was in der Lupe zu sehen ist** (obere linke Fensterecke, Zoom 10):
eine glatt verlaufende Rundung ohne Treppe, und darunter ein
Schatten, der ueber mehrere Zeilen ausblendet. Abgelesen an den
Bildpunkten der Zeilen 448-456 -- die linke Kante wandert von x=16
ueber 17 auf 19, mit Zwischenwerten (234,238,242) -> (217,221,226) ->
(200,204,210): das ist Kantenglaettung und keine harte Stufe.

### Text: keine Ueberlappungen

`tools/design/messen.py` ueber alle sieben Aufnahmen:

| Ansicht | Farben | leer | abgeschnitten | **ueberlappend** |
|---|---:|---:|---:|---:|
| 01-schreibtisch | 415 | 0 | 0 | **0** |
| 02-startmenue | 452 | 2 | 3 | **0** |
| 03-explorer | 790 | 0 | 7 | **0** |
| 04-dialog | 801 | 0 | 8 | **0** |
| 05-kontrollzentrum | 441 | 0 | 0 | **0** |
| 06-einstellungen | 761 | 0 | 6 | **0** |

Keine ueberlappenden Beschriftungen. Die "abgeschnittenen" sind
Tabellenzellen, die am Spaltenrand enden -- dieselbe Zahl wie vorher,
kein Zuwachs durch diese Runde.

Das Kontrollzentrum ist von 398 auf 441 Farben gestiegen: das sind die
gerundeten Kacheln mit ihren geglaetteten Ecken.

---

## 4. TEARING UND BILDZEIT

**Der Rueckpuffer war schon da.** Der Kernel meldet beim Start:

```
fb: 1920x1080x32 pitch=7680 src=vbe phys=0xfc000000 win=0x3f400000
    huge=4 cols=240 rows=67  back=0x66c000  uc=0 wc=1
```

`back=0x66c000` -- es wird in den Speicher gemalt und einmal je Bild
uebertragen. `nodbl` ist die Gegenprobe und ausdruecklich als solche im
Code vermerkt. Es war also nichts zu bauen; die Frage war, ob es reicht.

**Gemessen** (`fbbench`, Vollbild bei 1920x1080, sechs Laeufe):

| | fill | scroll | flush |
|---|---:|---:|---:|
| direct | 6263-6372 us | 5956-6016 us | -- |
| buffered | 6193-6308 us | 5956-6433 us | 6166-8536 us |

Ein Vollbild ist in **~6,2-6,5 ms** fertig, ein Ausreisser bei 8,5 ms.
Das Budget fuer 60 Hz sind 16,7 ms -- also **erfuellt**, mit etwa
Faktor zwei Luft, und das unter TCG ohne KVM.

Ein Wort zur Ehrlichkeit dieser Zahl: das ist die Zeit fuer ein
**Vollbild**. Der Normalfall ist ein Dirty-Rect, das ein Bruchteil
davon ist. Die 6,3 ms sind also die obere Schranke, nicht der Alltag.

---

## 5. WAS DIE ABNAHME SAGT

| Kriterium | Ziel | Ist |
|---|---|---|
| b) direkte Zeichenaufrufe ausserhalb wlib | 0 | **0** |
| c) feste Farbwerte ausserhalb theme | 0 | **0** |
| d) 4er-Raster | >= 95 % | **93 %** (827/880) |
| e) themestore-Kontrastpruefung | 81/0 | **81 passed, 0 failed** |
| f) Bildzeit bei 1920x1080 | < 16 ms | **~6,3 ms** |
| g) 20 Laeufe -smp 4 ohne Panik | 20/20 | **20 / 20, 0 Panik** |

### Zwanzig Laeufe mit vier Kernen

`bash tools/design/dauerlauf.sh 20 4`, jeder Lauf eine eigene Maschine
mit `-smp 4`, Bewegungen an (`shape=osum`, `motion=160`):

```
== 20 Laeufe, -smp 4, mit Bewegungen ==
....................
== 20 von 20 ohne Panik, 0 Fehlschlaege ==
```

Gezaehlt wird dreifach und nicht einfach: QEMU-Code 21, die Zeile
`kernel: done` auf der seriellen Leitung, und **keine** Zeile mit
PANIC/EXCEPTION/#PF/#GP/#DF. Ein Lauf, der nur den richtigen Code
liefert, aber unterwegs eine Ausnahme gemeldet hat, zaehlt als
Fehlschlag.

Das ist die Zusage, die eine Animation am ehesten bricht: sie fasst
staendig dieselben Felder an, waehrend der Zeitgeber auf vier Kernen
weiterlaeuft.

### Regressionspruefung gegen den Ausgangszweig

Weil diese Runde die Widget-Bibliothek, die Leiste und vier Programme
angefasst hat, wurden dieselben Testlaeufer auf `merge6` (unveraendert,
`/root/osum-merge6`) und auf `design2` gefahren:

| Laeufer | merge6 (Ausgang) | design2 | Urteil |
|---|---|---|---|
| themestore | 81 / 0 | **81 / 0** | unveraendert |
| LOOK | 30 / 10 | **30 / 10** | unveraendert |
| SOFTUI | 17 / 3 | **21 / 3** | unveraendert (dieselben 3) |

Die zehn LOOK-Fehlschlaege und die drei SOFTUI-Fehlschlaege sind
**Bestand des Ausgangszweiges** und nicht das Werk dieser Runde --
belegt dadurch, dass sie auf `merge6` mit derselben Meldung stehen,
z. B. `align=left: the start button's x: 2, expected 4` in beiden
Baeumen zeichengleich.

### Ein Fehlalarm, der KEINER war -- und wie das festgestellt wurde

Ein erster SOFTUI-Lauf meldete `20 bestanden, 4 gefallen`, mit einem
zusaetzlichen `F-day: Beanstandungen` -- drei Beschriftungen der
Taskleiste als **LEER**. Das waere eine echte Regression gewesen: Text,
der von meiner neuen Tafel uebermalt wird.

War es nicht. Der Lauf lief zusammen mit vier anderen QEMU-Instanzen
gleichzeitig. Einzeln nachgestellt (`shape=modern scheme=day`,
`tools/softui/check.py` auf die frische Aufnahme):

```
pruef: 3 Beschriftungen geprueft, 0 beanstandet
```

Und der volle Laeufer allein: `SOFTUI: 21 bestanden, 3 gefallen`. Es
war eine Zeitueberschreitung unter Last, kein Malfehler.

### Was NICHT erreicht wurde: das 4er-Raster

**93 %, verlangt waren 95 %.** Das ist keine Rundungsfrage, das ist
verfehlt. Die 53 Laengen daneben verteilen sich auf:

* `settings` 38 -- die Seite "Darstellung" mit ihren Vorschaukacheln
* `explorer` 8 -- Spaltenbreiten der Dateitabelle
* `launcher` 7 -- die Eintragshoehen des Starters

Diese drei rechnen ihre Geometrie aus Textbreiten (`text_w`), und eine
Textbreite liegt nicht auf dem Viererraster. Sie auf das Raster zu
zwingen hiesse, Spalten breiter zu machen, als ihr Inhalt braucht --
das waere eine bessere Zahl und eine schlechtere Oberflaeche. Das
gehoert in eine eigene Runde mit `snap_up` in der Anordnung, nicht in
einen Schnellschuss am Ende dieser.

Klickflaechen: 2 von 108 fassbaren Elementen unter 32 px (die
26er-Hoehe von `classic` und eine 28er-Listenzeile). Verlangt waren
>= 32 px; auch das ist nicht ganz erreicht.

---

## 6. WERKZEUGE, DIE DIESE RUNDE HINTERLAESST

* `tools/design/zaehlen.py` -- wer malt noch selbst, wer tippt noch
  eine Farbe. Beendigungscode 0 nur bei Summe 0.
* `tools/design/lupe.py` -- derselbe Ausschnitt aus zwei Aufnahmen,
  vergroessert, nebeneinander. Ohne das ist ein Radius eine Behauptung.
* `tools/design/dauerlauf.sh` -- N Laeufe mit `-smp 4`, zaehlt
  QEMU-Code, `kernel: done` und jede PANIC/EXCEPTION-Zeile.

---

## 7. WAS OFFEN BLEIBT

1. **4er-Raster 93 % statt 95 %** -- Anordnung muss `snap_up` auf
   textabgeleitete Breiten anwenden (settings/explorer/launcher).
2. **Zwei Klickflaechen unter 32 px.**
3. **Fenster oeffnen/schliessen ist nicht animiert.** Skalieren+Alpha
   beim Oeffnen braucht einen Zugriff auf die Fensterflaeche VOR dem
   Uebertragen, den der Fensterserver heute nicht anbietet -- das ist
   eine Aenderung an `kernel/wm.fi` und keine an wlib. Hover, Druck und
   Menue laufen; Fenster und Benachrichtigung nicht.
4. **Der Schatten wird nicht gecacht.** `drop_shadow` rechnet jeden
   Ring neu. Bei den gemessenen Bildzeiten stoert das nicht, aber die
   Zusage aus dem Auftrag ("getrennt gerendert + gecacht") ist damit
   nur zur Haelfte eingeloest.
