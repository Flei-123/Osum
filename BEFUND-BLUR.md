# RUNDE BLUR -- DAS ACRYL

Justin, mehrfach: *"der Blur wie in Windows ist nicht drin"*.

Jetzt ist er drin -- hinter Taskleiste, Startmenue, Klapp- und
Kontextmenues und Blasen. **Nicht** hinter gewoehnlichen Fenstern, und
das ist keine Voreinstellung, sondern eine Struktur. Warum, steht in
Abschnitt 3.

---

## 1. WAS DER EIGENTLICHE UMBAU WAR -- und warum er kleiner ausfiel als gedacht

Die Auftragsliste nennt als ersten und schwersten Punkt: *"Den
Hintergrund durchreichen -- ein Fenster, das durchscheinen will,
braucht Lesezugriff auf das, was hinter ihm liegt."*

Beim Nachsehen stellte sich heraus, dass dieser Server das **schon
kann**, ohne es zu wissen:

* `wm.compose` malt den Schreibtisch, dann die Fenster **von unten nach
  oben**, alle in den Zweitpuffer (`fb`, `S_DRAW`).
* Wenn ein Fenster an der Reihe ist, steht alles, was unter ihm liegt,
  dort **bereits fertig**.
* `fb.get_pixel` und `fb.draw_at` lesen genau aus diesem Puffer.

Es braucht also **keinen Mitschnitt des Hintergrunds**, keine zweite
Flaeche und keinen zusaetzlichen Puffer je Fenster. Der Blur liest an
Ort und Stelle, bevor sich das Fenster darueber malt. Ein Mitschnitt
waere die teurere **und** die falsche Loesung gewesen; die billige war
schon da.

**Was statt dessen wirklich gefehlt hat**, war das Gegenstueck -- und
das hat die Messung erst nach dem ersten Bildbeweis gezeigt. Siehe
Abschnitt 5, Fehler 2.

---

## 2. DIE DREI TEILE, UND WARUM ES DREI SIND

Was Windows Acryl nennt, sind drei Dinge uebereinander. Man sieht
sofort, wenn eines fehlt.

| Marke | Bereich | Vorgabe | wozu |
|---|---|---|---|
| `FM_BLUR` | 0..16 | 8 | Radius des zweifachen Kastenfilters |
| `FM_BLURTINT` | 0..100 | 22 | Toenung in Richtung der Flaechenfarbe |
| `FM_BLURNOISE` | 0..16 | 3 | Amplitude des Korns |

Jede Zahl ist **Schalter und Regler zugleich**: 0 heisst aus. Dieselbe
Regel wie `FM_SHADOW` und wie die drei Marken der Runde ZIEH -- ein
Schalter neben einem Regler kann sich widersprechen, eine Zahl nicht.

### Der Filter: zweifacher Kasten, kein Gauss

Zweimal Kasten hintereinander ist eine Dreiecksfunktion; optisch ist
der Unterschied zu einem echten Gauss bei diesen Radien nicht zu sehen.
Der Preis ist es umso mehr: Gauss kostet je Bildpunkt `2r+1`
Multiplikationen, der Kasten mit gleitender Summe kostet **eine
Addition und eine Subtraktion** -- unabhaengig vom Radius.

### Das Rauschen ist nicht die Zierde, sondern der Unterschied

Ohne Korn sieht eine weichgezeichnete Flaeche aus wie **Milchglas**: zu
sauber, zu glatt, sie wirkt wie ein Filter und nicht wie ein Material.
Das Korn ist genau der Punkt, an dem Acryl anfaengt, nach Acryl
auszusehen -- der Unterschied, den man sieht, ohne ihn benennen zu
koennen.

Es ist **ortsfest**: der Streuwert haengt an `x` und `y`, nicht an einem
laufenden Zaehler. Sonst flimmerte die Flaeche bei jedem Bild neu, und
aus dem Korn wuerde Fernsehschnee. Das ist zugleich der Grund, warum
der Zwischenspeicher das Rauschen mitkopieren darf.

---

## 3. DIE KOSTEN -- und warum ganze Fenster NICHT durchscheinen

`tools/blur/kosten.c`, ein Kern, 60-Hz-Budget = 16,7 ms, Radius 8:

```
Benachrichtigung    360x120     0,87 ms     5,2 %
Taskleiste         1920x48      1,64 ms     9,8 %
Startmenue          320x520     3,16 ms    18,9 %
ein Fenster         900x650    10,96 ms    65,6 %   <- zwei davon reissen das Budget
Vollbild FHD       1920x1080   37,90 ms   227,0 %   <- unmoeglich
```

**Also: Leiste, Startmenue, Menues, Blasen -- ja. Ganze Fenster --
nein.** Und zwar gar nicht, auch nicht als Wahlmoeglichkeit.

Die Auswahl trifft deshalb nicht der Geschmack, sondern die **Ebene**
des Fensters. `wm.blur_will` laesst `L_TOP`, `L_MENUE`, `L_POPUP` und
`L_TIP` durch und `L_NORMAL`/`L_DESK` strukturell nicht. Was man nicht
bezahlen kann, bietet man nicht an.

### Zwei Messungen, die die Zahlen des Auftrags korrigiert haben

Die Auftragsliste nannte fuer das Startmenue 11,9 ms (72 %). Die erste
eigene Messung kam auf **27,88 ms (167 %)** -- mehr als das Doppelte.
Der Filter war nicht falsch; der **senkrechte Durchgang lief
spaltenweise**, und zwei Bildpunkte untereinander liegen `w*4` Oktette
auseinander, also faellt je Bildpunkt eine eigene Cachezeile an.

Umgestellt auf **zeilenweise** (eine Zeile gleitender Summen im
Speicher, das Bild von oben nach unten): 27,88 -> **15,32 ms (92 %)**.

Dann die Division. Je Bildpunkt und Durchgang stand eine ganzzahlige
Division je Kanal -- **zwoelf** im ganzen Filter. Ersetzt durch eine
Multiplikation mit dem Kehrwert: 15,32 -> **3,16 ms (18,9 %)**.

Zusammen ist der gebaute Filter **um den Faktor 6 schneller** als die
Grundlinie der Auftragsliste.

---

## 4. DER ZWISCHENSPEICHER -- und die Ungueltigkeitserklaerung

**Er ist Pflicht, nicht Kuer.** Ein Startmenue ueber einem stehenden
Schreibtisch liefert Bild fuer Bild dasselbe Ergebnis. Ohne
Zwischenspeicher wuerde es sechzig Mal in der Sekunde neu gerechnet:
3,16 ms je Bild, dauerhaft, fuer ein Bild, das sich nicht aendert. Mit
Zwischenspeicher kostet dasselbe **0,02 ms** -- gemessen ein Faktor von
157.

### Die schwierige Frage ist nicht das Kopieren, sondern das Verwerfen

Woran erkennt der Server, dass sich **unter** der Flaeche etwas
geaendert hat? Die naheliegende Antwort -- *"wenn das Fenster schmutzig
ist"* -- ist falsch, und zwar auf **beide** Seiten:

* **Zu oft:** die Taskleiste meldet sich bei jedem Uhrenwechsel
  schmutzig. Der Schreibtisch darunter hat sich dabei nicht geruehrt.
  Neu zu rechnen waere reine Verschwendung.
* **Zu selten:** ein Fenster, das **unter** dem Startmenue verschoben
  wird, macht das Menue selbst gar nicht schmutzig -- und trotzdem ist
  der Blur darunter veraltet. Das ist der Fall, der ein eingefrorenes
  Bild stehen laesst.

Also wird die Frage dort beantwortet, wo sie hingehoert: **am
Schmutzrechteck**. `wm.damage` ist die eine Stelle, durch die in diesem
Server jede Aenderung geht. Sie ruft `blur_touch`, und das zaehlt den
Zaehler eines Platzes genau dann hoch, wenn das gemeldete Rechteck
dessen Flaeche **schneidet**. Ein Schmutzrechteck daneben laesst sie
gueltig.

Gueltig ist ein Platz damit, wenn **drei** Dinge stimmen: dasselbe
Fenster, dasselbe Rechteck, derselbe Zaehler. Die Regel hat keinen
Sonderfall und haengt an derselben Buchfuehrung wie das Zeichnen selbst.

**Ein Zaehler JE PLATZ**, nicht einer fuer alle -- sonst haette eine
Aenderung unter dem Startmenue auch den Speicher der Leiste am anderen
Ende des Schirms entwertet.

---

## 5. DREI FEHLER, DIE ERST DIE MESSUNG GEZEIGT HAT

### 1. Der Zwischenspeicher mit EINEM Platz war wertlos

Auf dem einfachen Schreibtisch sah er hervorragend aus:

```
blur: rad=8 tint=22 noise=3  n=2  cache=83  quote=97%
```

Dann lief die Vorfuehrung mit **drei** durchscheinenden Flaechen
gleichzeitig (Leiste, Startmenue, zweite Leiste):

```
blur: rad=8 tint=22 noise=3  n=273  cache=0  quote=0%
```

**Die Quote fiel auf null.** Nicht der Filter war schuld, sondern der
eine Platz: jede Flaeche warf die vorige hinaus, und in jedem Bild
wurden alle drei neu gerechnet. Genau die Sorte Fehler, die auf dem
Prueftisch nicht auffaellt und auf dem Schreibtisch des Menschen jeden
Tag zuschlaegt -- **Leiste und offenes Menue sind der Normalfall**.

Behoben mit `BC_N = 4` Plaetzen. Danach, derselbe Lauf:

```
blur: rad=8 tint=22 noise=3  n=26  cache=247  quote=90%
```

### 2. Der Blur war gerechnet -- und unsichtbar

Der erste Bildbeweis zeigte das gemusterte Schreibtischbild mit
gestochen scharfen Kanten und darueber eine **deckend graue** Leiste.
Die Zaehler sagten `n=26 cache=247`, der Filter lief also nachweislich.

Der Grund: `paint_win` kopiert den Fensterpuffer mit `fb_row`
**wortweise und deckend** in den Zweitpuffer. Die Leiste hat den Blur,
den sie selbst ausgeloest hatte, sofort wieder zugedeckt. **In diesem
Server gab es ueberhaupt kein Durchscheinen** -- `blend()` je Bildpunkt
gab es, aber kein Fenster konnte sagen, dass es durchscheinen will.

Das war der eigentliche fehlende Umbau (und nicht das Durchreichen des
Hintergrunds, siehe Abschnitt 1). Dazugekommen sind deshalb:

* `W_OPAC` je Fenster -- die Deckung, 0..255, gespeichert als
  *Wert + 1*, damit ein wiederverwendeter Platz (alles null) das alte,
  deckende Verhalten hat.
* `wm.set_opac` / `wm.win_opac`.
* `fb_row_mix` -- liest, was schon dasteht (nach `blur_flaeche` genau
  die weichgezeichnete Flaeche), und mischt die Fensterzeile darueber.
  Sie wird **nur** gerufen, wenn ein Fenster wirklich durchscheint;
  alles andere geht weiter den billigen Weg ueber `fb_row`.

**Lehre:** ein Zaehler, der sagt "es wurde gerechnet", ist kein Beleg
dafuer, dass man es sieht. Deshalb gibt es jetzt `tools/blur/kante.py`.

### 3. Eine Namenskollision auf der Befehlszeile

Der Schalter der Vorfuehrung hiess zuerst `wmblur` -- und ist damit ein
echter **Praefix** von `wmblur=8`. `find` sucht die Zeichenkette
irgendwo in der Befehlszeile; wer also nur den Radius setzen wollte,
haette stillschweigend auch die Vorfuehrung eingeschaltet und bekaeme
ein gemustertes Schreibtischbild, das er nie bestellt hat.

Umbenannt auf `wmacryl`. Dieselbe Sorte Fehler wie die doppelten Zahlen,
vor denen `messzeile_x` seit Runde BLECHDREI warnt.

---

## 6. DIE ZAHLEN

### Bilder je Sekunde -- drei Faelle, wie verlangt

Gemessen auf 1280x800, `shape=osum`, KVM, aus `wm: vsync=` und
`bildzeit:` desselben Laufs. Der Blur liegt auf Leiste **und**
Startmenue **und** einer zweiten Leiste, also dem teuersten Fall, den
dieses System zulaesst.

Drei Laeufe, **derselbe Kern**, nur eine andere Befehlszeile -- alles
andere waere kein Vergleich. Die Vorfuehrung (`wmacryl`) haelt dabei
**drei** durchscheinende Flaechen gleichzeitig offen (Taskleiste,
Startmenue, zweite Leiste), also den teuersten Fall, den dieses System
zulaesst.

| Fall | Befehlszeile | gerechnet | kopiert | Quote | Zeit im Filter |
|---|---|---|---|---|---|
| ohne Blur | `wmblur=0` | 0 | 0 | -- | **0 us** |
| Blur, **ohne** Speicher | `wmnocache` | 274 | 0 | 0 % | **8 536 931 us** |
| Blur, **mit** Speicher | (Vorgabe) | 26 | 247 | **90 %** | **1 146 710 us** |

**Der Zwischenspeicher spart den Faktor 7,4 an Arbeit** -- fuer
praktisch dieselbe Zahl Flaechen (274 gegen 273) faellt ein Siebtel der
Rechenzeit an. Abgeschaltet kostet der Blur exakt nichts: `n=0`,
`px=0`, `us=0`; `blur_flaeche` kehrt bei `blur=0` auf der ersten Zeile
um und `blur_will` laesst kein Fenster durch.

Die Gegenprobe, dass die Zaehler ehrlich sind: der Server meldet
`px=25 548 800` bei `n=274`, also **93 244 Bildpunkte je Rechnung**.
Das Mittel der drei Flaechen (35 840 + 166 400 + 61 440) / 3 ist
**87 893** -- dieselbe Groessenordnung, und die Differenz ist die echte
Taskleiste, die mal mitgerechnet wird und mal nicht.

### Was die Zahl `bildzeit:` NICHT sagt

`bildzeit: mittel=` liegt in allen drei Laeufen zwischen 75 und 91 ms
und ist als Vergleich **unbrauchbar**: sie mittelt ueber das
Hochfahren mit, in dem einzelne Bilder 280 ms kosten -- auch im Lauf
**ohne** Blur (`max=278 859 us` bei `blur=0`). Deshalb stehen oben die
Zaehler des Filters selbst und nicht diese Zahl.

### Und eine ehrliche Einschraenkung

Unter QEMU kostet der Filter **0,334 us je Bildpunkt**, in C auf dem
Wirt **0,019 us** -- Faktor 17,6. Der Kern laeuft im Gastspeicher, ohne
die Schleifenoptimierung des Wirts-gcc und mit `__mmio_read32` /
`__mmio_write32` je Bildpunkt.

Das heisst: **der volle Drei-Flaechen-Fall reisst unter QEMU das
60-Hz-Budget**, auf echtem Blech nach der C-Messung nicht. Im Alltag
sind ohnehin selten drei Flaechen gleichzeitig offen, und genau dafuer
gibt es den Zwischenspeicher -- er druckt die Zahl der Rechnungen von
274 auf 26. Wer es trotzdem nicht bezahlen will, schaltet es in den
Einstellungen ab; das ist der Grund, warum es den Schalter gibt.

### Der Bildbeweis, maschinell gelesen

`tools/blur/kante.py` misst nicht die Summe der Unterschiede -- die
taugt nicht, weil eine getoente Flaeche schon kleinere Unterschiede
hat, ohne weichgezeichnet zu sein. Gemessen wird die **Verteilung**:
eine harte Kante ist **ein** grosser Sprung zwischen zwei Nachbarn,
eine weiche ist eine **lange Reihe** kleiner.

```
 Zeile  was                           harte Kanten  weiche Uebergaenge
   680  blanker Grund                           10                   0
   700  blanker Grund                           10                   0
   720  HINTER der Leiste                        0                 306
   735  HINTER der Leiste                        0                 310
   750  HINTER der Leiste                        0                 320
   500  HINTER dem Menue                         0                 145
   600  HINTER dem Menue                         0                 144
   500  blanker Grund daneben                    5                   0
   600  blanker Grund daneben                    5                   0
```

**Jede harte Kante verschwindet hinter der Flaeche, und an ihre Stelle
treten dreihundert weiche Uebergaenge.** Das ist der Blur, in Zahlen,
aus dem Bild gelesen.

Ueber **einfarbigem** Grund waere davon nichts zu sehen -- der
Mittelwert einer einfarbigen Umgebung ist wieder dieselbe Farbe, ein
Blur darueber ist bildpunktgenau ein Nichtstun. Genau deshalb malt die
Vorfuehrung (`wmacryl`) ein Schachbrett mit harten Kanten.

### Der Kehrwert ist exakt, nicht ungefaehr

Die erste Fassung rundete den **Kehrwert** auf (`(1<<16)+n-1)/n`) und
lag um bis zu **16 Helligkeitsstufen** daneben -- ein sichtbarer
Farbstich. Richtig ist Aufrunden im **Zaehler**.

```
BLUR-KEHRWERT: shift=19, n=1..33, 143088 Faelle geprueft
  OK    jeder Fall EXAKT wie die Division
```

Mit Shift 16, 20 und 24 blieb je ein Fehler von einer Stufe stehen --
und eine Stufe ist auf einer weichgezeichneten Flaeche genau das, was
man als Streifen sieht. Dieselbe Sorte Fehler, die `blendcheck.py` in
diesem Projekt schon einmal gejagt hat.

---

## 7. EINSTELLBAR, OHNE NEUSTART

*Einstellungen -> Darstellung*, unter "Fenster ziehen:":

* **Durchscheinende Flaechen (Acryl)** -- ein Kaestchen
* **Staerke** und **Toenung** -- je eine Stufenwahl

Uebernehmen schreibt `blur=`, `blur_tint=` und `blur_noise=` nach
`/etc/theme.conf`; `theme_reload` holt sie im selben Durchgang wie
Schema und Form. Auf schwacher Hardware laesst sich der Blur damit
abschalten, ohne die Form zu wechseln -- `/etc/theme.conf` sticht die
Formdatei, weil es die Vorliebe des Menschen ist.

**Das Rauschen hat absichtlich keinen eigenen Regler.** Unter 2 sieht
man es nicht, ueber 8 wird es Griesel; ein Regler, dessen brauchbarer
Bereich drei Stufen breit ist, ist ein Regler, an dem man nur etwas
falsch machen kann. Er haengt am selben Kaestchen: Acryl an heisst Korn
an.

Vorgabe in `assets/shapes/osum.shape` (8 / 22 / 3); `classic` setzt alle
drei auf 0 -- *"das ist die Vergangenheit"*, und in der Vergangenheit
war nichts durchsichtig.

---

## 8. WAS DIESE RUNDE NICHT ANGEFASST HAT

* **`glas`-Gebiet** (Rundungen/Radien, Theme-Store): nicht beruehrt.
  `FM_RADIUS` und die Radien der Formdatei stehen unveraendert; die
  drei neuen Marken liegen daneben und nicht darin.
* **Die Animationen der Runden OBERFLAECHE und ZIEH**: `pruef/anim-ab.sh`
  liefert nach jedem groesseren Schritt weiter `anim=4`.
* **Ganze Fenster durchscheinend**: bewusst nicht gebaut, siehe
  Abschnitt 3.

---

## 9. ABNAHMEN

| Abnahme | Soll | Ist |
|---|---|---|
| `tools/install/abnahme.sh` | 35 / 0 | **35 gruen, 0 rot** |
| `tools/hotplug/run.sh` | 45 / 0 | **45 passed, 0 failed** |
| `tools/clip2/run.sh` | 32 / 0 | **32 gruen, 0 rot** |
| `tools/logind/run.sh` (UITRACE=1) | 49 / 0 | 35 / 1 -- **siehe unten, nicht von dieser Runde** |
| `tools/check-ui.sh` | 196 Dateien, 0 Verstoesse | **196 / 0, PASSED** |
| `tools/paint/scalars.py` | 0 Ueberschneidungen | **0** |
| `pruef/anim-ab.sh` | `anim=4` | **anim=4** |
| `tools/blur/kehrwert.py` | Fehler 0 | **0, 143 088 Faelle** |

### Die eine rote Zusage -- und warum sie nicht dieser Runde gehoert

`tools/logind/run.sh` meldet 35 / 1. Die gefallene Zusage ist:

```
FAIL  das Startmenue ging nicht auf (fl=19)
```

Das Startmenue liegt auf `L_MENUE` -- also genau auf einer Ebene, die
diese Runde anfasst. Der Verdacht lag damit bei mir, und eine Behauptung
haette hier nicht gereicht. Also die **Gegenprobe auf unveraendertem
main** (`fb-osum`, `fe475d47`, ohne eine Zeile dieser Runde), auf
derselben Maschine, unter derselben Last:

| Baum | ABMELDEN | LOGIND |
|---|---|---|
| main, **ohne** Blur | 9 bestanden, **4 gescheitert** | 35 / 1 |
| `runde-blur`, **mit** Blur | 12 bestanden, **1 gescheitert** | 35 / 1 |

**Dieselbe Zusage, dieselbe Zahl (`fl=19`), auch ohne Blur** -- und main
schneidet im selben Abschnitt sogar schlechter ab. `fl=19` heisst: Bit 0
(`F_HIDDEN`) steht noch. `pruef/abmelden.py` drueckt `meta_l` und wartet
**vier Sekunden**; auf einer Maschine, auf der fuenf Runden gleichzeitig
QEMU fahren, reicht das manchmal nicht. Ein lastabhaengiger Wackler,
vorbestehend, und keine Regression dieser Runde.

Was diese Runde dagegen belegen kann: `check-ui` laeuft **innerhalb**
desselben logind-Laufs gruen durch (196 Dateien, 0 Verstoesse), und die
drei anderen Abnahmen stehen ohne eine einzige rote Zusage.

### Die Gegenprobe auf die Pflichtliste

`/etc/shapes/osum` traegt die drei neuen Marken. Eintrag aus dem
Bauplan genommen, Pflichteintrag stehen gelassen:

```
== FEHLT IM ABBILD: /etc/shapes/osum
== 1 Pflichtdatei(en) fehlen im Abbild
RC=1
```

Der Bauer bricht ab, wie er soll. Danach wiederhergestellt.
