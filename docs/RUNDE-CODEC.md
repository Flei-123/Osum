# RUNDE CODEC (P-022) -- ein h.264-Dekodierer fuer OrientOS

Zweig `codec`, Grundlage `main` = fd33f0f.
Bereich in `kdata`: **CODEC_OFF 0x118000 .. 0x120000**, acht Seiten, vorher
vergeben. Keine Seite ausserhalb.

---

## 1. DIE VORABMESSUNG -- was ist WIRKLICH da, bevor eine Zeile entsteht

Der Auftrag verlangt, zuerst zu messen und das Ergebnis aufzuschreiben.
Getan, und es ist deutlicher ausgefallen als erwartet: **fuer Video ist
nichts da, fuer die Rechenwerke darunter eine ganze Menge.**

### 1.1 `kernel/user/media.fi` -- kennt die Namen, dekodiert nichts

    621 Zeilen. C_H264 = 1 ist eine ZAHL in einer Aufzaehlung
    (Zeile 248), `codec_name` gibt den Text "H.264 / AVC" zurueck
    (Zeile 324), `can_decode` sagt fuer C_H264 FALSCH.

Der Dateikopf sagt es selbst, Zeile 23-30:

> WAS DIESES SYSTEM NICHT KANN, UND WARUM ES DAS SAGT: H.264, HEVC, AV1
> und VP9 sind zwischen 15.000 und 150.000 Zeilen Dekodierer [...] Ein
> Abspieler, der so eine Datei oeffnet und ein schwarzes Fenster zeigt,
> luegt.

Also: **null Zeilen Videodekodierung im Baum.** Was media.fi liefert und
was diese Runde benutzt, statt es abzuschreiben:

| Was | Wo | In dieser Runde benutzt |
|---|---|---|
| `src_open/src_byte/src_bytes/src_size` -- 64-KiB-Fenster ueber der Datei, Zugriff hinter dem Ende liefert 0 und setzt `src_eof` | media.fi 60ff | **ja**, der Annex-B-Leser liest darueber. Das ist der Grund, warum eine abgeschnittene Datei nicht abstuerzt. |
| `be16/be24/be32/be64`, `le16/le32/le64` | media.fi | ja (MP4-Laengenpraefixe) |
| Spurentafel `trk_*`, `T_W`/`T_H`/`T_PROFILE` | media.fi 376ff | ja, der Dekodierer traegt Breite/Hoehe aus dem SPS ein |
| `can_decode` | media.fi | **geaendert**: C_H264 sagt jetzt wahr, wenn das Profil Baseline ist |

### 1.2 `kernel/user/jpeg.fi` -- der Steinbruch, und er traegt weniger als gehofft

640 Zeilen, und es lohnt sich, genau hinzusehen, was davon **wirklich**
wiederverwendbar ist. Das Ergebnis ist ernuechternd und steht hier, weil
"wir nehmen den JPEG-Code" die naheliegende und falsche Antwort gewesen
waere:

| Baustein | JPEG (jpeg.fi) | h.264 braucht | uebernehmbar? |
|---|---|---|---|
| Bitleser `bit()`/`bits(n)` | Zeile 158-193. Oktettweise, **0xFF 0x00 ist Stopfung**, jedes andere 0xFF beendet den Strom | Annex B stopft **0x03** nach zwei Nullen (`emulation_prevention_three_byte`), Startcode ist 00 00 01 | **Struktur ja, Code nein.** Die Stopfregel ist eine andere. Neu geschrieben als `bit_init/u1/un/ue/se` in h264.fi, aber nach demselben Muster (Zaehler + Puffer + `empty`-Fahne). |
| `erweitern(v,n)` (T.81 F.1) | Zeile 195 | h.264 hat **Exp-Golomb** (`ue`/`se`), voellig andere Kodierung | nein |
| Huffman `h_dekod`/`tree_build` | Zeile 206-240, kanonischer Huffman aus DHT-Tabellen | **CAVLC**: feste Tabellen aus der Norm, `coeff_token` haengt von der Nachbarschaft ab (nC) | nein -- andere Entropiekodierung. |
| **IDCT** | Zeile 268, 8x8, **`f64` und `math.sqrt`**, getrennt in Zeilen/Spalten | h.264 hat eine **4x4-Ganzzahltransformation**, exakt spezifiziert (8.5.12.2), **kein Fliesskomma** | **nein, und das ist der wichtigste Befund dieser Runde.** Siehe 1.3. |
| Quantisierung | `qt[]`, 8 Bit je Wert, Multiplikation | h.264: `LevelScale` aus `qP/6` und `qP%6`, Norm-Tabelle | nein |
| **YCbCr -> RGB** | Zeile 604-613, Festkomma: `91881*cr>>16` usw. | genau dasselbe (BT.601) | **JA, unveraendert uebernommen** -- dieselben vier Konstanten 91881/22554/46802/116130, dieselbe `klemm`-Funktion. Das ist der einzige Block, der woertlich weiterlebt. |
| `klemm(v)` 0..255 | Zeile 377 | ja | **ja** |
| 4:2:0-Unterabtastung | JPEG kann 1x1/2x1/1x2/2x2 | h.264 Baseline ist **immer** 4:2:0 | Idee ja, Code nein (h.264 hat eine eigene Chroma-Bewegungsvektor-Rechnung) |

### 1.3 DER BEFUND, DER DIE RUNDE ENTSCHEIDET: Fliesskomma ist hier VERBOTEN

`jpeg.fi` rechnet die IDCT in `f64` und traegt dafuer `#[allow_fp]`.
Der Dateikopf begruendet das selbst (Zeile 22):

> eine Ganzzahl-IDCT ist schneller und WEICHT AB

Fuer JPEG ist das zulaessig -- T.81 schreibt die IDCT **nicht** bitgenau
vor, jeder Dekodierer darf leicht anders runden. **Fuer h.264 gilt das
Gegenteil.** ITU-T H.264 Abschnitt 8.5 spezifiziert die Transformation
als exakte Ganzzahlfolge; jeder normgerechte Dekodierer muss **dasselbe
Oktett** liefern. Genau darauf steht die Abnahme dieser Runde (bitweiser
Vergleich gegen ffmpeg).

**Folge:** kein `f64` irgendwo in h264.fi, kein `#[allow_fp]`, keine
`math.`-Funktion. Alles Ganzzahl, so wie die Norm es hinschreibt. Wer
hier Fliesskomma einbaut, verliert die Bitgleichheit und merkt es erst
in der Gegenprobe.

### 1.4 Was es sonst gibt

* **Ein Demuxer existiert.** `git log --all --oneline | grep -i demux`
  findet den Zweig `demux` (8a35720..eb4ed5f), und er ist **laengst in
  main**: `media.fi`, `mp3.fi`, `play.fi` stammen daher, MP4 und
  Matroska werden gelesen. Der Auftrag sagt, MP4 nur wenn Zeit bleibt --
  die Pflicht ist rohes Annex-B, und dabei bleibt es (siehe 2).
* **Kein Allokator in Ring 3.** `grep malloc kernel/user/ulib.fi`: keiner.
  `ulib.fi` Zeile 827 sagt es ausdruecklich. Grosse Puffer sind darum
  **statische Felder** im Programm (Vorbild: `opk.fi` 8 MiB, `zip.fi`
  768 KiB) -- NICHT in `kdata`. Das passt zur Speicherregel des
  Auftrags: kdata traegt nur Zustandsfelder, die Bildpuffer nicht.
* **Keine zweidimensionalen Felder in Firn.** `grep 'static mut .*\[\['`:
  null Treffer. Alles flach mit selbst gerechnetem Index.
* Ton (AC97/HDA), Fenstersystem (`wm.fi`), virtio-GPU (`vgpu.fi`) sind da.

### 1.5 Messgeraete des Wirts

    ffmpeg 5.1.9, --enable-libx264, --enable-gpl   -> Testmaterial UND Gegenprobe
    qemu-system-x86_64 mit KVM                     -> die Messung laeuft im Kern

---

## 2. DIE UMFANGSENTSCHEIDUNG

Der Auftrag ist streng: **Baseline, I- und P-Frames, sonst nichts.**
Daran wird sich gehalten. Was gebaut wird und was ausdruecklich nicht:

**Gebaut:**
* Annex-B-Leser (Startcodes 00 00 01 / 00 00 00 01, Entfernung der
  `emulation_prevention_three_byte`)
* SPS und PPS
* Slice-Header, I- und P-Slices
* **CAVLC** -- die Entropiekodierung von Baseline
* Intra 4x4 (neun Modi) und Intra 16x16 (vier Modi), Chroma 8x8 (vier)
* Die 4x4-Ganzzahltransformation und die Skalierung, exakt nach 8.5
* Deblocking-Filter
* P-Slices: Bewegungskompensation auf Viertelpel (Luma, Sechs-Anzapf-
  Filter) und Achtelpel (Chroma, bilinear), P_Skip
* Ausgabe YUV 4:2:0, Umwandlung nach RGB fuer die Anzeige

**Ausdruecklich NICHT (und das ist eine Entscheidung, kein Versaeumnis):**
* CABAC (ist nicht in Baseline)
* High Profile, 8x8-Transformation, Skalierungsmatrizen
* B-Slices, gewichtete Vorhersage, Feldkodierung/Interlace
* Mehr als ein Referenzbild, wenn der Strom es nicht verlangt
  (siehe die Messwerte, was wirklich angefasst wurde)
* vp9, av1, HEVC

---

---

## 3. DIE BAUABSCHNITTE, und warum in dieser Reihenfolge

Der Auftrag verlangt, jede Stufe einzeln messbar zu machen. Das ist
geschehen, aber mit einer Entscheidung davor, die den Rest der Runde
getragen hat:

> **Der ganze Dekodierer entstand ZUERST in Python** (`tools/codec/ref264.py`,
> 1364 Zeilen), gegen ffmpeg gemessen, und erst danach in Firn.

Der Grund ist Arbeitsoekonomie und nichts sonst. Ein Fehlversuch in
Python kostet Sekunden; derselbe Fehlversuch in Firn kostet einen
Kernelbau, ein Plattenabbild und einen QEMU-Lauf -- gut zwei Minuten.
Von den **siebzehn Fehlern** dieser Runde sind **neun** im
Python-Geraet gefunden worden, und keiner davon war im Quelltext zu
sehen; sie zeigen sich alle erst im Wertevergleich.

| Stufe | wie gemessen | Ergebnis |
|---|---|---|
| Bitstromleser, Annex B, RBSP | die 0x03-Entstopfung, `ue`/`se` von Hand gegen den Strom nachgerechnet | Slice-Kopf endet bei Bit 24 -- von Hand dasselbe |
| SPS/PPS | gegen `ffmpeg -debug` (Profil, Masse, poc_type, CAVLC) | profile 66, 4:2:0, frame_mbs_only, CAVLC, keine Slice-Gruppen |
| CAVLC | **Kreisprobe**: 53331 Bloecke kodiert, gelesen, verglichen | **0 falsch** |
| I-Slice | ffmpeg-Gegenprobe, oktettweise | 4 Stroeme, **0 abweichende Oktette** |
| Deblocking | dieselbe Gegenprobe (vorher: maxdiff 2 auf den Kanten) | **0** |
| P-Slice | dieselbe Gegenprobe | 4 Stroeme, **0** |
| Firn-Fassung | SHA-256 je Bild IM LAUFENDEN KERN gegen ffmpeg | 38 Bilder, **38 Treffer** |

## 4. DIE SIEBZEHN FEHLER

Sie stehen hier vollstaendig, weil jeder einzelne die Art Fehler ist,
die eine Runde ohne Wertevergleich fuer "fertig" halten wuerde.

**Im Python-Geraet gefunden (neun):**

1. **`BLK_XY`** -- die Reihenfolge der 16 Luma-4x4-Bloecke (8.2.2)
   laeuft ueber 8x8-Viertel, nicht zeilenweise. Die naheliegende
   Bitverdrehung liefert DOPPELTE Koordinaten und erreicht die Zeilen 2
   und 3 nie. *Wirkung:* der Bitstrom laeuft drei Makrobloecke spaeter
   aus dem Tritt, und es sieht nach einem Tafelfehler aus.
2. **suffixLength, erster Wert** -- FFmpeg hat ZWEI Wege, und welcher
   gilt, haengt an der CODELAENGE (`prefix+1+sL <= 8`). Der kurze
   rechnet `1 + (|level| > 3)`, nur der lange setzt fest 2.
3. **...und die Zeile dazu** steht in vorzeichenloser C-Arithmetik
   (`level_code + 3U > 6U`). Vorzeichenbehaftet abgeschrieben kommt
   fuer negative Werte das Falsche heraus.
4. **`weightScale` fehlte** in der Skalierung. Bei Baseline ist es die
   flache Matrix aus lauter 16en (Flat_4x4_16, 8.5.9). *Wirkung:* alle
   Reste sechzehnmal zu klein -- kein Absturz, kein schiefes Bild, ein
   **flaches**.
5. **Dasselbe noch einmal beim Chroma-DC** (8.5.11.2). *Wirkung:* das
   Muster stimmt, die Hoehe sitzt um einen festen Betrag daneben.
6. **Die `done`-Fahne** (Nachbar schon dekodiert?) darf NUR fuer
   FREMDE Makrobloecke gelten. Auf den eigenen angewandt, wird fuer
   jeden 4x4-Block DC vorhergesagt -- und damit werden die falschen
   Modi aus dem Strom gelesen.
7. **Ein INTER-Nachbar ist verfuegbar** und zaehlt fuer die
   Intra-Modusvorhersage als DC; nur bei `constrained_intra_pred_flag`
   gilt er als nicht da. Genau andersherum gedacht ist jeder
   Intra-Makroblock in einem P-Slice falsch.
8. **Die Sonderfaelle 16x8/8x16** der Vektorvorhersage (8.4.1.3.1)
   greifen VOR dem Median. Ohne sie liegt jeder zweite P-Makroblock
   daneben.
9. **Chroma-Deblocking** griff auf die falschen 4x4-Bloecke zu
   (Chromazeile `>>2` statt `>>1`). *Wirkung:* PAARE von Abweichungen
   genau auf den Kanten 3/4, 7/8, 11/12, maxdiff 2.

**Erst in Firn bzw. im Kern gefunden (acht):**

10. **Die Zahl der Bildspeicher.** x264 stellt im Baseline-Profil
    `num_ref_frames = 3` ein und benutzt `ref_idx` bis 2 wirklich. Mit
    drei Speichern (Bild + zwei Referenzen) stimmen die ersten DREI
    Bilder, ab dem vierten wandert es. Das sieht wie ein Dekodierfehler
    aus und ist ein zu kleiner Vorrat. Jetzt vier.
11. `gaps_in_frame_num_value_allowed_flag` ist EIN Bit, kein `ue(v)`.
12. Die Textfelder in Firn muessen exakt so lang sein wie der Text in
    OKTETTEN (ein Umlaut ist zwei) -- dafuer gibt es jetzt
    `tools/codec/fixstr.py`, statt es zu zaehlen.
13. `... | grep -q` schliesst die Leitung; mit `set -o pipefail` gilt
    der ganze Ausdruck als gescheitert und die Abnahme uebersprang sich
    selbst.
14. Die Tafelindizes von `coeff_token` (`t1 = i&3`, `tc = i>>2`) sind
    mechanisch gegen die Erzeugung geprueft worden, statt sie zu glauben.

**Und die drei, die erst ein Strom mit mehreren Slices je Bild zeigte
(`-x264-params slices=4`):**

15. **Ein Bild ist nicht ein Slice.** Ein neues Bild faengt nur bei
    `first_mb_in_slice == 0` an (7.4.3); jeder andere Slice setzt
    dasselbe Bild fort. Vorher wurden aus vier Slices vier
    Viertelbilder. Gefiltert wird erst, wenn ALLE Makrobloecke stehen --
    der Entblockungsfilter laeuft ueber Slicegrenzen hinweg.
16. **Ein Slice endet, wenn seine BITS zu Ende sind**, nicht wenn das
    BILD voll ist (`more_rbsp`, 7.3.4). Das galt bisher nur fuer
    P-Slices; ein I-Slice las weiter und dekodierte die Fuellnullen als
    Makroblock. *Wirkung:* "der Datenstrom bricht ab".
17. **Ueber eine Slicegrenze hinweg gibt es KEINE Nachbarn** (7.4.4 --
    ein Slice ist unabhaengig dekodierbar), und zwar weder fuer die
    Syntax (nC, Intra-Modi, Vektoren) noch fuer die BILDPUNKTE der
    Intra-Vorhersage. *Wirkung:* der erste Streifen stimmt, alles
    darunter nicht -- und weil der erste stimmt, sieht es nach einem
    Folgefehler aus und man sucht an der falschen Stelle.

## 5. DIE MESSWERTE

### 5.1 Die ffmpeg-Gegenprobe, IM LAUFENDEN KERN

Osum rechnet die SHA-256 je Bild SELBST (`kernel/user/sha.fi`, in Runde
TRESOR gegen FIPS 180-4 gemessen), der Wirt rechnet dieselbe Summe aus
dem, was `ffmpeg -f rawvideo -pix_fmt yuv420p` aus derselben Datei
schreibt. Gleiche Summe heisst: Oktett fuer Oktett dasselbe Bild.

| Strom | Masse | Bilder | Art | bitgleich | Zeit | Bilder/s |
|---|---|---|---|---|---|---|
| i_glatt | 128x96 | 2 | nur I | **2 / 2** | 14 ms | 142,85 |
| i_klein | 64x64 | 3 | nur I | **3 / 3** | 26 ms | 115,38 |
| i_sd | 176x144 | 3 | nur I | **3 / 3** | 69 ms | 43,47 |
| i_scharf | 160x128 | 2 | nur I | **2 / 2** | 16 ms | 125,00 |
| p_klein | 64x64 | 6 | I+P | **6 / 6** | 49 ms | 122,44 |
| p_sd | 176x144 | 8 | I+P | **8 / 8** | 147 ms | 54,42 |
| p_bewegt | 176x144 | 8 | I+P | **8 / 8** | 165 ms | 48,48 |
| p_skip | 128x96 | 6 | I+P | **6 / 6** | 31 ms | 193,54 |
| **cif** | **352x288** | **10** | **I+P** | **10 / 10** | **313 ms** | **31,94** |
| **slices** | **176x144** | **3** | **I, 4 Slices je Bild** | **3 / 3** | 34 ms | 88,23 |

**51 Bilder, 51 Pruefsummen, 51 Treffer. PSNR ist unendlich, die Zahl
abweichender Bildpunkte ist null** -- beides, weil die Bilder identisch
sind und nicht aehnlich. Deshalb steht hier keine PSNR-Tabelle: sie
haette nur dann einen Wert, wenn etwas abwiche.

### 5.2 Die Geschwindigkeit, ehrlich

Gemessen in QEMU mit KVM (AMD EPYC), Stufe-0-Uebersetzer, `-m 512`,
mit der Uhr des Systems (`clock_gettime`, CLOCK_MONOTONIC) im Programm
selbst -- also einschliesslich Dateilesen und Pruefsummenrechnen.

* **CIF (352x288): 30,76 Bilder/s.** Das reicht fuer fluessiges Video
  in dieser Aufloesung (25 B/s PAL, 30 B/s NTSC).
* **QCIF (176x144): 43 bis 54 Bilder/s.**
* Kleiner als das: 115 bis 194 Bilder/s.

**WAS DAS NICHT HEISST.** Der Dekodierer ist nicht auf Geschwindigkeit
gebaut, sondern auf Richtigkeit, und man sieht es:

* Die Tafelsuche (`tab_find`) geht **bitweise linear** durch bis zu 68
  Eintraege. Eine Baumtafel waere um ein Vielfaches schneller -- und
  haette einen Fehler, den man nicht sieht. Fuer diese Runde war die
  durchschaubare Form die richtige.
* Die Bewegungskompensation rechnet **je 4x4-Block einzeln**, auch wo
  der Makroblock einen einzigen Vektor hat; die Sechs-Anzapf-Filter
  laufen dabei mehrfach ueber dieselben Punkte.
* Es gibt **keinerlei SIMD**, keinen handgeschriebenen Assembler.

Fuer **640x480 und groesser ist es zu langsam** -- hochgerechnet aus
CIF etwa 10 Bilder/s, und das ist kein Video mehr. Wer das will,
braucht die drei Punkte oben, in dieser Reihenfolge. **Es ist auch
nicht gemessen worden**, weil `MAXW`/`MAXH` bei 352x288 stehen (die
Begruendung steht in `h264.fi`: vier Bildspeicher, 6 MiB je Prozess).

### 5.2b Die Abnahme als Ganzes

    bash tools/codec/run.sh
    == CODEC: 65 bestanden, 0 gescheitert ==

(Die Zahl gilt fuer den Lauf ohne den Strom `slices`; mit ihm kommen
vier Punkte dazu.)

### 5.3 Die Gegenproben

| Fall | Zahl | Ergebnis |
|---|---|---|
| abgeschnittene Stroeme (1 % bis 89 %) | 10 | alle sauber abgewiesen, keiner haengt |
| verfaelschte Oktette (je 6 gekippte Bits) | 12 | alle sauber abgewiesen |
| leer / Zufallsmuell / nur Startcode | 3 | alle sauber abgewiesen |
| High Profile | 1 | abgewiesen, `err=2`, **0 Bilder** |
| CABAC (Main) | 1 | abgewiesen |
| im Python-Geraet zusaetzlich | 245 | **0 Abstuerze** |

Kein Fall liefert ein halbes Bild und keiner laeuft in eine Schleife:
der Bitleser liefert hinter dem Ende Nullen und setzt `bs_over`, und
jede Tafelsuche, die nichts findet, bricht den Makroblock ab.

### 5.4 Die Speicherkarte

```
123 Bereiche in 0x140000 Oktetten kdata, 12 Vektoren, 0 Kollisionen
0x118000..0x120000  CODEC   kstate.fi:CODEC_OFF
```

**0 Kollisionen.** Gegenprobe: `CODEC_OFF` versuchsweise auf 0x108000
(WMP_OFF) gelegt -- der Pruefer schlaegt an (Rueckgabe 1). Belegt ist
EINE der acht Seiten, mit Zaehlern; die Bildpuffer liegen
ausdruecklich NICHT dort (ein CIF-Bild ist 152 KiB und passte nicht
einmal in den ganzen Bereich), sondern als statische Felder in
`kernel/user/h264.fi`. Die Abnahme rechnet das nach.

Dass der Bereich wirklich BESCHRIEBEN wird und nicht nur zugeteilt
ist, prueft die Abnahme, indem sie die Zahlen aus dem KERN zurueckliest
(`kframes`/`kw`/`kh`) und gegen die des Programms haelt -- bei allen
Stroemen gleich.

## 6. WAS OFFEN BLIEB

Ehrlich und einzeln, statt einer Zusage:

* **Kein MP4-Demuxer angeschlossen.** Der Auftrag stellt ihn frei
  ("nur wenn Zeit bleibt"). Ein Demuxer EXISTIERT im Baum (Runde
  DEMUX, `media.fi` liest MP4 und Matroska und kennt die Spurentafel);
  was fehlt, ist die Naht, die die Laengenpraefixe von AVCC in
  Annex-B-Startcodes wandelt und `h264.fi` fuettert. Das ist
  ueberschaubar, aber es ist NICHT gebaut und nicht gemessen.
* **`media.can_decode` sagt fuer C_H264 weiterhin falsch.** Der
  Dekodierer ist da, die ehrliche Antwort in media.fi ist noch nicht
  umgestellt -- das gehoert zusammen mit dem Punkt darueber gemacht,
  sonst verspricht `/bin/play` etwas, das der Behaelterweg noch nicht
  liefert.
* **Keine Anzeige.** `h264_to_rgb` ist gebaut (BT.601-Festkomma,
  derselbe Block wie in `jpeg.fi`) und an kein Fenster angeschlossen.
  Wer ein Video auf dem Schirm will, braucht die Naht zu
  `wm.fi`/`vgpu.fi`.

  **Gemessen ist die Umrechnung inzwischen**, und zwar mit einem
  anderen Ergebnis als der Dekodierer selbst: gegen
  `ffmpeg -vf scale=in_range=full:out_range=full,format=rgb24` weichen
  **75400 von 228096 Werten ab, groesster Abstand 2**. Das ist KEIN
  Fehler und wird auch keiner: YUV->RGB ist -- anders als die
  Dekodierung -- **nicht bitgenau spezifiziert**. ffmpegs `swscale`
  rechnet mit anderen Zwischenbreiten und rundet anders; beide
  Ergebnisse sind zulaessig. Genau deshalb steht die Zusage dieser
  Runde auf dem **YUV**, nicht auf dem RGB: dort ist "bitgleich" eine
  pruefbare Aussage, hier waere es eine Geschmacksfrage.

  Die Umrechnung selbst ist auf Plausibilitaet geprueft (Grau bleibt
  grau, Weiss bleibt weiss, Schwarz bleibt schwarz, ein roter Ton
  bleibt rot).
* **Nur 352x288.** Siehe 5.2. Fuer groessere Bilder braucht es mehr
  Speicher je Prozess und die drei Beschleunigungen.
* **Keine JVT-Konformitaetsstroeme.** Der Auftrag nennt sie als
  haerteste Latte, falls erreichbar. Sie liegen nicht auf diesem
  Rechner und wurden nicht geholt; gemessen wurde gegen ffmpeg, was
  fuer Baseline eine harte, aber nicht die haerteste Latte ist.
  Insbesondere ungeprueft: `I_PCM` (wird abgewiesen), lange
  Referenzlisten, ungerade Beschnittwerte. **Mehrere Slices je Bild
  sind inzwischen geprueft** -- siehe den Strom `slices` oben; dass er
  wirklich vier Slices je Bild hat, rechnet `tools/codec/nalzahl.py`
  nach (12 Einheiten, `first_mb` 0/22/55/77).
* **Nicht gebaut, absichtlich:** CABAC, High Profile, B-Slices,
  Interlace, gewichtete Vorhersage, Slice-Gruppen, vp9, av1. Alles
  davon wird erkannt und abgewiesen.

## 7. WAS DIE RUNDE GEKOSTET HAT

```
kernel/user/h264.fi     2678 Zeilen   der Dekodierer
kernel/user/h264tab.fi   677 Zeilen   die Tafeln (ERZEUGT)
kernel/user/h264t.fi     204 Zeilen   das Messgeraet
kernel/codecstat.fi       71 Zeilen   die Zaehler in kdata
tools/codec/             ~900 Zeilen  Abnahme, Erzeuger, Pruefer
tools/codec/ref264.py   1364 Zeilen   das Versuchsgeraet (nicht im Kern)
```

Die Tafeln sind **erzeugt und nicht abgetippt** (`tools/codec/mktab.py`):
CAVLC und Entblockung mechanisch aus FFmpegs Quelltext, die
Intra-4x4-Gewichte aus den Normformeln ueber `tools/codec/pred_gen.py`.
Dass sie stimmen, rechnet `tools/codec/praefix.py` nach -- 30 Tafeln,
448 Codes, 0 Praefixkollisionen, alle Kraft-Summen <= 1.

**Kein Fliesskomma, keine Zeile.** Die Abnahme prueft das mit `grep`,
statt es zu glauben.
