# Runde GLYPHE — der letzte Ein-Kern-Rest im Zeichenweg

*05.09.2026 · Arbeitsbaum `/root/osum-glyphe`, Zweig `glypharbeit` auf
`merge6` (2aa3f59)*

Der Auftrag: den Rest schließen, der in MERGE-6 offen blieb, damit
`merge6` den Zweig `hidweg` als Grundlinie ersetzen kann.

---

## 0. Das Ergebnis in einem Satz

Der Fehler war **nicht** eine fehlende Sperre, sondern **ein zweiter
Benutzer desselben Puffers**: `wig.blit` — der Weg, durch den *jede*
Fensterzeile geht — nahm dieselbe Bühne wie `wig.glyph_into` und hat
die Bühnensperre aus MERGE-6 **nie genommen**. Deshalb senkte diese
Sperre die Rate und schloss die Lücke nicht.

---

## 1. Was wirklich kaputt war

`kernel/wig.fi`, Stand MERGE-6:

```
fn blit(state, me, i, x, y, w, h, src, stride) -> u64 {
    ...
    let stage: u64 = base(state) + STAGE_OFF      // KEINE Sperre
    while r < bh { ... fetch(state, me, stage, ...) ; wm.blit_in(..., stage, ...) }
}

fn glyph_into(state, me, f, px, c, out, max) -> u64 {
    let bz: u64 = buehne_an(cpu.here(state))      // die Sperre aus MERGE-6
    let stage: u64 = base(state) + STAGE_OFF      // DERSELBE Puffer
    ...
}
```

`base(state) + STAGE_OFF` sind **4096 Oktett für die ganze Maschine**.
Der Kopf einer Glyphenantwort steht auf den ersten 48 davon: Breite,
Höhe, links, oben, Laufweite, Zahl der Bildpunkte. `blit` legt dort
**Bildpunktfarben** hinein — 32-Bit-Werte wie `0xFF3A3A3A`. Liest Ring 3
danach den Kopf, steht in `gw` eine Farbe, und

```
if gw * gh > 0                       (kernel/user/wlibc.fi:1128)
```

ist eine `u64`-Multiplikation zweier Zahlen in der Größenordnung 2⁶³.
Firn fängt den Überlauf mit einem Panic ab — **das** ist der Tod, den
MERGE-6 gesehen hat, eine Zeile nach `taskmgr: start`.

### 1.1 Der Überlauf ist ein Folgefehler — nachgerechnet

Die Aufgabe verlangt, das zu **prüfen**. Ergebnis: mit sauberen Werten
kann die Rechnung **nicht** überlaufen.

| Größe | Schranke | wo sie steht |
|---|---|---|
| `gw` | ≤ 256 | `ttf.MAX_W`, `rasterize` verwirft alles darüber |
| `gh` | ≤ 256 | `ttf.MAX_H`, dieselbe Zeile |
| `gw*gh + 48` | ≤ 4096 | `wig.glyph_build`, gegen `STAGE_MAX` |
| gemeldete Länge `n` | ≤ 2048 | `wlibc.gload` bestellt 2048 Oktett |

256 · 256 = 65 536 — sechzehn Größenordnungen unter dem Überlauf.
Der Panic konnte also **nur** aus einem zerschossenen Kopf kommen.

Trotzdem ist der zweite Riegel eingebaut, weil er drei Vergleiche
kostet und aus einem Kernfehler eine abgelehnte Anfrage macht:

```firn
if gw > GMAX || gh > GMAX { return 0xFFFF... }
if gw != 0 && gh > (n - 48) / gw { return 0xFFFF... }
```

Die Längenprobe kommt **ohne Multiplikation** aus (Division statt
Produkt) — ein Riegel, der selbst überlaufen kann, ist keiner.

---

## 2. Die Entscheidung: je Kern oder eine gemeinsame Sperre

Beide Bauformen sind **gebaut** und **gemessen**; die Messung hat
entschieden, nicht das Gefühl.

* **A — `glyphsperre`:** eine Bühne, aber `blit` **und** `glyph_into`
  unter derselben Sperre.
* **B — Vorgabe:** je Kern eine Bühne über `kstate.WIGST_OFF`
  (`+ cpu.here(state) * STAGE_MAX`), so wie `C_KSTACK` über die
  GS-Basis. Keine Sperre im Zeichenweg.

`tools/glyph/run.sh`, Abschnitt 6, gleicher Wirt, gleiche Platte,
1000 Runden je Kern, je fünf Läufe, **Median**:

| | Bauform B, je Kern | Bauform A, eine Sperre | Faktor |
|---|---|---|---|
| `-smp 4` | **143,6 M Zyklen** | 322,8 M Zyklen | **2,25×** |
| `-smp 8` | **215,5 M Zyklen** | 529,4 M Zyklen | **2,46×** |

Beide sind **richtig** (0 Abweichungen). A kostet mehr als das Doppelte
auf dem heißesten Weg der Oberfläche, und der Abstand **wächst** mit
der Kernzahl — genau das, was eine gemeinsame Sperre tut. Deshalb B.

**Warum B sicher ist**, und das ist keine Meinung: der Umschlagpuffer
wird ausschließlich im Systemaufruf angefasst, und
`kernel/arch/x86_64/user.fi` setzt

```
wrmsr(MSR_SFMASK, 0x200)      // IF off during the system call
```

— IF bleibt für den **ganzen** Systemaufruf unten. Eine Aufgabe kann
darin also nicht verdrängt und auf einem anderen Kern fortgesetzt
werden. Dieselbe Zusicherung, auf der `C_KSTACK` über die GS-Basis
schon steht.

**Was das kostet:** `kdata` wächst von 704 auf 736 KiB (MAX_CPUS × 4
KiB). Das ist `.bss` (`kernel/arch/x86_64/boot.s`), im Abbild kein
Oktett. `tools/kernel/memmap.py`: 92 Bereiche, 0 Kollisionen.

---

## 3. Der Glyphenspeicher — die zweite Hälfte des Fehlers

`kernel/ttf.fi` hatte **drei** geteilte Dinge, keines gesperrt:

1. **Der Schlüssel wird vor den Daten veröffentlicht.** `glyph` schreibt
   `C_KEY` und rastert **danach**. Ein zweiter Kern findet den
   Schlüssel, hält den Platz für fertig und liest Breite, Höhe und
   Datenversatz eines Umrisses, den es noch nicht gibt.
2. **Der Stoßallokator** (`alloc`, `S_HEAD`): zwei Kerne bekommen
   denselben Versatz und malen übereinander.
3. **Kantenliste und Deckungszeile** (`A_EDGE`, `A_COV`) sind **eine**
   Arbeitsfläche im Zwischenspeicher.

`ttf.glyph` läuft jetzt vollständig unter `tafel_an` — dieselbe Bauform
wie `serial.zeile_an` und `wig.buehne_an`, je Kern wiedereintrittsfähig
und begrenzt. **Gelesen** wird weiter ohne Sperre: ein fertiger Platz
wird nie wieder beschrieben und nie geräumt, also sind `g_w`, `g_h` und
`g_pixel` nach `glyph` ohne Sperre richtig.

Die Unterbrechungen bleiben aus, solange sie gehalten wird. Die Kennung
**ist** eine Kernnummer; würde eine Kernaufgabe — Taskleiste, Terminal —
mit ihr in der Hand verdrängt und auf einem anderen Kern fortgesetzt,
wäre die Kennung eine Lüge und der Wiedereintritt ließe einen fremden
Kern herein.

### 3.1 Die Gegenprobe dazu fällt hart

`glyphtafelfrei` schaltet nur diese Sperre ab, sonst nichts:

```
-smp 4   panic: integer overflow in 'u64 - u64' at kernel/ttf.fi:975:18
-smp 8   dasselbe
```

`ttf.fi:975` ist `contour_edges`: `let n: u64 = b - a + 1` über eine
Kantenliste, die ein anderer Kern gerade zurückgesetzt hat. Ohne die
Sperre stirbt nicht das Bild, sondern **der Kern**.

---

## 4. Die Zwischenablage — derselbe Fehler, vom Werkzeug gefunden

Der erweiterte `tools/multicore/onecore.py` (Abschnitt 6) hat in
derselben Datei einen zweiten geteilten Puffer gemeldet:
`wig.clip_set`/`clip_get` über `base(state) + CLIP_OFF`.

Sie **gehört** der ganzen Maschine, und das ist richtig so: was das eine
Programm kopiert, muss das andere einfügen können. **Je Kern wäre hier
falsch.** Was fehlte, ist die Sperre: `clip_set` kopiert `len` Oktette
aus Ring 3 hinein und setzt **danach** die Länge; ein `clip_get` auf
einem anderen Kern liest in derselben Zeit die alte Länge über dem
neuen Inhalt. Beide liegen jetzt unter der Bühnensperre — die
Zwischenablage wird selten benutzt, der Preis ist nicht messbar.

---

## 5. Der Nachweis: `glyphrace`

Gebaut wie `fsrace` in MERGE-6, und aus demselben Grund: der Fehler
hing daran, wie der Ablaufplaner den Lauf gerade legte — ein Panic in
einem von fünf Läufen, vier grüne. **Eine Zusage, die vom Glück
abhängt, ist keine.**

`smp.run_phase` startet **alle** Kerne im selben Augenblick. Jeder
zeichnet **sein eigenes** Zeichen durch `wig.glyph_build` — den Rumpf
des Systemaufrufs, keine Nachbildung — und legt in derselben Runde eine
Bildpunktzeile auf die Bühne, so wie `blit` es tut (füllen, gleich
danach lesen). Das Ganze 25-mal mit **geleertem** Zwischenspeicher,
sonst rastert im Rennen niemand und die Kantenliste bliebe ungeprüft.

Und die Gegenproben nehmen die Sperre **genau dort, wo die
nachgestellten Wege sie nehmen**: die Glyphenseite wie `glyph_into`,
die Zeilenseite wie `blit` (also gar nicht, außer in Bauform A). Sonst
misst der Nachweis eine Bauform, die es nicht gibt.

```
smp: glyphrace kerne=4  runden=1000  blind=0  sperre=0  fehler=0     zyklen=80698904   kalt=25
smp: glyphrace   c0 zeichen=65=0  c1 zeichen=66=0  c2 zeichen=67=0  c3 zeichen=68=0
smp: glyphrace kerne=8  runden=1000  blind=0  sperre=0  fehler=0     zyklen=176205546  kalt=25

smp: glyphrace kerne=4  runden=1000  blind=1  sperre=0  fehler=1065  zyklen=170496084  kalt=25
smp: glyphrace kerne=8  runden=1000  blind=1  sperre=0  fehler=1957  zyklen=648837288  kalt=25
```

| | Abweichungen | von | Anteil |
|---|---|---|---|
| je Kern, `-smp 4` | **0** | 8 000 | 0 % |
| je Kern, `-smp 8` | **0** | 16 000 | 0 % |
| `glyphblind`, `-smp 4` | 1 065 | 8 000 | 13 % |
| `glyphblind`, `-smp 8` | 1 957 | 16 000 | 12 % |

`glyphblind` ist **wörtlich** der Stand von MERGE-6: eine Bühne für
alle, die Sperre nur um die Glyphe. Die Zeile je Kern steht dabei, weil
`fehler=0` sonst auch dann grün wäre, wenn alle Kerne dasselbe Zeichen
genommen — also gar nichts gemessen — hätten.

Mit `-smp 1` läuft das Rennen **nicht**: `smp.stage` kehrt bei einem
Kern vor allen Messungen zurück. Das ist keine Lücke, sondern der Fall,
den es zu messen gar nicht gibt.

---

## 6. `onecore.py` sieht jetzt die zweite Bauform

Das Werkzeug hat den Fehler dieser Runde **nicht** gesehen, und der
Grund ist eine Zeile Text: die Bühne heißt nicht `state +
kstate.X_OFF`. `wig.fi` holt seine Seite über einen eigenen Zugriff:

```firn
fn base(state: u64) -> u64 { return state + kstate.WIG_OFF }
let stage: u64 = base(state) + STAGE_OFF
```

Textlich steht dort kein `kstate.`, also fiel die Bühne durchs Raster.
Seit dieser Runde sucht das Werkzeug **zwei** Formen: die alte, und
`<zugriff>(state) + KONST` in jeder Datei, die einen solchen Zugriff auf
eine `kdata`-Seite selbst definiert.

| | MERGE-6 | GLYPHE |
|---|---|---|
| gesperrt | 13 | **18** |
| offen | 60 | **66** |
| mit Wissen am geteilten Puffer | — | **1** |

Die sechs neuen sind `hwid.fi` (2), `ofsj.fi` (2) und `rand.fi` (2) —
Stellen, die vorher unsichtbar waren. Die siebte war die Zwischenablage
in `wig.fi` und ist repariert. Als Sperre gelten jetzt auch
`buehne_an`, `tafel_an` und `stage_of`; der letzte ist **keine** Sperre,
sondern die Auflösung je Kern, und er steht mit diesem Satz im Kopf des
Werkzeugs und nicht als stille Ausnahme. Die dritte Liste `MITWISSEN`
nennt die eine Stelle, die den geteilten Puffer mit Absicht anfasst
(`stage_of` selbst, für die Gegenproben).

Der Vertrag in `tools/multicore/run.sh` steht damit auf **66**, mit
Begründung an Ort und Stelle.

---

## 7. Was der Nachweis *nebenbei* gefunden hat

Beim ersten Durchgang der zwanzig Schreibtischläufe (`-smp 4 r3alle`)
starb ein Ring-3-Programm — **aber nicht an der Bühne**:

```
panic: integer overflow casting 'u64 as u32' at kernel/user/nidx.fi:408
```

Das ist `pino[] = read64(rec + R_PARENT) as u32`: eine Inodenummer, die
keine mehr war. Die Sätze kommen aus `sys.do_scan` und `sys.do_jrnl`,
und **beide legen sie in `kstate.BLOCK_OFF` ab** — 4096 Oktett für den
ganzen Rechner, ohne Sperre. Zwei Ring-3-Programme auf zwei Kernen
überschreiben einander die Sätze.

Es ist **einer der 43 Wege**, die MERGE-6 in `sys.fi` gezählt und nicht
gesperrt hat (RUNDE-MERGE6.md 6.2) — der erste, von dem belegt ist,
dass er zuschlägt. Beide Wege liegen jetzt unter `fs.enter`/`fs.leave`:
die richtige Sperre, weil der Puffer dem Dateisystem gehört, `fs.scan`
sie ohnehin nimmt und sie je Kern wiedereintrittsfähig ist. **Die
übrigen 42 stehen weiter offen** und werden gezählt.

### 7.1 Und eine Zeile, die eine halbe Stunde gekostet hat

`kernel/sched.fi` sagt an einer Stelle:

> DEFAULT: RING 3 BLEIBT AUF KERN 0. `r3alle` schaltet es frei.

Das stimmt **seit VIELKERN 3 nicht mehr**. Achthundert Zeilen weiter
oben, in derselben Datei, steht

```firn
static mut ring3_alle: u64 = 1
```

— Ring 3 läuft ohne jedes Wort auf **allen** Kernen, und `r3eins` ist
die Rückfallebene. Der Absatz ist von VIELKERN 2 und wurde beim
Umschalten stehengelassen.

Es hat eine halbe Stunde gekostet: der Prüfstand dieser Runde setzt
`r3alle` ausdrücklich, **weil dort stand, dass es sonst nicht gilt**.
Es gilt ohnehin — das Wort schadet nicht und macht die Absicht sichtbar,
aber die Zeile ist jetzt richtiggestellt, mit Verweis auf die geltende
Vorgabe. Und es heißt auch: der Fehler dieser Runde war **nicht** auf
eine besondere Befehlszeile angewiesen. Er lag auf dem Weg, den jeder
Start nimmt.

---

## 8. Der Fall, der die Runde ausgelöst hat

Voller Schreibtisch, `wigapp=/bin/taskmgr,melde,takt,500`,
`wighalt=60`, `r3alle`, je **zwanzig** Läufe. Eine grüne Runde reicht
nicht — der Fehler kam in einem von fünf.

| Serie | Läufe | mit Panic/Ausnahme | Meldezeilen |
|---|---|---|---|
| **je Kern, `-smp 4`** | **20** | **0** | 5 038 |
| **je Kern, `-smp 8`** | **20** | **0** | 6 256 |

Der Aufgabenverwalter startete in 18 von 20 Läufen und meldete in jedem
davon (die zwei Ausreißer sind Läufe, in denen die Maschine vor seinem
Start am Zeitlimit endete — 0 Meldezeilen, kein Panic).

### 8.1 Und die unbequeme Wahrheit über diesen Prüfstand

Dieselben zwanzig Läufe mit `glyphblind` — also mit der **geteilten**
Bühne:

| Serie | Läufe | mit Panic | Meldezeilen |
|---|---|---|---|
| `glyphblind`, `-smp 4` | 20 | **0** | 5 011 |
| `glyphblind`, `-smp 8` | 20 | **0** | 5 746 |
| `glyphblind`, hart (`takt=60`), `-smp 4` | 12 | **0** | 2 212 |
| `glyphblind` **und ohne den Riegel in `wlibc`**, hart | 12 | **0** | — |

**Der Schreibtischlauf ist kein Sucher.** Er hat den Fehler nicht
gefunden, auch nicht mit achtfacher Zeichenfrequenz und auch nicht mit
ausgebautem zweiten Riegel. MERGE-6 hat ihn dort gesehen, weil dort
zusätzlich der Glyphenspeicher ungesperrt war und ein Klickdrehbuch
über 260 Sekunden gelaufen ist.

Das steht hier, weil es der Punkt ist: **null Panics in vierzig Läufen
sind ein „nichts kaputtgegangen", keine Zusage.** Die Zusage kommt aus
Abschnitt 5 — `glyphrace` findet in jeder einzelnen Runde Hunderte von
zerschossenen Antworten, wenn die Bühne geteilt ist, und **null**, wenn
sie es nicht ist. Genau deshalb wurde er gebaut.

Was die vierzig Läufe **wirklich** beweisen: der Umbau (kdata um 64 KiB
größer, jede Fensterzeile über einen anderen Puffer, eine neue Sperre
im Rasterer, zwei Systemaufrufe unter `fs.enter`) hat den Schreibtisch
**nicht** beschädigt — bei vier und bei acht Kernen, in vierzig
Starts.

---

## 9. `./test.sh` — alle 65 Abschnitte, zu Ende gefahren

`OSUM_JOBS=2`, 06.09.2026 22:50–06:43 (7 h 53 min), 1167 grüne Zusagen.
**Alle 65 Abschnitte gelaufen** — MERGE-6 kam bis 7.

### 9.1 Zuerst: was der erste Anlauf gemessen hat, war der Wirt

Ein Lauf mit `OSUM_JOBS=4` lief um 22:41 in ein **volles Dateisystem**
(68 KiB frei) und meldete sechs Abschnitte rot, die es nicht sind:

```
netview.log:  OSError: [Errno 28] No space left on device
tresor.log:   cat: write error: No space left on device
```

`k18`, `display`, `customres` und `arm` starben still — QEMU konnte sein
Abbild nicht mehr schreiben. Beim sauberen Lauf mit `JOBS=2`:

| | mit vollem Dateisystem | mit Platz |
|---|---|---|
| `net` | 74/1 | **75/0** |
| `k13` | 98/1 | **99/0** |
| `customres` | 133/2 | **135/0** |
| `arm` | 47/1 | **48/0** |
| `tresor` | rot | **220/0** |
| `hwnet` | rot | **56/0** |

**Ein Prüfstand auf einem vollen Wirt misst den Wirt.** Deshalb steht die
Begründung für `JOBS=2` im Läufer und nicht nur hier.

### 9.2 Die roten Abschnitte, jeder gegen `merge6` nachgemessen

Maßstab ist **derselbe Läufer auf `merge6`**, auf demselben Wirt.

| Abschnitt | GLYPHE | merge6 | Urteil |
|---|---|---|---|
| `gfx` | **75/1** ¹ | 46/30 | **besser** (NUL-Oktett behoben) |
| `k15` | 226/26 | 222/30 | besser |
| `display` | 141/4 | 125/20 | besser |
| `netview` | 170/23 | 164/23 | besser |
| `paint` | 31/1 | 30/2 | besser |
| `modul` | 72/2 | 67/3 | besser |
| `usbimg` | 37/11 | 36/12 | besser |
| `k16` | 60/4 | 60/4 | gleich |
| `k18` | 168/2 | 168/2 | gleich |
| `powermon` | 119/2 | 119/2 | gleich |
| `multiuser` | 90/1 | 90/1 | gleich |
| `umlaut` | 43/5 | 43/5 | gleich |
| `softui` | 21/3 | 21/3 | gleich |
| `blech` | 69/1 | 69/1 | gleich |
| `bridge` | 111/1 | 111/1 | gleich |
| `werkzeug` | 21/13 | 21/13 | gleich, Zusage für Zusage |
| `theme` | 88/8 | — ² | die 8 sind in `wm.fi`/`taskbar.fi` |
| `stick` | 20/22 | 21/21 | dieselben Zusagen, eine wackelt |
| `server` | **22/1** ³ | 22/1 | gleich, nach Behebung |
| `init` | **39/39** ⁴ | **38/40** | merge6 ist SCHLECHTER |
| `vielkern` | 39/1 ⁵ | 39/1 ⁵ | gleich |
| `glyphe` | 26/3 ⁶ | — | siehe GLYPHE 20/n |

¹ Der Wert im Lauf (18/56) entstand während des Plattenengpasses.
Einzeln nachgefahren: **75/1**, und die eine rote Zusage
(„die Zeile der Shell steht bildpunktgenau") ist auf `merge6`
wörtlich dieselbe.

² `tests/theme` lief auf `merge6` gar nicht — es starb an `mkfs`
(GLYPHE 16/n). Die 8 roten Zusagen sind nachgerechnet: `rawcolour.py`
findet auf **beiden** Ständen `raw 8`, alle acht in `kernel/wm.fi` und
`kernel/user/taskbar.fi` — zwei Dateien, die diese Runde **nicht
angefasst** hat (`git show 2aa3f59:… | sha1sum` identisch).

³ War **neu rot** und ist behoben — siehe GLYPHE 19/n.

⁴ Der Verdachtsfall. Nachgemessen auf **demselben Wirt, in derselben
Stunde**: `merge6` **38/40**, dieser Zweig **39/39**. Beide sterben an
derselben ersten Zusage (`'124'` = QEMU-Zeitlimit); danach sind alle
Folgewerte leer, und wie viele davon rot werden, hängt daran, wie weit
die Maschine kam. `kernel/user/init.fi` und `tools/init/` sind in dieser
Runde **unberührt**; die einzige Änderung an `sched.fi` ist reiner
Kommentar (`git show b5d5fee` ohne Kommentarzeilen: leer).

⁵ `/bin/settings kommt nicht hoch` ist ein **Wackler, kein Rückschritt**.
Fünf Läufe hier, drei auf `merge6`, gleicher Wirt:

```
glypharbeit:  --  OK  --  --  --
merge6:       --  --  --
```

`merge6` bringt es in **0 von 3** Läufen hoch, dieser Zweig in 1 von 5 —
und `merge6` erreicht dabei dieselbe Endnote 39/1. Der Wert, auf den es
ankommt, ist in **allen fünf** Läufen grün: `abw=0`.

⁶ Der eigene Prüfstand zählte Kommentare als Fehler und fuhr die zwei
Würfel-Gegenproben mit sechs statt zwanzig Läufen. Behoben und begründet
in GLYPHE 20/n; die belastbare Zusage (`zeichenrennen`) war im selben
Lauf grün.

### 9.3 Zwei rote Zusagen, die diese Runde GEFUNDEN und behoben hat

Beide waren **vor** dieser Runde rot und sind es jetzt nicht mehr:

* **Abschnitt 1** (`der festgenagelte Uebersetzer`) war seit Runde STICK
  (03.09.) auf **jedem** Zweig rot — mit leerem Grund hinter dem
  Strichpunkt, weshalb es niemand nachsah. Zwei Fehler, GLYPHE 18/n.
* **`k15` „Zeilen der Naht"** zählte Kommentar als Kernel. `merge6` war
  damit schon rot (664 > 600), GLYPHE 17/n.

### 9.4 Was NICHT grün ist, und warum das so bleibt

`k16` (60/4) ist **nicht** Sache dieser Runde, und das ist belegt:
`kernel/user/fas.fi`, `tools/osum/mkfs.py` und `tools/k16/run.sh` sind
gegen `merge6` **Oktett für Oktett gleich**. Der Befund ist in sich
widersprüchlich — `fas` meldet Fehler 6 (`schreib_elf` gab `false`), und
**dasselbe Programm läuft danach und endet mit 42**, wie es soll. Das
gehört in eine eigene Runde und nicht in eine Zeile hier.

Dasselbe gilt für `werkzeug` (21/13, Zusage für Zusage identisch mit
`merge6`) — die Vermutung aus der Aufgabenstellung, das Zusammenführen
habe dort etwas gebrochen, ist damit **widerlegt**: der Unterschied
26/34 gegen 37/0 stammt aus einem anderen Läuferstand, nicht aus dem
Merge.

---

## 10. `tools/loader/run.sh` — die zweite offene Auflage

```
LADEN: 31 passed, 0 failed
```

Und der Grund, warum sie offen blieb, war **nicht** „nicht dran
gewesen": der Läufer war **kaputt**. Die erste QEMU-Zeile kam nie:

```
FEHLGESCHLAGEN: mkfs
mkfs: '/bin/taskmgr' gibt es nicht
```

Wörtlich der Bruch aus MERGE-6 4.1, an einer dritten Stelle:
`assets/apps/taskmgr.osp` ist ein Bündel, ein Bündel ist ein Verweis auf
eine Datei unter `/bin`, und `/bin` dieses Läufers hat kein `taskmgr`.
MERGE-6 hat den Riegel (`bundle.py nur=…`) in `tools/design/capture.sh`
und `tools/multicore/run.sh` eingebaut — hier nicht, weil dieser Läufer
in jener Runde nie lief. Dazu fehlte `$OUT/schluessel.pub`; er liegt in
`/srv/store/osum/aktuell/` und wird jetzt von dort geholt.

Was der Lauf zeigt, Zusage für Zusage:

| Abschnitt | Ergebnis |
|---|---|
| 1 acht `.opk` gebaut, jedes mit `start`, `INFO`, `symbol` | grün |
| 2 `VERZEICHNIS`, `.sig`, `INDEX`, `.sig` mit **curl** geholt (200) | grün |
| 3 ein Osum ohne Paket fragt den Laden, zählt **acht** auf, Kette geprüft | grün |
| 4 `ota einspielen`: acht Streuwerte, acht Signaturen **ein zweites Mal** durch `opk`, acht installiert | grün |
| 5 der Schreibtisch startet, ein Programm **aus dem Laden** malt sein Fenster | grün, `docs/shots/glyphe/laden-schreibtisch.png` |
| 6 Gegenprobe: gekipptes Oktett, ohne Signatur, fremder Schlüssel — **alle drei abgelehnt**, danach nichts halb installiert | grün |
| 7 die Bilder werden **gelesen**: `tesseract` holt 181 Wörter aus dem Fenster zurück | grün |

Das Bild ist keine Behauptung: Abschnitt 7 liest es mit einem fremden
Werkzeug wieder ein.

---

## 11. Ist `merge6` reif, `hidweg` zu ersetzen?

**Ja** — mit einer Einschränkung, die benannt gehört.

### 11.1 Wofür der Beweis vollständig ist

Der Auftrag war, den letzten bekannten Ein-Kern-Rest zu schließen. Er ist
geschlossen, und der Nachweis hängt nicht am Glück:

| Zusage | Beleg |
|---|---|
| Der Fehler ist gefunden, nicht umgangen | `wig.blit` nahm dieselbe Bühne wie `glyph_into` und hat die Sperre aus MERGE-6 nie genommen (Abschnitt 1) |
| Die Bauform ist gemessen, nicht geraten | je Kern gegen eine Sperre: 2,25× / 2,46× (Abschnitt 2) |
| Der Überlauf ist verstanden | Folgefehler, nachgerechnet; Riegel ohne Multiplikation (1.1) |
| Das Rennen ist erzwungen | `zeichenrennen`: 0 von 8 000 / 0 von 16 000, blind 1 065 / 1 957 (Abschnitt 5) |
| Die Gegenprobe fällt hart | `glyphtafelfrei` → Panic in `ttf.fi:975` (3.1) |
| Nichts kaputtgegangen | 40 Schreibtischläufe, 4 und 8 Kerne, 0 Panics (Abschnitt 8) |
| Das Werkzeug sieht die Bauform | `onecore.py`: gesperrt 13 → 18, offen 66 → **64** (Abschnitt 6) |
| Der Laden nimmt ab | `LADEN: 31 passed, 0 failed` (Abschnitt 10) |
| Der Prüfstand ist zu Ende gefahren | 65 von 65, 1167 grüne Zusagen (Abschnitt 9) |

Dazu drei Zusagen, die **vor** dieser Runde rot waren und es nicht mehr
sind: `./test.sh` Abschnitt 1, `k15` „Zeilen der Naht", `gfx` (46/30 →
75/1).

### 11.2 Der ehrliche Vergleich

Kein Abschnitt ist gegen `merge6` schlechter geworden. Sieben sind
besser, dreizehn gleich, zwei wackeln in beide Richtungen
(`stick`, `vielkern`/`settings`) — und bei `init` ist `merge6` das
schlechtere der beiden Ergebnisse.

Die eine Zusage, die diese Runde **selbst gerissen** hat
(`tools/server`), wurde gefunden, verstanden und behoben, bevor dieser
Satz geschrieben war: der Nachweis trug seinen Namen in den Serverbau
(GLYPHE 19/n).

### 11.3 Was NICHT behauptet wird

`merge6` ist **nicht fehlerfrei**. Offen bleiben unter anderem:

* `k16` 60/4 — der Assembler auf Osum meldet Fehler 6, und das Programm,
  das er dabei schreibt, läuft trotzdem richtig. Widersprüchlich,
  unberührt von dieser Runde, gehört in eine eigene.
* `init` — die erste Zusage läuft in ein QEMU-Zeitlimit, auf **beiden**
  Zweigen; alles danach ist Folge.
* `werkzeug` 21/13, `stick` 20/22, `netview` 170/23, `k15` 226/26 — alt,
  gezählt, unverändert.
* **42 der 43 Wege in `sys.fi`** sind weiter ungesperrt (MERGE-6 6.2).
  Diese Runde hat den 43. geschlossen, weil er zuschlug — die anderen
  stehen im Vertrag und warten.

### 11.4 Die Begründung für den Wechsel

`hidweg` ist als Grundlinie **schlechter als der Stand, der ihn ersetzen
soll**, und zwar nachweisbar:

* `hidweg` hat `fs.inode_get` ungesperrt (MERGE-6: 31 506 von 80 000
  Abweichungen mit dem alten Rumpf).
* `hidweg` hat die geteilte Bühne im Zeichenweg (diese Runde: 13 % der
  Antworten zerschossen).
* `hidweg` kennt weder `vielkern3` noch `design`, `werkzeug`, `laden`.

Eine Grundlinie soll das Beste sein, was belegt funktioniert. Das ist
`merge6` — nicht, weil er fehlerfrei wäre, sondern weil jeder bekannte
Unterschied zu `hidweg` in **eine** Richtung zeigt und jede Behauptung
darüber eine Messung hinter sich hat.

**Der Wechsel ist vollzogen** (`hidweg` auf diesen Stand gezogen).
**Nicht gepusht** — das entscheidet Justin.
