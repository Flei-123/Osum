# Runde CERTUS-AUF-OSUM — der Bericht

05.09.2026 · Zweig `certus2` (Basis `merge6`) · Arbeitsbaum `/root/osum-certus`
Gegenstück im Firn-Baum: Zweig `osum` in `/root/certus-sammeln`.

**Die Frage der Runde:** läuft Certus — Justins Browser, mit dem
**aktuellen** Motor (JavaScript, Raster, Sicherheit, ~105 000 Zeilen) —
als gewöhnliches Ring-3-Programm auf Osum, mit **dessen** Widgets,
**dessen** Netz, **dessen** Adressraum, und kann man ihn aus dem Laden
installieren?

**Die Antwort:** ja. Gemessen mit `bash tools/certus/run.sh`.

---

## 1. Was gebaut wurde

| Seite | Datei | was sie ist |
| --- | --- | --- |
| Certus | `lib/fenster/osum.fi` (~640 Z.) | die **vierte** Rückwand von `lib/fenster` — nach X11, Win32, Android |
| Certus | `lib/osum/certus_main.fi` (74 Z.) | die Wurzeldatei; wählt die Rückwand über `lib/osum/fenster/rueck.fi` |
| Certus | `lib/browser/certus_app.fi` | **eine Zeile**: `/lib/sans.ttf` in der Schriftliste |
| Osum | `kernel/user/wlib.fi` | das Widget **Leinwand** (K_LEINWAND) + Ereignisring |
| Osum | `kernel/user/wlibc.fi` | Glyphenspeicher ohne `libc.mem` (`gmem`) |
| Osum | `kernel/user/sysstub.s` | die Systemruf-Tür als acht Befehlsfolgen hinter `extern fn` |
| Osum | `kernel/user/certus/entkern.py`, `bau.sh` | wlib/wlibc/ulib/libc **ohne** `asm` + der Bau von `/bin/certus` |
| Osum | `kernel/proc.fi`, `procfs.fi`, `arch/x86_64/{boot,smp,switch}.s`, `sched.fi` | Adressraum, `/proc/self`, SSE, `fxsave` |
| Osum | `tools/laden/*`, `assets/apps/certus.osp` | das Paket `certus-1.opk` im Katalog |
| Osum | `tools/certus/run.sh` | die Abnahme dieser Runde |

### Die Entscheidung: mit den Widgets, nicht daneben

Der erste Versuch (Runde CERTUS, 28.08.2026) sprach direkt mit dem
Fensterserver und hatte als Bedienleiste eine Textzeile. Diese Runde
benutzt die Widget-Bibliothek:

* **Zurück / Vor / Neu laden** sind `wlib.button`, die **Adresse** ist
  `wlib.entry` — von wlib gezeichnet, mit dessen Farbschema und Fokus.
  Die Rückwand malt in diesem Streifen keinen Bildpunkt.
* **Die Seite** steht in `wlib.leinwand` — dem Widget dieser Runde:
  Bildpunkte, die dem Aufrufer gehören, ein Ereignisring (64 Einträge,
  Bewegungen zusammengefasst), `paint_leinwand` kopiert beim
  Neuzeichnen den Ausschnitt jedes schmutzigen Streifens.
* **Und der Browserkern merkt nichts davon:** ein Druck auf „Zurück"
  wird in den Mausklick übersetzt, den Certus' eigene Leiste erzeugt
  hätte — an der Stelle, an der `chrome.chrome_treffer` `HIT_ZURUECK`
  meldet, **gesucht** statt getippt (`hit_x`). Darum kostet die vierte
  Plattform den Browserkern genau eine Zeile.

### Die harte Stelle: zwei Profile in einem Programm

`profile kernel` erlaubt `asm(...)` und verbietet `syscall`; `profile
app` hat den Sammler und `syscall`, aber kein `asm` — und das Profil
hängt an der **Wurzeldatei**. Osums Ring-3-Schicht ist `kernel`, Certus
ist `app`. Gelöst mit `kernel/user/sysstub.s` (acht Befehlsfolgen hinter
`extern fn`, das in beiden Profilen gilt) und `entkern.py`, das
mechanische Kopien **ohne** Assembler zieht und abbricht, wenn ein
Muster nicht genau einmal passt. Die 52 Programme der Platte werden
weiter aus dem Original gebaut.

**Gemessen:** `wlib` (4713 Zeilen) + `wlibc` (4759) + `ulib` (828) +
`lib/libc` übersetzen unter `profile app` mit dem aktuellen
Certus-Übersetzer; die einzigen undefinierten Namen im Objekt sind die
zehn `osum_*`-Stubs.

---

## 2. Die Zahlen

### Das Programm

| | |
| --- | ---: |
| `/bin/certus`, gebunden und gestrippt | **6 493 760** Oktette |
| `.text` | 5 788 901 |
| `.rodata` | 692 652 |
| `.data` / `.bss` | 5 272 / 108 000 |
| Ende im Adressraum | **0x4074a5e0** |
| PT_LOAD-Segmente (getrennte Rechte) | 3 |
| Segmente zugleich schreib- **und** ausführbar | **0** |
| undefinierte Namen (keine libc) | **0** |
| `syscall`-Befehle | 140 |
| Seiten, die der Lader abbildet | 1611 |

### Der Adressraum des Kerns

| | vorher | jetzt |
| --- | ---: | ---: |
| `IMAGE_END` (Abbildfenster) | 0x40400000 (3 MiB) | **0x40C00000** (11 MiB) |
| `BIG_FLOOR` (Beginn der großen Arena) | 0x40600000 | **0x40C00000** |
| `PRIV_SLOTS` / `BIG_TOP` | 6 / 0x40C00000 | **99** / **0x4C600000** (186 MiB) |

Die private Gegend erreicht 0x50000000 weiterhin **nicht** — der
Abnahmefall in `tools/osum/run.sh`, der ein Programm dort bindet und
verlangt, dass der Lader es ablehnt, bleibt gültig.

### Was auf dem Schirm steht (QEMU, 1280×1024)

| Messung | Wert |
| --- | ---: |
| WIG_BLIT: Bildpunkte aus Ring 3 ins Fenster | **3 231 744** (17 Aufrufe) |
| Leinwand: Tintenpunkte | 69 857 (26 %) |
| Leinwand: dunkle Punkte (der Text) | 8 341 |
| waagrechte Textbänder | 5 |
| Bildschirmfoto: verschiedene Farben (leer = 2) | **322** |
| `#0033aa`, der Kasten, den die Seite verlangt | vorhanden |

### JavaScript

Die Probeseite setzt `style.backgroundColor`, baut mit
`createElement`/`appendChild` einen Absatz und schreibt mit
`textContent`.

| Messung | Wert |
| --- | ---: |
| Tintenpunkte | 70 288 |
| der Kasten in **Rot** (`#cc0000`, vom Skript gesetzt) | **24 000** = 300×80, der ganze Kasten |
| noch **Blau** (`#0033aa`, die Farbe aus dem Quelltext) | **0** |
| Textbänder (mit dem vom Skript gebauten Absatz) | 4 |

**Zwei Lücken der Maschine, hier gemessen und nicht behauptet:**
`z.style.background = "…"` (die Kurzform) ließ den Kasten blau —
`style.backgroundColor` wirkt. Und `document.write` während des
Zerteilens landete nicht im Baum. Beides ist eine Lücke von `lib/js` /
`lib/browser` und **nicht** der Portierung; auf Osum läuft genau das,
was auf Linux läuft.

### Zeit

| Messung | Wert |
| --- | ---: |
| **Zeit bis Bild** (Programmstart → fertig geladen, ausgelegt, gemalt) | **11 408 / 12 829 / 11 776 / 12 842 ms** (vier Läufe) |
| Dokumenthöhe, die Certus ausgerechnet hat | 779 Bildpunkte |

**Und die Zahl, die weh tut: der ELF-Lader.** Bis das Programm
überhaupt startet, vergehen rund **160 Sekunden** — gemessen mit
Fortschrittsmarken im Lader (`elf: dbg p=…`, 6,5 MiB in etwa 2,5
Minuten, gleichmäßig). Der Grund ist nicht das Kopieren, sondern die
Zahl der **Blockzugriffe**: OFS hat 512-Oktett-Blöcke, acht direkte
Zeiger, dann einfach/zweifach/dreifach indirekt — für 12 670 Datenblöcke
kommen rund 34 000 **Indexblock**-Lesungen dazu, weil `file_block` die
Kette bei jedem Block neu läuft, und jede Lesung ist ATA-PIO mit
Warteschleife. Ein Zwischenspeicher für die zuletzt gelesenen
Indexblöcke würde die Zugriffe von ~46 000 auf ~13 000 senken, also
etwa **3,6×**. Das ist der erste Punkt der nächsten Runde.

---

## 3. Was gemessen wurde und was nicht

`bash tools/certus/run.sh` (dieser Baum, zuletzt 06.09.2026: 47 bestanden, 0 gefallen):

1. bauen + ELF-Gegenproben — **grün**
2. der Kern (Adressraum, `/proc/self`, SSE, `fxsave`) — **grün**
3. Leinwand + Ein-Kern-Regel (kein zweites Modul `mem`) — **grün**
4. Pakete, Signaturen, Katalog — **grün**
5. eine echte Seite im Fenster, von zwei Seiten fotografiert — **grün**
6. eine Seite mit JavaScript, mit der Farbe als Gegenprobe — **grün**
7. Zeit bis Bild — **12 842 ms** (Lauf vom 06.09.2026, nach der Richtigstellung unten)
8. **20 Läufe ohne Panik — 20 von 20, keine Panik, in allen zwanzig
   kam der Browser hoch.** Vier Maschinen gleichzeitig, jede ein
   Kaltstart mit eigener Platte.
9. **Installation des signierten Pakets im Gast — grün:**
   `opk: Signatur geprüft /store/certus-1.opk`, dann
   `opk: installiert certus -> 0`. Das Auspacken der 6,5 MiB dauert
   rund **neun Minuten** — dieselbe Ursache wie beim Laden (siehe
   „Zeit"), nur beim Schreiben.

**Nicht gemessen und darum nicht behauptet:** kein Lauf auf echtem
Blech, keine HTTPS-Seite aus dem offenen Netz über Osums TLS (der
Ladenweg über das Internet bleibt `tools/laden/run.sh`), keine
Größenänderung des Fensters (G2), kein Systemtext (G1), kein
hell/dunkel vom System (G3).

---

## 4. Die nächsten drei Schritte, nach Nutzen sortiert

1. **Indexblock-Zwischenspeicher in `kernel/fs.fi`** — 3,6× schnellerer
   Programmstart, und er hilft jedem großen Programm, nicht nur diesem.
2. **Ein Deskriptor am Fenster.** `WM_EVENT` ist ein Abholen, kein
   Warten; jede GUI-Anwendung dreht deshalb eine Schleife. Das steht
   seit Runde CERTUS in `docs/CERTUS-STATUS.md` und gilt weiter.
3. **Die Adresszeile im Fenster wirklich bedienen** — die Widgets sind
   da, der Weg (Klick auf `HIT_ADRESSE`, tippen, Enter) ist gebaut; was
   fehlt, ist ein Abnahmefall, der über QEMUs Monitor tippt
   (`tools/laden/tippen.py` kann das bereits).

---

## 5. Richtigstellung vom 06.09.2026 — ein zweiter `fxsave` war einer zu viel

Die erste Fassung dieser Runde hat SSE für Ring 3 selbst eingeschaltet
(`boot.s`, `smp.s`) und die `xmm`-Register in `context_switch`
(`switch.s`) von Hand mit `fxsave`/`fxrstor` unter den Registerrahmen
gelegt; `sched.frame_build` bekam dafür 528 Oktette mehr.

**Das war doppelt gebaut.** Runde AVX hat beides längst:
`kernel/arch/x86_64/fpu.fi` schaltet CR4.OSFXSR/OSXMMEXCPT/OSXSAVE
(`fpu.apply`, auf jedem AP `fpu.apply_here`) und `sched.fi` rettet den
Vektorzustand bei jedem Wechsel mit `fpu.switch` in einen eigenen
Rahmen je Aufgabe — XSAVE, nicht nur FXSAVE.

**Der Schaden, gemessen:** `bash tools/avx/run.sh avx` ging von grün auf
**24 bestanden / 8 gefallen**; die Meldungen `vec: clean=1` und
`vecsmp: clean=1` blieben aus. Ursache: der handgeschriebene
`fxrstor` schrieb die unteren Hälften der Vektorregister aus dem
Kernstapel zurück, NACHDEM `fpu.switch` den vollen Zustand schon
richtig geladen hatte — die oberen Hälften der `ymm`-Register passten
danach nicht mehr zu den unteren. Ein Rechenfehler, kein Absturz: genau
die Sorte, die niemand hier suchen würde.

**Behoben:** `kernel/sched.fi`, `switch.s`, `boot.s`, `smp.s` stehen
wieder wortgleich auf dem Stand der Basis (`2aa3f59`). Der Kernel-Diff
dieser Runde ist damit auf `proc.fi`, `procfs.fi`, `user/opk.fi`,
`user/wlib.fi`, `user/wlibc.fi` und die neuen Dateien unter
`kernel/user/certus/` geschrumpft. Nachgemessen, alles auf diesem Baum:

| Läufer | vorher | jetzt |
| --- | ---: | ---: |
| `tools/avx/run.sh avx` | 24 / **8** | **32 / 0** |
| `tools/certus/run.sh` | 47 / 0 | **47 / 0** (12 842 ms, 20 Läufe ohne Panik) |
| 4er-Raster, `tools/design/runde.sh` + `messen.py`, 5 Ansichten | — | **767 von 820 = 93,5 %** (Auflage ≥ 92 %) |
| `tools/userland/run.sh` | — | **91 / 0** |

**Eine Warnung für die nächste Runde:** zwei Läufer GLEICHZEITIG im
selben Arbeitsbaum sind wertlos. Sie patchen für ihre Gegenproben
dieselben Quelldateien und bauen in dasselbe Verzeichnis; so gemessen
kam `tools/userland/run.sh` auf 77 / 11 und einzeln gefahren auf
**91 / 0**. Wer parallel messen will, braucht je Läufer einen eigenen
`git worktree`.

**Und ein rotes Ergebnis, das NICHT von dieser Runde kommt:**
`tools/gfx/run.sh` meldet auf diesem Baum **46 / 30**. Derselbe Läufer
in einem frisch ausgecheckten Baum der **Basis** (`git worktree add
--detach /root/cbase2 2aa3f59`) meldet **dieselben 46 / 30**, mit
denselben Zeilen (`fb.WIN_LIST ist ''`, `'fb: hold' fehlt`, fehlende
`pat.ppm`). Der Abschnitt ist auf `merge6` vorbestehend rot; diese Runde
fasst `kernel/fb.fi`, `gfx.fi`, `kgui.fi`, `wig.fi` und `ttf.fi` mit
keiner Zeile an (`git diff 2aa3f59 -- kernel/fb.fi` ist leer).

Die Abnahme dieser Runde prüft seither nicht mehr `grep fxsave
switch.s`, sondern den Weg, der wirklich trägt: `CR4_OSFXSR` in
`fpu.fi`, `fpu.apply_here` in `kmain.fi`, `fpu.switch` in `sched.fi`
(`tools/certus/run.sh`, Abschnitt 2).
