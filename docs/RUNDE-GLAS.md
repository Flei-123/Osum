# Runde GLAS — Eckenrundung, Durchsicht, Milchglas

Justins Wunsch dieser Runde stand in zwei Saetzen: die **Eckenrundung
stufenlos regeln** und die **Taskleiste transparent bzw. als Milchglas**
haben. Beides gibt es jetzt, beides steht in `/etc/theme.conf`, beides
haengt an einem Regler auf der Seite "Darstellung", und beides ist
gemessen.

**Jede Zahl unten kommt aus einem Lauf.** Wo eine fehlt, steht warum.
Abschnitt 8 nennt die Punkte, die **nicht** erreicht wurden — sie stehen
hier und nicht nur im Protokoll, weil eine Runde, die nur ihre Erfolge
aufschreibt, beim naechsten Mal an derselben Stelle wieder anlaeuft.

Beleg fuer alles: `bash tools/themestore/run.sh`. Ergebnis des Laufs,
auf den sich dieses Blatt bezieht (21.09.2026, QEMU/TCG ohne KVM):

```
THEMESTORE: 136 passed, 0 failed
```

Vorher waren es 81 Zusagen. Keine davon ist abgeschwaecht oder entfernt
worden; die 55 neuen stehen in Abschnitt 11 des Laeufers.

Die Bilder liegen unter `docs/shots/glas/` (Tabelle dort in
`README.md`), die Einzelaufnahmen des Laufs unter
`docs/shots/themestore/glas-*.png`.

---

## 1. Was neu ist, in vier Zahlen

| Schluessel | Bereich | Bedeutung | Vorgabe |
|---|---|---|---|
| `radius` | 0 … 24 | Eckenrundung in Bildpunkten, ueberall | aus `shape=` |
| `taskbar_alpha` | 20 … 100 | Deckkraft der Leiste in Prozent | 100 |
| `window_alpha` | 20 … 100 | Deckkraft gewoehnlicher Fenster | 100 |
| `taskbar_blur` | 0 … 16 | Milchglas unter der Leiste, 0 = aus | 0 |

Jeder der vier liest **nur Ziffern** und wird beim Einlesen geklemmt.
Die Sicherheitszusage der Vorlagen bleibt damit Wort fuer Wort
dieselbe: ein untergeschmuggeltes `radius=/bin/sh` ist kein Radius,
sondern eine schlechte Zeile, und der Laeufer zaehlt sie als solche
(Abschnitt 7: *"GEGENPROBE: die zwei geschmuggelten Schluessel werden
GEZAEHLT: 2"*).

`shape=classic|modern` gibt es weiter. Es setzt nur noch den
**Startwert** des Radius (0 bzw. 8) und wird von einer `radius=`-Zeile
ueberstimmt.

---

## 2. Die Rundung kommt wirklich ueberall an

Gemessen wird nicht "sieht rund aus", sondern zweierlei: **wer** mit
welchem Radius gemalt hat (jede Widgetart meldet ihn) und **was im
Bild** an der Ecke steht.

| Radius | Widgetarten, die ihn melden | Ecke: tiefe | Ecke: Zeilen mit Mischton |
|---|---|---|---|
| 0 | 10 | 0 | 0 |
| 12 | 10 | 10 | 8 |
| 24 | 10 | 32 | 18 |

* **tiefe** = wie viele Bildpunkte der Ecke abgeschnitten sind
  (`glascheck.py ecke`). 0 bei Radius 0 ist die Gegenprobe: dort ist
  ein rechter Winkel und nichts zu runden.
* **Zeilen mit Mischton** = Kantenglaettung. 18 von 24 Zeilen der
  Rundung tragen bei Radius 24 einen Zwischenton; eine Treppe haette
  null.
* **Der Inhalt wandert nicht**: von 36 gemessenen Rechtecken der Seite
  "Darstellung" hat sich zwischen Radius 0 und 24 **kein einziges**
  bewegt.
* Der Griff des Reglers bleibt auch bei Radius 0 ein Kreis (7 Farben in
  seiner Ecke) — ein Kreis ist keine Ecke und darf nicht mitgeklemmt
  werden.

Bilder: `01-radius-0-scharfe-ecken.png`, `02-radius-12-mittel.png`,
`03-radius-24-weiche-kacheln.png`.

---

## 3. Die Leiste mischt wirklich

`glascheck.py mix` rechnet die Mischung auf dem Wirt ein zweites Mal
nach — aus dem Kommentar in `kernel/ui/wm.fi` abgeschrieben, nicht aus
dem Code — und vergleicht Bildpunkt fuer Bildpunkt.

| Deckung | Bildpunkte, die der nachgerechneten Mischung gleichen | Farben unter der Leiste | Streuung (`var`) |
|---|---|---|---|
| 100 % | 100 von 100 | 1 | 0 |
| 70 % | 100 von 100 | 2 | 1 597 |
| 40 % | 100 von 100 | 2 | 6 389 |
| 70 % + Milchglas 12 | — | 13 | **788** |

"Farben 1" bei voller Deckung und "Farben 2" darunter ist die Probe
darauf, dass das **Muster** des Hintergrundbildes durchschlaegt und
nicht bloss die Flaeche heller wird. Die Streuung steigt von 0 ueber
1 597 auf 6 389, je durchsichtiger die Leiste ist.

Bilder: `04-taskleiste-100-deckend.png`,
`05-taskleiste-70-prozent.png`, `06-taskleiste-40-prozent.png`,
`12-leiste-vergleich-ausschnitt-2x.png` (dieselbe Stelle vierfach,
2-fach vergroessert).

---

## 4. Milchglas: weichgezeichnet, und schnell genug

Der Weichzeichner ist ein **separierbarer Kastenfilter in drei
Durchgaengen mit laufender Summe**, also O(1) je Bildpunkt und
unabhaengig vom Radius. Die Zeile, die er je Vollbild meldet:

```
wm: glas r=12 px=35840 us=42701 max=46319 cache=2/26 key=ffffff
```

| Zahl | Bedeutung |
|---|---|
| `px=35840` | angefasste Bildpunkte je Streifen (1280 × 28) |
| `us=42701` | Mikrosekunden fuer den letzten Durchgang, **QEMU/TCG ohne KVM** |
| `max=46319` | die teuerste je gemessene Mischung, 46,3 ms |
| `cache=2/26` | 26 mal gebraucht, **2 mal aus dem Zwischenspeicher** |
| `key=ffffff` | die Schluesselfarbe, gegen die das Abstandsalpha rechnet |

Der erste Streifen eines Laufs kostet `us=37464` bei `cache=0/1` — da
ist der Zwischenspeicher noch leer, und das ist die ehrliche Zahl fuer
"kalt".

**Die Streuung sinkt messbar**: 1 597 ohne Milchglas, **788** mit —
und aus zwei Farben sind 13 geworden, also ein Verlauf und keine zwei
Kacheln mehr.

Bilder: `07-milchglas-blur16-grobes-muster.png` (die Aufnahme, auf der
man es SIEHT -- siehe Abschnitt 9c), `14-milchglas-mit-reglerstand.png`.

**Abkuerzung, ausdruecklich benannt:** 46 ms je Vollbild sind unter
TCG gemessen. Auf Blech mit KVM ist dieselbe Rechnung um ein Vielfaches
billiger, aber **diese Zahl ist hier nicht gemessen worden** — es gibt
in diesem Lauf keine KVM-Messung des Weichzeichners. Wer sie braucht,
faehrt `tools/themestore/build.sh ... accel=kvm`.

---

## 5. Lesbarkeit unter Transparenz

Gerechnet wird gegen den **gemischten** Grund im Bild, nicht gegen die
theoretische Flaechenfarbe.

| Hintergrundbild | Deckung | Kontrast der Leistenschrift |
|---|---|---|
| hell (Schachmuster) | 40 % | **14,43 : 1** |
| dunkel | 40 % | **12,33 : 1** |

Beides weit ueber 4,5 : 1. Die Untergrenze `ALPHA_MIN = 20` in
`kernel/user/wlibc.fi` klemmt jede Deckkraft darunter weg — aber siehe
Abschnitt 8, Punkt 2: der eigentliche Grund fuer die hohen Zahlen ist
ein **anderer**, und er ist ein Mangel und kein Verdienst.

---

## 6. Keine Schlieren, wenn ein Fenster unter die Leiste geht

Die Regel: **jedes Schmutzrechteck, das das Leistenrechteck schneidet,
wird auf die volle Breite der Leiste aufgezogen.** Sonst mischt die
halbe Leiste neu und die andere Haelfte zeigt, was vorher da war.

| Probe | Zahl |
|---|---|
| Fenster unter die Leiste gezogen und zurueck, Vergleich mit dem ungezogenen Lauf | **diff 0** abweichende Bildpunkte |
| die Schlierenregel hat gegriffen | `grow=1` |
| GEGENPROBE `noglasgrow`: Regel steht still | `aus=0` aufgezogene Rechtecke |

Bild: `10-fenster-unter-leiste-gezogen-keine-schlieren.png`. Was diese
Probe **nicht** zeigt, steht in Abschnitt 8, Punkt 1.

---

## 7. Ein Ort je Ring fuer jede Sache, begruendet in `raster.liste`

Die Messlatte hiess urspruenglich "genau eine Stelle, die ein rundes
Rechteck malt / die mischt". Ueber den ganzen Baum gerechnet ist das
falsch, und zwar mit Grund: zwischen Ring 0 und Ring 3 liegt eine
Ringgrenze (ein Programm kann `wm.fill_round` nicht je Bildpunkt als
Systemaufruf rufen), und der Bildspeicher mischt im Format des Schirms
statt in gepackten Farbworten. Sie lautet deshalb **ein Ort je Ring und
je Format, jeder einzelne begruendet in `tools/themestore/raster.liste`**
— und genau so wird sie gemessen.

Mechanisch gezaehlt im Lauf:

| Frage | Befehl | Zahl |
|---|---|---|
| Wer malt im Fensterserver ein rundes Rechteck? | `grep -c '^fn fill_round(' kernel/ui/wm.fi` | 1 |
| Wer mischt dort? | `grep -c '^fn blend(' kernel/ui/wm.fi` | 1 |
| Wer entscheidet, wie deckend ein Punkt ist? | `grep -c '^fn glass_mix(' kernel/ui/wm.fi` | 1 |
| Rasterer/Mischer im ganzen Baum ohne Eintrag in `raster.liste` | Abschnitt 11e | 0 |
| Eintraege der Liste, die es nicht mehr gibt | Abschnitt 11e | 0 |
| Selbsttest der Mischung und des Weichzeichners | `wm: glastest` | 7 / 7 |

Die Einstellung ueberlebt den Neustart, und zwar als Klick gemessen:
Regler von **4** auf **16** geschoben, `settings: glas radius=16` in
der laufenden Sitzung, `radius=16` in `/etc/theme.conf` auf der Platte.
Gegenprobe ohne Klick: 4 und 4.

Die Seite "Darstellung" passt weiter vollstaendig ins Fenster:
**74 gemeldete Rechtecke, 0 ragen heraus** (Abschnitt 8 des Laeufers).

---

## 8. Was NICHT erreicht wurde

### 8.1 Bild 15: der Fensterrumpf bleibt nach einem Zug leer

`15-fenster-unter-die-leiste-gezogen.png` ist die Endlage **ohne
Rueckweg**: das Fenster wurde nach unten unter die Leiste gezogen und
dort losgelassen. Der Rahmen steht richtig, der **Rumpf ist leer**.

```
shotcheck.py 15-fenster-unter-die-leiste-gezogen.png  ->  empty 8  cut 0  overlapping 0
(alle anderen Bilder der Runde: empty 0)
```

Ursache: nach `MOVE` wird das Schmutzrechteck des **Rumpfes** nicht
gesetzt, das Fenster malt seinen Inhalt an der neuen Stelle nicht neu.

Und die Abnahme haette es finden muessen: Abschnitt 11f faehrt den Zug
**mit Rueckweg** (`400,10>400,600` und wieder zurueck) und vergleicht
danach gegen den ungezogenen Lauf. Auf dem Rueckweg wird ohnehin alles
neu gemalt, also ist `diff 0` dort kein Beleg fuer den Fall, in dem das
Fenster liegen bleibt. Die Probe braucht einen **zweiten Lauf ohne
Rueckweg mit `empty == 0`**.

### 8.2 Das Alpha wird still angehoben — Bild 11 ist keine 40 %

`glass_mix` hebt die Deckkraft eines Punktes an, je weiter der
Untergrund von der Schluesselfarbe (`key=ffffff`) entfernt ist, und
noch einmal ueber den **Schleier** (`SCHLEIER = 40`), wenn der
Helligkeitsabstand gross ist. Beides ist gewollt — es haelt die Schrift
lesbar —, aber **es wird nirgends gemeldet und nirgends angezeigt**.
Nachgerechnet aus den Bildern dieser Runde:

| Bild | Untergrund | `alpha_soll` | `alpha_ist` |
|---|---|---|---|
| 06 (hell) | 245,240,230 | 40 | **71** |
| 06 (hell) | 200,216,240 | 40 | **100** |
| 05 (hell) | 245,240,230 | 70 | **85** |
| 11 (dunkel) | 20,24,34 | 40 | **100** |
| 11 (dunkel) | 58,34,80 | 40 | **100** |

Daraus folgt dreierlei, und alles davon ist ein Mangel:

1. **Bild 11 heisst zu Unrecht "Leiste bei 40 %".** Ueber einem dunklen
   Bild ist die Leiste dort zu 100 % deckend; ihre Streuung ist
   `var 24` gegen `var 6389` beim hellen Bild bei derselben
   Einstellung. Als Beleg fuer "durchscheinend ueber dunklem Grund"
   taugt das Bild nicht. Die Bildtabelle in `docs/shots/glas/README.md`
   sagt das jetzt so.
2. **Der Kontrast 12,33 : 1 aus Abschnitt 5 ist zu billig erkauft.**
   Er ist der Kontrast gegen eine praktisch deckende Leiste. Die
   Zusage "4,5 : 1 unter Transparenz" ist damit fuer den dunklen Fall
   nicht wirklich geprueft.
3. **Der Regler luegt den Benutzer an.** Er steht auf 40 und die Leiste
   ist deckend. Faellig ist: das wirksame Alpha melden
   (`wm: glas alpha_soll=40 alpha_ist=100`), im Einstellungsfenster
   neben dem Regler anzeigen (`40 % (wirksam 100 %)`) und im Laeufer
   eine Zusage, die fuer ein dunkles Bild entweder `farben >= 2` unter
   der Leiste oder die gemeldete Anhebung nachweist.

### 8.3 Der Kontrast wird gegen den haeufigsten Grund gerechnet, nicht gegen den schlechtesten

`glascheck.py kontrast` nimmt `most_common(1)` — die haeufigste
Mischfarbe unter der Leiste. Der schlechteste Fall ist aber der
**schlechteste Grundpunkt**, und der Bereich der Uhr (x > 1150) ist
ganz ausgeschlossen, weil der Messstreifen bei x0=300 … x1=1100 endet.

### 8.4 Zwei Rasterer, eine Zusage

Abschnitt 11 zaehlt `fn fill_round`, `fn blend` und `fn glass_mix` —
aber **nur in `kernel/ui/wm.fi`**. Im Baum gibt es daneben
`wlibc.rrect` (Ring 3) und `vektor.polygon_round`. Das ist vertretbar
(Kern und Ring 3 teilen keinen Code), aber die Zusage "genau eine
Stelle malt ein rundes Rechteck" sagt mehr, als der Befehl prueft.
Faellig ist eines von beidem: auf EINEN Rasterer zurueck, oder die
zulaessigen Orte namentlich in eine Liste, die der Laeufer gegen
`grep -rc` ueber den ganzen Baum prueft.

### 8.5 Nachtrag: was von 8.1 bis 8.4 behoben ist -- mit Zahlen

Die vier Befunde darueber stehen unveraendert; hier steht, was danach
gemessen wurde.

**Zu 8.1 (Bild 15).** Der "leere Rumpf" war drei Sachen, und keine
davon war ein nicht gesetztes Schmutzrechteck:

1. Der Griffpunkt `400,10` lag im oberen GREIFRAND. Der Lauf hat also
   nie gezogen, sondern vierzehnmal die Oberkante nach unten geschoben
   (`wm: zieh k=4 ... h=16`) -- Bild 15 zeigt ein auf seine
   Mindesthoehe zusammengeschobenes Fenster. Der Greifrand oben ist
   jetzt so dick wie der Rahmen; dass in `zug1` KEINE einzige
   `wm: zieh`-Zeile mehr steht, ist die Gegenprobe.
2. Das Programm hat seine Beschriftungen weiter zu dem Ursprung
   gemeldet, an dem es ANGELEGT wurde: `win_ort_holen` fragt den
   Server nach der wahren Stelle, wurde aber nur aus `win_x`/`win_y`
   gerufen, und die ruft im Anstrich niemand. Jetzt steht der Aufruf
   in `wlib.flush_win` -- zwei Systemaufrufe je Anstrich, nicht je
   Bildpunkt. Ohne ihn suchte `shotcheck.py` die Buchstaben 590
   Bildpunkte ueber ihrer wirklichen Stelle.
3. Bei `400,600` haengt das untere Drittel des Fensters UNTER dem
   Bildrand. Was der Schirm nicht zeigt, ist keine leere
   Beschriftung: `shotcheck.py` trennt das jetzt und zaehlt es als
   `ausserhalb` (und `verdeckt`, wenn die Leiste darueber liegt).

| Lauf | Zug | Ergebnis |
|---|---|---|
| Bild 15 (vorher) | `400,10>400,600` | `empty 8` |
| derselbe Stand, berichtigter Pruefer | `400,10>400,600` | `empty 0  ausserhalb 13` |
| `zug1` (Abschnitt 11f2) | `400,10>400,210`, OHNE Rueckweg | `empty 0  cut 0  overlapping 0  ausserhalb 0` |

Und die Schnittflaeche mit der Leiste steht als Zahl da, damit
`diff 0` nicht ueber einem leeren Schnitt entsteht -- zweimal
gerechnet, wie in dieser Abnahme ueblich:

| Rechnung | Flaeche |
|---|---|
| Wirt, aus den gemeldeten Kanten | 15 960 Bildpunkte |
| Server selbst (`wm: schlieren ... unterpx=`) | 16 044 Bildpunkte (764 x 21) |
| GEGENPROBE: ungezogener Lauf | 0 |

**Zu 8.2 (der stille Schleier).** Der Server meldet das wirksame Alpha
jetzt dort, wo er mischt -- nur fuer die LEISTE, nicht fuer
gewoehnliche Fenster:

```
wm: glas alpha_soll=40 alpha_ist=82 alpha_max=100 hoch=865797 px=935060
settings: glas radius=10 tba=40 wa=100 blur=0 ist=82
```

`alpha_ist` ist der SCHNITT der wirklich benutzten Deckkraft, nicht
das Groesste: ueber einem gemusterten Bild hebt der Schleier an den
fernsten Bildpunkten bis auf 100 an, und "100" neben dem Regler waere
so falsch wie die 40. Die Seite "Darstellung" fragt dieselbe Zahl
ueber `WM_INFO`/`WI_TB_ALPHA_IST` und schreibt sie neben den Regler:
**"Taskleiste deckend % (wirkt 82)"** (Bild 18). Der Laeufer fordert
fuer jeden dunklen Lauf, dass entweder das Bild wirklich durchscheint
(Streuung ueber 100) ODER die Anhebung gemeldet ist -- und dass Seite
und Server dieselbe Zahl nennen (82 gegen 82).

Was dabei **nicht** behoben ist und offen bleibt: ueber einem dunklen
Bild gibt es bei `SCHLEIER = 40` keine sichtbare Durchsicht bei 40 %.
`var 24` bei zwei Gruenden ist der Messwert, und zwei Farben, die sich
um eine Helligkeitsstufe unterscheiden, sieht kein Mensch. Ein Bild
"Leiste bei 40 % ueber dunklem Grund, und man sieht hindurch" kann es
also nicht geben, solange die Lesbarkeit Vorrang hat; was es gibt, ist
Bild 18, auf dem die Oberflaeche diese Wahrheit ausspricht.

**Zu 8.3 (der schlechteste Grund).** `glascheck.py kontrast` nimmt
jede Farbe mit mindestens einem Prozent Anteil und davon das Minimum,
und der Streifen reicht bis an den rechten Rand, also ueber die Uhr.
Dazu zwei Laeufe, die 11d nicht hatte: mit Milchglas 12 ueber dem
dunklen Bild (`kontrast 1233`, `var 38`, 18 Gruende) und ueber einem
ZWEITEN dunklen Muster (senkrechte Streifen zu acht, Blaugruen gegen
Dunkelrot: `kontrast 1232`, 2 Kandidaten).

**Zu 8.4 (zwei Rasterer).** Die Zusage ist ehrlich gemacht, nicht
verschaerft: `tools/themestore/raster.liste` nennt alle **neunzehn**
Funde des Baumes (`^fn .*round|blend|mix8|rrect`) mit Begruendung in
einem Satz -- warum der Bildspeicher, der Fensterserver und Ring 3
jeder eine eigene Mischung haben, und warum `foreground_ok` nur so
klingt. Der Laeufer durchsucht den GANZEN Baum und haelt das Ergebnis
gegen die Liste: ein Fund ohne Eintrag ist rot, ein Eintrag ohne Fund
auch.

---

## 9. Nachtrag nach der Jury: der Weg der Konsolenschrift

Auf **jeder** Aufnahme dieser Runde stand im Terminalfenster

```
KEIN EINZIGES GERT!
```

Die Quelle (`kernel/ui/kgui.fi`, `usb_bericht`) schreibt "GERAET" mit
einem richtigen UTF-8-Ä, also den zwei Oktetten `0xC3 0x84`.
`kernel/ui/wm.fi`, `term_putc`, hatte eine Zeile

```
if ch < 32 || ch > 126 { return }
```

und die hat beide **spurlos** verschluckt — kein Kaestchen, kein
Fragezeichen. Runde UMLAUT2 hat denselben Fehler fuer die
Bedienoberflaeche abgestellt; der Weg ins Terminalfenster war der
letzte, der ihn noch hatte.

Behoben: `term_putc` dekodiert die zweioktettige Folge `C2..DF` /
`80..BF`. Alles, was in eine Zelle (ein Oktett) passt, ist damit
Latin-1 — Ä, ö, ß, °, µ —, und `cell_paint` gibt die Zeichennummer
unveraendert an `ttf.glyph` weiter, das seit Runde GLYPHE nach
Zeichennummer sucht. Drei- und vieroktettige Folgen bekommen ein
sichtbares `?`, weil ein Platzhalter der einzige Befund ist, der sich
spaeter noch melden laesst.

Zwei Dinge, die dabei mit aufgefallen sind, und beide gehoeren
zusammen:

* **Die Leiste hat gemeldet, was sie nicht gemalt hat.** Bei
  `labels=never` zog der Startknopf seinen Text auf leer und
  `say_text` schickte trotzdem `t=Start` hinaus.
* **Kein Pruefer hat die Leiste je angesehen.**
  `tools/themestore/shotcheck.py` misst seit dem ersten Tag GENAU EIN
  Fenster, naemlich das mit dem meisten Text — nie die Leiste. Der
  titellose Fensterknopf (ein gruenes Kaestchen mit `>_` darin, das
  ohne Vorwissen wie ein Unterstrich aussieht) lag deshalb in einem
  Bereich, den nichts gemessen hat.

Behoben: die Vorgabe der Beschriftung ist `room` statt `never` — der
Fenstertitel steht im Knopf, solange er ohne Abschneiden hineinpasst,
sonst faellt der Knopf auf das Symbol zurueck. Der Startknopf meldet
den Text, den er wirklich malt. `say_text` der Leiste meldet zusaetzlich
`tw=`, die gemessene Breite, und `shotcheck.py --leiste` stellt der
Leiste dieselben drei Fragen wie jedem Fenster (leer / abgeschnitten /
ueberlappend), auf einer eigenen Ausgabezeile und mit Wirkung auf den
Rueckgabewert.

### Die Zahlen des Nachtrags

Gemessen im Abschnitt 12 des Laeufers, gegen den Lauf `al100`
(Deckung 100 %, helles Musterbild):

| Frage | Zahl |
|---|---|
| Der Kern nennt sein Zellenraster (`wm: termgitter`) | `x=26 y=62 cellw=10 cellh=19 asc=14 px=16` |
| "KEIN EINZIGES GERÄT!" nachgerastert (`umlaut.py --gitter=1,1`) | 18 Zeichen, **1 014 Tintenpunkte, 0 falsch** |
| DIESELBE Zeile im Bild VOR dem Nachtrag | **112 falsch**, und das `!` fehlt ganz (um eine Zelle verrutscht) |
| GEGENPROBE: die alte Zeile "…GERT!" gegen das neue Bild | passt nicht — der Pruefer unterscheidet die beiden |
| `shotcheck.py --leiste` auf dieselbe Aufnahme | `texts 3  measured 3  empty 0  cut 0  overlapping 0` |
| Fensterknopf der Leiste | `t=Terminal -- sh` statt leer |

Und ein Fehler, den erst dieser Nachtrag sichtbar gemacht hat, mit
seiner Gegenprobe: mit `labels=room` malte der Startknopf zuerst "Sta"
— `start_w()` gab "zwei Klickflaechen breit" zurueck, also 40
Bildpunkte fuer eine Leiste mit 20 hohen Knoepfen, und "Start" braucht
mit seinem Zeichen 61. Der Fensterknopf daneben hat den Rest
ueberdeckt. Die neue Pruefung meldet genau das:

```
LEISTE CUT  'Start' meldet x=27 tw=36 und reicht damit 19 Bildpunkte
            ueber sein Bedienelement 4,4 40x20 hinaus
```

Nach der Berichtigung (`start_w` misst Zeichen + Luft + Wort + Rand)
steht dieselbe Zusage auf `cut 0`. Die Tinte allein haette den Fehler
NICHT gefunden — der Nachbar hat zuerst gemalt, also steht dort, wo
"rt" stehen sollte, sauberer Knopfgrund und keine fremde Tinte.

Bilder: `16-umlaut-im-terminal.png` (der ganze Schreibtisch nach dem
Nachtrag), `17-vorher-nachher-umlaut-und-leiste.png` (vorher/nachher,
2-fach vergroessert, abgeleitet aus 04 und 16).

---

## 9b. Nachtrag nach der Jury: die Zeile, der Strich und die Bilder

Vier Maengel, vier Messungen (fix-r3-4).

**Die Statuszeile lag auf der Kartenkante.** `bereit` sass bei
`ty + body`, und genau dort verlief die untere Kante der linken Karte
(die zwoelf Bildpunkte ueber den Rumpf hinausging). Zwei Rechtecke,
die sich nur BERUEHREN, melden keine Ueberlappung — Abschnitt 8 und 10
konnten das also nie sehen. Jetzt ist die Zeile eine eigene Zeile im
Fluss: die Karte endet mit dem Rumpf (`kh = body`), dann acht
Bildpunkte Luft (`STAT_GAP`), dann die Zeile; gemessen auf `modern`
endet die linke Spalte bei 504, die Karte bei 504, die Zeile steht bei
512..532 in einem Fenster von 542. Die zwoelf Bildpunkte, die die
Spalte dafuer hergeben musste, kommen aus der Schemaliste (92 → 80,
drei gemalte Zeilen vorher wie nachher).

Gemessen wird es im BILD: `shotcheck.py --linien` sucht links und
rechts neben jeder Beschriftung, auf derselben Bildzeile, einen
einfarbigen Lauf von zehn Bildpunkten, der nicht der gemessene Grund
ist. Abschnitt 11h haelt das auf `linie 0` fuer beide Seiten und
beweist mit einer Gegenprobe, dass die Null etwas misst: dieselbe
Aufnahme mit einer auf dem Wirt quer durch die Zeile gemalten Linie
wird rot (`linie 1`).

**Der Strich unter dem Leistenknopf folgte einer zweiten Rechnung.**
`pill` nahm `w * 45 / 100`, mittig — eine Zahl, die mit der
Knopfbreite wuchs und mit dem Wort darueber nichts zu tun hatte;
sobald ein Symbol vor dem Titel stand, begann der Strich links vom
Symbol. Anfang und Laenge kommen jetzt aus derselben Breitenmessung
wie der Text (`button_sym` merkt `lab_tx`/`lab_tw`, `pill` liest sie),
und die Leiste meldet beides nebeneinander:
`taskbar: pille i=1 x=235 w=101 tx=235 tw=101` gegen
`taskbar: text button x=235 ... tw=101`. Abschnitt 11i haelt sie
gegeneinander. Ein Knopf ohne Wort (ein Anhefter ist nur ein Symbol)
behaelt die schmale, mittige Pille — unter einem Symbol gibt es keine
Textbreite, an die man einen Strich binden koennte.

**Bild 10 hiess, was es nicht zeigt.** Es heisst jetzt
`10-zug-hin-und-zurueck-keine-schlieren.png`, und der Abnahmelauf legt
daneben `22-zug-endlage-unter-der-leiste.png` ab: derselbe Zug OHNE
Rueckweg, das Fenster bleibt unter der Leiste stehen
(`unterpx=16044`), `empty 0 cut 0 overlapping 0 linie 0`, keine
einzige `wm: zieh`-Zeile.

**Bild 12 brauchte die README, um lesbar zu sein.** Es wird jetzt von
`tools/themestore/leistenvergleich.py` aus den vier Aufnahmen
desselben Laufs gebaut, und jede Zeile traegt im Bild ihre
Reglerstellung UND die gemessene Streuung: `var 0` / `1597` / `6389` /
`788`, dazu die Zahl der Farben (1 / 2 / 2 / 13). Die Zahl wird nicht
abgetippt, sondern mit `glascheck.leiste`/`glascheck.hell` gerechnet —
derselben Rechnung, mit der Abschnitt 11c das Milchglas nachweist —,
und der Lauf haelt die vier Zahlen im Bild gegen die vier, die er
selbst gemessen hat.

---

## 9c. Nachtrag nach der Jury: die Reiterleiste, die Spalte und das Milchglas

Vier Maengel, vier Messungen (fix-r3-1).

**Die Messlatte "genau eine Stelle" war ueber den Baum gerechnet
falsch.** Sie heisst jetzt, was sie immer gemessen hat: **ein Ort je
Ring und je Format, jeder begruendet in
`tools/themestore/raster.liste`** — im Fensterserver `wm.fill_round`
und `wm.blend`, im Bildspeicher `fb.blend`/`fb.mix8` (anderes
Bildformat), in Ring 3 `wlibc.rrect`/`wlibc.blend` (ueber die
Ringgrenze geht kein Systemaufruf je Bildpunkt, siehe
`BEFUND-VEKTOR-ENTSCHEIDUNG.md`) und `vektor.polygon_round` fuer
beliebige Formen. Abschnitt 11e sucht den GANZEN Baum ab und haelt
den Fund gegen die Liste: ein Fund ohne Eintrag ist rot, ein Eintrag
ohne Fund auch. Dieselbe Formulierung steht in `PLAN.md` und `RUN.md`
an genau den Stellen, an denen vorher "genau eine" stand.

**Neun von elf Reitern wurden gekuerzt gemalt, und die Zusage hiess
"hoechstens neun".** Eine Schranke, die den Ist-Zustand als
Obergrenze nimmt, misst nichts. Elf deutsche Reiter messen 861
Bildpunkte in einer Leiste von 728; `wlib.paint_tabs` verteilt sie
jetzt auf **zwei Zeilen**, geteilt bei der halben Gesamtbreite
(`tab_split`), und die Division auf schmalere Reiter bleibt nur als
Rueckfall fuer den Tag, an dem eine ZEILE allein nicht mehr passt.
Breite, Stelle, Zeile und Hoehe kommen aus vier Funktionen, die Maler,
Mausklick und Fokusring gemeinsam benutzen; die Hoehe entscheidet
`wlib.place`, weil erst dort die Breite feststeht.

Zwei Zeilen von 24 statt einer von 32 kosten 16 Bildpunkte. Die holt
die Seite an ihren zwei Raendern zurueck (`ctop`-Rand 4 statt 16, die
Luft unter der Leiste 4 statt 8), also ist **keine einzige Zeile der
beiden Spalten gewichen**. Gemessen:

```
wlib: tab i=0  x=4   y=4   w=106 h=24  nq=11 nv=11 t=Darstellung
wlib: tab i=5  x=398 y=4   w=101 h=24  nq=11 nv=11 t=Netzzugriff
wlib: tab i=6  x=4   y=28  w=81  h=24  nq=7  nv=7  t=Sprache
wlib: tab i=10 x=326 y=28  w=71  h=24  nq=7  nv=7  t=Brücke
```

Die Schranke im Laeufer steht jetzt auf **zwei** (`TABKURZ <= 2`, heute
0), daneben eine Zusage, dass die Leiste wirklich zwei verschiedene
Zeilen hat — sonst koennte sie auch durch noch kuerzere Namen gruen
werden.

**Drei Fliesstextzeilen der linken Spalte waren gekuerzt, und niemand
konnte es zaehlen.** `paint_label` meldete den GEMALTEN Text als
ungekuerzt (`nq = nv`), also sah `shotcheck.py` nur die neun Reiter.
Jetzt meldet es beide Laengen, und die Zahl ist in zwei zerlegt:
`reiterkurz` und `fliesskurz`. Fuer Fliesstext gilt **0 als Zusage**,
auf beiden Seiten. Moeglich wird sie durch die Spalte: sie ist von 300
auf **340** Bildpunkte gewachsen (gemessen: "Akzentfarbe RRGGBB (leer
= Schema)" misst 285, die Kontrastzeile 290, in 300 blieben nach dem
Innenabstand 268). Das kostet keinen Bildpunkt in der Hoehe. Als Netz
gibt es zusaetzlich `wlib.umbruch`: ein so bezeichnetes Etikett
bekommt eine zweite Zeile statt drei Punkten, wenn eine andere Sprache
doch einmal laenger ist.

**Milchglas war gemessen da und angeschaut nicht.** `var` fiel von
1 597 auf 788, und trotzdem sah man auf Bild 07 zwei Kacheln mit
weichen Naehten. Zwei Gruende, beide abgestellt: das Musterbild ist
ein Schachbrett von zwoelf Bildpunkten, das der Schreibtisch auf rund
achtzig dehnt — ein Weichzeichner von zwoelf verwischt davon nur die
Naehte —, und ueber einem HELLEN Bild hebt `glass_mix` die Deckkraft
auf 82 an, so dass nichts mehr zu verwischen bleibt.
`tools/themestore/build.sh` kennt darum `wallpaper=hellgrob` und
`dunkelgrob` (Schachbrett von 24, also Felder von rund 160
Bildpunkten), und Bild 07 ist mit dunklem Schema, 40 Prozent und
`blur=16` neu aufgenommen:

| Stand | `var` | Farben im Leistengrund |
|---|---|---|
| grobes Muster, dunkles Schema, ohne Milchglas | 4 102 | 2 |
| dasselbe mit `taskbar_blur=16` | 3 563 | **36** |

Zwei Farben gegen sechsunddreissig, harte Kacheln gegen einen Verlauf
— das ist der Unterschied, den ein Mensch sieht. Bild 12 hat dafuer
zwei Reihen mehr (jetzt sechs), jede mit ihrer gemessenen Zahl als
Beschriftung IM BILD, und Abschnitt 11c2 misst das Paar: der Abfall
der Streuung, mindestens zwoelf Stufen mit und genau zwei ohne
Weichzeichner, und der Kontrast der Leistenschrift auf dem
verwischten Grund.

---

## 9d. Nachtrag nach der Jury: die Vorschaukachel und der Name darauf

Zwei Maengel an einer Stelle des Bildes 09, und die Messung hat sie
getrennt (fix-r3-3).

**Der helle Keil am Rand der Kachel "Mitternacht" war ein Loch in der
FLAECHE, kein abgerutschtes Zeichen.** Die Kachel holte ihre Flaeche
aus `fuib.tafel` (dem Vektorrasterer) und ihren Rahmen aus
`wlibc.rring` (der Eckendeckung `corner_cov`) — zwei Rasterer fuer
EINE Form, und der Unterschied war sichtbar: `fuib.tafel` beschneidet
ein Rechteck, das oben aus dem Malband herausragt, auf die Bandkante
und rundet danach die Ecken des **beschnittenen** Rechtecks. Liegt die
Bandkante mitten in einer Kachel, malt die Bruecke damit eine runde
Ecke **mitten in die Flaeche**. Gemessen an Bild 09 (alter Stand):
acht Bildpunkte breit, x=331..338, Zeilen 229..233, in der Farbe des
Seitengrunds. Seit fix-r3-3 kommen Flaeche und Rahmen aus derselben
Eckendeckung (`wlibc.rrect` / `wlibc.rring`, derselbe Radius 12,
dieselben Kanten); der Auswahlring geht weiter ueber fUi und faellt
auf dieselbe Eckendeckung zurueck, wenn fUi ihn wegen des Bandes
ablehnt — bis hierher fehlte er in diesem Fall ganz.

| Kachel | `innen` vorher | `innen` jetzt |
|---|---|---|
| Kontrast Nacht | 6 | 0 |
| Mitternacht | 7 | 0 |
| die anderen acht | 0 | 0 |

`innen` ist die neue Zahl von `glascheck.py kachel`: Bildpunkte am
linken Rand (Spalten 4..7, hinter dem Auswahlring und vor dem Namen)
und in zwei waagerechten Streifen, die nicht die Flaechenfarbe der
Kachel tragen. Die Gegenprobe stanzt ein Loch von acht mal fuenf
Bildpunkten in dasselbe Bild; die Probe findet 20.

**Der Name war nie verstuemmelt — das Schriftbild ist es.**
`tools/themestore/namecheck.py` haelt jede gemalte Kachelzeile
(`wlib: text ... kind=12 ... t=`) gegen die `name=`-Zeile ihrer Vorlage
und sieht danach an **jeder gerechneten Glyphenstelle** im Bild nach,
ob dort Tinte steht; die Stellen kommen aus dem zweiten Rasterer
(`tools/ttf/raster.py stellen`, dieselbe Schrift, dieselben 15
Bildpunkte, dieselbe Unterschneidung). Ergebnis: `gemalt=10 soll=10
fehlt=0 gekuerzt=0 ohnetinte=0`. Dass ein Mensch "Mittemacht" liest,
kommt vom Paar 'rn': der Arm des 'r' endet bei 15 Bildpunkten 0,9
Bildpunkte hinter seiner Laufweite und die Unterschneidung des Paares
zieht das 'n' noch einmal 36/64 Bildpunkte heran — die beiden
Buchstaben beruehren sich und sehen aus wie ein 'm'. Das ist eine
Eigenschaft von `assets/osum-sans.ttf` und liesse sich nur dort
aendern; hier steht es als Befund mit seiner Zahl. Gegenprobe: ein mit
der Flaechenfarbe uebermaltes 'r' meldet `ohnetinte=1`.

**Und der Lauf, der diese Seite aufnimmt, klickt zweimal.** Mit einem
Klick trug der Reiter "Vorlagen" zwar den Fokusring, die Seite wurde
aber erst **nach** der Aufnahme gemalt (die zehn Kachelzeilen standen
in den letzten vierundzwanzig Zeilen des Mitschnitts) — jede
Bildpunktprobe dieses Laufs mass dann die Seite "Darstellung" und
meldete trotzdem eine Zahl. Derselbe Grund wie in 11g: der erste Klick
holt das Fenster nach vorn.

**Was hier NICHT noch einmal gemacht wurde.** Die Lesbarkeitsschranke
fuer gewoehnliche Fenster und die Zusage dazu (Kontrast jeder
Fensterbeschriftung, Reiterzeile eingeschlossen, gegen den GEMISCHTEN
Grund bei `window_alpha=55`) stehen seit fix-r3-2 als Abschnitt 11j
mit `glascheck.py fenster` im Lauf — gemessen 5,16:1 auf der
Reiterzeile. Eine zweite Fassung derselben Messung waere genau der
zweite Ort, den diese Runde nicht haben will. Ebenso ist die
Aufnahme, auf der bei Reglerstellung 40 wirklich etwas durchscheint,
Bild 21 (`var 4218`, Schrift 13,09:1) — nachgemessen und unveraendert
gueltig.

---

## 9e. Nachtrag nach der Jury: der Knopf, das durchsichtige Fenster und der stille Filter

Vier Befunde, vier Zahlen (fix-r3-2).

**Der Knopf "Uebernehmen" sah aus wie eine Beschriftung.** Er IST seit
jeher ein `wlib.button` — die Rolle war nie falsch. Gemalt hat ihn
aber fUi (`fuib.draw(S_BUTTON)`), und das malt flach: Flaeche
`#ffffff` auf einer Karte `#f8fafc`, neun Helligkeitsstufen
Unterschied, kein Rand. Der Rueckweg in `wlib` rahmt selbst; der
fUi-Zweig tat es nicht, und damit hing das Aussehen eines
Bedienelements davon ab, welcher von zwei Malern gerade lief.
`paint_button` merkt sich jetzt, ob der malende Zweig gerahmt hat
(`gerahmt`), und legt sonst mit `fuib.ring` eine Kante in `T_LINE` mit
demselben Radius nach — eine Stelle, ein Ring, kein zweiter Maler.
Gemessen wird es im Bild und nicht im Quelltext: `wlib.say_knopf`
meldet Rechteck, Radius und Ecke auf dem Schirm, `shotcheck.py
--knoepfe` sieht an den vier Kanten nach (Linie 227,233,240 zwischen
zweimal 246,247,247) und zaehlt `knopf`/`ohnekante`. Abschnitt 11j2:
zwei Seiten, `ohnekante 0`, und die Gegenprobe (derselbe Knopf auf dem
Wirt flach uebermalt) wird gefunden.

**Unter einem durchsichtigen Fenster lief fremder Text durch die
Reiterzeile.** Die Lesbarkeitsschranke `glass_mix` gilt seit der Runde
fuer Leiste UND Fenster, aber mit derselben Zahl: 40 Helligkeitsstufen
Abstand von der Fensterfarbe. Das ist fuer eine Leiste mit drei kurzen
Beschriftungen ein Hauch und in einer Zeile Schrift ein zweiter Text —
auf Bild 13 (`window_alpha=55`) stand die USB-Zeile des Terminals
lesbar zwischen "Sprache" und "Vorlagen". `SCHLEIER_WIN = 20` ist die
Zahl fuer gewoehnliche Fenster; sie steht als ARGUMENT von `glass_mix`
und nicht als stille Statische, damit nicht der letzte Aufrufer ueber
das Bild des naechsten entscheidet. Selbsttest 8 rechnet den Fall von
Hand nach (`0xED` gegen `0xD8` der Leiste, `wm: glastest 8 / 8`).
Gemessen (Abschnitt 11j, `glascheck.py fenster`): 31 Beschriftungen,
schlechtestes Paar **5,16:1** (das ist die ausgewaehlte Listenzeile auf
der Akzentfarbe, also kein Fall von Transparenz); die Reiter selbst
steigen von 5,26:1 auf **6,34:1**. Gegenprobe gegen `window_alpha=100`:
39 120 abweichende Bildpunkte — es wird wirklich gemischt, "lesbar"
heisst hier nicht "deckend".

**Abschnitt 8 hatte einen stillen Filter.** Das Muster
`^w[a-z][a-z]$` liess genau die Rechtecke aus, die einen SACHnamen
tragen: die zwei Karten (`kartel`, `karter`) und die fuenf Elemente,
auf die ein Laeufer klickt (`edge`, `size`, `autohide`, `ontop`,
`apply`). Gemessen wird jetzt jedes gemeldete Rechteck ausser `win`,
gegen Innenhoehe UND Innenbreite, und die ZAHL der gemessenen
Rechtecke (**100**, gefordert >= 88) steht als eigene Zusage daneben:
faellt sie, hat wieder jemand gefiltert.

**Und die Platte der Abnahme war zu klein geworden.** Zehn Programme
(7,6 MiB) plus drei Schriften plus ein Hintergrundbild passen nicht in
16 384 Bloecke; `mkfs: the disk is full` traf ausgerechnet die Laeufe
mit `wallpaper=`, also die, die Durchsicht ueberhaupt belegen koennen.
32 768 Bloecke, die Zahl, mit der `tools/look/shot.sh` und
`tools/wmplug/*.sh` seit Runden bauen.

Bild 11 heisst jetzt `11-dunkles-bild-leiste-soll40-wirkt82-
kontrast.png` — der Name sagt, dass dort 82 wirkt und nicht 40 —, und
der Lauf `dunkelmod` ist als **Bild 21** dazugekommen: dunkles Schema
auf dunklem Bild, `var 4218`, Schrift 13,09:1. Das ist die Aufnahme,
auf der Reglerstellung 40 und Durchsicht zugleich gelten.

---

## 10. Wo was steht

| Datei | Was dieser Runde gehoert |
|---|---|
| `kernel/user/template.fi` | die vier Schluessel, jeder nur Ziffern, jeder geklemmt |
| `kernel/user/wlibc.fi` | `radius()`, `tb_alpha()`, `win_alpha()`, `tb_blur()` und die vier Setzer; `ALPHA_MIN`, `BLUR_MAX`; `rrect` (Ring 3) |
| `kernel/ui/wm.fi` | `fill_round`, `blend`, `glass_mix`, der Weichzeichner, die Schlierenregel, `term_putc` (Nachtrag) |
| `kernel/user/wlib.fi` | `draw_board` und der Radius je Widgetart |
| `kernel/user/taskbar.fi` | die Leiste mischt; Beschriftung, `tw=` (Nachtrag) |
| `kernel/user/settings.fi` | die vier Regler auf "Darstellung" |
| `tools/themestore/run.sh` | Abschnitt 11, 55 neue Zusagen |
| `tools/themestore/glascheck.py` | die zweite Rechnung auf dem Wirt; `fenster` misst jede Fensterbeschriftung gegen den gemischten Grund |
| `tools/themestore/shotcheck.py` | `--leiste` (Nachtrag), `--linien` (Bildpunktprobe auf Rahmenlinien), `--knoepfe` (jeder Knopf zeigt einen Umriss) |
| `tools/themestore/leistenvergleich.py` | Bild 12, beschriftet und mit gemessener `var` |
| `tools/themestore/namecheck.py` | der Kachelname gegen `name=` der Vorlage, Glyphe fuer Glyphe gegen `tools/ttf/raster.py` |
| `docs/shots/glas/` | die 15 Aufnahmen und ihre Tabelle |
