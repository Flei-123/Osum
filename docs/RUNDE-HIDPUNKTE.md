<!-- SPDX-License-Identifier: GPL-2.0-only -->
# RUNDE HIDPUNKTE — der falsche Regler hat gewonnen

**03.09.2026**, Zweig `hidpunkte`, auf `main` nach Runde HIDWEG.
Abnahme: `bash tools/hidpunkte/run.sh` → **19 gehalten, 0 gefallen**.

---

## 0. WAS JUSTIN GEMESSEN HAT

Zweiter Blech-Lauf auf seinem AMD-Brett, Abbild `46df9d4c`, zwei Fotos.
Die Runde davor hat damit **teilweise** recht behalten und **teilweise
nicht**:

| | |
|---|---|
| `usb: hc0 … events=50 IRQS=20` | die Meldung läuft jetzt auch auf hc0 (vorher `irqs=0`) |
| `usb: hc1 melde=MSI-X` | MSI-X greift auf echtem Silizium |
| **Eingabe im Schreibtisch** | **weiterhin tot** — Zeiger unbewegt, keine Taste |
| **Taskleiste** | **unten nichts, reines Blau** |
| **Terminalfenster** | links abgeschnitten: „al -- sh" statt „Terminal -- sh" |
| **Mauszeiger** | ein weißer Fleck, kein Pfeil |

Die drei Bildfehler haben eine gemeinsame Ursache, und der Eingabefehler
eine eigene. Alle vier sind **nachgestellt**, bevor etwas geändert wurde.

---

## 1. DER SPERRPUNKT: `usb.stage` HAT DEN FALSCHEN REGLER BEHALTEN

Das ist keine Vermutung. Justins Aufstellung ist in QEMU nachstellbar,
weil `usb-tablet` derselbe Fall ist wie seine Kingston `0951:16df`:
HID, `class=03:00:00`, **kein** Boot-Protokoll.

```
hc0 (qemu-xhci)     usb-storage  +  usb-tablet      <- sein Stick + die Kingston
hc1 (nec-usb-xhci)  usb-kbd      +  usb-mouse       <- seine Tastatur + Maus
```

**Gemessen, vor der Änderung:**

```
usb: xhci … hc=0
usb: port=1 … class=08:06:50 driver=msc
usb: port=6 … class=03:00:00 driver=mouse      <- das Tablet, generisch gebunden
usb: devices=2 kbd=0 mouse=1 msc=1
eingabe: ber=2 … ta=0 lo=0 bew=0 pk=2 wm=3
```

`ta=0 lo=0 bew=0`. **Keine Taste, keine Bewegung** — genau Justins Bild.
hc1 taucht im ganzen Mitschnitt nicht auf; er wurde nie aufgesetzt.

Der Grund stand in `usb.fi` in vier Zeilen:

```
while u < anzahl {
    if versuch(state, u, armed) { behalten = u; u = anzahl }   // der ERSTE gewinnt
    else { u = u + 1 }
}
```

`versuch` gab `have_kbd || have_mouse` zurück. Runde HIDWEG hatte die
generische HID-Bindung eingebaut — seither zählt **jedes** Gerät, dessen
Berichtsbeschreibung nach Zeigegerät aussieht, als Maus. Damit gab hc0
`true`, die Schleife brach ab, und der Regler mit der Tastatur wurde nie
angefasst. Die Runde davor hat den Fehler also nicht nur nicht gefunden —
sie hat ihn **eingebaut**.

**Behoben:** jeder Regler wird aufgezählt und **bewertet**, danach wird
der beste noch einmal aufgesetzt. Die Punkte richten sich nach der
Schnittstelle und nicht danach, auf welchem Weg der Kern sie gerade
liest:

| was am Regler hängt | Punkte |
|---|---|
| Boot-Tastatur oder Boot-Maus (Unterklasse 1, Protokoll 1/2) | 8 |
| HID, das nur über seine Berichtsbeschreibung als Tastatur/Zeiger durchgeht | 3 |
| sonstiges HID (Verbrauchersteuerung, Lautstärkeregler) | 1 |
| **Massenspeicher** | **0** |

Der Stick zählt absichtlich null: Kern und Wurzelabbild sind zu diesem
Zeitpunkt längst geladen (Multiboot-Module). Ein Regler ohne Eingabe ist
für einen Menschen vor dem Schirm wertlos.

**Gemessen, nach der Änderung, dieselbe Aufstellung:**

```
usb: wahl hc0=3 hc1=16  -> hc1
eingabe: ber=11 irq=46 … ta=3 lo=3 bew=5 pk=5 wm=6
```

| | `ta` | `lo` | `bew` | `pk` | `wm` |
|---|---|---|---|---|---|
| vorher | **0** | **0** | **0** | 2 | 3 |
| nachher | **3** | **3** | **5** | **5** | **6** |

Und die **Gegenprobe in die andere Richtung** (Tastatur+Maus an hc0, das
schwache HID an hc1) gibt `-> hc0` und ebenfalls `ta=3 bew=5`. Ohne sie
wäre aus einer festen Wahl nur eine andere feste Wahl geworden.

Die Zeile `usb: wahl hc0=… hc1=… -> hcN` steht ab jetzt in jedem
Bericht. Sie ist die eine Zeile, an der auf einem Foto abzulesen ist,
welcher Regler bedient wird.

---

## 2. WAS DAMIT NOCH IMMER NICHT GEHT — UND DAS IST WICHTIG

**Es wird weiterhin nur EIN Regler gleichzeitig gefahren.** Der Vorrat
des Treibers (`0x50000..0x58000`: Ringe, Zusammenhänge, Endpunkttafel)
ist einmal da; zwei Regler gleichzeitig hieße, ihn zu verdoppeln und
jeden Zugriff reglerrelativ zu machen — eine eigene Runde.

Für Justin heißt das konkret: **Tastatur und Maus müssen am selben
Regler stecken.** Tun sie das (wie auf seinem Foto: beide an hc1),
gewinnt dieser Regler jetzt zuverlässig. Steckt die Tastatur an hc0 und
die Maus an hc1, gewinnt der mit mehr Punkten und das andere Gerät
bleibt stumm. Der Bericht sagt für jeden Regler, was an seinen
Anschlüssen steht — die Zeile `usb: hcN … verbunden=` — damit man
notfalls umstecken kann.

---

## 3. `ctx=64` WAR NIE GETESTET

Justins hc1 meldet `ctx=64`, QEMU meldet überall `ctx=32`. In
`xhci.fi` stand:

```
fn devctx(state, slot) -> u64 { return state + DEVCTX_OFF + (slot - 1) * 1024 }
```

Ein Gerätezusammenhang hat 32 Einträge, und wie groß ein Eintrag ist,
sagt der **Regler** in HCCPARAMS1. Bei 32 Oktett geht `32 * 32 = 1024`
auf. Bei **64** braucht einer 2048 — und der zweite Steckplatz lag
mitten im ersten; ab dem dritten wären die Übertragungsringe
überschrieben worden.

Der Abstand ist jetzt gerechnet (`32 * ctx_size`), und `max_slot` sagt,
wie viele Steckplätze in den Bereich passen: vier bei 32 Oktett, **zwei**
bei 64. Ein drittes Gerät an einem `ctx=64`-Regler wird jetzt abgelehnt,
statt Speicher zu zerstören. Justin hat dort zwei.

Das ist ein **latenter** Fehler, keiner, der sein Bild erklärt — aber er
wäre beim nächsten Gerät zugeschlagen.

---

## 4. DIE DREI BILDFEHLER: ALLE DREI SIND DER SCHIRM

Nachgestellt mit `fbres=3440x1440` (bis dahin lief hier alles auf
1280x800). Der Kern meldet dort `fb: skala x2`, also `uiscale=2`.

### 4.1 Die Taskleiste war **128 Bildpunkte breit**

```
taskbar: size w=3440 h=56 rc=-4      <- der Wunsch scheitert
taskbar: STEHT x=0 y=1384 w=3440 h=56
```

Und im Bildschirmfoto nachgemessen: die Leiste weicht in Zeile 1410 nur
von x=0 bis **x=127** vom Hintergrund ab. Der Rest ist Hintergrund.
Justin sieht das als „unten ist nichts" — 128 Punkte ganz links unten
auf einem Ultrawide übersieht man.

Der Grund stand in `wm.resize_win`:

```
if w * h * 4 > wg(state, i, W_BUFBYTES) {
    return false // ohne neuen Puffer nicht groesser als angelegt
}
```

Die Leiste entsteht klein und will auf `3440 x 56` wachsen — 770 560
Oktett. Der Server weigerte sich und legte **keinen** neuen Puffer an.
Auf 1280x800 passte der Wunsch zufällig in den vorhandenen Puffer,
deshalb ist das nie aufgefallen.

**Behoben:** ein Fenster, das wächst, bekommt einen größeren Puffer
(`mem.frame_run`). Nachher: `rc=0`, und im Bildschirmfoto reicht die
Leiste von **x=7 bis x=3433**.

### 4.2 Das Terminalfenster war zu schmal für seinen eigenen Titel

`wm.create(state, 0, 24, 40, 560, 380, …)` — feste Bildpunkte. Bei
`uiscale=2` ist die Zeichenzelle 20x38; 560 Punkte sind dann **28
Spalten**. In 28 Spalten passt weder „Terminal -- sh" in die Titelzeile
noch „K10 WINDOW SERVER 0123 …" in eine Zeile. Der Titel wird **mittig**
gesetzt, ist breiter als das Fenster und ragt links hinaus — und links
abgeschnitten liest man das **Ende**: „al -- sh". Genau das steht auf
Justins Foto.

**Behoben:** das Fenster wächst mit derselben Zahl wie alles andere an
dieser Oberfläche (`wm.uisc`), und es bleibt in jedem Fall ganz auf dem
Schirm. Nachher: `wm: term win=0 cols=56 rows=20`.

### 4.3 Der Zeiger war ein Pfeil — nur zu klein, um einer zu sein

Die Bitmaske stimmt. Aus dem echten Bildschirmfoto (3440x1440)
geschnitten war der Zeiger **8 mal 15 Bildpunkte** groß. Auf einem
34-Zoll-Ultrawide ist das ein Fleck, und als „einzelner weisser Fleck"
hat Justin ihn beschrieben.

Titelleiste, Rand und Schrift wachsen seit Runde SCHIRM mit
`uisc(state)`; der Zeiger war das einzige Stück Oberfläche, das es nicht
tat. Jetzt wird jeder Bildpunkt der Maske zu einem Block von `uisc` mal
`uisc`. Auf 1280x800 (uisc=1) ändert sich damit **kein einziger
Bildpunkt** — das ist die Gegenprobe.

**Aus dem echten Bildschirmfoto, nachher, 16x30:**

```
    ....
    ....
    ..##..
    ..##..
    ..####..
    ..####..
    ..######..
    ..######..
    ..########..
    ..########..
    ..##########..
    ..##########..
    ..############..
    ..############..
    ..##############..
    ..##############..
    ..################..
    ..################..
    ..##############....
    ..##############....
    ..############..
    ..############..
      ..##########..
      ..##########..
        ..########..
        ..########..
          ..######..
          ..######..
          ..######..
          ..######..
          ..######..
          ..######..
          ..........
          ..........
```

`#` Füllung, `.` Rand. Spitze oben links, durchgehender Körper,
durchgehender Schwanz, umlaufender Rand. Der Läufer schneidet dieses
Bild bei jedem Lauf neu aus und legt es nach `docs/shots/hidpunkte/`.

---

## 5. DIE MESSLEISTE — DIAGNOSE, DIE AN NICHTS HÄNGT

Der Eingabepuls stand bisher **im Terminalfenster**. Auf Justins Brett
war ausgerechnet dieses Fenster zu schmal und links abgeschnitten: die
Diagnose war da, wo man sie am wenigsten lesen konnte.

`wm.messleiste` malt dieselbe Zeile jetzt zusätzlich **oben links
unmittelbar in den Rahmenpuffer**, an `compose` vorbei, mit dem
eingebauten Bitmapzeichensatz — kein Fenster, kein Puffer, keine Arena,
keine TTF-Schrift. Sie steht deshalb auch dann da, wenn Fensterserver,
Taskleiste und Schrift allesamt versagen. Schwarz hinterlegt, grüner
Text, mit `uisc` vergrößert.

Im Bildschirmfoto nachgemessen: **2266** grüne Bildpunkte in den obersten
40 Zeilen.

---

## 6. DIE ABNAHME

```
bash tools/hidpunkte/run.sh   ->  19 gehalten, 0 gefallen
bash tools/k17/run.sh         ->  158 passed, 0 failed
bash tools/hid/run.sh         ->  57 bestanden, 0 gefallen
```

### Die zwei roten Zusagen in `tools/hidweg/run.sh` — und warum sie dem Läufer gehörten

Der Läufer meldete nach dieser Runde `28 gehalten, 3 gefallen`. Die drei
Zusagen vergleichen die **letzte** Pulszeile mit der **ersten**
(„irq steigt", „ber steigt", „der Zeiger bewegt sich").

Das ist **keine Regression**, und das ist gemessen und nicht behauptet:
derselbe Läufer, **derselbe Kern ohne die Änderungen dieser Runde**
(`git stash`, neu gebaut, 3 897 100 Oktett):

```
eingabe: ber=13 irq=47 … mk=1016 … xy=799,539 … sh=1     <- erste Zeile
eingabe: ber=13 irq=47 … mk=5516 … xy=799,539 … sh=12    <- letzte Zeile
```

Erste und letzte Zeile sind in `ber`, `irq` und `xy` **identisch**. Der
Läufer wartete auf das Terminalfenster und speiste dann elf Sekunden
Eingabe ein; der Puls hängt aber an den Marken (alle fünf Sekunden).
Fiel die Eingabe in diese Lücke, stand in der ersten Pulszeile schon
alles — und dieselbe Zahl ist nicht größer als sie selbst.

**Repariert wurde deshalb der Läufer, nicht die Zusage:** er wartet jetzt
auf die erste Pulszeile, bevor er einspeist, und `feld1` nimmt die erste
**vollständige** Zeile (erkennbar am letzten Feld `sh=`) — die erste
Zeile ist beim Lesen sonst oft halb geschrieben, und ein leerer
Vergleichswert lässt jede Zusage darauf fallen.

### `tools/desktop/run.sh`: 19 rote Zusagen, und keine davon ist neu

Der Läufer rechnet durchgehend mit `SCREEN_W=800 SCREEN_H=600`, gibt QEMU
aber keine Auflösung mit und bekommt 1280x800 — er sagt das in jeder
seiner Meldungen selbst („work area (0, 0, 1280, 800), expected
(0, 0, 800, 600)"). Runde BLECH-HID und Runde HIDWEG haben dasselbe
vermerkt.

Die roten Zeilen sind Zeile für Zeile gegen den Lauf der Runde davor
gehalten (Zahlen normalisiert, sortiert, `comm`):

```
nur VORHER (also jetzt behoben):  FAIL  tools/kN/run.sh: KN: N passed, N failed
nur JETZT (also neu):             — keine —
```

**20 vorher, 19 jetzt, kein einziger neuer.** Nichts in dieser Runde
fasst die Bildschirmgröße an; der Läufer gehört einer eigenen.

---

## 7. WAS DIESE RUNDE NICHT ERREICHT HAT

* **Kein Beweis auf Justins Blech.** Alles hier ist in QEMU gemessen,
  mit einer nachgestellten Aufstellung. Ob es auf `1022:43d5` und
  `1022:149c` greift, sagt erst sein nächstes Foto.
* **Zwei Regler gleichzeitig** gibt es weiterhin nicht (Abschnitt 2).
* **Kein Hub-Treiber.** Hängen Tastatur und Maus hinter einem USB-Hub
  (auch im Monitor oder in der Tastatur), sieht Osum sie nicht.
* **`taskbar: icons=0`** — die Symbolliste ist auch auf 3440x1440 leer.
  Die Leiste ist jetzt sichtbar und trägt ihre Knöpfe, aber die Symbole
  fehlen weiterhin. Das gehört einer eigenen Runde.
* **Justins genaue Auflösung ist unbekannt.** Gemessen wurde 3440x1440,
  weil das die verbreitetste Ultrawide-Größe ist. Meldet sein Schirm
  etwas anderes, kann die Zahl in `fb: … skala x` abweichen — die
  Fehlerursachen (Puffer, feste Bildpunkte, unskalierter Zeiger) hängen
  aber nicht an einer bestimmten Auflösung, sondern daran, dass sie
  größer ist als 1280x800.
