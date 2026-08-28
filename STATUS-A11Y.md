# STATUS — Runde A11Y

Zweig `a11y`, abgezweigt von `mergeline` (6b602af). **Nicht nach `main`
gemergt.** Arbeitsbaum `/root/osum-a11y`.

Die ausführliche Fassung mit der Begründung steht in **`docs/A11Y.md`**;
hier stehen die Zwischenstände und die Zahlen.

---

## Zwischenstand 1 — der Kernel steht (Commit 1/8)

Was gebaut wurde:

* `kernel/ax.fi` (neu, ~640 Zeilen): die Ablage des Baumes. 256 Knoten zu
  64 Oktetten, ein Ereignisring von 64 Einträgen, eine Rechtetafel für 32
  Aufgaben, die systemweiten Einstellungen. Sechzehn Rollen, sieben
  Zustandsbits.
* `kstate.AX_OFF = 0x7A000`, `AX_MAX = 0x6000` — sechs Seiten, der letzte
  freie Block in `kdata`. **Speicherkarte: 65 Bereiche, 0 Kollisionen.**
* Wort 10 des Modusvektors (`M_A11Y` … `M_A11YKEYS`) — eine eigene
  Schicht, kein Bit aus Wort 1 (der Oberfläche).
* Sechs Aufrufe 1960..1965 in `kernel/sys.fi` mit den Prüfungen an der
  Ringgrenze.
* Die Bildschirmlupe in `kernel/wm.fi`, die Einrastfunktion und
  Umschalt-Tab (`ESC [ Z`) in `kernel/kbd.fi`.
* `proc.create` räumt Baum und Freigabe eines wiederverwendeten
  Aufgabenplatzes weg.

Kernel baut, Stufe 0. `ax: selftest 9 / 9`.

---

## Zwischenstand 2 — Ring 3, und der Baum entsteht von selbst

* `kernel/user/wlibc.fi`: `px_ui()`, `px_mono()`, `sc()` — die
  Schriftgröße ist von jetzt an eine Rechnung. Die Aufrufhüllen. Der
  hohe Kontrast, der jede andere Farbquelle schlägt.
* `kernel/user/wlib.fi`: `ax_flush()` baut den Baum aus dem, was die
  Bibliothek ohnehin weiß. Vier neue Felder je Bedienelement
  (`D_MINW`, `D_MINH`, `D_AXN`, `D_AXF`). Skalierung in `size`,
  `box_*`, `window`, `place`. Umschalt-Tab, Menüleiste per Tastatur,
  Pfeile im Auswahlfeld, Esc im Dialog. Die Fokusspur.
* `kernel/user/a11ydemo.fi`, `kernel/user/axlesen.fi`: die Messanwendung
  und der Leser.

**Drei Fehler, die dabei gemessen und behoben wurden** — sie stehen hier,
weil sie mehr über die Runde sagen als das, was auf Anhieb ging:

1. **Die Freigabe kam nie an.** `elf.spawn` gibt den *Aufgabenplatz*
   zurück, nicht die pid; die erste Fassung suchte den Platz über `T_PID`
   und fand keinen (Platz 3 trägt die pid 4). Der Leser bekam auch mit
   `a11ygrant` ein `-EPERM` — die Gegenprobe war grün, **aber aus dem
   falschen Grund**. Genau der Fall, den ein Test nicht findet, wenn er
   nur die negative Richtung prüft.
2. **Der hohe Kontrast war unlesbar.** Mit dem Kontrastschema (hell,
   Schrift schwarz) und der alten Überschreibungsdatei `/etc/theme` aus
   Runde K15 (zwölf *dunkle* Flächenfarben) kam schwarze Schrift auf
   dunklem Grund heraus: `fg=0` auf `bg=0x1C2030`, **1,3 zu 1**. Es
   brauchte zwei Sperren in `wlibc.fi`, weil `wlib.begin` die alte Datei
   auf einem zweiten Weg noch einmal lädt.
3. **Die Tabulator-Messung log.** Ein Programm, das den Fokus nur
   *abfragt*, sieht ihn nicht: `step()` verarbeitet bis zu 64 Ereignisse
   am Stück. Von vierzehn Tabulatoren tauchten elf Stellen auf — nicht
   weil drei unerreichbar waren, sondern weil niemand hinsah. Erst eine
   Spur, die bei *jedem* Fokuswechsel schreibt, macht aus „durchtabben
   und zählen" eine Messung.

---

## Die Zahlen der Abnahme

`bash tools/a11y/run.sh`, QEMU mit `-accel kvm`.

### Der Baum

| Messung | Wert |
|---|---:|
| Selbsttest der Schicht | 9 / 9 |
| Knoten in der Ablage (Messanwendung) | 13 |
| davon Bedienelemente | 12 |
| Rollen im Baum vertreten | 10 von 16 |
| Knoten mit Fokus | genau 1 |
| Zeilen, die eine Anwendung dafür schreiben muss | **0** |

Der Baum wird aus der **Ablage im Kernel** gelesen (`ax: node …` auf der
seriellen Leitung), nicht aus dem, was die Anwendung über sich selbst
sagt. Fünf Knoten wurden zusätzlich im **Bildschirmfoto** nachgerechnet:
an der Stelle, die der Baum nennt (Fensterecke + Rahmen 2 + Titelleiste
22 + Knotenlage), steht wirklich Tinte, und rechts davon ist Luft.

### Das Passwortfeld

| Messung | Wert |
|---|---:|
| Vorkommen des Kennworts im gesamten Mitschnitt | **1** (die Selbstmeldung der Anwendung) |
| davon in einem Knoten der Ablage | 0 |
| davon in einer Zeile des Lesers | 0 |
| Rolle / Zustand des Feldes | 6 / 67 (aktiv, fokussierbar, **geschützt**) |
| sein Wert | 0 |
| `AI_SECRETS` (geschützte Knoten gesehen) | 1 |
| **`AI_LEAKS` (Werte, die trotzdem ankamen)** | **0** |

### Das Leserecht

| Lauf | `may` | gelesene Knoten | abgewiesen |
|---|---:|---:|---:|
| `a11yread a11ygrant` | 1 | **13** | 0 |
| `a11yread` (ohne Freigabe) | 0 | **0** | 14 (`-EPERM`) |
| `a11ynotree` (Gegenprobe zum Baum) | 1 | 0 | 0 — die Ablage ist leer |

### Die Tastatur

| Messung | Wert |
|---|---:|
| fokussierbare Bedienelemente | 11 |
| durch Tabulator **erreichte** (verschiedene) | **11** |
| Fokuswechsel bei 14 Tabulatoren | 14 |
| Menüleiste per Tabulator erreichbar | ja (war vorher **nein**) |
| Umschalt-Tab geht rückwärts | ja (gab es vorher **nicht**) |

### Die Skalierung

Je Bedienelement gemessen: `platz >= text`.

| Skalierung | Schrift | Fenster | Beschriftungen zu breit | Luft rechts im Bild |
|---:|---:|---|---:|---|
| 100 % | 15 px | 480 × 372 | **0 von 12** | ja |
| 125 % | 18 px | 600 × 465 | **0 von 12** | ja |
| 150 % | 22 px | 720 × 558 | **0 von 12** | ja |

Bei 100 Prozent sind die Rechtecke der Runde K15 **bildpunktgleich**
dieselben wie vorher (Abschnitt 11 des Läufers rechnet drei davon
wörtlich nach).

### Die Lupe

| Messung | Wert |
|---|---|
| Tafel | 200 × 150 bei (600, 0) |
| Vergrößerung | 2× |
| Ausschnitt bei Zeiger (399, 299) | ab (349, 262) |
| gemalte Bilder im Lauf | 63 |
| **Bildpunkte der Tafel, die der Quelle entsprechen** | **29 304 von 29 304** |
| ohne `a11ymag` gemalt | 0 |

### Der Kontrast

| Schema | Schrift auf Fläche | WCAG |
|---|---:|---|
| gewöhnlich (`day`/`/etc/theme`) | 14,93 : 1 | AAA |
| **`a11yhigh`** | **21,00 : 1** | AAA, Maximum |

### Die Einrastfunktion

| Lauf | `sticky` | `sticks` | nach *Umschalt allein* geht der Tabulator |
|---|---:|---:|---|
| `a11ysticky` | 1 | 1 | **zurück** |
| ohne | 0 | 0 | vor |

---

## Bildschirmfotos

`docs/shots/a11y/` — `baum.png`, `tastatur-fokus.png`,
`skalierung-100.png`, `skalierung-125.png`, `skalierung-150.png`,
`lupe.png`, `hoher-kontrast.png`.

---

## Was NICHT in dieser Runde ist

Die **Sprachausgabe**. Sie ist ein eigenes großes Projekt
(Stimmerzeugung, Aussprachewörterbuch, Tonausgabetreiber — den dieses
System noch nicht hat). `docs/A11Y.md`, Abschnitt 6, sagt Punkt für
Punkt, was der Baum ihr schon liefert und was noch fehlt; die zwei
großen Lücken sind **Text mit Struktur** (Einfügemarke, Auswahl,
Zeichenoffsets) und **Handeln über den Baum** (mit einer eigenen
Sicherheitsentscheidung).

## Auflagen der Runde

* Jeder Schritt committet: ja.
* Kein bestehender Test entschärft: ja — `tools/a11y/run.sh` Abschnitt 11
  rechnet die Rechtecke der Runde K15 wörtlich nach, und `test.sh`
  bekommt einen **zusätzlichen** Abschnitt (28), keiner wird geändert.
* Nicht nach `main` gemergt: ja.
