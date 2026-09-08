# RUNDE VSYNC -- die Bildgrenze und die Fensterbewegung

Zwei Dinge sollten aus dieser Runde herauskommen: **kein sichtbares
Reissen** beim Bewegen von Fenstern, und **Fenster, die sich beim
Oeffnen und Schliessen bewegen** statt zu springen. Beides gehoert in
`kernel/wm.fi`, weil beides Zugriff auf die Fensterflaeche *vor* dem
Uebertragen braucht -- den Zugriff, den Runde DESIGN-2 in wlib
vermisst hat (siehe dort Abschnitt 7, Punkt 3).

Der Befund der Runde in einem Satz: **der Rueckpuffer war schon da und
hat das Reissen nicht beseitigt; erst der Wechsel der ganzen Bildseite
tut es.**

---

## 1. WAS SCHON DA WAR, UND WARUM ES NICHT REICHTE

`fb.fi` hat seit Runde SCHIRM einen Zweitpuffer. Der Kern meldet ihn
beim Start:

```
fb: 800x600x32  pitch=3200  src=vbe  ...  back=0x67f000  uc=0  wc=1
```

Es wird also in den Arbeitsspeicher gemalt und von dort auf die Karte
uebertragen. DESIGN-2 hat daraus geschlossen, die Sache sei erledigt.
Sie war es nicht, und der Grund ist eine Ebene tiefer:

**`flush` kopiert Zeile fuer Zeile.** Waehrend dieser Schleife steht
auf der Karte oben schon das neue und unten noch das alte Bild. Wer in
diesem Augenblick abliest -- der Bildaufbau eines Schirms tut es
ununterbrochen --, sieht beides. Der Zweitpuffer hat das Reissen nicht
beseitigt, sondern nur *verlegt*: von "zwei Zeichner auf einer
Flaeche" zu "ein Kopierer und ein Ableser auf einer Flaeche".

Dazu kam ein zweites: `compose` rief `fb.flush` **selbst**, am Ende
jedes Laufs. Zwischen zwei Mauspaketen liegen mehrere `compose`-Laeufe,
und jeder schob seinen Streifen einzeln hinueber. Es war nirgends
gesagt, welche Zeichenschritte zusammen EIN Bild sind -- es gab keine
**Bildgrenze**.

---

## 2. WIE MAN REISSEN UEBERHAUPT MISST

Das war der schwierigste Teil der Runde, und die ersten zwei Anlaeufe
waren falsch. Sie stehen hier, weil der naechste, der das misst, sonst
dieselben Wege geht.

### Anlauf 1: fotografieren. Falsch.

Die naheliegende Messung: waehrend eines Zuges viele Bildschirmfotos
machen und nachsehen, ob eines davon zwei Zustaende zeigt. Dafuer
faerbt der Server im Signaturbetrieb (`wmsig`) einen Streifen am oberen
und einen am unteren Rand jedes Fensters mit einer Farbe, die aus der
Bildnummer faellt; beide entstehen im selben Zeichenlauf und muessen
also gleich sein.

**Gemessen: 40 Bilder waehrend eines Zuges, mit ausdruecklich
ABGESCHALTETER Bildgrenze (`nopresent`) -- 0 zerrissene Bilder.**

Eine Messung, die auch dann gruen bleibt, wenn die Zusage abgeschaltet
ist, misst nichts. Der Grund liegt in QEMU: `screendump` liest die
Bildflaeche in EINEM Zug, wenn gerade niemand schreibt. Ein halb
uebertragenes Bild ist darin nicht zu sehen. `tools/vsync/zerreiss.py`
und `schuesse.py` sind dieser Weg; sie liegen im Baum, weil sie auf
echtem Blech (wo wirklich ausgelesen wird) etwas taugen, aber unter
QEMU beweisen sie nichts, und das steht in ihrem Kopf.

### Anlauf 2: im Kern ablesen, auf einem Kern. Auch falsch.

Also die Frage dorthin, wo sie beantwortbar ist: ein Ableser im Kern
liest den **Vorderpuffer** (`fb.front_pixel`, die Karte -- nicht
`get_pixel`, das liest den Zweitpuffer und damit die Quelle statt des
Ziels) und vergleicht oben und unten.

**Gemessen: 1,8 Millionen Ablesungen, 0 Risse -- auch ohne
Bildgrenze.** Auf EINEM Kern sind `compose`, `flush` und der Ableser
derselbe Faden. Der Ableser kommt erst dran, wenn die Uebertragung
fertig ist. Er kann per Bauart kein halbes Bild finden.

### Anlauf 3: zwei Kerne. Richtig.

Ein Bildschirm ist ein zweiter Leser. Also liest ein **zweiter Kern**
den Vorderpuffer, waehrend der Startprozessor malt und uebertraegt
(`smp.scheduler_core` -> `gfx.leser_tick` -> `wm.leser_tick`; die Naht
ueber `gfx.fi` ist noetig, weil `smp.fi` auch ohne Oberflaeche gebaut
wird). Das ist keine Nachbildung des Reissens -- es *ist* das Reissen:
ein Bildschirm, der in diesem Augenblick abgelesen haette, haette
dasselbe gesehen.

Vier Fallen dabei, alle gemessen und alle behoben:

* **Der Ableser gehoert in den Leerlauf des Ablaufplaners, nicht in
  `phases`.** Ein gestarteter Kern verlaesst `phases` mit `PH_SCHED`
  fuer immer. Vorher: 14 202 Ablesungen auf 4 735 Bilder, also drei je
  Bild -- eine Uebertragung dauert Mikrosekunden und wurde so gut wie
  nie getroffen.
* **Gemessen wird am STEHENDEN Fenster (`wmruhe`), das trotzdem in
  jedem Takt neu gemalt wird.** Am *gezogenen* Fenster rechnet der
  Ableser seine zwei Punkte aus dem Ort, und der aendert sich zwischen
  den Ablesungen: er las oben an der neuen und unten an der alten
  Stelle. Ergebnis 97 Prozent "Risse", waehrend derselbe Ableser am
  stehenden Bild null fand. **Der Fehler lag in der Messung, nicht im
  Gemessenen** -- die auffaelligste Zahl der Runde und die einzige, die
  beinahe zu einer falschen Diagnose gefuehrt haette.
* **Der Ableser braucht eine Folgenummer.** Auch mit alledem blieben
  etwa 1 bis 5 "Risse" je Million Ablesungen stehen. Sie sind KEINE:
  der Ableser liest zwei Punkte nacheinander, und wird dazwischen die
  Bildseite gewechselt, gehoeren sie zu verschiedenen Seiten. Der
  Beweis liegt in der Skalierung -- **die Rate haengt an der Zahl der
  UMSCHALTUNGEN, nicht an der Zahl der Ablesungen**:

  | | Ablesungen | Umschaltungen | "Risse" |
  |---|---:|---:|---:|
  | ohne `wmruhe` | 2 892 193 | 1 | **0** |
  | mit `wmruhe` | ~1 200 000 | ~18 800 | ~2 |

  Ein wirklich zerrissenes Bild muesste mit den Ablesungen skalieren.
  Also traegt `fb.flip` jetzt eine Folgenummer (`S_SEQ`, ungerade
  waehrend des Wechsels), und `front_paar` verwirft jede Ablesung, die
  darueber rutscht. Sie werden als `verworf=` gezaehlt und NICHT als
  Riss -- eine verworfene Ablesung ist "keine Aussage", nicht "kein
  Riss".
* **Und nicht an einem Fenster messen, das sich gerade bewegt.**
  Waehrend einer Oeffnungsbewegung wird die Flaeche skaliert und
  gemischt gemalt; die Signaturstreifen liegen dann nicht dort, wo der
  Ableser sie aus `win_x`/`win_y` errechnet. `leser_tick` ueberspringt
  deshalb Fenster mit laufender Bewegung und alles, was gezogen wird.

---

## 3. DAS ERGEBNIS

Stehendes Fenster, in jedem Takt neu gemalt, zwei Kerne, 6 Sekunden:

| | Ablesungen | **Risse** |
|---|---:|---:|
| `nopresent noflip` -- ohne alles | 182 136 | **19 260** |
| `vsync noflip` -- nur sammeln | 180 341 | **23 733** |
| `vsync flip` -- Seitenwechsel | 167 948 | **0** |

Sechs Wiederholungen der letzten Zeile mit VIER Kernen (also drei
Ablesern gleichzeitig): 0 Risse in je ~310 000 gueltigen Ablesungen,
bei je ~11 000 verworfenen. Und der Dauerlauf: **20 von 20 Laeufen mit
`-smp 4` sauber, 0 Panik, 0 Risse.**

**Die mittlere Zeile ist der Befund der Runde.** Das Sammeln der
Zeichnungen zu einem Bild senkt die Zahl der Uebertragungen deutlich
(gemessen an anderer Stelle: 174 Zeichnungen -> 30 Uebertragungen) und
damit die *Gelegenheiten* zum Reissen. Beseitigt hat es das Reissen
**nicht** -- jede einzelne Uebertragung ist weiter zerlegbar. Wer nur
sammelt, hat das Problem verkleinert und fuer geloest gehalten.

### Warum der Seitenwechsel die Antwort ist

Es gibt auf VESA/GOP **keinen Vblank-IRQ**; man kann nicht warten, bis
der Schirm mit dem Auslesen fertig ist. Man kann aber dafuer sorgen,
dass **nie in die Haelfte geschrieben wird, die gerade gezeigt wird**.

Der Bochs-VBE-Baustein (QEMU `-vga std`, und dieselbe Schnittstelle auf
echtem Blech) verwaltet mehr Bildspeicher als der Schirm zeigt, und
`VBE_YOFF` sagt ihm, ab welcher Zeile er auslesen soll. Also: die
doppelte Hoehe abbilden, abwechselnd in die eine und die andere Haelfte
malen, und am Bildende **einen Registerschreib** -- die ganze Seite
wechselt auf einmal. Ein halbes Bild kann es danach nicht mehr geben.

**Die Regel, die dabei nirgends gebrochen werden darf:** gemalt wird in
`S_SEITE`, gezeigt wird die andere. Die erste Fassung setzte beide auf
0; dann malte der Server in genau die Haelfte, die der Schirm auslas,
und die Seitenumschaltung war ein teures Nichts -- gemessen als 97
Prozent zerrissene Ablesungen, waehrend `flips` munter stieg.

### Wo der Seitenwechsel nicht zustande kommt

Er braucht die doppelte Bildhoehe **im Abbildungsfenster**, und das hat
acht 2-MiB-Plaetze (`WIN_SLOTS`), von denen Geraete schon welche
belegen.

| Aufloesung | ein Bild | doppelt | Kacheln | flip |
|---|---:|---:|---:|:--:|
| 800x600 | 1,9 MB | 3,8 MB | 2 | **ja** |
| 1280x800 | 4,1 MB | 8,2 MB | 4 | **ja** |
| 1920x1080 | 7,9 MB | 15,8 MB | 8 | nein |
| 3440x1440 (Justins Brett) | 19,8 MB | 39,6 MB | 20 | nein |

Ab 1920x1080 faellt `fb.init` in den Streifenbetrieb, und
`flip_setup` meldet ehrlich `flip=0`. Dann bleibt es beim Sammeln --
weniger Gelegenheiten zum Reissen, aber nicht null. Das ist **kein
Fehler und keine Panne**, sondern die Grenze der Abbildung; sie steht
hier, damit niemand `flip=0` fuer einen Defekt haelt. Wer sie
verschieben will, muss das Abbildungsfenster vergroessern
(`WIN_SLOTS`) oder auf virtio-gpu mit eigenem Ressourcen-Flush gehen --
beides eine eigene Runde.

---

## 4. DIE FENSTERBEWEGUNG

Beim Oeffnen waechst ein Fenster von `AN_SCALE0` (85 Prozent) auf volle
Groesse und wird dabei von durchsichtig nach deckend gemischt; beim
Schliessen und Minimieren laeuft dieselbe Kurve rueckwaerts. Gemalt
wird die Fensterflaeche abgetastet und mit `fb.pixel_a` gemischt
(`paint_win_anim`) -- **der Rahmen wird dabei weggelassen**, weil ein
mitskalierter Rahmen an jeder Kante eine andere Strichstaerke haette
und nach Fehler aussieht.

**Die Zeiten kommen aus den Formmarken, nicht aus eigenen Konstanten.**
`FM_MOTION` ist eine neue Marke neben Radius und Schatten; steht keine
da, gilt `MOTION_DEF = 120 ms` -- dieselben 120 ms, die wlib seit
DESIGN-2 als `MO_FAST` fuer Hover und Menue nimmt. Die Kurve ist
dieselbe (`ease_out`, ganzzahlig, `1-(1-t)^2` in Tausendsteln): ein
Fenster, das aufgeht, und ein Knopf, der hell wird, sollen sich gleich
anfuehlen. Keine Fliesskommazahl -- der Kern rettet in `syscall` kein
SSE.

Der Fortschritt faellt aus der **vergangenen Zeit** und nicht aus der
Zahl der Bilder (`MS_PRO_TICK = 10`, weil `time.TICK_HZ = 100`): ist
der Server einmal langsamer, springt die Bewegung weiter, statt sich zu
dehnen.

**Ein Fenster verschwindet erst, wenn seine Schliessbewegung durch
ist.** `close_anim` schickt das Ereignis und meldet die Bewegung an;
`destroy` ruft erst `anim_tick`, wenn der Fortschritt 1000 erreicht.
Waere es beim Klick verschwunden, haette die Bewegung nichts mehr zu
zeigen gehabt.

### Gemessen

Vorfuehrung im Halten (`wmanim`): ein Fenster geht bei Tick 50 auf, bei
Tick 150 wieder zu.

```
mit Bewegung   anim=2  frames=38
ohne (noanim)  anim=0  frames=0
```

38 Zwischenbilder auf zwei Bewegungen, also ~19 je Bewegung -- bei 120
ms und 100 Hz sind ~12 zu erwarten, der Rest sind die Takte, in denen
der Fortschritt gleich blieb und trotzdem gezeichnet wurde.

Und im Bild, ueber eine Serie von 90 Fotos (`tools/vsync/bewegung.py`,
ausgezaehlt mit `wachstum.py` -- gezaehlt wird die Flaeche des
vorgefuehrten Fensters, das eine Farbe traegt, die sonst nirgends
vorkommt):

| | verschiedene Flaechen | staerkste Mischung |
|---|---:|---:|
| mit Bewegung | **5** (2048, 2276, 62276, 65423, 66157) | 65 423 Bildpunkte |
| `noanim` | **2** (2276, 66157) | 2 276 |

Mit Bewegung kommen Zwischengroessen im Bild an, und sie sind
**gemischt** (weder Fensterfarbe noch Hintergrund) -- das ist das
Alpha. Ohne Bewegung ist das Fenster in einem Bild gar nicht und im
naechsten voll da, ohne jede Zwischenstufe.

**`noanim` erreicht denselben Endzustand** (`wm: wins n=1`). Das ist
die Zusage hinter "Animationen reduzieren": jede Bewegung ist dann
sofort fertig, nicht uebersprungen.

---

## 5. WAS NICHT GEBAUT WERDEN MUSSTE

**Der Schatten war schon gecacht.** Der Auftrag nannte "Schatten dabei
cachen" als offenen Punkt, und DESIGN-2 hatte ihn als halb eingeloest
gemeldet. Im Kern ist er es ganz: `shadow_build` legt eine Deckungsmaske
an (`S_SHMASK`, zwei Baenke fuer scharf und unscharf), und `shadow_key`
baut sie nur neu, wenn sich wirklich eine der fuenf Formzahlen geaendert
hat. Gemessen im Betrieb: `shbuild=0` -- kein einziger Neubau waehrend
des Malens. Die ganzzahlige Wurzel laeuft 1600 mal je Formwechsel und
kein einziges Mal je Bild.

Was DESIGN-2 gemeint hat, ist `drop_shadow` in **wlib** (Ring 3), und
das ist eine andere Datei und eine andere Runde. Im Fensterserver war
nichts zu tun, und es waere falsch gewesen, hier etwas zu bauen und als
Fortschritt zu melden.

---

## 6. DIE SPARSAMKEIT DER RUNDE UHRWERK

Runde UHRWERK hat gemessen, dass der Server ohne Eingabe kaum zeichnet,
und diese Sparsamkeit ausdruecklich als Gut bezeichnet. Die Bildgrenze
*sammelt* nur; sie darf nichts zusaetzlich anstossen.

Gemessen, 10 Sekunden Halten ohne Eingabe, derselbe Lauf auf dem
Kernel VOR und NACH dieser Runde:

```
vorher:   wm: composites=42  blits=42  pixels=10564320
nachher:  wm: composites=42  blits=42  pixels=10564320
```

Auf das Bildpunkt genau gleich. Ueber das ganze Halten gerechnet: 145
Zeichnungen in 10 s auf beiden Kerneln, und 2,2 Vollbilder je Sekunde
an Flaeche -- kein Vollbild-Neuanstrich.

---

## 7. DIE WOERTER

| Wort | was es tut |
|---|---|
| `vsync` | die Bildgrenze: `compose` merkt vor, `present` uebertraegt im Takt |
| `nopresent` | Gegenprobe -- der alte Weg, sofort schieben |
| `flip` | die Seitenumschaltung (doppelte Hoehe abbilden) |
| `noflip` | Gegenprobe -- weiter zeilenweise kopieren |
| `wmanim` | Fenster oeffnen/schliessen mit Skalieren und Alpha (samt Vorfuehrung) |
| `noanim` | Gegenprobe -- kein Zwischenbild, aber derselbe Endzustand |
| `wmsig` | Signaturbetrieb samt Ableser (nichts fuer den Alltag) |
| `wmruhe` | stehendes Fenster, das trotzdem neu gemalt wird -- fuer die Zerreissprobe |

Die Meldezeile:

```
wm: vsync=1  comp=5298  pres=5154  pend=5298  anim=0  frames=0
    ticks=5153  sig=1  frame=5298  motion=0  liest=167948  risse=0
    flip=1  flips=5154  ...
```

`pres` **muss** kleiner sein als `comp`, sonst hat das Sammeln nichts
gesammelt.

---

## 8. WAS OFFEN BLEIBT

1. **Seitenwechsel erst ab 1920x1080 nicht mehr moeglich** (Abschnitt
   3). Auf Justins 3440x1440 waeren 20 Kacheln noetig. Der Weg dahin
   ist ein groesseres Abbildungsfenster oder virtio-gpu.
2. **Die Zerreissprobe braucht zwei Kerne.** Auf einem Kern kann sie
   per Bauart nichts finden. `tools/vsync/run.sh` startet QEMU deshalb
   mit `-smp 2`.
3. **Das `fb: hold`-Problem aus `tools/gfx/run.sh`** (46/30 auf merge6)
   ist von dieser Runde weder beruehrt noch behoben worden.
4. **Der Zeiger laeuft mit im Bild.** Bei Seitenwechsel wird die volle
   Flaeche kopiert, bevor umgeschaltet wird -- das kostet mehr als das
   schmutzige Rechteck. Bei den gemessenen Bildzeiten (unter 1 ms bei
   1280x800) faellt es nicht auf; auf einem grossen Schirm mit
   Seitenwechsel waere ein Rechteck je Seite die naechste Verbesserung.
