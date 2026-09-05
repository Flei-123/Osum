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

`tools/glyphe/run.sh`, Abschnitt 6, gleicher Wirt, gleiche Platte,
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

Der erweiterte `tools/vielkern/einkern.py` (Abschnitt 6) hat in
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

## 6. `einkern.py` sieht jetzt die zweite Bauform

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

Der Vertrag in `tools/vielkern/run.sh` steht damit auf **66**, mit
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

## 9. `./test.sh`

*(wird nach dem Lauf eingetragen)*

---

## 10. `tools/laden/run.sh` — die zweite offene Auflage

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
MERGE-6 hat den Riegel (`bundle.py nur=…`) in `tools/design/aufnahme.sh`
und `tools/vielkern/run.sh` eingebaut — hier nicht, weil dieser Läufer
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

*(wird am Ende beantwortet)*
