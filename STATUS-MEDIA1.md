<!-- SPDX-License-Identifier: GPL-2.0-only -->
# STATUS-MEDIA1 — der Ton

Zweig `media1` von `mergeline` (6b602af). **Nicht nach main mergen.**
Arbeitsordner: `/root/media1-osum` (siehe „Ein Hinweis zum Arbeitsordner“ ganz unten).

Auftrag: Block F, Schritte **F1–F3** — AC97-Treiber, Tonschicht, WAV-Wiedergabe,
eigenes Behälterformat, Systemklänge. **Video kommt danach.**

---

## 1. Was jetzt da ist

| Stück | Datei | Zeilen |
|---|---|---|
| AC97-Treiber (PCI, Mischer, BDL-Ring, Abspielposition) | `kernel/ac97.fi` | 841 |
| Tonschicht — **die Grenze, die HDA bedienen muss** | `kernel/audio.fi` | 785 |
| Drei Systemaufrufe (1840–1842) | in `kernel/sys.fi` | +263 |
| Abspieler WAV + OMC | `kernel/user/play.fi` | 585 |
| Leser des eigenen Behälters | `kernel/user/omc.fi` | 305 |
| Lautstärkeregler | `kernel/user/vol.fi` | 292 |
| Reiter „Ton“ | in `kernel/user/einstellungen.fi` | +150 |
| Systemklang bei jeder Fehlermeldung | in `kernel/user/ulib.fi` | +40 |
| Behälterformat, beschrieben | `docs/CONTAINER.md` | 110 |
| **Die Treibergrenze, festgeschrieben** | `docs/AUDIO.md` | 190 |
| Umwandler auf dem PC (ffmpeg) | `tools/media/omcpack.py` | 250 |
| Abnahme | `tools/media1/run.sh` + 2 Prüfer | 560 |

**Zusammen rund 4400 Zeilen**, davon 1626 im Kern. Der Fahrplan veranschlagte für
den AC97-Treiber 300–600 Zeilen; 841 sind es geworden, weil die Abspielposition,
die Aussetzerzählung und die Begründungen mit drin stehen.

---

## 2. Die Zahlen — gemessen, nicht behauptet

Alles unten kommt aus `tools/media1/run.sh` (QEMU 7.2, `-accel kvm`,
`-audiodev wav`, AMD EPYC 7571). **150 Zusagen, 149 gruen, 1 rot** (der rote Punkt
steht in Abschnitt 7 dieses Berichts, mit Namen und Zahl).

### Der Ton selbst

| Zusage | gemessen |
|---|---|
| FFT-Spitze eines 440-Hz-Sinus | **440,000 Hz** (Fehler 0 mHz) |
| dasselbe über 5 Sekunden | **440,000 Hz** |
| THD+N gegen den Grundton | **−93,2 dB** |
| Gleichanteil | **−0,001** von 32768 |
| Aussteuerung | genau die verlangte (24000) |
| beide Kanäle | Wert für Wert gleich |
| **Bitgleichheit** gegen die Rechnung des Wirts | **alle 48000 Rahmen exakt, maxdiff 0** |
| Länge der Datei | **48000 Rahmen, Fehler 0** |
| Aussetzer / Nullstrecken | **0 / 0** (1 s und 5 s) |
| Rückschritte der Position | **0** |

Der Bitvergleich ist die stärkste Zusage der Runde: `tools/media1/refsine.py`
rechnet dieselbe Festkomma-Reihe auf dem Wirt nach, und **jeder einzelne der 96000
Werte** in der Datei stimmt. Damit ist der ganze Weg — Erzeugung → Ringpuffer →
Deskriptorliste → DMA → Mischer → Datei — **rechnungsfrei**.

### Die Verzögerung

| Größe | Wert |
|---|---|
| ein Deskriptor-Eintrag | 128 Rahmen = **2,666 ms** |
| Ring (32 Einträge) | 4096 Rahmen = **85,333 ms** |
| Vorlauf vor dem Anfahren | 24 Einträge = **64,0 ms** |
| Stille beim Auffüllen am Dateiende | höchstens **2,64 ms** |

### Die Uhr (`samples_played`) — drei Uhren, zwei Längen

Aus **zwei** Messlängen lassen sich fester Versatz und Gangfehler **trennen**; eine
einzelne Messung kann das nicht.

| Größe | Wert |
|---|---|
| roher Unterschied über **1 s** | **1 bis 8 ms** |
| roher Unterschied über **5 s** | **1 bis 3 ms** |
| Gangfehler aus beiden Längen | **−427 bis −2695 ppm** |
| fester Versatz | **+1 bis +10 ms** |
| Ton gegen Zeitgeber (100 Hz, unabhängig) | **1549 bis 3096 ppm** bei 2039 ppm Körnung |
| Monotonie | **0 Rückschritte** in jedem Lauf |

Jede zeitkritische Messung wird **dreimal** genommen und der **kleinste** Wert gilt.
Das ist keine Rosinenpickerei, sondern die Bauart des Fehlers: ein Stillstand der
Gastmaschine (der Bauserver trug an diesem Tag zwanzig gleichzeitige Abnahmen)
macht die gemessene **Zeit** größer, niemals kleiner — die Tonuhr läuft derweil
unbeirrt weiter. Der Fehler ist **einseitig**, also ist das Minimum die beste
Schätzung. Alle drei Versuche stehen im Protokoll.

**Der Versatz ist kein Fehler.** `CIV`/`PICB` zählen, was der Regler **geholt** hat,
nicht was der Lautsprecher gesagt hat; dazwischen liegt der FIFO. Die Recherche hat
genau das vorhergesagt („konstanter Offset, kein Drift — einmalig messen und
abziehen“). Der Videopfad zieht ihn ab, dann stimmt es.

### Die Gegenproben — ohne sie beweist das Obige nichts

| Gegenprobe | Zusage | gemessen |
|---|---|---|
| `noaudio` | die Datei bleibt leer | **0 Rahmen** |
| `audnomix` | gleich lang, aber still | **54555 Rahmen, silent=1** |
| `audhalf` | QEMUs Mischerkurve, vorher gerechnet | erwartet 509804 ppm, **gemessen 509803** |
| `audstarve` | Aussetzer werden wirklich gezählt | **1 Aussetzer, 1 DCH** |
| `nosounds` | Fehlermeldung bleibt still | **0 Rahmen** |
| ohne `audio` | kein Oktett Ton, alles wie vorher | **0 Rahmen** |

Die Gegenprobe `audnomix` trennt zwei Fehler, die beide nach Stille klingen: „der
DMA läuft nicht“ und „der Mischer sperrt“.

### /bin/play und der Behälter

| Zusage | gemessen |
|---|---|
| Datei, die in einen Ring passt (4000 Rahmen) | **bitgleich, maxdiff 0, 0 Aussetzer** |
| dieselbe Datei als `.omc` | **bitgleich, maxdiff 0, 0 Aussetzer** |
| Kopf gelesen (`play -i`) | 48000 / 2 / 16 / 24000 Rahmen |
| lange Datei (24000 Rahmen, 6× der Ring) | alle Rahmen geschrieben, **5–6 Aussetzer unter Last 16** |

### Lautstärke und Klänge

`/bin/vol 40` setzt und schreibt `/etc/audio.conf`; der Systemklang bei einer echten
Fehlermeldung (`cat /gibtsnicht`) steht messbar in der Datei (4320 Rahmen = 90 ms),
und mit `nosounds` bleibt sie leer.

---

## 3. Vier Fehler, die diese Runde gemacht und gemessen hat

Sie stehen hier, weil sie auf echter Hardware genauso auftreten.

1. **Der laufende Index zählt immer bis 32.** Die erste Fassung hatte 8 Einträge zu
   512 Rahmen und rechnete `CIV % 8`. Der Regler lief durch 24 nie beschriebene
   Einträge der Länge null, die Umlaufzählung explodierte.
   *Gemessen: 48128 Rahmen geschrieben, **12288** in der Datei.*
   Behoben: 32 Einträge zu 128 Rahmen, kein Modulo mehr nötig.

2. **Das Vorzeichenbit einer 32-Bit-Phase in einem 64-Bit-Wort.** `(phase >> 31) != 0`
   ist nicht „sin ist negativ“, sondern „die Phase war einmal über 2³¹“ — und das ist
   sie nach 55 Rahmen für immer.
   *Gemessen: gleichgerichteter Sinus, FFT fand **880 Hz** statt 440, Gleichanteil
   −15243.* Behoben durch ein `& 1`.

3. **Der Vorlauf muss größer sein als der Ausgabepuffer der Hardware.** Der Regler
   holt im Voraus (FIFO bzw. QEMU-Mischer, 46 ms). Steht weniger im Ring, ist er nach
   einem Wimpernschlag leer.
   *Gemessen: mit 21 ms Vorlauf **24 Aussetzer bei 24 Schreibvorgängen**, 24000 Rahmen
   Ton auf 111209 Rahmen Datei verteilt; mit 64 ms Vorlauf 0–5.*

4. **„Alles geholt“ ist nicht „alles gehört“.** `/bin/play` schaltete den Lauf ab,
   sobald `A_REMAIN` null war.
   *Gemessen: **331 von 4000 Rahmen** fehlten am Dateiende.* Behoben durch eine
   Nachfrist von 150 ms — dieselbe, die der Kernpfad schon hatte.

5. **`read` darf weniger liefern als verlangt.** `omc.read_payload` nahm das Ergebnis
   **eines** Aufrufs und übersprang den Rest als „nicht gelesen“. Aus einem Block von
   3840 Oktetten wurden 3584, und die Tonspur war ab da um einen Rahmen verschoben.
   *Gemessen: `maxdiff 1727` — genau der Abstand zweier benachbarter Werte eines
   660-Hz-Sinus bei dieser Aussteuerung.* Und er trat **nur auf einer bestimmten
   Belegung der Platte** auf: auf einer anderen lagen die Blockgrenzen anders.
   Ein Fehler, der von der Belegung der Platte abhängt, ist der unangenehmste, den es
   gibt — und drei Wiederholungen haben ihn nicht weggedrückt, sondern
   **festgenagelt**. Behoben durch eine Leseschleife.

---

## 3a. Der eine rote Punkt, der offen bleibt

`tools/media1/run.sh`, Abschnitt 8: **„auch aus dem eigenen Behälter kommt die Datei
BITGLEICH heraus“ — `cmp_exact = 0, maxdiff 1727`**, drei Anläufe hintereinander.

Was gesichert ist:

* Die Leseschleife aus Punkt 5 oben ist drin und behebt **eine** Ursache dieses
  Bildes. Danach ist derselbe Fall **einzeln aufgebaut viermal hintereinander
  bitgleich** (zwei Läufe vor und zwei nach dem Nachbau der Platte mit genau den
  Dateien und Programmen, die auch der Läufer schreibt).
* Im vollen Läufer bleibt er rot, mit **immer derselben Zahl** (1727 = ein Rahmen
  Versatz bei 660 Hz). Also **kein** Lastflattern, sondern ein zweiter, noch nicht
  gefundener Auslöser.
* Der WAV-Weg über dieselbe Strecke ist im selben Lauf **bitgleich** (`cmp_exact = 1`),
  ebenso der Kernpfad. Die Tonspur ist **vollständig** (4000 Rahmen ungleich null),
  fängt **sofort** an (`loud_first = 1`) und hat **keine Lücke** (`gaps = 0`).

Es ist also ein Versatz um einen Rahmen im Behälter-Weg unter noch unbekannter
Bedingung — hörbar wäre er nicht, richtig ist er trotzdem nicht. **Er wird nicht
weggeschrieben und nicht entschärft; die Zusage bleibt rot, bis die Ursache
gefunden ist.** Das ist der erste Punkt der nächsten Runde.

## 4. Was für VIDEO noch fehlt (Block F, Schritte F5–F7)

1. **Ein Baseline-JPEG-Dekodierer.** 1500–3000 Zeilen: Huffman, Dequantisierung,
   8×8-IDCT (Loeffler/AAN), Chroma-Upsampling, YCbCr→RGB, Restart-Marker. Das ist
   Runde VIEWER und zugleich F5.
2. **Write-Combining auf den Rahmenpuffer (MTRR oder PAT).** Ohne das ist der Puffer
   uncached und liefert 30–100 MB/s; 720p30 braucht 110 MB/s. **Pflicht, keine
   Optimierung.**
3. **Die Präsentationsschleife.** Sie ist konzeptionell fertig (Ton ist die Leituhr,
   Bild auslassen oder wiederholen, nie blockierend warten) und in `docs/AUDIO.md`
   festgehalten — geschrieben ist sie nicht.
4. **Der konstante A/V-Versatz.** Er ist gemessen (9–11 ms) und muss vom Videopfad
   abgezogen werden.
5. **Vorlaufpuffer für Bilder**, 3–5 dekodierte Bilder.
6. **Kein echtes Vsync.** Ohne GPU-Treiber gibt es keinen Vblank; Tearing ist
   einzuplanen, Rückpuffer plus schneller Blit mildert es.
7. **Die Sprungtafel des Behälters.** Vorgesehen, nicht geschrieben — ohne sie kein
   Spulen.
8. **Bildspur in `/bin/play`:** wird gelesen, gezählt und übersprungen. `omcpack.py`
   schreibt sie (MJPEG) bereits.

**Nicht angefangen und bewusst nicht:** AV1 (80k+ Zeilen), VP9 (30–50k), Opus
(12–25k), H.264 (Patente bis 29.11.2027, danach 6–18 Monate Vollzeit).

---

## 5. Was für ECHTE HARDWARE noch fehlt

1. **Intel HDA** — der eigentliche Punkt. 1000–2000 Zeilen, Trefferquote 70–85 %, der
   Schmerz ist die Codec-Topologie je Hersteller. Die Schicht darüber bleibt
   unverändert; welche neun Funktionen zu füllen sind, steht in `docs/AUDIO.md`.
2. **Unterbrechungsbetrieb.** `IOCE`/`LVBIE` sind aus, weil kein Vektor auf der
   Leitung liegt. Ohne sie braucht Wiedergabe einen laufenden Prozess.
   `ac97.irq` ist geschrieben und wartet auf den Vektor.
3. **AC97 auf echtem Blech:** ins PCM-Register gehört dort `0x0808` (0 dB) statt
   `0x0000` (+12 dB); QEMU kennt die Verstärkung nicht. Steht in `docs/AUDIO.md`.
4. **Kein Mischer** — ein Strom zur Zeit. Braucht A3 (Systembus mit Rechten).
5. **Keine Aufnahme.**
6. **Umrechnung der Abtastrate** ist linear (Q16), kein Sinc-Fenster: bei 44 100 →
   48 000 bleiben Spiegelfrequenzen.
7. **`/etc/audio.conf` wird beim Start nicht angewandt** — `vol laden` tut es, aber
   kein Dienst ruft es. Gehört zu A2 (init).

---

## 6. Was diese Runde bewusst NICHT getan hat

* **Kein `/dev/audio`.** Der Weg über die drei Aufrufe ist gebaut und gemessen; ein
  Geräteknoten wäre eine zweite Tür in dieselbe Schicht. Er kostet später wenige
  Zeilen in `devfs.fi` und `sys.do_write`.
* **Keine Lautstärkekachel in der Schnelleinstellung.** Deren Anordnung wird von
  `tools/netview/kachel.py` an Bildschirmfotos vermessen; eine vierte Kachel hätte
  eine fremde Abnahme angefasst. Der Regler steht stattdessen im Reiter „Ton“ und in
  `/bin/vol`.
* **Keine Wiedergabeliste, kein Spulen, keine Untertitel.** Das ist „wie VLC“ auf der
  Bedienseite und gehört in die Runde, die die Oberfläche baut.

---

## Ein Hinweis zum Arbeitsordner

Der Auftrag nannte `/root/mg-osum`. Während dieser Runde hat dort eine **zweite**
Runde (`certus`) denselben Arbeitsordner übernommen und den Zweig gewechselt; der
erste Commit dieser Runde ist dadurch im Zweig `certus` gelandet
(`4d8730c`, inhaltlich identisch mit `dda4b76` hier). Ab da läuft MEDIA1 in einem
**eigenen** Arbeitsordner `/root/media1-osum` auf dem Zweig `media1`, sauber von
`mergeline` abgezweigt. Wer `certus` verschmilzt, bekommt denselben Inhalt zweimal —
er ist Datei für Datei gleich, also verschmilzt er ohne Konflikt.
