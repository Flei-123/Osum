# RUNDE VIRTIOGPU -- ein Grafiktreiber, und was er wirklich bringt

Osum malt seit Runde K7 in einen Zweitpuffer und **kopiert** ihn danach
in den linearen Rahmenpuffer, den die Firmware gesetzt hat. Jeder
Bildpunkt geht dabei durch die Recheneinheit, zweimal sogar -- einmal
gelesen, einmal geschrieben. Diese Runde baut den ersten echten
Grafiktreiber: `kernel/vgpu.fi`, virtio-gpu im 2D-Betrieb nach
VIRTIO 1.2, Abschnitt "GPU Device".

Der Befund in einem Satz: **der Treiber ist dort gut, wo sich wenig
aendert, und dort schlechter, wo sich alles aendert -- und er beseitigt
das Reissen auch ohne Seitenumschaltung.**

---

## 1. WARUM VIRTIO-GPU UND NICHT INTEL

Weil es auf dieser Maschine **messbar** ist. Ein Intel-Treiber waere auf
diesem Wirt nicht einmal startbar -- es steckt keine Intel-Grafik im
Kasten. Es gaebe Quelltext ohne einen einzigen Messwert dahinter, und
davon hat dieses Repo genug gesehen.

virtio-gpu ist kein Spielzeug: Ressourcen anlegen, Speicher anhaengen,
Rechtecke uebertragen, Scanout setzen, und ein Ereignis bei
Schirmwechsel. Ein Blechtreiber hat **dieselben** vier Schritte, nur mit
anderen Registern davor. Wer das kann, hat die Struktur.

**Was auf Justins Brett davon gilt, steht in Abschnitt 8.** Kurz: der
Rueckfall, und sonst nichts.

---

## 2. DIE SECHS SCHRITTE

```
  1. FINDEN            1af4, Klasse 03:80
  2. AUFSETZEN         vier Bereiche, Aushandlung, eine Warteschlange
  3. RESOURCE_CREATE_2D        die Bildflaeche, wie das Geraet sie sieht
  4. RESOURCE_ATTACH_BACKING   der Zweitpuffer wird UNTERLAGE
  5. SET_SCANOUT               Schirm 0 zeigt diese Flaeche
  6. je Bild: TRANSFER_TO_HOST_2D + RESOURCE_FLUSH
```

Schritt 4 ist der Trick. Das Geraet bekommt **keine Kopie**, sondern die
Adresse des Speichers, in den `fb.fi` ohnehin malt. Ab da ist "was Osum
gemalt hat" und "was das Geraet lesen kann" dasselbe Stueck Speicher,
und Schritt 6 sagt nur noch, **welcher Teil** davon neu ist.

Der Gewinn liegt in Schritt 6 und nirgends sonst. 3 bis 5 passieren
einmal.

Ausdruecklich **nicht** gebaut: kein 3D (`VIRGL` wird abgelehnt), keine
Zeigerwarteschlange, keine Unterbrechung (abgefragt), keine mehreren
Schirme. Die Gruende stehen im Kopf von `kernel/vgpu.fi`.

---

## 3. DIE WAAGE -- UND WARUM SIE IN `fb.fi` STEHT

"Oktette je Bild" ist nur dann ein Vergleich, wenn **vorher und nachher
dasselbe gezaehlt wird**. Stuende der Zaehler im Treiber, gaebe es fuer
den alten Weg gar keinen, und man haelte eine Messung gegen eine
Schaetzung.

Also zaehlt `fb.fi`, und **jeder** Weg wiegt sich selbst: `flush`,
`flush_stripe`, `flush_rows`, `flush_rect` (beide Zweige), `present` --
und `vgpu.present` legt sich auf dieselbe Waage.

Die Bildgrenze ist `wm.present` und sonst nichts. `flushes` zaehlt
Uebertragungen, und davon gibt es mehrere je Bild.

    gpu: okt=<Oktette>  rect=<Uebertragungen>  bilder=<Bilder>  je=okt/bilder

---

## 4. DIE ZAHLEN

Alle Laeufe: **derselbe Kern**, dieselbe Maschine, dieselbe
Kommandozeile. Der einzige Unterschied ist das Wort `novgpu`.
`tools/vgpu/paar.sh` macht genau das.

### 4.1 Der Alltag: eine tickende Uhr (`vgpuuhr`)

Ein Rechteck von 96x20 aendert sich in jedem Takt, der Rest steht. Das
ist ein Schreibtisch, wie er wirklich dasteht.

| | Oktette je Bild | Bilder in 4 s |
|---|---:|---:|
| alt (Kopie) | 8 850 | 106 713 |
| **neu (virtio-gpu)** | **7 745** | 58 128 |

Das Rechteck selbst ist `96*20*4 = 7 680` Oktette. Der Treiber liegt bei
7 745 -- **101 Prozent des theoretisch Moeglichen**. Mehr ist nicht
herauszuholen.

Dass der Gewinn trotzdem nur 12 Prozent ist, liegt **am alten Weg**: er
ist besser als erwartet, weil `wm.present` schon `flush_rect` ruft und
das Spalten kann. Diese Runde hat also weniger zu holen gefunden, als
sie erwartet hat, und das steht hier, statt eine groessere Zahl zu
suchen.

### 4.2 Der Streifenbetrieb -- Justins Fall

`fbstreifen` erzwingt den Weg, den Justins Brett faehrt: der Puffer
passt nicht ins Abbildungsfenster, also wird er scheibenweise durch
**einen** 2-MiB-Platz geschoben.

| | Oktette je Bild | Uebertragungen je Bild |
|---|---:|---:|
| alt (Kopie) | 9 344 | **20,0** |
| **neu** | **7 782** | **1,0** |

Hier liegt der eigentliche Befund. Zwanzig Umlegungen des
Abbildungsfensters je Bild, **jede mit abgeschalteten Unterbrechungen**
(Runde BLECHZWEI musste das so bauen, sonst schreibt der Zeitgeber in
den falschen Block) -- gegen **einen** Befehl. Das ist der Unterschied,
den man auf echtem Blech spueren wuerde.

### 4.3 Der schlimmste Fall (`wmruhe`) -- hier ist der Treiber SCHLECHTER

Der ganze Schirm wird in jedem Takt schmutzig.

| | Oktette je Bild | Bilder in 4 s |
|---|---:|---:|
| alt (Kopie) | 1 941 538 | **5 711** |
| neu | 1 920 000 | 4 187 |

**27 Prozent weniger Bilder.** Bei vollem Schmutz gibt es keine Oktette
zu sparen, also bleibt nur der Preis des Wartens auf das Geraet stehen.

Das ist kein Schoenheitsfehler, sondern das Ergebnis, und es steht
hier so deutlich wie die guten Zahlen. Es ist allerdings auch der Fall,
den ein Schreibtisch nie hat -- kein Mensch aendert jeden Bildpunkt
sechzig Mal je Sekunde.

Die erste Fassung war hier **47 Prozent** schlechter. Siehe Abschnitt 6.

---

## 5. DAS REISSEN -- DIE UEBERRASCHUNG DER RUNDE

`docs/VSYNC.md` hat drei Anlaeufe gebraucht, um Reissen ueberhaupt
messbar zu machen, und ist bei diesem gelandet: **ein zweiter Kern liest
den Vorderpuffer, waehrend der erste malt.** Das ist keine Nachbildung
des Reissens -- es *ist* das Reissen.

Dieselbe Messung, mit und ohne Treiber, `nopresent noflip` (also
ausdruecklich **ohne** Seitenumschaltung -- die Lage, in der es reissen
MUSS):

| Lauf | Ablesungen | **Risse** |
|---|---:|---:|
| `novgpu` (Kopie) | 150 360 | **21 206** |
| `novgpu`, Wdh. 1 | 120 762 | **18 949** |
| `novgpu`, Wdh. 2 | 121 140 | **15 776** |
| **mit Treiber** | 143 511 | **0** |
| **mit Treiber**, Wdh. 1 | 114 794 | **0** |
| **mit Treiber**, Wdh. 2 | 122 444 | **0** |

**Die Gegenprobe kollabiert, wie sie muss.** Derselbe Kern, dieselben
Worte, dieselbe Maschine -- nur der Treiber ist anders, und die Risse
sind weg.

**Warum das so ist, und es ist keine Magie:** `RESOURCE_FLUSH` ist eine
*Zusage des Wirts*. Der Schirm sieht das Rechteck entweder ganz alt oder
ganz neu, nie zur Haelfte -- das Zusammensetzen passiert auf der anderen
Seite der Schnittstelle, wo kein Ableser des Gasts hinsieht. Der
Zweitpuffer, den der Ableser liest, wird waehrend der Uebertragung gar
nicht angefasst.

**Was das NICHT heisst:** es heisst nicht, dass ein *Bildschirm* nie ein
halbes Bild zeigt. Ob der Wirt seinerseits im Vblank umschaltet, kann
der Gast nicht sehen und diese Messung nicht beantworten. Was gemessen
ist: *aus der Sicht des Gasts* gibt es das halbe Bild nicht mehr -- und
genau das war bisher die Ursache.

Auf VESA/GOP gibt es keinen Vblank-IRQ; `docs/VSYNC.md` musste deshalb
die ganze Bildseite wechseln und konnte das ab 1920x1080 nicht mehr
(zu wenig Abbildungsfenster). **Der Treiber braucht diesen Umweg nicht**
-- er ist reissfrei ohne `flip`, in jeder Aufloesung. Das ist der Satz,
mit dem `docs/VSYNC.md` Abschnitt 3 endet ("wer sie verschieben will,
muss ... auf virtio-gpu mit eigenem Ressourcen-Flush gehen"), und er
stimmt.

---

## 6. DREI FEHLER, DIE DIE MESSUNG GEFUNDEN HAT

Sie stehen hier, weil der naechste sonst dieselben Wege geht.

### 6.1 Der Ringindex ist 16 Bit und laeuft ueber

`avail.idx` zaehlt frei weiter und wird modulo 2^16 gelesen (VIRTIO 1.2,
2.7.6). Ohne Maske lief der Kern genau so lange, bis 65 536 Befehle
heraus waren -- bei zwei je Bild sind das gut 32 000 Bilder, also eine
halbe Minute -- und dann:

    panic: integer overflow casting 'u64 as u16' at kernel/vgpu.fi:286

**Ein Fehler, der eine halbe Minute braucht, findet keine kurze
Messung.** Dieser hier wurde gefunden, weil der Lauf 103 420 Bilder lang
war. Dieselbe Vorsicht braucht die Wartebedingung in `befehl_paar`
(`(jetzt -% vor) & 0xFFFF`), sonst haengt der Treiber einmal je 65 536
Befehlen fuer immer.

### 6.2 `dirty` kannte nur Zeilen -- und das war fast der ganze Gewinn

Die erste Fassung meldete in `dirty` einfach die **volle Bildbreite** an.
Damit uebertrug der Treiber fuer eine Uhr von 96 Bildpunkten Breite ein
Rechteck von 800:

    je=64086 Oktette je Bild   gegen   je=8879 beim alten Weg

**Der Treiber war schlechter als das, was er ersetzen sollte.** Die Zahl
war der Hinweis: 64086/4 sind 16 021 Bildpunkte, und das ist genau
800 x 20. Wer nur Zeilen anmeldet, verschenkt die halbe Ersparnis.

Jetzt melden `hline`, `hline_a`, `pixel_a` und `line` ihre **Spalten**
mit (`dirty_x`). `fill` und `clear` gehen durch `hline`, also stimmen
sie automatisch.

### 6.3 Zwei Wartungen je Bild

`present` schickt zwei Befehle und wartete nach **jedem** auf seine
Antwort -- zwei volle Umlaeufe zum Wirt je Bild. Im schlimmsten Fall
kostete das 47 Prozent der Bilder.

Die Abhilfe ist nicht, weniger zu pruefen, sondern beide Befehle
**zusammen** einzureihen: vier Deskriptoren, ein Klopfen, eine Wartung
auf zwei Antworten (`befehl_paar`). Die Reihenfolge des Rings ist genau
die, die das Protokoll verlangt. Beide Antwortcodes werden geprueft.

Ergebnis: 2 890 -> 4 187 Bilder, also **45 Prozent mehr**.

---

## 7. EINE FEHLMESSUNG, DIE FAST ZUR FALSCHEN DIAGNOSE GEFUEHRT HAETTE

Der erste Bildvergleich sagte: **99,98 Prozent der Bildpunkte
verschieden**, das neue Bild fast ganz schwarz. Das sah nach einem
kaputten Treiber aus.

Es war die Messung. `screendump` ohne Geraetenamen fotografiert das
**erste** Anzeigegeraet, und das ist die VGA-Karte, die QEMU immer
dazustellt. Mit Treiber steht das Bild auf der virtio-gpu; die
VGA-Flaeche bleibt schwarz. Das Foto zeigte nicht "der Treiber malt
nicht", sondern "hier wird das falsche Geraet fotografiert".

`tools/vgpu/schuss.py` gibt `screendump` den Geraetenamen mit. Danach:

    alt.ppm gegen neu.ppm: 0 von 480 000 Bildpunkten verschieden

`pruef/bildpruef.py` auf beide: dieselben 61 Farben, dieselben Anteile,
dieselben zwei einfarbigen Bloecke. Die Bilder liegen in
`docs/shots/vgpu/`.

---

## 8. WAS AUF JUSTINS BRETT GILT -- EHRLICH

**Von den Zahlen in Abschnitt 4 und 5 gilt dort keine einzige.**

Justins Brett hat eine Intel-Grafikeinheit und einen Rahmenpuffer von
der Firmware. Es hat kein virtio-gpu und wird nie eines haben. Dort
laeuft weiter genau der Weg, der vorher lief.

Was **gemessen** ist und dort gilt:

* **Der Rueckfall steht.** Derselbe Kern ohne virtio-gpu auf dem Bus:
  `vgpu: kein Geraet`, der Rahmenpuffer kommt normal hoch, kein panic,
  sauberes Ende. Justins Brett merkt von dieser Runde nichts.
* **`tools/check-ui.sh` PASSED**, `tools/gfx/run.sh` **76 passed, 0
  failed** -- mit allen Aenderungen im Baum.
* Die Spaltenmeldung aus 6.2 (`dirty_x`) wirkt **auch ohne Treiber**:
  `flush_rect` bekommt dadurch genauere Rechtecke. Das ist die einzige
  Aenderung dieser Runde, die dem alten Weg zugutekommt -- gemessen ist
  sie dort nicht, weil `flush_rect` schon vorher Spalten konnte.

Was diese Runde fuer das Brett **wirklich** wert ist, ist die
**Struktur**: die Naht (`gfx.bild_fertig`), die Waage, das
Schmutzrechteck mit Spalten, die Bildgrenze. Ein Intel-Treiber haengt
sich an dieselben Stellen. Die Zahl aus 4.2 -- zwanzig Fenster-
umlegungen je Bild gegen eine -- ist der Grund, warum sich das lohnen
wuerde.

**Und was nicht gemessen ist:** ob der Schirmwechsel vom Wirt wirklich
ankommt. Unter `-display none` setzt QEMU `EVENT_DISPLAY` nie. Belegt
ist nur der **Abfrageweg** (`vgpuereig`):

    vgpu: ... ereig=1  neu=1280x800  umst=0

1280x800 ist, was das Geraet wirklich als seine Groesse meldet -- die
Antwort wird also richtig gelesen. Dass der Wirt das Bit setzt, zeigt
erst ein Lauf mit einem Fenster. Bis dahin ist Punkt 3 des Auftrags
**halb erledigt**, und das ist die ehrliche Auskunft.

---

## 9. WAS ALS NAECHSTES DRAN WAERE

1. **Der schlimmste Fall (4.3).** Die Wartung auf `RESOURCE_FLUSH` ist
   nicht noetig -- der naechste `TRANSFER` darf erst danach laufen, aber
   das Bild darf ohne Wartung weitergehen. Ein Ring mit zwei offenen
   Befehlen statt einem wuerde die 27 Prozent wahrscheinlich aufheben.
   Das ist eine eigene Runde, weil es die Fehlerbehandlung aendert.
2. **Eine Liste von Rechtecken statt eines umschliessenden.** Zwei
   Fenster an gegenueberliegenden Ecken ergeben heute ein Rechteck ueber
   den ganzen Schirm.
3. **G-007** (mehrere Schirme, freie Skalierung): `display_info` liest
   die Liste schon, `S_SCANOUTS` haelt die Zahl. Was fehlt, ist ein
   Rahmenpuffer je Schirm -- und der Umbau von `fb.fi`, den diese Runde
   ausdruecklich nicht angefasst hat.
4. **P-009** (MJPEG 854x480@24): der Weg dorthin fuehrt ueber
   `RESOURCE_CREATE_2D` mit einer zweiten Ressource fuer das Bild und
   `SET_SCANOUT` auf einen Ausschnitt. Die Struktur steht.

---

## 10. WIE MAN ES NACHMISST

```
git worktree add /root/os-gpu virtiogpu
cd /root/os-gpu
bash tools/build-kernel.sh /tmp/k.mb

# die Zahlen aus 4.1 / 4.2 / 4.3
VGPU_KERNEL=/tmp/k.mb bash tools/vgpu/paar.sh 4 vgpuuhr
VGPU_KERNEL=/tmp/k.mb bash tools/vgpu/paar.sh 4 "vgpuuhr fbstreifen"
VGPU_KERNEL=/tmp/k.mb bash tools/vgpu/paar.sh 4 wmruhe

# die Bilder aus 7
VGPU_KERNEL=/tmp/k.mb bash tools/vgpu/bilder.sh /tmp/bilder
python3 pruef/bildpruef.py /tmp/bilder/alt.ppm

# die Zerreissprobe aus 5 (zwei Kerne!)
qemu-system-x86_64 -smp 2 -kernel /tmp/k.mb -m 256 \
  -append "gfx wm wmhold wmsig wmruhe vsync nopresent noflip \
           wighalt=4 nokbd noproc nofs [novgpu]" \
  -vga std -device virtio-gpu-pci,id=vg ...
```

`novgpu` weglassen heisst: mit Treiber. Das ist der ganze Unterschied
zwischen den Zeilen jeder Tabelle hier.
