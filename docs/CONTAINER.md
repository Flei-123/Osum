<!-- SPDX-License-Identifier: GPL-2.0-only -->
# OMC — der Behaelter von Osum

Stand: Runde MEDIA1, 28.08.2026. Leser: `kernel/user/omc.fi` (206 Zeilen).
Umwandler auf dem PC: `tools/media/omcpack.py`.

## Warum ueberhaupt ein eigenes Format

Gezaehlt, nicht geschaetzt (`/root/osum-research-raw.md`, Teilaufgabe 2a):

| Behaelter | Zeilen fuer einen Leser |
|---|---|
| **eigenes Format** | **150–300** |
| WAV (RIFF, nur Ton) | 200–400 |
| Ogg | 600–1000 |
| Matroska/WebM (EBML) | 1500–3000 |
| MP4/ISOBMFF | 2000–4000 |
| MPEG-TS | 1000–2000 |

Ein Fremdbehaelter kostet das Fuenf- bis Zwanzigfache und liefert genau **eine**
Sache, die dieses Projekt braucht: **Zeitstempel je Block**. Die stehen hier in
acht Oktetten. Das Umwandeln passiert auf dem PC, wo ffmpeg ohnehin steht.

Das ist kein Verzicht auf Kompatibilitaet — es ist die Verschiebung der
Kompatibilitaet an die Stelle, die sie tragen kann.

## Der Kopf, 32 Oktette

| Versatz | Groesse | Inhalt |
|---|---|---|
| 0 | 4 | `"OMC1"` — Kennung und Fassung |
| 4 | 2 | Kopflaenge, immer 32 (ein Leser, der etwas anderes sieht, lehnt ab) |
| 6 | 2 | Zahl der Spuren, 1..4 |
| 8 | 8 | Dauer in **Mikrosekunden**, 0 = unbekannt |
| 16 | 4 | Versatz des ersten Blocks (= 32 + 32 × Spuren) |
| 20 | 4 | Zahl der Bloecke, 0 = unbekannt |
| 24 | 4 | Flags. Bit 0 = eine Sprungtafel liegt am Dateiende |
| 28 | 4 | Versatz der Sprungtafel, 0 = keine |

Alle Zahlen sind **little-endian**. Das ist keine Geschmacksfrage: der Zielrechner
ist x86-64, und ein Format, das dort umgedreht werden muss, kostet in jeder
Schleife Befehle.

## Eine Spurbeschreibung, 32 Oktette, direkt hinter dem Kopf

| Versatz | Groesse | Inhalt |
|---|---|---|
| 0 | 1 | Spurnummer (0..3) |
| 1 | 1 | Art: **1 = Ton**, **2 = Bild** |
| 2 | 2 | Kodierung: **1 = PCM s16le**, **2 = MJPEG**, **3 = FLAC** |
| 4 | 4 | Ton: Abtastrate in Hz · Bild: Bilder je Sekunde **mal 1000** |
| 8 | 2 | Ton: Kanaele · Bild: Breite in Bildpunkten |
| 10 | 2 | Ton: Bit je Wert · Bild: Hoehe in Bildpunkten |
| 12 | 4 | groesster Block dieser Spur in Oktetten |
| 16 | 8 | Zahl der Bloecke dieser Spur |
| 24 | 8 | reserviert, null |

`Bilder je Sekunde mal 1000` und nicht als Bruch: 23,976 fps ist 23976, und ein
Betriebssystem ohne Fliesskomma muss dafuer nichts umrechnen.

## Ein Block, 16 Oktette Kopf und dann die Nutzlast

| Versatz | Groesse | Inhalt |
|---|---|---|
| 0 | 1 | Spurnummer |
| 1 | 1 | Flags. Bit 0 = **Schluesselbild** (bei MJPEG ist jedes eines) |
| 2 | 2 | reserviert, null |
| 4 | 4 | Laenge der Nutzlast in Oktetten |
| 8 | 8 | Zeitstempel in **Mikrosekunden** seit Anfang |

Die Bloecke stehen **nach Zeitstempel geordnet** hintereinander (verschraenkt).
Ein Abspieler liest also vorwaerts und bekommt Ton und Bild in der Reihenfolge,
in der er sie braucht — genau dafuer gibt es dieses Format.

**Blockgroesse Ton:** ein Block sind 20 ms PCM (48 kHz Stereo 16 Bit = 3840
Oktette). Klein genug, dass ein Bild nie lange auf Ton wartet; gross genug, dass
der Kopf (16 Oktette) unter einem halben Prozent bleibt.

## Was diese Runde davon benutzt — und was nicht

* **Benutzt:** Kopf, Spurbeschreibungen, Bloecke der Tonspur (PCM s16le).
  `/bin/play` spielt eine `.omc`-Datei genauso wie eine `.wav`.
* **Vorgesehen, aber nicht dekodiert:** die Bildspur. `omcpack.py` schreibt sie
  (MJPEG), `/bin/play` ueberspringt sie und **zaehlt sie**, damit der Testlauf
  belegen kann, dass sie wirklich dasteht. Der JPEG-Dekodierer ist Runde VIEWER.
* **Vorgesehen, aber nicht geschrieben:** die Sprungtafel. Ohne sie gibt es kein
  Spulen. Steht in der Restliste.

## Die Uhr

Zeitstempel sind Mikrosekunden, 64 Bit. Das reicht fuer 584 000 Jahre und macht
den klassischen Fehler unmoeglich, an dem MPEG-TS leidet (33 Bit PTS, Ueberlauf
alle 26,5 Stunden).

**Der Zeitstempel ist nicht die Uhr.** Die Uhr ist `samples_played()` aus
`kernel/audio.fi` — was der Tonchip wirklich abgespielt hat. Der Zeitstempel
sagt, WANN ein Bild dazu gehoert. Warum das so herum ist und nicht andersherum,
steht in `docs/AUDIO.md`.

## Umwandeln auf dem PC

```
python3 tools/media/omcpack.py film.mp4 film.omc                 # Ton + Bild
python3 tools/media/omcpack.py lied.flac lied.omc --nur-ton      # nur Ton
python3 tools/media/omcpack.py film.mp4 f.omc --breite 854 --fps 24 --guete 5
python3 tools/media/omcpack.py --sinus 440 --dauer 2 test.omc    # Pruefton
```

Voreinstellung ist genau das Ziel aus Block F der Roadmap: **854×480 bei 24
Bildern je Sekunde, Ton 48 kHz Stereo 16 Bit.**
