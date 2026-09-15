# RUNDE H264T (P-023) -- der Dekodierer wird schnell, ohne ein Bit zu verlieren

Zweig `h264t`, Basis `main` d5583ee.

Die Vorrunde (P-022, `docs/RUNDE-CODEC.md`) hat einen h.264-Dekodierer
gebaut, der **bitgenau** ist: 51 Bilder aus 10 Stroemen, 51 SHA-256
gegen ffmpeg, 51 Treffer. Er ist aber zu langsam fuer alles ueber CIF.
Diese Runde macht ihn schnell -- und die Bitgenauigkeit ist dabei keine
Nebenbedingung, sondern die Messlatte, an der jede Aenderung scheitert
oder nicht.

**Das Ergebnis in einer Zeile:** 640x480 laeuft mit **25,21 Bilder/s**
(Median aus neun Laeufen), die Messlatte waren 25. 720p laeuft mit
**8,38 Bilder/s** und ist damit dekodierbar, aber nicht fluessig. Alle
61 Bilder aus 12 Stroemen sind weiterhin oktettweise dieselben wie bei
ffmpeg. **SIMD wurde nicht gebraucht.**

---

## 1. ZUERST MESSEN. UND DIE MESSUNG WIDERLEGT DEN AUFTRAG.

Der Auftrag nennt drei Ursachen **in dieser Reihenfolge**:

> 1. `tab_find` geht bitweise linear durch bis zu 68 Eintraege.
> 2. Die Bewegungskompensation rechnet je 4x4-Block einzeln.
> 3. Kein SIMD.

Er sagt aber auch dazu, dass das **Vermutungen aus dem Bericht sind und
nicht gemessen**, und verlangt die Profiltabelle, **bevor** etwas
geaendert wird. Das war die richtige Auflage, denn die Rangfolge stimmt
nicht -- und Punkt 1 hat sich am Ende sogar als **wirkungslos**
erwiesen, obwohl er einzeln messbar schneller war (Abschnitt 4.2).

### 1.1 Wie gemessen wurde

Fuenf Zaehler in `kernel/user/h264.fi`, gefuellt mit `rdtsc`:

| Zaehler | was er umschliesst |
|---|---|
| `PF_CAVLC` | `residual_block` -- die Entropiedekodierung, und `tab_find` sitzt darin |
| `PF_MC` | `mc_mb` -- die Bewegungskompensation eines Makroblocks |
| `PF_RECON` | `recon_mb` -- Transformation, Skalierung, Intra-Vorhersage |
| `PF_DEBLOCK` | `deblock` -- der Entblockungsfilter, einmal je Bild |
| `PF_REST` | `slice_verarbeiten` -- **die Gesamtzeit**, gegen die die anderen vier geprueft werden |

**Warum Takte und nicht Nanosekunden:** ein Abschnitt liegt unter der
Aufloesung, die `clock_gettime` ueber einen Syscall hergibt, und der
Syscall kostet mehr als das, was er messen soll. `rdtsc` ist ein Befehl
ohne Ringwechsel. Dasselbe Argument steht in `kernel/kaesni.fi`.

**Was die Messung selbst kostet, nachgerechnet statt behauptet:** zwei
`rdtsc` je Abschnitt, bei CIF 16 764 Messpunkte auf 260 Mio. Takte --
**rund 0,5 %**. Bei 720p 0,45 %.

`PF_REST` ist absichtlich die **Gesamtzeit** und nicht "der Rest": so
muss die Summe der vier Abschnitte kleiner sein als sie, und die
Differenz ist das, was zwischen den Abschnitten liegt (Syntax,
Nachbarschaftsrechnerei, Slice-Kopf). Eine Tabelle, deren Teile sich
nicht zum Ganzen fuegen, waere kein Messgeraet.

### 1.2 DIE PROFILTABELLE VORHER

QEMU mit KVM, `-cpu host`, `-m 512`, AMD EPYC 7571. Stufe-0-Uebersetzer.

**CIF 352x288, 10 Bilder -- 214 ms, 46,72 Bilder/s**

| Abschnitt | Takte | Anteil | Aufrufe |
|---|---:|---:|---:|
| **Bewegungskompensation** | 118 071 580 | **45,4 %** | 3 303 |
| **Entblockung** | 64 280 546 | **24,7 %** | 10 |
| Transformation + Intra | 38 956 742 | 15,0 % | 1 579 |
| **Entropie (`tab_find`)** | 28 419 666 | **10,9 %** | 11 862 |
| Rest (Syntax, Nachbarn) | 10 626 440 | 4,1 % | |
| **gesamt** | 260 354 974 | 100 % | 10 |

**640x480, 6 Bilder -- 288 ms, 20,83 Bilder/s**

| Abschnitt | Takte | Anteil | Aufrufe |
|---|---:|---:|---:|
| **Bewegungskompensation** | 155 614 118 | **42,1 %** | 5 530 |
| **Entblockung** | 101 246 750 | **27,4 %** | 6 |
| Transformation + Intra | 65 058 928 | 17,6 % | 2 776 |
| **Entropie (`tab_find`)** | 33 970 574 | **9,2 %** | 15 431 |
| Rest | 14 001 636 | 3,8 % | |
| **gesamt** | 369 892 006 | 100 % | 6 |

**1280x720, 4 Bilder -- 586 ms, 6,82 Bilder/s**

| Abschnitt | Takte | Anteil | Aufrufe |
|---|---:|---:|---:|
| **Bewegungskompensation** | 316 380 724 | **39,1 %** | 10 329 |
| **Entblockung** | 231 695 420 | **28,7 %** | 4 |
| Transformation + Intra | 156 164 162 | 19,3 % | 5 639 |
| **Entropie (`tab_find`)** | 74 248 790 | **9,2 %** | 29 831 |
| Rest | 29 735 046 | 3,7 % | |
| **gesamt** | 808 224 142 | 100 % | 4 |

### 1.3 WAS DARAUS FOLGT, und es ist nicht das, was im Auftrag steht

> **`tab_find` ist NICHT die Hauptursache. Es ist der vierte Posten mit
> 9 bis 11 Prozent.**

Waere die Baumtafel **unendlich schnell** -- nicht schneller, sondern
kostenlos --, brächte sie bei 640x480 aus 20,83 Bilder/s ganze 22,9.
Die Messlatte sind 25. Der Auftrag haette mit seiner Reihenfolge in die
falsche Richtung gearbeitet, und zwar zuerst.

Die Zeit liegt bei **Bewegungskompensation (39-45 %)** und
**Entblockung (25-29 %)**. Zusammen sind das **zwei Drittel**.

Warum die Bewegungskompensation so teuer ist, sieht man an
`qpel_one`/`rpix`: **jeder einzelne Bildpunkt** geht durch `rpix`, und
`rpix` klemmt jedes Mal beide Koordinaten gegen den Bildrand (vier
Vergleiche), obwohl der weit ueberwiegende Teil aller Bloecke gar nicht
am Rand liegt. Bei `fx=2, fy=2` (dem teuersten Fall) ruft `jhalf` sechs
`hraw` auf, und jedes `hraw` ruft sechs `rpix` -- **36 geklemmte
Zugriffe fuer EINEN Bildpunkt**, und die Zwischenwerte werden fuer den
Nachbarpunkt vollstaendig neu gerechnet.

Die Vermutung des Auftrags ("rechnet je 4x4-Block einzeln") trifft
damit den richtigen Bereich, aber aus dem falschen Grund: teuer ist
nicht die Blockgroesse, teuer ist die **fehlende Zwischenspeicherung
der Filterwerte und die Klemmung je Bildpunkt**.

---

## 2. DIE AUFLOESUNGSGRENZE -- die alte Begruendung war schlicht veraltet

`MAXW`/`MAXH` standen bei 352x288. Die Begruendung im Quelltext lautete:
*"Ein Prozess dieses Systems hat 6 MiB Abbild."*

**Das stimmt seit der Runde CERTUS-AUF-OSUM nicht mehr.** Nachgesehen
in `kernel/proc.fi`:

    const IMAGE_BASE: u64 = 0x40100000
    const IMAGE_END:  u64 = 0x40C00000   // war 0x40400000 (K16)

Das sind **11 MiB**, nicht 6 -- das Fenster ist gewachsen, weil Certus
(der Browser) 6,5 MiB gross ist. Damit war die Grenze nie eine Frage
des Speichers, sondern nur eine, die niemand nachgerechnet hatte.

**Nachgerechnet, nicht geschaetzt** (`readelf -lW` auf dem gebundenen
`/bin/h264t`):

| | Ende des Datensegments | ueber IMAGE_BASE |
|---|---|---|
| bei 352x288 | 0x4036ba38 | 2,42 MiB |
| bei 1280x720 | 0x40a6af00 | **9,42 MiB** |

Es bleiben **1,58 MiB Luft**. Die Rechnung im Einzelnen: vier
Bildspeicher zu 1280x720 sind 5.529.600 Oktette (5,27 MiB), die Felder
je Makroblock (3600 Stueck: Typ, Modi, Vektoren, nz) 2.714.400 Oktette
(2,59 MiB).

**Bildpuffer liegen weiterhin NICHT in kdata**, sondern als statische
Felder im Programm -- so wie es der Auftrag verlangt und wie `opk.fi`
es mit seinen 8 MiB vormacht.

### 2.1 Eine Falle, die dabei aufging

`mbs_clear` lief ueber `MAXMB`. Solange MAXMB 396 war, war das
dasselbe wie "das ganze Bild". Mit MAXMB = 3600 waere es das nicht mehr
gewesen: ein QCIF-Bild hat 99 Makrobloecke, und jedes Bild haette den
**sechsunddreissigfachen** Loeschlauf bezahlt. Die Grenze heisst jetzt
`s_mbw * s_mbh`.

Das ist die Art Fehler, die eine Aufloesungsgrenze stillschweigend in
eine Bremse fuer alle kleineren Masse verwandelt.

---

## 3. WAS GEBAUT WURDE

Fuenf Schritte, jeder einzeln gemessen und einzeln committet.

### 3.1 Bewegungskompensation: erst holen, dann filtern (00d1add)

Zwei Aenderungen an derselben Stelle:

**`mc_luma_schnell`** holt den Quellbereich `(bw+5) x (bh+5)` **einmal**
nach `mcbuf`, und **nur dabei** wird geklemmt. Liegt der Block ganz im
Bild -- der Regelfall --, ist es ein reiner Zeilenkopier ohne jeden
Vergleich. Die senkrechten Rohwerte fuer `j` stehen danach zeilenweise
in `mctmp`, statt fuer jeden Zielpunkt neu gerechnet zu werden.

**`mc_mb_inner`** fasst benachbarte 4x4-Bloecke mit **gleicher Referenz
und gleichem Vektor** zu einem Rechteck zusammen (erst in der Breite,
dann in der Hoehe). Ein `P_L0_16x16` ist damit **ein** Aufruf statt
sechzehn.

> **Warum das bitgenau dasselbe ist:** der Sechs-Anzapf-Filter ist ein
> reines Fenster um den Zielpunkt. Sein Wert haengt am Vektor und am
> Referenzbild -- **nicht** an der Groesse des Blocks, in dem er
> gerechnet wird. Zwei benachbarte 4x4-Bloecke mit demselben Vektor
> liefern dieselben Punkte wie ein 8x4-Block mit diesem Vektor. (Bei
> B-Slices mit gewichteter Vorhersage waere das anders -- die gibt es
> in Baseline nicht.)

### 3.2 Entblockung je 4x4-Block statt je Bildpunktzeile (504ff57)

`bs_of`, die Klemmung auf 0..51 und die drei Tafelzugriffe (ALPHA,
BETA, TC0) haengen am **Block**, liefen aber **je Zeile**: sechzehnmal
je Luma-Kante statt viermal, achtmal je Chroma-Kante statt viermal.
Alle vier Stellen (senkrecht/waagerecht, Luma/Chroma) rechnen das jetzt
einmal je Block. `filter_line` selbst ist unveraendert -- nur die
Entscheidung darueber faellt seltener.

### 3.3 Chroma-MC und der Ganzpunktfall (5dd5f7e)

`mc_chroma` bildete die vier Gewichte `(8-xf)*(8-yf)` usw. **je
Bildpunkt** neu, obwohl sie am Vektor haengen. Und es ging je Punkt
viermal durch `rpix` mit Klemmung; liegt der Block samt rechtem und
unterem Nachbarpunkt im Bild, lesen zwei Zeilenzeiger die vier Werte
ohne Vergleich.

`mc_luma_schnell` faengt ausserdem `fx==0 && fy==0` vorweg ab: ganzer
Bildpunkt, kein Filter, kein Randpuffer -- ein Zeilenkopier. Das ist
der haeufigste Fall ueberhaupt (jeder P_Skip mit ganzzahligem Vektor).

### 3.4 Innere Kanten ueberspringen, wo bs sicher 0 ist (91b2de8)

Ein Inter-Makroblock ohne Koeffizienten, dessen sechzehn 4x4-Bloecke
dieselbe Referenz und denselben Vektor tragen, hat auf **allen inneren
Kanten** bs=0. Das ist dieselbe Bedingung wie in `bs_of`, nur einmal je
Makroblock geprueft statt vierundzwanzigmal. Die aeusseren Kanten
bleiben unberuehrt.

*Der Gewinn dieses Schrittes allein ist klein* -- in den Pruefstroemen
(`testsrc2`, viel Bewegung) gibt es wenige glatte Makrobloecke. In
ruhigem Material waere er groesser; das ist aber nicht gemessen und
wird deshalb auch nicht behauptet.

### 3.5 Skalierung und Inter-Wiederaufbau (f873c91)

`scale_into` rief je Koeffizient `norm_adjust`, und das rechnete jedes
Mal Zeile, Spalte und zwei Paritaeten aus, um einen von **drei** Werten
aus VMAT zu waehlen -- sechzehnmal je Block fuer drei Ergebnisse. Die
drei Gewichte stehen jetzt vor der Schleife, die Auswahl ist eine feste
Tafel. Auch die Fallunterscheidung `qp >= 24` ist aus der Schleife
heraus.

> **Eine Anmerkung, die hierher gehoert:** diese Tafel wurde beim ersten
> Versuch **falsch abgetippt** (drei von sechzehn Stellen). Aufgefallen
> ist es, weil sie **vor dem Bauen gegen `norm_adjust` nachgerechnet**
> wurde -- nicht im Bild, wo man es nicht gesehen haette. Genau darum
> steht in `mktab.py`, dass Tafeln erzeugt und nicht abgetippt werden.

Der Inter-Zweig von `recon_mb` sah jeden 4x4-Block sechzehn Werte lang
an, um zu wissen, ob er leer ist -- auch wenn der erste Wert schon von
null verschieden war, und auch in 8x8-Vierteln, die laut `cbp` gar
keine Koeffizienten tragen. Jetzt fragt er zuerst `cbp` und hoert beim
ersten Treffer auf.

### 3.6 alpha/beta einmal je Kante (05ac5ce)

`qav`, die Klemmung und die Tafelzugriffe ALPHA/BETA haengen an den
**beiden Makrobloecken** einer Kante, nicht am einzelnen Block -- bei
den inneren Kanten ist `mP == mQ`. Sie stehen jetzt vor der
Blockschleife; nur `tc0` haengt noch an bs. Zugleich faellt die
Blockschleife ganz weg, wenn alpha oder beta null sind.

---

## 4. WAS NICHT FUNKTIONIERT HAT

Zwei Versuche sind gemessen, fuer schlecht befunden und **verworfen**
worden. Sie stehen hier, weil ein Bericht ohne sie den Eindruck
erweckte, jeder Einfall haette getragen.

### 4.1 Die Fallunterscheidung aus der Bildpunktschleife ziehen

`mc_luma_schnell` prueft je Bildpunkt `fx`/`fy` in einer Kette von bis
zu fuenfzehn Vergleichen, obwohl beide fuer den ganzen Block fest sind.
Der naheliegende Griff -- `fall = fy*4+fx` einmal je Block, danach
springen -- hat es **langsamer** gemacht:

| | 640x480, Median aus 12 Laeufen |
|---|---|
| Kette je Punkt (so wie es ist) | **25,00 B/s** |
| gerechneter Index einmal je Block | 24,29 B/s |

Vermutung: firnc uebersetzt die gepaarten Vergleiche besser als den
gerechneten Index, und der haeufigste Fall steht in der Kette vorne.
Verworfen.

### 4.2 DIE BAUMTAFEL FUER CAVLC -- Punkt 1 des Auftrags

Gebaut wurde sie vollstaendig: 8-Bit-Vorschautafeln, in `mktab.py`
**erzeugt** (nicht abgetippt), mit einer Zusicherung gegen
Mehrdeutigkeit, `tab_vor` loest ein Achtbitmuster in **einem** Zugriff
auf, `tab_find` bleibt als Rueckfall fuer Codes ueber acht Bit.

Sie war **bitgenau** (10/10, 6/6, 4/4) und hat die gemessenen
CAVLC-Takte deutlich gesenkt: bei CIF von 32,7 auf 22,8 Millionen.

**Und sie hat trotzdem nichts gebracht.** Verschraenktes A/B, je zehn
Laeufe abwechselnd auf denselben Kernen:

| | ohne Vorschau | mit Vorschau |
|---|---|---|
| 640x480 | 25,00 B/s | 25,10 B/s |
| 1280x720 | **8,40 B/s** | **8,16 B/s** |

Bei 640x480 im Rauschen, bei 720p **schlechter**. Die naheliegende
Erklaerung: die Tafeln sind rund 60 KiB, und was die Entropiedekodierung
an Takten spart, zahlt der Rest an Cache-Fehlzugriffen drauf -- bei
720p, wo die Bildpuffer ohnehin gross sind, am deutlichsten.

**Verworfen.** Das ist die zweite, unabhaengige Bestaetigung der
Profilmessung: `tab_find` war nie das Problem.

---

## 5. DIE PROFILTABELLE NACHHER

Derselbe Aufbau wie in 1.2.

**CIF 352x288, 10 Bilder**

| Abschnitt | Takte | Anteil | vorher |
|---|---:|---:|---:|
| Bewegungskompensation | 61 404 552 | 38,8 % | 45,4 % |
| Entblockung | 35 364 164 | 22,3 % | 24,7 % |
| Transformation + Intra | 30 125 194 | 19,0 % | 15,0 % |
| Entropie | 22 575 542 | 14,2 % | 10,9 % |
| Rest | 8 978 816 | 5,7 % | 4,1 % |
| **gesamt** | **158 448 268** | 100 % | 260 354 974 |

**640x480, 6 Bilder**

| Abschnitt | Takte | Anteil | vorher |
|---|---:|---:|---:|
| Bewegungskompensation | 95 644 824 | 35,6 % | 42,1 % |
| Entblockung | 65 981 190 | 24,6 % | 27,4 % |
| Transformation + Intra | 59 343 944 | 22,1 % | 17,6 % |
| Entropie | 33 394 570 | 12,4 % | 9,2 % |
| Rest | 14 093 618 | 5,2 % | 3,8 % |
| **gesamt** | **268 458 146** | 100 % | 369 892 006 |

**1280x720, 4 Bilder**

| Abschnitt | Takte | Anteil | vorher |
|---|---:|---:|---:|
| Bewegungskompensation | 189 665 696 | 33,2 % | 39,1 % |
| Entblockung | 152 936 234 | 26,8 % | 28,7 % |
| Transformation + Intra | 132 899 184 | 23,3 % | 19,3 % |
| Entropie | 68 881 296 | 12,1 % | 9,2 % |
| Rest | 26 414 454 | 4,6 % | 3,7 % |
| **gesamt** | **570 796 864** | 100 % | 808 224 142 |

Die Gesamtzeit je Bild ist bei CIF auf **61 %**, bei 640x480 auf
**73 %** und bei 720p auf **71 %** gefallen. Die Rangfolge ist
dieselbe geblieben -- die Bewegungskompensation ist auch nach der
Arbeit der groesste Posten, nur nicht mehr so deutlich.

---

## 6. DIE TEMPOZAHLEN, EHRLICH

### 6.1 Wie gemessen wird, und warum das hier dazugehoert

Der Wirt traegt neben dieser Messung noch anderes (Lastmittel zwischen
5 und 12). **Einzelmessungen schwanken dadurch um mehr als zehn
Prozent** -- genug, um jede Aussage dieser Runde wahlweise zu bestaetigen
oder zu widerlegen, je nachdem, welchen Lauf man nimmt.

Deshalb gilt hier durchgaengig: **`taskset -c 2,3`, neun Laeufe je
Zahl, angegeben ist der MEDIAN.** Nicht der beste Lauf -- der waere
geschmeichelt.

Wie ernst das ist, zeigt die Geschichte dieser Zahl: 640x480 hat im
Lauf der Runde 25,31 (Bestwert aus 5), 23,62 (Median aus 12, Wirt unter
Last) und 25,21 (Median aus 9, Wirt ruhig) gemessen -- bei **demselben
Quelltext**. Die erste Zahl waere ein geschoenter Erfolg gewesen.

### 6.2 Die Zahlen

Alle vier Masse, `main` d5583ee gegen `h264t`, gleiche Bedingungen:

| | main d5583ee | h264t | |
|---|---:|---:|---:|
| **QCIF 176x144** | 145,45 B/s | **166,66 B/s** | 1,15x |
| **CIF 352x288** | 54,94 B/s | **67,11 B/s** | 1,22x |
| **640x480** | *ging nicht* | **25,21 B/s** | -- |
| **1280x720** | *ging nicht* | **8,38 B/s** | -- |

*"Ging nicht"* heisst woertlich: `MAXW`/`MAXH` standen bei 352x288, ein
groesserer Strom wurde mit `E_GROSS` abgewiesen. Ein Vergleichsfaktor
liesse sich nur gegen eine Hochrechnung bilden, und Hochrechnungen
stehen in diesem Bericht nicht.

### 6.3 Die Messlatte

> **640x480 fluessig, also mindestens 25 Bilder/s.**

**Erreicht: 25,21 Bilder/s** (Median aus neun Laeufen). Die Streuung
dieser Messreihe war 23,43 bis 25,64 -- die Zahl liegt also **knapp**
ueber der Latte, nicht komfortabel. Ein staerker belasteter Wirt
drueckt sie unter 25; auf einer ungeteilten Maschine liegt sie
darueber. Das ist die ehrliche Auskunft.

**720p ist nicht erreicht: 8,38 Bilder/s.** Das ist dekodierbar und
fuer Einzelbilder brauchbar, aber kein fluessiges Video. Fuer 25 B/s
bei 720p fehlt der Faktor 3, und den gibt es mit skalarem Code nicht
mehr -- dafuer waere SIMD noetig (Abschnitt 8).

---

## 7. DIE BITGENAUIGKEIT -- die Belege

Das ist die Zusage, an der alles andere haengt.

### 7.1 Die Abnahme als Ganzes

    bash tools/codec/run.sh
    == CODEC: 95 bestanden, 0 gescheitert ==

Vorher waren es 71/0. Die 24 neuen Zusagen sind die zwei neuen Stroeme,
die Kreisprobe und die Grenzprobe.

### 7.2 Gegen ffmpeg, Bild fuer Bild

**61 bitgleiche Bilder aus 12 Stroemen** (vorher 51 aus 10). Der Wirt
kodiert mit `x264 -profile:v baseline`, dekodiert **dieselbe Datei**
mit ffmpeg nach rohem YUV 4:2:0 und rechnet je Bild eine SHA-256; Osum
rechnet dieselbe Summe im laufenden Kern mit `sha.fi`. Neu dabei:

| Strom | Masse | Bilder |
|---|---|---|
| `vga` | 640x480 | 6 |
| `hd720` | 1280x720 | 4 |

Beide werden **genauso** oktettweise geprueft wie die kleinen. Eine
schnelle Umsetzung, die anders rechnet, waere wertlos.

### 7.3 Die Kreisprobe: schneller gegen langsamen Weg

`/bin/h264t --langsam` faehrt die alte, Punkt fuer Punkt rechnende
Bewegungskompensation; `mc_langsam` schaltet in `mc_luma` und
`mc_chroma` auf den alten Zweig zurueck. Die Abnahme (Abschnitt 7f)
vergleicht die SHA-256 beider Laeufe:

    OK  [i_klein]  schneller Weg == langsamer Weg, 3 Bilder oktettweise gleich
    OK  [i_sd]     ... 3 Bilder
    OK  [i_glatt]  ... 2   OK [i_scharf] ... 2   OK [p_klein] ... 6
    OK  [p_sd]     ... 8   OK [p_bewegt] ... 8   OK [p_skip]  ... 6
    OK  [cif]      ... 10  OK [vga]      ... 6   OK [hd720]   ... 4
    OK  [slices]   ... 3 Bilder oktettweise gleich

**Alle zwoelf Stroeme.** Das ist mehr als die ffmpeg-Probe hergibt: die
prueft den schnellen Weg gegen ffmpeg, diese prueft die **beiden Wege
gegeneinander** -- und schlaegt auch dann an, wenn beide zusammen
abweichen wuerden.

Der alte Weg bleibt dafuer im Baum. Das kostet Zeilen und ist es wert.

### 7.4 Was weiterhin abgewiesen wird

* **35 kaputte Stroeme** (20 abgeschnitten, 12 verfaelscht, 3 Unsinn) --
  keiner haengt, keiner stuerzt ab, alle weisen ab.
* **High Profile** und **CABAC** -- abgewiesen mit `err=2`.
* **NEU: ueber der Grenze.** Ein 1920x1080-Strom wird mit `err=4`
  abgewiesen und liefert **kein** Bild (Abschnitt 7g). Ohne diese Probe
  waere die neue Grenze eine Behauptung -- und ein Strom darueber
  schriebe ueber das Ende der Bildspeicher hinaus.

### 7.5 Die uebrigen Auflagen

| | |
|---|---|
| `python3 tools/kernel/memmap.py` | **0 Kollisionen** (127 Bereiche) |
| `tools/check-ui.sh` | **PASSED** |
| `tools/build-kernel.sh` | baut |
| `tools/usbimg/build.sh` | erzeugt das Abbild (130 MiB, GPT) |
| kein Fliesskomma in `h264.fi`/`h264tab.fi` | geprueft, keine f32/f64 |
| beide Uebersetzerstufen | firnc0 **und** firnc1 bauen |

**Zum Speicher:** diese Runde hat **weder kdata noch Modusindizes
gebraucht**. Der zugeteilte Bereich 0x12C000..0x12E000 und die Indizes
1060-1069 sind **unangetastet geblieben** -- es gab nichts, was dort
haette stehen muessen. `CODEC_OFF` bleibt unveraendert bei
0x118000..0x120000. Die Bildpuffer liegen, wie verlangt, als statische
Felder im Programm.

---

## 8. WAS OFFEN BLIEB

**1. 720p ist nicht fluessig (8,38 statt 25 B/s).** Dafuer fehlt der
Faktor 3. Mit skalarem Code ist er nicht zu holen -- die drei grossen
Posten sind nach dieser Runde ausgeraeumt, was bleibt, ist die eigentliche
Rechenarbeit.

**2. SIMD ist nicht gebaut, und das war eine Entscheidung.** Der Auftrag
nennt es als dritten Schritt, *"falls es dann noch noetig ist"*. Fuer
640x480 war es das nicht. Fuer 720p waere es der naechste Griff, und die
Stellen stehen fest:

* der Sechs-Anzapf-Filter auf acht Punkten gleichzeitig (PSHUFB/PMADDWD),
* `filter_line` ueber vier Zeilen gleichzeitig,
* die 4x4-Transformation als vier Zeilen in einem Register.

Die Auflagen des Auftrags dafuer sind geprueft und gelten unveraendert:
`cpuid` muss die Befehle bestaetigen (sonst `#UD`), und die
XMM-Sicherung im Kontextwechsel ist da -- `docs/RUNDE-AESNI.md` 1.3
belegt sie (`fpu: mode=3`, eager FXSAVE/XSAVE je Aufgabe). Ein
Rueckfallweg muesste bleiben; die Naht dafuer **existiert schon**, denn
`mc_langsam` ist genau so ein Schalter, und die Kreisprobe in 7f ist
genau die Probe, die ein SIMD-Weg bestehen muesste.

**3. Die 25 B/s bei 640x480 sind knapp.** 25,21 im Median, 23,43 im
schlechtesten von neun Laeufen. Auf einem ungeteilten Rechner ist das
bequem; auf diesem Wirt ist es die Grenze.

**4. Der Randfall der Bewegungskompensation ist unbeschleunigt.**
Bloecke, deren Vektor aus dem Bild zeigt, gehen weiter Punkt fuer Punkt
durch `rpix`. Das ist Absicht -- sie sind selten, und der schnelle Weg
haette dort die meisten Sonderfaelle. Bei Material mit viel Bewegung am
Bildrand faellt es staerker ins Gewicht als in den Pruefstroemen.

**5. Die Profiluhr bleibt eingebaut** (rund 0,5 % Kosten). Sie
abzuschalten waere ein Compilerschalter; sie zu behalten heisst, dass
die naechste Runde nicht wieder bei null anfaengt. Das schien der
bessere Handel.
