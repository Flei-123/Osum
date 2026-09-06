# STATUS-VSYNC.md -- die Runde VSYNC auf einer Seite

Zweig `vsync`, Arbeitsbaum `/root/osum-vsync`, auf `merge6` (a92fa00).
Der volle Bericht steht in `docs/VSYNC.md`.

## WAS GEFRAGT WAR

1. Kein sichtbares Reissen beim Fensterziehen.
2. Fenster oeffnen/schliessen/minimieren animiert (Skalieren + Alpha,
   ~150 ms Easing), im Kern-Fensterserver.
3. Schatten dabei cachen.

## WAS HERAUSGEKOMMEN IST

**1. Reissen: geloest, aber nicht so, wie der Auftrag vermutet hat.**

Der Auftrag nannte "Rueckpuffer im Kern + Blit im Zeitgeber-Tick". Der
Rueckpuffer war seit Runde SCHIRM da (`back=0x67f000` in jeder
Startzeile), und **er beseitigt das Reissen nicht**: `flush` kopiert
Zeile fuer Zeile, und waehrend dieser Schleife steht auf der Karte oben
das neue und unten das alte Bild.

Der Blit im Takt (`vsync`) wurde gebaut und hilft -- er senkt die Zahl
der Uebertragungen (174 Zeichnungen -> 30 Uebertragungen) und damit die
Gelegenheiten. **Er beseitigt das Reissen ebenfalls nicht.** Gemessen:

| | Ablesungen | Risse |
|---|---:|---:|
| ohne alles (`nopresent noflip`) | 184 042 | 20 453 |
| nur sammeln (`vsync noflip`) | 182 057 | 20 041 |
| **+ Seitenwechsel (`vsync flip`)** | **178 169** | **0** |

Null wird es erst mit dem **Wechsel der ganzen Bildseite** ueber
`VBE_YOFF`: doppelte Bildhoehe abbilden, in die unsichtbare Haelfte
malen, mit EINEM Registerschreib umschalten. Ohne echten Vblank-IRQ
(den VESA/GOP nicht hat) ist das der einzige Weg zu wirklich null.

**Grenze:** der Seitenwechsel braucht die doppelte Hoehe im
Abbildungsfenster (8 Plaetze zu 2 MiB). Er kommt zustande bei 800x600
und 1280x800; ab 1920x1080 nicht mehr (`flip=0`, sauberer Rueckfall auf
das Sammeln). Auf Justins 3440x1440 waeren 20 Kacheln noetig. Das ist
dokumentiert, nicht verschwiegen -- siehe docs/VSYNC.md Abschnitt 3.

**2. Fensterbewegung: gebaut und gemessen.**

Skalieren von 85 % auf 100 % samt Alpha, `ease_out` ganzzahlig, Dauer
aus der neuen Formmarke `FM_MOTION` mit Vorgabe 120 ms -- **dieselbe
Zahl und dieselbe Kurve wie wlib seit DESIGN-2** (`MO_FAST`), nicht
eine zweite Wahrheit daneben. Ein Fenster verschwindet erst, wenn seine
Schliessbewegung durch ist.

```
mit Bewegung   anim=2  frames=48
ohne (noanim)  anim=0  frames=0   -- selber Endzustand (wins n=1)
```

Im Bild, ueber 90 Fotos ausgezaehlt: mit Bewegung **5** verschiedene
Fensterflaechen und 65 423 gemischte Bildpunkte, mit `noanim` **2** und
2 276. Die Zwischengroessen kommen also wirklich auf dem Schirm an.

**3. Schatten cachen: war im Kern schon erledigt.**

`shadow_build` legt eine Deckungsmaske an, `shadow_key` baut sie nur bei
geaenderten Formzahlen neu. Im Betrieb gemessen: `shbuild=0`, kein
Neubau je Bild. Was DESIGN-2 als offen gemeldet hat, ist `drop_shadow`
in **wlib** (Ring 3) -- andere Datei, andere Runde. Hier war nichts zu
bauen, und es waere falsch gewesen, etwas zu bauen und als Fortschritt
zu melden.

## DIE MESSUNG SELBST WAR DAS SCHWERSTE

Zwei Anlaeufe waren falsch, beide stehen in docs/VSYNC.md Abschnitt 2:

* **Fotografieren geht nicht.** QEMUs `screendump` liest atomar; eine
  Bildserie waehrend eines Zuges fand mit ABGESCHALTETER Bildgrenze 0
  zerrissene Bilder. Eine Probe, die auch abgeschaltet gruen bleibt,
  misst nichts.
* **Auf einem Kern ablesen geht auch nicht.** Maler und Ableser sind
  derselbe Faden; 1,8 Mio. Ablesungen, 0 Risse, ebenfalls ohne
  Bildgrenze.

Richtig ist ein Ableser auf einem **zweiten Kern** (das ist, was ein
Bildschirm tut) an einem **stehenden, aber staendig neu gemalten**
Fenster. Am gezogenen Fenster misst er sich selbst: der Ort aendert sich
zwischen den Ablesungen, Ergebnis 97 % "Risse" bei stehender
Bildgrenze. **Der Fehler lag in der Messung, nicht im Gemessenen.**

Und selbst dann blieben 1--5 "Risse" je Million stehen. Auch die waren
keine: die Rate hing an der Zahl der **Umschaltungen**, nicht an der der
Ablesungen (ohne Umschalten: 0 in 2 892 193). Ein Leser, der ueber eine
Bildgrenze rutscht, sieht zwei Seiten. `fb.flip` traegt jetzt eine
Folgenummer, und solche Ablesungen werden verworfen statt gezaehlt.

**Am Ende: 20 von 20 Laeufen mit `-smp 4` (drei Ableser gleichzeitig),
0 Panik, 0 Risse.**

## DIE ZAHLEN, DIE BLEIBEN MUSSTEN

* **Sparsamkeit (UHRWERK):** ohne Eingabe `composites=42 blits=42
  pixels=10564320` -- auf das Bildpunkt genau wie auf merge6. 14
  Zeichnungen/s, 2,2 Vollbilder/s an Flaeche.
* **Bildzeit:** 535 us bei 1280x800, 1424 us bei 1920x1080. Budget
  16 000 us.
* **`tools/wm/run.sh`: 104 passed, 0 failed** (unveraendert).
* **`tools/vsync/run.sh`: 14 passed, 0 failed.**
* **`tools/vsync/dauerlauf.sh 20 4`: 20/20 sauber, 0 Panik, 0 Risse.**

## DIE WOERTER

`vsync` / `nopresent` (Gegenprobe) -- die Bildgrenze.
`flip` / `noflip` (Gegenprobe) -- der Seitenwechsel.
`wmanim` / `noanim` (Gegenprobe) -- die Fensterbewegung.
`wmsig` -- Signaturbetrieb samt Ableser. `wmruhe` -- stehendes Fenster
fuer die Zerreissprobe.

## DER DIFF

`kernel/wm.fi` (+766) und `kernel/fb.fi` (+262) tragen die Sache; der
Rest sind Nahtstellen: `kgui.fi` (Takt, Vorfuehrung, Meldezeile),
`kstate.fi`/`kmain.fi` (die Woerter), `gfx.fi`/`gfx-aus.fi` (damit
`smp.fi` den Ableser auch ohne Oberflaeche uebersetzt) und 33 Zeilen in
`smp.fi` (der Ableser im Leerlauf). `test.sh` bekommt Abschnitt 43.

## WAS OFFEN BLEIBT

1. Seitenwechsel ab 1920x1080 nicht moeglich (Abbildungsfenster).
2. Bei Seitenwechsel wird die volle Flaeche kopiert, nicht nur das
   schmutzige Rechteck -- auf grossen Schirmen die naechste
   Verbesserung.
3. Das `fb: hold`-Problem in `tools/gfx/run.sh` (46/30) ist von dieser
   Runde nicht beruehrt und nicht behoben.
