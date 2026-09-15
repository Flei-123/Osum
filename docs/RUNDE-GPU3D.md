# Runde GPU (G-012) — echter GPU-Treiber und 3D-Beschleunigung

Zweig `gpu`, Basis `main 7a80727`. Abnahme: `tools/gpu3d/run.sh`.

---

## 1. Was dieser Wirt hergibt — GEMESSEN, BEVOR GEBAUT WURDE

Der Auftrag verlangte ausdrücklich, zuerst zu prüfen, ob **VIRGL** auf
diesem Rechner läuft, und das Ergebnis aufzuschreiben, bevor eine Zeile
entsteht. Das ist getan, und es war ein klares **Nein** — aus mehreren
voneinander unabhängigen Gründen:

| Prüfung | Ergebnis |
|---|---|
| `qemu-system-x86_64 -device help \| grep virtio-gpu` | `virtio-gpu-gl-pci` **ist gelistet** |
| `-device virtio-gpu-gl-pci` wirklich starten | **`opengl is not available`** |
| `-display egl-headless` | **`egl: no drm render node available`** |
| `-display help` | `module ui-ui-none not found` (`qemu-system-gui` fehlt) |
| `ldconfig -p \| grep virgl` | `libvirglrenderer.so.1` (0.10.4) **ist da** |
| `ls /dev/dri` | **existiert nicht** |
| `systemd-detect-virt` | **`lxc`** |
| `ls /lib/modules/$(uname -r)/kernel/drivers/gpu/drm` | **existiert nicht** |
| `modprobe vgem` | `Module vgem not found` |

QEMU ist 7.2.22 (Debian `1:7.2+dfsg-7+deb12u18+b3`).

**Die Lage in einem Satz:** Die Gerätemodelle und `libvirglrenderer`
sind vorhanden, aber dieses QEMU ist **ohne OpenGL gebaut**, und es gibt
in diesem LXC-Behälter **keinen DRM-Renderknoten** — weder durchgereicht
noch selbst herstellbar (kein DRM-Modul im Kernelbaum, `vgem` nicht
ladbar). Beides ist von innen nicht zu ändern.

Ein VIRGL-Pfad wäre auf diesem Wirt also **nicht einmal zu starten**,
folglich auch **nicht zu messen**. Genau das war im Auftrag als der Fall
benannt, in dem der Auftrag ein anderer ist: **Punkt 4, der Ausbau der
2D-Beschleunigung.** Das ist kein Ausweichen — es ist dieselbe Regel,
aus der schon der virtio-gpu-Treiber selbst entstanden ist: was sich
nicht überprüfen lässt, ist hier nichts wert.

### Was daraus NICHT folgt

Dass VIRGL grundsätzlich nicht ginge. Auf einem Wirt mit `/dev/dri` und
einem QEMU mit OpenGL ist der Weg offen; die Arbeit dafür ist unter
"Offene Punkte" beschrieben und nicht angefangen worden, weil sie hier
unbelegbar geblieben wäre.

---

## 2. Die Wahl der Baustelle — und warum gerade der Zeiger

Der 2D-Weg von virtio-gpu war nach der Runde VIRTIOGPU schon **nicht**
naiv: `present` holt sich das Schmutzrechteck aus `fb.rect_take` und
überträgt **nur dieses**, und beide Befehle (`TRANSFER_TO_HOST_2D` und
`RESOURCE_FLUSH`) gehen in **einem** Umlauf hinaus. Gemessen an der
Ausgangslage (800x600, bewegtes Bild):

```
vga    okt=140554012  rect=205  bilder=94  je=1495255   (ganze Bilder)
vgpu   okt=3956828    rect=43   bilder=42  je=94210     (nur Rechtecke)
```

Also **35x weniger Oktette** — "nur geänderte Rechtecke" aus Punkt 4 war
bereits gebaut. Was **nicht** gebaut war, zeigte dieselbe Messung an
anderer Stelle: `comp=186` Zusammensetzungen auf `pres=42` Bilder. Der
Grund steht in `wm.fi`:

* `paint_cursor` malt den Zeiger **in den Zweitpuffer** — drei Lagen mit
  Deckung, Bildpunkt für Bildpunkt.
* `on_mouse` macht bei **jeder** Bewegung **zwei** Rechtecke schmutzig
  (das alte und das neue), damit der Hintergrund darunter wieder stimmt.

Bei einem Zeigerstrom ist das die häufigste Arbeit des ganzen
Fenstersystems — und virtio-gpu kann sie vollständig abnehmen: Die
Spezifikation kennt eine **zweite Warteschlange** (`cursorq`) und den
Zeiger als **eigene Fläche**, die der Wirt über das Bild legt. Der
Treiber hatte davon nichts: `queue_setup` richtete nur Warteschlange 0
ein, `CURSOR` kam im ganzen Modul nur als Kommentarzeile vor
("KEINE Zeigerwarteschlange").

Das ist die Stelle, an der heute wirklich jeder Bildpunkt durch die CPU
geht — also wurde sie gebaut.

---

## 3. Was gebaut wurde

### `kernel/vgpu.fi` — die zweite Warteschlange und die Zeigerfläche

* `cursor_queue_setup` richtet **Warteschlange 1** ein: eigener Ring
  (`CRING_BYTES = 0x5000`, eigene Deskriptoren, eigene Tür `S_CDOOR`).
  Sie teilt sich mit der Steuerwarteschlange **keinen** Deskriptor — der
  Zeiger bewegt sich, während ein Bild unterwegs sein kann.
* `CMD_UPDATE_CURSOR` (0x0300) und `CMD_MOVE_CURSOR` (0x0301), Befehl mit
  fester Länge 56 Oktette (VIRTIO 1.2, 5.7.6.10).
  **Es wird nicht auf die Antwort gewartet** — der Sinn der Sache ist,
  dass eine Zeigerbewegung den Kern nicht anhält.
* Eine zweite Ressource (`CUR_RES_ID = 2`), **64x64** in
  `B8G8R8A8` — virtio-gpu führt den Zeiger immer in dieser Größe.
  Osums Zeiger ist höchstens 48x48 und liegt links oben darin.
* `cursor_bild_fuellen` baut das Bild aus **derselben Quelle**, aus der
  `wm.paint_cursor` malt (`cursor.deck` — Kern, Rand, Schatten), und
  mischt sie zu echtem BGRA mit Durchsichtigkeit.
* `cursor_zeigen` / `cursor_bewegen` / `cursor_aus`: Das **Bild** geht
  nur hinaus, wenn Form oder Größe sich geändert haben; eine Bewegung
  kostet danach **einen Befehl von 56 Oktetten**.

### `kernel/wm.fi` — der Zeiger verlässt das Bild

* `hwcur_moeglich` / `hwcur_an` / `hwcur_bewegen` als Naht zum Treiber.
* `compose` malt den Zeiger **nicht mehr**, wenn die Hardware ihn trägt
  (sonst stünde er **doppelt** im Bild).
* `on_mouse` macht bei einer Bewegung **kein Rechteck mehr schmutzig** —
  das ist die eigentliche Ersparnis.

### `kernel/kgui.fi` — `mauslauf=<n>`, eine Waage, die wirklich wiegt

`mausflut=<hz>` rechnet aus der **Uhr** (`marken * hz / 100`). Auf diesem
Wirt laufen acht Runden gleichzeitig (Lastmittel **10,5** bei 20 Kernen),
und **derselbe Kern mit derselben Zeile** lieferte nacheinander
`packets=0`, `0`, `1` — und in einem früheren Lauf `21`. Eine Waage, die
bei gleicher Last verschiedene Zahlen zeigt, wiegt nichts.

`mauslauf=<n>` schickt **genau n** Zeigerpakete, ohne die Uhr zu fragen,
und meldet `mauslauf: pakete= us= curdef= curmove= curerr= hw=`. Damit
ist die Zahl der Bewegungen eine **Zusage** und keine Beobachtung.

### Die Gegenprobe

`nohwcur` (`M_NOHWCUR = 1080`, in `kstate.fi` und `kmain.fi`): derselbe
Kern, dasselbe Gerät, nur malt `wm.fi` den Zeiger wieder selbst.

---

## 4. Die Messwerte

**2000 Zeigerpakete, 800x600, identischer Kern, `-accel kvm`.**
Der einzige Unterschied zwischen den Läufen ist `nohwcur`.

| | **mit Hardware-Zeiger** | **ohne (`nohwcur`)** | |
|---|---|---|---|
| Bilder übertragen | **17** | **2001** | **117x weniger** |
| Oktette übertragen | **3 987 456** | **9 151 692** | **2,3x weniger** |
| Zeit für 2000 Pakete | **550 596 µs** | **759 979 µs** | **~28 % schneller** |
| Oktette je Bild | 234 556 | 4 573 | |
| `curdef` / `curmove` | 17 / 1984 | 0 / 0 | |
| `curerr` | **0** | 0 | |
| **`update_cursor` BEIM WIRT** | **2001** | **0** | |

Die letzte Zeile ist die wichtigste: Sie kommt **nicht** aus dem Kern,
sondern aus QEMU selbst (`-trace virtio_gpu_* -D …`). Der Wirt bezeugt,
dass die Zeigerbefehle wirklich ankamen — und dass mit `nohwcur`
**keiner einziger** ankommt.

Die Zeit ist auf diesem Wirt lastabhängig und schwankt zwischen den
Läufen (371 ms … 550 ms mit, 527 ms … 760 ms ohne); **Bilder und
Oktette sind die harten Zahlen**, sie waren über alle Läufe identisch.

---

## 5. Der Bildbeleg

`docs/bilder/gpu3d-hw.png` und `docs/bilder/gpu3d-sw.png`, maschinell
geprüft von `tools/gpu3d/zeigerpruef.py`:

```
Groesse: 800x600, beide gleich
Unterschied: 236 Bildpunkte in x 662..676, y 399..420 (15x22)
im Softwarebild an dieser Stelle: 95 dunkle, 68 helle Bildpunkte
im Hardwarebild an derselben Stelle: 1 verschiedene Farben
       und zwar einfarbig (30, 42, 56) -- glatter Grund.
```

**Warum das ein Beweis ist und nicht nur ein Bild:** `screendump vg`
fotografiert die **Fläche des Geräts** — die Zeigerüberlagerung ist darin
nicht enthalten. Also muss gelten: Ohne den neuen Weg stehen an der
Zeigerstelle seine Farben (dunkler Kern, weißer Rand); mit ihm steht dort
**glatter Schreibtischgrund**. Genau das ist gemessen, und der
Unterschied ist **ein einziges Rechteck von 15x22** — Zeigergröße, an
der Zeigerposition. Stünde der Zeiger in beiden Bildern, würde er doppelt
gezeichnet; stünde er in keinem, wäre nichts übertragen worden.

Der Prüfer weist die falschen Fälle auch wirklich zurück (nachgefahren):
zwei gleiche Bilder → `FEHL: die Fotos sind IDENTISCH`; Bilder vertauscht
→ `FEHL: dort steht kein gemalter Zeiger`.

---

## 6. Der saubere Rückfall — gefahren, nicht behauptet

| Fall | Ergebnis |
|---|---|
| `novgpu` (Treiber abgeschaltet) | 2000 Pakete, `hw=0`, keine Panik, VGA-Weg |
| **gar kein** virtio-gpu-Gerät | 2000 Pakete, `hw=0`, keine Panik, VGA-Weg |
| Gerät ohne zweite Warteschlange | `cursor_queue_setup` gibt `false`, `S_CRING` wird 0, `init` läuft weiter |

`init` bricht am Zeiger **nicht** ab: Das Anzeigegerät steht und trägt
Bilder, der Zeiger in der Hardware ist eine Zugabe. Fällt sie aus, malt
`wm.fi` ihn weiter ins Bild — genau wie vor dieser Runde.

---

## 7. Die Abnahme

`tools/gpu3d/run.sh` — **18 Zusagen gehalten, 0 gebrochen, PASSED.**

Sie fährt den Wirtsbefund aus Abschnitt 1 **erneut**, misst mit und ohne
den Weg, prüft das Foto maschinell und fährt beide Rückfälle. Dazu:

* `python3 tools/kernel/memmap.py kernel` → **0 Kollisionen**
* `tools/check-ui.sh` → **CHECK-UI PASSED**
* `tools/build-kernel.sh` → baut (5 966 664 Oktette)
* `tools/usbimg/build.sh` → Abbild entsteht (130 MiB, GPT, EFI + Wurzel)

---

## 8. Die Speicherregel

* **kdata:** Der Runde waren `0x132000..0x138000` zugeteilt. Sie sind
  **nicht angetastet** worden — die Zeigerfelder passten in die schon
  vorhandene Seite `VGPU_OFF = 0xF2000` (belegt bis `0x148`, die Seite
  fasst `0x1000`). Die großen Puffer (Ring der zweiten Warteschlange,
  64x64-Zeigerfläche) liegen **nicht** in kdata, sondern in echten
  Rahmen aus `mem.frame_run` — so, wie es die Regel verlangt.
* **Modusindizes:** zugeteilt 1080..1087, benutzt **genau einer**:
  `M_NOHWCUR = 1080`.
* **`MODE_WORDS` bleibt 17.** Die Zuteilung liegt vollständig unter der
  harten Grenze 1087; eine Erhöhung war nicht nötig.
* `memmap.py`: `127 Bereiche in 0x140000 Oktetten kdata, 12 Vektoren,
  235 Modusnamen in 17 Woertern, **0 Kollisionen**`.

---

## 9. Zwei Fehler, die die Messung gefunden hat

Beide seien genannt, weil sie zeigen, wozu die Gegenproben da sind.

1. **Der Zeiger ging nie hinaus.** `hwcur_an` hieß zuerst
   `hwcur_moeglich(state) && vgpu.cursor_an(state)`. Beim **ersten**
   Aufruf ist `cursor_an` aber noch falsch — also nahm die Bewegung den
   Softwareweg, `cursor_zeigen` kam nie dran, und der Zeiger blieb für
   immer im Bild. Auffällig wurde es nur an der Wirtsspur: **null**
   `update_cursor`, obwohl die Fläche nachweislich angelegt war
   (`res_create_2d res 0x2` stand da). Der Kern hätte nichts gemeldet.
2. **Unterlauf in der Mischung.** `rr + (0 - rr) * ak / 255` ist die
   übliche Mischformel — aber diese Zahlen sind vorzeichenlos, `0 - rr`
   läuft unter. Der Kern blieb mit
   `panic: integer overflow in 'u64 - u64' at kernel/vgpu.fi:1069`
   stehen. Richtig ist `rr - rr * ak / 255`.

Dazu ein Fehler **in der Abnahme selbst**: `grep -c` schreibt bei null
Treffern schon `0` und gibt trotzdem 1 zurück — mit `|| echo 0` stand
`"0\n0"` in der Variablen, und die Gegenprobe meldete einen Fehler, wo
keiner war.

---

## 10. Offene Punkte — ehrlich benannt

* **VIRGL ist nicht gebaut.** Auf einem Wirt mit `/dev/dri` und einem
  QEMU **mit** OpenGL wäre der Weg: `VIRTIO_GPU_CMD_CTX_CREATE`,
  `RESOURCE_CREATE_3D`, `SUBMIT_3D` und darüber eine kleine
  Zeichen-Schnittstelle (Puffer, Eckpunkte, zeichnen, tauschen). Hier
  wäre davon keine Zeile überprüfbar gewesen. **Das Merkmalsbit
  `VIRGL` wird vom Treiber weiterhin ausdrücklich abgelehnt** — was man
  nicht bedienen kann, nimmt man nicht an.
* **Mehrere Scanouts** (Punkt 4, letzter Teil) sind **nicht** gebaut.
  `S_SCANOUTS` wird gelesen und gemeldet, benutzt wird weiterhin
  Scanout 0. QEMU müsste dafür mit `max_outputs>1` laufen, und das
  Fenstersystem hat heute keinen Begriff von zwei Schirmen — das ist
  eine eigene Runde (G-007) und kein Nebenher.
* **`SET_SCANOUT` zur Laufzeit** (Größenwechsel) ist weiterhin nur
  erkannt, nicht ausgeführt: `ereignis_pruefen` merkt sich die neue
  Größe, der Rahmenpuffer wird **nicht** mitten im Betrieb getauscht.
  Unverändert gegenüber der Runde VIRTIOGPU.
* **Der Zeiger kennt nur Scanout 0** (`scanout_id` fest 0) — folgt aus
  dem Punkt darüber.
* **`cursor_aus` ist gebaut, aber ungefahren.** Der Weg, den Zeiger zu
  verstecken (`UPDATE_CURSOR` mit `resource_id = 0`), wird von `wm.fi`
  heute nicht gerufen, weil der Schreibtisch ihn immer zeigt. Er steht
  da und ist nicht gemessen — das ist der ehrlichere Satz als "vorhanden".
* **Die Zeit schwankt lastabhängig.** Auf einem ruhigen Wirt wäre die
  Zeitzahl schärfer; Bilder und Oktette sind davon unberührt.
