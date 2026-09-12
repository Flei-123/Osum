# RUNDE SCHNELLBILD — der Bildweg für 3440x1440

**Frage:** Wird der Bildweg schnell genug für Justins 3440x1440 — durch
Speicher-Mapping und Zeichenstrategie, ohne GPU-Treiber?

**Kurze Antwort:** Ja, und der Engpass war ein anderer als vermutet.
Der Rahmenpuffer war **nie uncached** — Write-Combining steht seit Runde
ZWISCHENSPEICHER und ist hier zum ersten Mal *aus der Seitentafel selbst
zurückgelesen* worden. Das Vollbild bei 3440x1440 kostet **3,5 ms**
(Ziel: unter 16,7 ms). Der wirkliche Engpass war das **Alpha-Mischen**:
40mal so teuer wie das Füllen. Mit SSE2 ist es **30,5mal schneller** —
und dabei kam heraus, dass die Vektoreinheit beim ersten Bild noch gar
nicht eingeschaltet war.

---

## 0. Aufbau der Messung

| | |
|---|---|
| Zweig | `schnellbild` von `merge8` @ c0f7151, Arbeitsbaum `/root/osum-schnellbild` |
| Maschine | `qemu-system-x86_64 -accel kvm -cpu host -m 2048 -smp 2` |
| Grafik | `-device VGA,vgamem_mb=32,xmax=4096,ymax=2160` |
| Auflösung | Kernwort `fbres=BxH` (`docs/SCHIRM.md`) |
| Zeitbasis | TSC über `apic.tsc()` / `apic.tsc_hz()`, wie `fbbench` |
| Werkzeuge | `/tmp/sb-mess/lauf.sh` (Kern-Prüfstand), `desk.sh` (echter Schreibtisch + Foto) |

**3440x1440 braucht `vgamem_mb=32`.** Mit der QEMU-Vorgabe (16 MB) meldet
der Kern `fb: nat=0x0 why=0` und `fb: kein Rahmenpuffer` — 3440·1440·4 =
**19,8 MB** passen nicht in 16 MB Grafikspeicher. Das ist eine Grenze des
Prüfstands, kein Fehler in Osum; auf Blech kommt der Puffer von der GOP.

---

## 1. Die Hypothese aus FREMDSOFTWARE.md 4a — WIDERLEGT

Die Vorlage erwartet: *„wenn der Framebuffer uncached (UC) gemappt ist,
kommen 50–200 MB/s raus"*. **Das ist bei Osum nicht der Fall**, und das
ist jetzt gemessen statt geglaubt:

```
durchsatz:   pde=0xfc2010e3  pat=0x7040100070406  wc=1  uc=0
```

* `pde=…10e3` — **Bit 12 gesetzt** = die PAT-Stelle, also Write-Combining.
  (`00E3` wäre Write-Back, `00FB` uncached.)
* `pat=0x…0100070406` — Stelle 4 des MSR ist **01** = WC. Ohne diese
  zweite Zahl wäre das Bit oben wirkungslos.

`fb.pde_roh`/`fb.pat_roh` gab es seit Runde BLECHZWEI; **niemand hat sie
je in einer Durchsatzmessung ausgegeben.** Genau das tut `durchsatz` jetzt.

### Die Gegenprobe, die die Messung erst zu einer macht

Mit `fbuc` (uncached erzwungen), 1920x1080, **dieselbe Maschine**:

| | `pde` | `flush` je Vollbild | `line` |
|---|---|---|---|
| WC (Vorgabe) | `0xfd0010e3` | **1 379 µs** | 236 µs |
| UC (`fbuc`) | `0xfd0000fb` | **129 058 µs** | 1 515 µs |

**Faktor 94.** Die UC-Zahl (8,29 MB / 129 ms = **64 MB/s**) liegt exakt im
Band, das die Vorlage für UC nennt (50–200 MB/s). Der Prüfstand misst also
richtig — der Rahmenpuffer steht nur eben nicht so.

---

## 2. Durchsatz und Vollbildzeit, je Auflösung

Reiner Schreibweg in den Zeichenpuffer (`rep stosq`, 5 Durchgänge):

| Auflösung | Oktette | µs | MB/s | fps-Obergrenze |
|---|---|---|---|---|
| 1280x800 | 4 096 000 | 179 | **22 882** | 5 586 |
| 1920x1080 | 8 294 400 | 737 | **11 254** | 1 356 |
| 2560x1440 | 14 745 600 | 1 599 | **9 221** | 625 |
| **3440x1440** | 19 814 400 | 2 357 | **8 406** | **424** |

Die Übertragung Zweitpuffer → Karte (`fbbench: buffered flush`):

| Auflösung | flush | fps daraus | Ziel 16,7 ms |
|---|---|---|---|
| 1280x800 | 390 µs | 2 564 | **erfüllt** |
| 1920x1080 | 1 379 µs | 725 | **erfüllt** |
| **3440x1440** | **3 523 µs** | **284** | **erfüllt, Faktor 4,7 Luft** |

**Das Ziel „Vollbild-Neuzeichnen bei 3440x1440 unter 16,7 ms" ist mit
3,5 ms erreicht.** Der Streifenbetrieb (`streifen=1`, zehn 2-MiB-Kacheln
durch ein Fenster) kostet dabei nichts Auffälliges.

---

## 3. Der wirkliche Engpass: das Alpha-Mischen

`paintbench` stellt Füllen und Mischen nebeneinander, in Takten je
Bildpunkt (Tausendstel):

| Auflösung | `fill` | `fill_a` | Faktor |
|---|---|---|---|
| 1280x800 | 442 | 53 929 | **122** |
| 1920x1080 | 849 | 53 788 | **63** |
| 3440x1440 | 1 602 | 62 479 | **39** |

Ein gemischter Bildpunkt kostete das **39- bis 122fache** eines
gefüllten. Das ist der Engpass — nicht die Abbildung.

### SSE2: vier Bildpunkte je Durchgang

`fb.hline_a_simd` entfaltet mit `punpcklbw`/`punpckhbw` vier Punkte auf
16 Bit, mischt mit `pmullw` und ersetzt die Division durch 255 durch
`(t + (t>>8)) >> 8` — exakt für alle 16,7 Mio Tripel, und SSE2 hat keine
Ganzzahldivision.

**GEMESSEN, 3440x1440, dieselbe Maschine:**

| | `fill_a` je Punkt | `simd_px` |
|---|---|---|
| `fbnosimd` (skalar) | 57 902 | 0 |
| SSE2 | **1 897** | 19 814 400 |

**Faktor 30,5** — deutlich über den 4–8, die die Vorlage nennt.

---

## 4. Zwei Funde, die die Laufzeit allein NICHT gezeigt hätte

### 4a. Die erste Messung war Rauschen — der Zähler hat es aufgedeckt

Die erste SSE2-Fassung maß `faktor=19951/1000` gegen `38470/1000` und sah
nach **Faktor 1,9** aus. Sie war in Wahrheit **nie gelaufen**:
`simd_px=0`. Eine Laufzeit allein kann nicht zwischen *„der schnelle Weg
bringt nichts"* und *„der schnelle Weg läuft nicht"* unterscheiden.
Ohne den Zähler wäre die 1,9 als Ergebnis in diesen Bericht gewandert.

### 4b. Die Vektoreinheit war beim ersten Bild noch aus

`fpu.apply` stand in `kmain` Abschnitt **3b**, `gfx.stage_graphics` steht
in **3c**. Also lief **jedes Mischen während des Hochlaufs skalar** —
Messtafel, `paintbench`, der ganze Bildaufbau vor dem Planer — obwohl
`fpu: mode=3` im selben Mitschnitt steht. `fpu.apply` ist mehrfach
aufrufbar und steht jetzt **zusätzlich** vor dem ersten Bild; der spätere
Aufruf vor `sched.init` bleibt, wo er ist.

### 4c. Die Schleife gehört in den asm-Block

Ein eigener `asm`-Block je vier Bildpunkte kostet mehr Rahmen
(Registerbelegung, Speicherbarriere, Schleifenprüfung in Firn) als er
Rechnung spart. Mit `dec rcx / jnz` **innerhalb** des Blocks fällt das weg.

---

## 5. Wo aus dem Rahmenpuffer GELESEN wird (Schritt 3 des Auftrags)

Gesucht wurde jede Stelle, die aus dem Rahmenpuffer liest — WC/UC-Reads
sind katastrophal langsam. **Befund: der Zeichenweg liest nie von der
Karte, solange es einen Zweitpuffer gibt.**

| Stelle | liest aus | Bewertung |
|---|---|---|
| `fb.hline_a`, `hline_mask`, `pixel_a` (Mischen) | `S_DRAW` | **unkritisch mit Zweitpuffer** — `S_DRAW` = `S_BACK` = Arbeitsspeicher |
| `fb.get_pixel` | `S_DRAW` | dito |
| `fb.front_pixel` | `S_ADDR` (Karte) | **liest wirklich von der Karte** — nur für die Zerreißprobe, nicht im Zeichenweg |
| `fb.flush`/`flush_rect`/`flush_stripe` | Rest-Oktette per `__mmio_read32` aus dem **Zweitpuffer** | unkritisch |

**Die Ausnahme, und sie ist gemessen:** ohne Zweitpuffer (`nodbl`) zeigt
`S_DRAW` in die Karte, und dann ist jedes Mischen ein Lesezugriff über
PCI. Genau das misst `fbbench: direct` bei 1920x1080 UC mit
`fill=167 905 µs` gegen `816 µs` gepuffert — **Faktor 205**.
Der Kern zählt diese Rücklesevorgänge bereits getrennt (`blend_reads`).

---

## 6. Dirty-Rects: wie viel wird wirklich übertragen

`wm.present` gibt die übertragene Fläche seit Runde VSYNC zurück — sie
wurde nur nie aufsummiert. `S_PXSUM` tut das jetzt.

Gemessen am **echten Schreibtisch** (Wurzelabbild, 25 s Laufzeit):

| Auflösung | je Anstrich | Anteil am Schirm |
|---|---|---|
| 1920x1080 | 223 388 Punkte | **10,77 %** |
| 3440x1440 | 365 760 Punkte | **7,38 %** |

**Nicht die 1–5 % der Vorlage, aber weit weg von 100 %.** Der Grund steht
in den Einzelzahlen: der Schreibtischhintergrund (`id=8`) meldet je
Anstrich die volle Fläche (377 444 bzw. 689 541 Punkte) — ein Hintergrund,
der neu gemalt wird, wird ganz neu gemalt. Die kleinen Fenster liegen mit
52 000–74 000 Punkten genau dort, wo die Vorlage sie erwartet.

Zeilenweises Kopieren in `fb.flush` ist **nicht** mehr der Normalfall:
`wm.present` ruft `fb.flush_rect` mit dem Schmutzrechteck (wm.fi:3829,
Runde VSYNC, bereits in merge8) — also nur die wirklich schmutzigen
Spalten, nicht die ganze Bildbreite.

---

## 7. Das Bild ist noch richtig

Ein schnelles falsches Bild ist wertlos. Drei Gegenproben:

**7a. SIMD gegen skalar, Bildpunkt für Bildpunkt.** Derselbe Schreibtisch,
einmal mit und einmal ohne `fbnosimd`, 1920x1080:

* **unterhalb der Messtafel (ab Zeile 346): 0 von 1 409 280 Bildpunkten
  verschieden — 0,0000 %.** Byte für Byte dasselbe Bild.
* Die 2 916 abweichenden Punkte liegen **alle** in Zeile 8–345, und
  `fb: band=388` sagt warum: das ist die Messtafel mit den laufenden
  Zählern (`TAKT IRQ 85 MAL 9`), die sich zwischen zwei Läufen
  zwangsläufig unterscheiden.

**7b. Echter Text, mit `searchtext.py` gegen den Zeichensatz gerechnet:**

| Lauf | Text | Treffer |
|---|---|---|
| SIMD, 1920x1080 | „kein Netz" | **100 %** der 63 Tintenpunkte, 100 % der 234 Gegenpunkte |
| skalar, 1920x1080 | „kein Netz" | **100 %** — identische Lage x=1686, Grundlinie 1065 |
| SIMD, 1920x1080 | „08.09.26" | **100 %** der 88 Tintenpunkte |
| skalar, 1920x1080 | „08.09.26" | **100 %** — identische Lage x=1846 |
| **SIMD, 3440x1440** | „kein Netz" | **100 %** der 571 Tintenpunkte (px=30, `skala x2`) |

**7c. Die Selbsttests des Kerns:** `fb: selftest 13/13 failed=0x0` und
`paint: selftest 14 of 14 ok` in **jedem** Lauf, mit und ohne SIMD.

---

## 8. Kein Rückschritt

| Läufer | vorher | nachher |
|---|---|---|
| `tools/avx/run.sh` | 32 passed, 0 failed | **32 passed, 0 failed** |
| `tools/gfx/run.sh` | 76 passed, 0 failed | **76 passed, 0 failed** |
| `tools/wm/run.sh` | 104 passed, 0 failed | **104 passed, 0 failed** |

`tools/schirm/run.sh` **gibt es nicht** (im Auftrag genannt, im Baum nicht
vorhanden) — die Auflösungsfragen deckt `tools/gfx/run.sh` ab.

**Der `fxsave`-Regress ist nicht zurück.** `tools/avx/run.sh` Abschnitt 1
verlangt, dass im Kern keine Vektoranweisung außerhalb der Probe steht;
`fb__hline_a_simd` ist dort **einzeln und mit Begründung** aufgenommen:
der Aufrufer klammert sie in `arch.irq_save`/`irq_restore`, also findet
während der Schleife kein Wechsel statt, und nach `irq_restore` hält die
Funktion keinen Vektorzustand. Eine **weitere** Kernfunktion mit
Vektoranweisungen fällt wieder rot aus — und soll es.

---

## 9. Was nur am Blech prüfbar ist — die Tafelzeile zum Fotografieren

Die Messtafel zeigt die Abbildung bereits (`FB WC` in Zeile 9). Am Blech
ist zusätzlich zu prüfen, was QEMU nicht hergibt:

```
tafel: 9 EICH   LSR 60 PIT 2202 PM 2199 ABW 0 FB WC
```

| Frage | am Blech zu prüfen | erwartet |
|---|---|---|
| Steht WC auch auf der echten Karte? | `FB WC` in Tafelzeile 9 | `WC`, nicht `WB`/`UC` |
| Sind die echten MTRR-Bereiche im Weg? | `pde=` endet auf `10e3` | Bit 12 gesetzt |
| GOP statt VBE? | `src=` in der `fb:`-Startzeile | `src=mb` (vom Lader) |
| Zeilenbreite ≠ Breite·4? | `pitch=` gegen Breite·4 | GOP meldet für 3440 gern 3456 |
| Streifenbetrieb? | `streifen=` | `1` bei 3440x1440 (19,8 MB > 8·2 MiB) |

Der Punkt „Zeilenbreite" ist kein theoretischer: `fbpad=<n>` gibt es im
Kern genau deshalb (Runde VIELKERN), weil Justin bei 3440x1440 fehlende
erste Zeichen je Zeile berichtet hat.

---

## 10. Was offen blieb

* **Non-temporal Stores (`movntdq`) sind NICHT gebaut.** Bei 3,5 ms
  Vollbild gegen 16,7 ms Ziel gab es dafür keinen Anlass; die Messung
  hätte den Gewinn im Rauschen versenkt. Der Platz dafür ist
  `fb.copy_words`/`fill_words`.
* **AVX2 ist nicht gebaut**, nur SSE2. Grund: SSE2 ist auf x86-64
  garantiert, AVX2 nicht — und die Maschine im Prüfstand meldet
  `sup=0x7` (kein AVX-512). Bei Faktor 30,5 mit SSE2 ist der Bedarf
  gering.
* **Der Dirty-Anteil liegt bei 7–11 %, nicht bei 1–5 %.** Der
  Schreibtischhintergrund malt sich ganz neu. Ob das lohnt zu ändern,
  ist eine eigene Runde — bei 3,5 ms Vollbild ist es kein Engpass.
* **Alles hier ist in QEMU gemessen.** Abschnitt 9 sagt, was am Blech
  nachzuziehen ist.
