# STATUS-DEMUX — Zwischenstand der Runde DEMUX

Zweig `demux`, aus `mergeline`, mit `media1` darin. **Nicht nach `main`.**

Auftrag: MP4 und MKV sollen sich ÖFFNEN lassen, obwohl H.264 nicht
dekodierbar ist — mit klarer Meldung statt Absturz — und der Ton soll
gespielt werden, wenn MP3 oder AAC darin steckt.

---

## 1. Was in dieser Runde entstanden ist

| Datei | Zeilen | Was sie ist |
|---|---:|---|
| `kernel/user/media.fi` | 621 | Quelle mit 64-KiB-Fenster, Zahlenformate, Spurentafel, Beispielliste, die EINE Stelle mit `can_decode` |
| `kernel/user/mp4.fi` | 786 | ISOBMFF: Kastenbaum, `stbl` → flache Beispielliste |
| `kernel/user/mkv.fi` | 979 | EBML/Matroska: Kopf, Segment, Info, Tracks, Cluster, SimpleBlock mit allen vier Verschachtelungen, Untertitel |
| `kernel/user/mp3.fi` | 1586 | MPEG-1 Layer III, vollständig, in Festkomma |
| `kernel/user/mp3tab.fi` | 1343 | **erzeugt** von `tools/demux/mktab.py` — Huffman-Bäume, Fenster, Kosinustafeln, x^(4/3), Syntheseflanke |
| `kernel/user/srt.fi` | 274 | SubRip-Untertitel |
| `kernel/user/demuxt.fi` | 378 | der Messkopf (nicht die Anwendung) |
| `kernel/user/play.fi` | 746 → 1340 (**+594**) | die Erweiterung von MEDIA1s Abspieler |
| `tools/demux/*` | 1242 | Erzeuger, Testdateien, Abnahme, Vergleich mit ffmpeg |

Zusammen **5967 Zeilen Firn** in neuen Dateien, **+594 Zeilen** in
`play.fi` und **1242 Zeilen** Werkzeug auf dem Wirt.

### Die Abnahme

```
bash tools/demux/run.sh
...
DEMUX: 141 bestanden, 0 gescheitert
```

Neun Abschnitte: Bau (samt der Probe, dass die eingecheckte Zahlentafel
genau das ist, was der Erzeuger liefert), 60 Zusagen der Behälterleser
gegen `ffprobe`, zehn kaputte Dateien, die ehrliche Meldung, sechs
Vergleiche gegen ffmpeg, die Rechenlast, der Weg über den AC97 mit
Mitschnitt und die Bedienung.

---

## 2. Die Entscheidung: MP3 richtig statt MP3 und AAC halb

Der Auftrag ließ die Wahl, wenn beide zu groß werden. Es wurde **MP3**,
und zwar aus drei Gründen, in dieser Reihenfolge:

1. **MP3 ist der einzige Codec, der in ALLEN DREI Behältern dieser Runde
   vorkommt** — als eigene Datei, in MP4 (`.mp3` bzw. `esds` mit
   objectTypeIndication 0x69/0x6B) und in Matroska (`A_MPEG/L3`). Ein
   Dekodierer, drei Wege hinein. AAC gibt es praktisch nur in MP4.
2. **Der Alltagsnutzen ist die Musiksammlung.** Was auf einem Rechner
   wirklich als Datei liegt, ist `.mp3`. Ein `.m4a` entsteht meist aus
   einem Dienst, der ohnehin einen Browser braucht.
3. **Die Prüfbarkeit.** Für MP3 gibt es mit ISO/IEC 11172-4 eine
   ausgesprochene Genauigkeitsforderung (Effektivfehler unter 2^-15 der
   Vollaussteuerung gegen die Referenz), und es gibt gemeinfreie
   Tafeln, die man gegen die Kraft-Ungleichung nachrechnen kann. Für
   AAC-LC wäre die zweite Hälfte der Arbeit — TNS, Fensterfolgen,
   PNS — genau die, die man beim ersten Anlauf falsch macht und erst
   an fremden Dateien merkt.

**Was AAC gekostet hätte, geschätzt an dem, was MP3 wirklich gekostet
hat:** die Huffman-Ebene ist vergleichbar (11 Codebücher statt 34
Tafeln), die Requantisierung ist dieselbe Potenzfunktion, die
Filterbank ist eine IMDCT über 2048 statt 36 Punkte — aber dazu kämen
die Fensterfolgen (LONG/START/SHORT/STOP mit acht Kurzfenstern),
Sinus- **und** KBD-Fenster, TNS (ein Gitterfilter über die
Spektralwerte), PNS, Intensitätsstereo mit anderer Semantik und der
`AudioSpecificConfig` samt SBR-Erkennung, die man wenigstens ABLEHNEN
muss. Das ist keine Woche mehr, sondern eine zweite Runde in dieser
Größe. **Halb wäre schlimmer als gar nicht**: ein AAC-Dekodierer, der
lange Blöcke kann und kurze nicht, spielt jede Musik an jedem
Schlagzeugschlag kaputt — und genau dieser Fehler ist in dieser Runde
beim MP3-Kurzblock wirklich passiert (siehe 5.).

AAC ist deshalb **nicht halb drin, sondern gar nicht** — und `/bin/play`
sagt das mit dem Codecnamen, statt es zu verschweigen.

---

## 3. Was geht und was nicht

### Behälter

| Behälter | Lesen | Bemerkung |
|---|---|---|
| MP4 / ISOBMFF (`.mp4`, `.m4a`, `.mov`) | **ja** | `ftyp`, `moov`, `mvhd`, `trak`, `tkhd`, `mdia`, `mdhd`, `hdlr`, `minf`, `stbl` mit `stsd`/`stts`/`stsc`/`stsz`/`stz2`/`stco`/`co64`, `esds` (auch in `wave`) |
| MP4 fragmentiert (`moof`) | **nein, aber erkannt** | wird benannt und abgelehnt, nicht halb gelesen |
| Matroska / WebM (`.mkv`, `.mka`, `.webm`) | **ja** | EBML-Kopf mit DocType, Segment, Info (TimestampScale, Duration als IEEE 754 in Ganzzahlarithmetik), Tracks, Cluster, SimpleBlock **und** BlockGroup, alle vier Verschachtelungen (keine/Xiph/fest/EBML) |
| MP3 roh (`.mp3`) | **ja** | ID3v2 wird übersprungen, Rahmen werden gezählt, Dauer und Datenrate werden GERECHNET (kein Xing-Kopf wird geglaubt) |
| RIFF/WAV, OMC | **ja** | aus Runde MEDIA1, unverändert |

### Codecs

| Codec | Dekodiert | Warum |
|---|---|---|
| **MP3 (MPEG-1 Layer III, 32/44,1/48 kHz)** | **ja, vollständig** | siehe 4. |
| PCM (WAV) | ja | Runde MEDIA1 |
| SRT / SubRip | ja | Text |
| MPEG-2/2.5 Layer III (8–24 kHz) | **nein, erkannt** | zweiter Skalenfaktorpfad mit eigenen Tafeln; Musik gibt es dort praktisch nicht |
| Layer I / II | **nein, erkannt** | anderer Dekodierer |
| AAC-LC | **nein, erkannt und benannt** | siehe 2. |
| H.264 / AVC | **nein, erkannt und benannt** | 15 000–25 000 Zeilen, Patente bis 29.11.2027, Bit-Exaktheit zwingend (ROADMAP Block F) |
| HEVC, AV1, VP9, VP8 | **nein, erkannt und benannt** | 30 000–150 000 Zeilen; AV1 braucht handgeschriebenen Assembler für Echtzeit |
| AC-3, E-AC-3, FLAC, Opus, Vorbis, ALAC | **nein, erkannt und benannt** | keiner davon war Auftrag dieser Runde |
| ASS/SSA, VobSub | **nein, erkannt** | ASS ist ein Textsatzsystem |

---

## 4. Der MP3-Dekodierer

**Ganzzahlig, 20 Bruchbits.** Ring 3 hat kein Fließkomma
(`kernel/user/netstat.fi` sagt dasselbe über Prozentangaben). Alle
Tafeln erzeugt `tools/demux/mktab.py`.

Vollständig enthalten: Rahmenkopf, Seiteninformation, **Bitreservoir**
(bis 511 Oktette rückwärts), Skalenfaktoren mit `scfsi`-Vererbung
zwischen den Granulaten, Huffman über 17 Bäume (34 Tafelnummern) samt
`linbits` und den beiden count1-Tafeln, Requantisierung mit
`global_gain`/`scalefac_scale`/`preflag`/`subblock_gain`, Umsortierung
der Kurzblöcke, **MS- und Intensitätsstereo**, Aliasminderung, IMDCT
mit allen vier Fenstern (lang, Anfang, kurz, Ende) inklusive
Mischblock, Frequenzumkehr und Polyphasensynthese.

### Woher die Zahlen kommen

Zwei Sorten, und ihre Herkunft ist verschieden (steht auch in
`THIRD_PARTY.md`):

* **Gerechnet** aus den Formeln von ISO/IEC 11172-3: die vier IMDCT-
  Fenster, beide Kosinustafeln, die Synthesematrix, x^(4/3), 2^(k/4),
  die Aliasfaktoren aus `ci`, die Intensitätsverhältnisse.
* **Tabelliert** (Zahlenkolonnen ohne Formel): die Huffman-Tafeln
  (ISO Tabelle B.7), die Syntheseflanke D[512] (Tabelle B.3) und die
  Bandgrenzen (Tabelle B.8). Maschinenlesbare Quelle: **pdmp3, Public
  Domain**. Die Bäume werden nicht kopiert, sondern **abgelaufen** —
  aus dem fremden Baum kommt die Liste (Code, Länge, x, y), daraus wird
  ein Baum in unserem Format gebaut, und für jede der 17 Tafeln wird
  die **Kraft-Ungleichung** nachgerechnet: alle 17 summieren sich auf
  genau 1.

**Ein Fehler in der Quelle gefunden:** pdmp3 zeigt für Tafel 33 auf
Versatz 2261 — mitten in den Baum von Tafel 24. Dort liefert der Ablauf
EINEN Code der Länge null. Der richtige Versatz ist 2773; dort liegen
16 Codes zu je vier Bit, wie es Tabelle B.7 für die count1-Tafel B
verlangt. `tools/demux/mktab.py` korrigiert das und sagt im Kopf, warum.

### Die Geschwindigkeit: gemessen, nicht behauptet

Die erste lauffähige Fassung war die aus der Norm abgeschriebene:
64 Zeilen Synthesematrix, 36 Zeilen IMDCT, der V-Vektor bei jedem
Abtastschritt um 64 Plätze umkopiert. Drei Änderungen, jede eine
IDENTITÄT und keine Näherung — das Ergebnis blieb Abtastwert für
Abtastwert dasselbe (mittlerer Fehler 0,19 vorher wie nachher):

| Schritt | Rechenlast (Anteil eines Kerns) |
|---|---:|
| aus der Norm abgeschrieben | **84,5 %** |
| + IMDCT halbiert (`cos[p] = −cos[17−p]`, `cos[p] = cos[53−p]`), Synthesematrix halbiert (`N[32−i] = −N[i]`, `N[i] = N[96−i]`), Ringpuffer statt Umkopieren, Nullteilbänder übersprungen | **29,1 %** |
| + U-Vektor nicht mehr gebaut, sondern in derselben Schleife gefenstert | **18,6 %** |

Das ist ein Faktor **4,5** ohne eine einzige geänderte Zahl im Ergebnis.
Gemessen auf dem Bauserver unter `-accel kvm`. Die Zahl hängt an der
Wirtslast, und das steht im Protokoll: **18,6 %** bei Last 7 auf 12
Kernen, **28 %** bei Last 8–13. Beides ist eher zu hoch als zu niedrig,
weil der Zähler des Gastes Wanduhrzeit misst und der Wirt in dieser
Runde ständig fünf bis fünfzehn fremde Abnahmen trug. Die
Recherche setzt für einen optimierten MP3-Dekodierer 1–3 % an — der
Unterschied ist der Übersetzer: `firnc0` ist der Bootstrap-Übersetzer
ohne Optimierung, und jede Rechnung trägt eine Überlaufprüfung (SPEC 13,
`dev-fast`). Das ist ehrlich so und keine Ausrede: für einen
Musikspieler reicht es, für 1080p-Video wäre es der falsche Weg.

---

## 5. Der Beweis: gegen ffmpeg, nicht gegen das Gehör

`tools/demux/vergleich.py` legt die Abtastwerte nebeneinander:
mittlerer und größter Fehler je Abtastwert (in Einheiten des 16-Bit-
Wertes), Effektivfehler, Störabstand und ein FFT-Vergleich über das
ganze Stück.

Ergebnis für `ton1.mp3` (44,1 kHz, Stereo, Joint, 128 kbit/s,
155 Rahmen, 178 560 Abtastwerte je Kanal):

```
n=357120  mittel=0,1935  max=3  rms=0,4400  (Signal-Effektivwert 6415)
```

Das sind **0,19 Einheiten mittlerer Fehler** bei einem Wertebereich von
±32 767 und ein **größter Fehler von 3**. Der Effektivfehler von 0,44
liegt deutlich unter der einen Einheit, die ISO/IEC 11172-4 für einen
„vollständig übereinstimmenden" Dekodierer verlangt. Null
Dekodierfehler, null begrenzte Spektralwerte.

**Der Fehler, den diese Messung gefunden hat.** Die erste Fassung hatte
einen mittleren Fehler von 1,50 und einen größten von 1597. Die
Aufteilung nach Rahmen zeigte: nur vier Rahmen waren betroffen — genau
die, in denen die absichtlich eingebauten Knackser stehen, und genau
die, deren Seiteninformation `block_type = 2` sagt. Der Grund: **ein
Kurzblock hat DREIZEHN Bänder (0…12), aber nur ZWÖLF übertragene
Skalenfaktoren.** Band 12 (Linien 408…575) wurde weder umsortiert noch
mit dem richtigen Faktor requantisiert. Ohne die Knackser im Testsignal
wäre dieser Fehler nicht aufgefallen — und ohne den Zahlenvergleich hätte
niemand gehört, dass die obersten Frequenzen dreier Rahmen falsch
liegen. Das ist der Grund, aus dem das Testsignal Knackser hat.

---

## 6. Die ehrliche Meldung

`play -i /m/film.mp4` (H.264 + AAC):

```
play: spuren=2
  0  Video  H.264 / AVC  320x240  3.0 s  731 kbit/s  NICHT dekodierbar
  1  Ton    AAC-LC  44100 Hz  2 Ka  3.0 s  112 kbit/s  NICHT dekodierbar
play: Bildspur nicht dekodierbar
play:   H.264 / AVC  320x240  3.0 s  731 kbit/s
play: dieser Codec ist nicht selbst geschrieben -- 15000 bis
play: 150000 Zeilen Dekodierer, siehe ROADMAP.md Block F.
play: Tonspur nicht dekodierbar, Codec: AAC-LC
```

`play -i /m/film.mkv` (H.264 + MP3 + SRT) — dieselbe Ablehnung der
Bildspur, aber:

```
  1  Ton    MP3  44100 Hz  2 Ka  3.0 s  117 kbit/s  spielbar
  2  Text   SRT  3.0 s  spielbar
play: spiele nur den Ton dieser Datei
```

Die Datenrate ist **gerechnet** (Summe der Beispielgrößen durch die
Dauer) und nicht aus einem Kopffeld gelesen — ein Kopffeld kann lügen,
die Summe der Beispiele nicht.

---

## 7. Die Anwendung

`/bin/play` aus Runde MEDIA1, erweitert. Das Format entscheiden die
ersten Oktette, nicht der Dateiname.

```
play [-v N] [-q] [-i] [-t N] [-s SEK] [-u datei.srt] [-K] datei ...
```

* **Wiedergabeliste**: mehrere Dateien, der Reihe nach.
* **Lautstaerke** `-v` und im Betrieb `+`/`-` in Zehnerschritten.
* **Spulen** `-s <Sekunden>` und im Betrieb Pfeil links/rechts (±5 s).
* **Pause** Leertaste, **weiter** `n`, **Ende** `q`.
* **Untertitel** aus einer `.srt`-Datei (`-u`) oder aus der
  Matroska-Spur, zur richtigen Zeit eingeblendet.
* **Spurwahl** `-t <n>`.

Die Tasten kommen über `SYS_HOTKEY` und nicht über `read`: ein `read`
auf das Terminal blockiert in diesem Kernel bis zu vier Sekunden
(`kernel/sys.fi`, `KEY_IDLE`), und ein Abspieler, der das tut, hat vier
Sekunden Stille.

---

## 7b. Der ganze Weg, gemessen

`play -q -K /m/ton1.mp3` auf einer Maschine mit `-device AC97` und
`-audiodev wav`: QEMU schreibt mit, was der Treiber wirklich ausgibt.

```
einsatz mitschnitt=1206 quelle=2  rahmen=194337 rate=48000
ton   440 Hz: mitschnitt= 4271.75 quelle= 4499.69 verhaeltnis=0.949
ton  1567 Hz: mitschnitt= 1418.92 quelle= 1499.94 verhaeltnis=0.946
ton  3000 Hz: mitschnitt=    0.02 quelle=    0.00 anteil=0.000005
```

Die beiden Töne des linken Kanals kommen mit **0,949** und **0,946**
ihres Pegels an — die fehlenden fünf Prozent sind der lineare
Umrechner von 44,1 auf 48 kHz, der Dämpfung hat und in `play.fi` als
solcher benannt ist. Die Gegenprobe: 3000 Hz kommt im linken Kanal des
Testsignals nicht vor und liegt im Mitschnitt bei **0,0005 %** des
440-Hz-Pegels.

Die Bedienung im selben Lauf:

```
play: [1/2] /m/ton1.mp3      frames=155  played=194432  underruns=0  volume=40
play: [2/2] /m/ton2.mp3      frames=85   played=97920   underruns=0
play -s 2 /m/ton1.mp3        frames=77   mp3skip=1
play -t 1 -u unter.srt film.mkv
play: [Erster Untertitel]
play: [Zweiter Untertitel, mit Komma]
play: [Dritter]
```

`frames=155` gegen `frames=77` ist das Spulen, gemessen und nicht
behauptet. `mp3skip=1` nach dem Sprung ist ehrlich: der erste Rahmen
hinter einer Sprungstelle hat sein Bitreservoir nicht und wird
übersprungen statt falsch ausgegeben.

**Die Gegenprobe zum Tongerät:** die Abschnitte 1 bis 7 der Abnahme
laufen ohne das Wort `audio` auf der Kernel-Befehlszeile. Dort gibt es
kein Tongerät — und `/bin/play` sagt genau das und gibt trotzdem
Auskunft, statt abzustürzen oder stumm zu bleiben.

---

## 8. Was diese Runde ABSICHTLICH nicht getan hat

* **Kein zweiter Tontreiber.** Der AC97 und die Tonschicht kommen aus
  Runde MEDIA1; dieser Zweig hat sie hereingeholt und benutzt sie.
* **Kein Video.** Nicht ein Bild wird dekodiert, und das steht in jeder
  Meldung.
* **Kein AAC halb.** Siehe 2.
* **Kein Umrechner mit Fenster (Sinc).** Der Ton wird linear von 44,1
  auf 48 kHz interpoliert, wie schon im WAV-Weg von MEDIA1. Das ist ein
  Tiefpass erster Ordnung; ein sauberer Umrechner steht auf der Restliste.
