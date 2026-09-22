# RUNDE MODULE — die Anzeigemodule des Schreibtischs

Justins Auftrag, 22.09.2026, wörtlich:

> „und man soll das alles einstellen können also so wie in einem
> minecraft client die ganzen module hin und herschieben etc"

Gemeint sind die Anzeigen, die Lunar, Badlion und Feather über das Bild
legen: Uhr, Speicher, Last. Der Nutzer macht einen Bearbeitungsmodus
auf, zieht jedes Kästchen an seinen Platz, und nach dem Neustart liegt
es wieder dort.

---

## 1. Was schon dalag — und warum es nicht reichte

In diesem Projekt lagen bei **zehn von zehn** gemeldeten „Lücken" schon
fertige Sachen im Baum. Deshalb zuerst die Bestandsaufnahme:

| Gefunden | Trägt es? |
|---|---|
| `kernel/user/pluguhr.fi` + `kernel/ui/wmplug.fi` (Runde WMPLUGIN) | **Nein.** Erweiterungen sind Ring-3-Prozesse und dürfen **ausdrücklich nicht malen**: ein Plugin schickt 31 Oktette Text (`WM_PLUG_BAR`), die **Taskleiste** malt sie an ihrem festen Platz. Ein Leistenfeld hat kein x/y. |
| `kstate.MODUL_OFF` (0xA9000) | **Nein** — das ist der **ELF-Modullader** (`kernel/ldr/module.fi`). Nur der Name ist gleich. |
| Zweig `modul` (lokal + origin) | **Leer** gegenüber `main` (`git log main..modul` = nichts). |
| `wlib.drag_take/drag_an/drag_drop`, Zugbild `zug_bilder` | **Teilweise.** Das ist das Ziehen von **Daten** zwischen Fenstern (Explorer legt einen Pfad hinein). Ein Modul zieht keine Daten, es bewegt sich selbst. |
| `wlibc.snap` / `grid` — das Viererraster | **Ja**, wird benutzt und nicht nachgebaut. |
| `kernel/pwr/batt.fi`, Uhr in `taskbar.fi` | **Ja** als Vorbild; die Uhr liest ihren Zeitversatz aus `/etc/time.conf`. |

Ein Modulsystem für den Schreibtisch gab es **nicht**. Das ist die erste
gemeldete Lücke dieses Projekts, die wirklich eine war.

---

## 2. Was gebaut wurde

### `kernel/user/modul.fi` (neu)

Die Tafel, die Lage, das Ziehen, die Datei. Acht Plätze vorgesehen, drei
belegt (`uhr`, `speicher`, `cpu`).

**Die Lage wird relativ zu einer Ecke gespeichert.** Das ist der Kern:

```
anker ∈ {links oben, rechts oben, links unten, rechts unten}
dx, dy  zählen von dieser Ecke aus nach innen
```

`x_von`/`y_von` sind die **einzige** Stelle, die daraus Bildpunkte
macht — stünde die Formel zweimal da (einmal beim Malen, einmal beim
Melden), wäre die Messung eine Tautologie.

Nachgerechnet über sieben Auflösungen von 320×240 bis 3840×2160:
**0 Module außerhalb des Schirms.** Die Gegenprobe mit fest
gespeicherten Bildpunkten verliert dasselbe Modul bei drei davon.

### `kernel/user/desktop.fi` (erweitert)

| Neu | Wozu |
|---|---|
| `fleck(x,y,w,h)` | malt **nur** das Rechteck eines Moduls neu. `all_paint` malt 800×600 = 480 000 Punkte einzeln; das je Modulbild zu wiederholen wäre der sichere Weg, eine Uhr teurer zu machen als den ganzen Schreibtisch. Gemalt wird mit `color_at`, also mit **derselben** Rechnung wie das große Bild. |
| `modul_malen` / `module_malen` | streifenweise, weil die Malfläche nur `wlibc.surf_rows()` Zeilen trägt. |
| `modul_say` / `module_say` | die Belegzeilen: Anker **und** Abstand **und** die daraus gerechneten Bildpunkte. |
| `EV_DOWN`/`EV_MOVE`/`EV_UP` | Anfassen, Ziehen, Loslassen. |
| Takt alle 40 Runden (= 1 s) | und **nur**, wenn `werte_holen` eine echte Änderung meldet. |

### Die Datei: `/etc/module.conf`

```
# /etc/module.conf -- name=an,anker,dx,dy
uhr=1,2,0,80
speicher=1,1,16,60
cpu=1,1,16,104
taste=280
```

**Eigene Datei und nicht `/etc/theme.conf`:** theme.conf ist die
*Erscheinung* (Schema, Modus, Akzent, Form) und wird von `theme_reload`
verteilt. Die Lage von Kästchen ist keine Erscheinung, und sie ändert
sich beim Ziehen im Sekundentakt — sie dorthin zu schreiben hieße, bei
jedem Zug das Farbschema neu zu verteilen. Dieselbe Trennung hält schon
`/etc/taskbar.conf` ein.

---

## 3. Zwei Fehler, die erst die Messung gefunden hat

**1. Zwei Uhren, zwei Zeiten.** Das Modul zeigte `06:32`, die Taskleiste
`08:32`. Beide hatten recht: der Kern liefert die Hardware-Uhr (UTC),
der Versatz auf die Ortszeit steht in `/etc/time.conf`. Die Taskleiste
liest ihn seit Runde ECHTHARDWARE-3, das Modul las ihn nicht. Behoben —
mit derselben Bedingung wie dort (`I_TZMIN == 0`), sonst wird er ein
zweites Mal addiert, und *das* war der Fehler jener Runde.

**2. Eine Treppe statt einer Kante.** Die drei Kästchen waren 74, 178
und 100 Bildpunkte breit und hingen am rechten Anker — also standen ihre
**linken** Kanten an drei verschiedenen Stellen. Jetzt nehmen alle die
Breite des breitesten (184).

Beide waren im Quelltext unsichtbar und nur im Bild zu sehen.

---

## 4. Was **nicht** geht: F9

Geplant war F9 als Bearbeitungstaste. **Sie kommt nie an.**

Der Schreibtisch liegt auf `L_DESK`, und der Fensterserver gibt einem
Fenster dieser Ebene den Fokus mit Absicht nicht — `kernel/ui/wm.fi`,
`on_down`:

> „RUNDE DESKTOP: SCHREIBTISCH UND TASKLEISTE NEHMEN DIE TASTATUR NICHT.
> […] ein Schreibtisch, der den Fokus an sich zieht, macht jeden
> Tastendruck danach wirkungslos."

**Gemessen:** `sendkey f9` über den QEMU-Monitor, 54 Befehle angekommen,
in der seriellen Ausgabe **keine einzige** `module bearbeit=`-Zeile.

Deshalb schaltet jetzt der **rechte Mausknopf** auf einem Modul den
Bearbeitungsmodus. Ein Minecraft-Client macht sein Modulfenster auch mit
einem Klick auf.

**Die Taste ist trotzdem schon da:** `taste=280` (0x118 = F9) steht in
`/etc/module.conf`, wird gelesen, geschrieben und ist einstellbar — sie
wartet nur auf den Weg, auf dem sie ankommt. Der saubere Weg dafür
existiert bereits: das globale Kürzelregister `WM_PLUG_KEY` mit dem
Recht `R_ACT_KEY`. Das ist die **nächste Runde** und kostet keinen
Eingriff in `wm.fi`.

---

## 5. Was es kostet

Drei Läufe zu je 20 Sekunden, `wm: pixels=` und `composites=` vom
Fensterserver selbst gezählt (`tools/dmodul/kosten.sh`):

| Lauf | composites | pixels | gegenüber „aus" |
|---|---:|---:|---:|
| alle Module **aus** | 62 | 1 315 440 | — |
| alle drei **an** | 64 | 1 470 512 | **+11,79 %** |
| **Bearbeitungsmodus** | 66 | 1 438 576 | +9,36 % |

Ein Modulsatz misst 3 × 184 × 36 = **19 872 Bildpunkte** je
Neuzeichnung. Die 155 072 zusätzlichen Bildpunkte sind also rund **7,8
Neuzeichnungen in 20 Sekunden** — eine alle 2,6 Sekunden, und das passt
genau zum Sekundentakt mit Änderungsprüfung.

Zum Rahmen: eine Blur-Blase 360×120 kostet gemessen 3,1 ms = 18 % des
60-Hz-Budgets. Ein Modulsatz wäre **mit diesem Satz** 1,43 ms = 8,6 % —
und Module haben **keinen** Weichzeichner, sind also ein Vielfaches
billiger. Deshalb bekommt ein Modul eine Tafel aus dem Schema und kein
Acryl; wer Acryl will, holt es über `WF_BLUR` am Fenster.

---

## 6. Die Abnahme

`bash tools/dmodul/run.sh <ausgabe>` — **grün=10, rot=0.**

Sie heißt `dmodul` und nicht `modul`, weil `tools/module/run.sh` schon
existiert: das ist der Läufer des **nachladbaren Treibers**. Zwei Läufer
mit fast demselben Namen im selben Verzeichnis sind die Falle, in die
eine spätere Runde tritt.

| Bild | Was es zeigt |
|---|---|
| `belege/module/1-vorgabe.png` | ohne `/etc/module.conf`: drei Kästchen rechts oben, `anker=1`, `x=1080` |
| `belege/module/2-gezogen.png` | nach Rechtsklick + Zug: `uhr an=1 anker=2 dx=0 dy=80 x=0 y=684` |
| `belege/module/3-neustart.png` | **dieselbe Platte** neu gebootet: die Uhr liegt wieder links unten |

**Die Gegenprobe, ohne die Bild 3 nichts sagt:** zwischen Lauf 2 und
Lauf 3 wird die Platte **nicht** neu gebaut. Ein `mkfs`, zwei Boots.
Zusätzlich wird die Datei aus der Platte zurückgelesen
(`mkfs.py cat`) — `uhr=1,2,0,80`.

---

## 7. Abnahmen und Revier

`tools/check-ui.sh`: **197 Dateien, 0 Verstöße** (196 vorher — die neue
Datei ist mitgezählt).
`pruef/anim-ab.sh`: **anim=4**.

**Pflichtliste:** `/etc/module.conf` steht in `tools/usbimg/build.sh` im
Bauplan **und** in `PFLICHT`. Gegenprobe gefahren: Eintrag aus dem
Bauplan genommen → `== FEHLT IM ABBILD: /etc/module.conf`, RC=1.
(`nedit` und `bold.ttf` sind genau daran zweimal gescheitert.)

**Revier:** `kernel/ui/wm.fi` und `kernel/user/taskbar.fi` wurden
**nicht angefasst** — dort sitzen die zwei Parallelrunden.
Geändert: `kernel/user/desktop.fi`, `tools/usbimg/build.sh`,
`tools/look/shot.sh`. Neu: `kernel/user/modul.fi`,
`tools/dmodul/run.sh`, `tools/dmodul/kosten.sh`.

---

## 8. Nächste Runde

1. **Echtes Tastenkürzel** über `WM_PLUG_KEY` (`R_ACT_KEY`,
   `/etc/wmplug.conf`) — ohne `wm.fi` anzufassen. `taste=` liegt bereit.
2. **Die Seite „Darstellung"** in `settings.fi`: Liste aller Module mit
   Kästchen, Taste einstellbar, „Anordnung zurücksetzen"
   (`modul.zuruecksetzen()` gibt es schon).
3. **Drei weitere Module**: Netzdurchsatz, Bilder je Sekunde, Akku
   (`batt.fi` liest ihn bereits). Die Tafel hat acht Plätze.
4. **Mehrere Modulfenster** („wie in CachyOS"), wenn Justin das
   weiterhin will — das wäre eine Gruppe von Modulen mit gemeinsamem
   Anker.
