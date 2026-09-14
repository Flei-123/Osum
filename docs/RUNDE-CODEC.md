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

*(Die Abschnitte 3 bis 7 -- Bauabschnitte, Messwerte, die
ffmpeg-Gegenprobe und die offenen Punkte -- werden waehrend der Runde
gefuellt.)*
