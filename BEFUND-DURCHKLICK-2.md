# BEFUND DURCHKLICK-2 — derselbe Durchgang, gegen das Abbild der Runde TÜRSCHLOSS

**Frage von Justin (unverändert seit DURCHKLICK):** „Geht wirklich alles?
Kann ich das OS booten und darin arbeiten?"

**Kurze Antwort:** Der Unterschied zur Vorrunde ist der zwischen *Vorführstück*
und *benutzbar*. In DURCHKLICK ließ sich **kein einziges Programm starten**
(`pid=-22` bei jedem Versuch), die Shell starb in einer Endlosschleife, es gab
keinen Übersetzer, kein Herunterfahren und keine deutsche Tastatur. Das ist
alles behoben und gemessen: ein Programmstart liefert jetzt **`pid=19`** statt
`-22`, `sh: bye` kommt **kein einziges Mal** mehr vor, `firnc` und `fas` liegen
auf dem Stick und übersetzen dort ein Programm, das mit **42** zurückkommt,
`shutdown` fährt über ACPI S5 herunter, und die Tastatur kommt **deutsch** hoch.

**Ergebnis nach dem Zwischenruf: 29 von 48 Punkten GEHT bei 1280x800, 25 von
42 bei 1920x1080** — vorher waren es **17 von 41**. Übrig bleiben bei 1280x800
noch **drei** echte „GEHT NICHT" (drei der sechs Programmstarts), bei 1920x1080
nur **einer**, und der ist ein Lesefehler auf der seriellen Leitung (3.1).

**Die drei Punkte aus dem Zwischenruf sind beantwortet:**
* **4.1 ist KEINE Regression.** Derselbe Zug gegen das alte merge8-Abbild und
  das neue liefert Zahl für Zahl dasselbe — beide **JA**. Der Fehler lag im
  Meßaufbau (QEMU-Monitor zog mit dem absoluten Tablet), nicht im System.
  Abschnitt 4.
* **4.2 geht ebenfalls** — auch auf merge8. Der Griff wurde nie getroffen, weil
  er aus der *alten* Fensterlage gerechnet wurde. Im 1920er Durchgang jetzt
  gemessen: `560x380` → **`714x484`**.
* **3.7** hat einen **echten Systemfehler** zutage gefördert: die Meßtafel malte
  ohne das Wort `tafel` über den ganzen Schirm. Behoben; danach steht
  `osum$ echo Gruesse` → `Gruesse` im Fenster, und 3.7 ist bei 1920x1080
  **GEHT**.

Daß es 48 statt 41 Zeilen sind, liegt an den Punkten, die DURCHKLICK gar nicht
erst prüfen konnte: sechs einzelne Programmstarts statt fünf, dazu 7.5, 8.1 und
8.2, die dort „entfällt" waren. (Der 1920er Lauf zählt 42, weil die
Programmstarts dort in einem Block gemessen wurden.)

**Der wichtigste Einzelfund dieser Runde steht nicht in der Tabelle:** Der
Meßaufbau der Vorrunde startete QEMU mit `-device usb-ehci`. Dieser Kern hat
genau **einen** USB-Wirtstreiber, und das ist **xHCI**. Auf der seriellen
Leitung stand deshalb in *jedem* Lauf von DURCHKLICK `usb: no controller`, und
es kam **nie eine Taste an**. Jede Aussage der Vorrunde über Tastatur — Super+A,
Alt+Tab, Tippen, AltGr — hat den Schalter gemessen und nicht das System.

---

## 0. Aufbau der Messung

| | |
|---|---|
| Abbild | `tools/usbimg/build.sh` aus diesem Baum, Stand `4c1a1be+` (Runde TÜRSCHLOSS) |
| Kern / Wurzel | `pruef/osum.mb` (5 391 676 Oktett) + `pruef/root.img` (20 971 520 Oktett, OFS v3) |
| Maschine | `qemu-system-x86_64 -accel kvm -cpu host -m 2048 -smp 4 -vga std`, **`-device qemu-xhci`** + `usb-tablet` + `usb-kbd`, virtio-net, Monitor auf Unix-Socket |
| Kommandozeile | `pruef/start.sh` — wörtlich der Schreibtisch-Eintrag aus `limine.conf`, ohne `tafel` und ohne `dhcp` (Begründung dort im Kopf) |
| Auflösungen | **1280x800 und 1920x1080**, beide vollständig |
| Werkzeuge | `pruef/durchklick3.py` (41 Punkte), `pruef/klick.py`, `pruef/sicht.py`, `pruef/start.sh`, `pruef/montage2.py` — die Vorbilder aus `/root/osum-durchklick/` sind übernommen und im Kopf jeder Datei begründet, wo sie abweichen |
| Fotos | `pruef/shots/dk1280/`, `pruef/shots/dk1920/`, Übersicht `pruef/uebersicht-2.png` |
| Rohdaten | `pruef/laeufe/dk1280/befund.json`, `pruef/laeufe/dk1920/befund.json`, serielle Mitschnitte daneben |

**Wie hier „gesehen" wird** — wie in der Vorrunde, nichts wird behauptet:
1. `tools/usbimg/suchtext.py` rastert eine Textzeile mit `assets/osum-sans.ttf`
   und gibt den Anteil getroffener Tintenpunkte. 100 % = der Text steht da.
   **Korrektur gegenüber dem ersten Entwurf dieser Runde:** der Aufruf lautet
   `suchtext.py <ppm> <ttf> <px> <text>`; ein Skript, das die Argumente anders
   herum übergibt, bekommt immer `None` und beantwortet die Umlautfrage dann
   versehentlich aus der seriellen Leitung.
2. `sicht.py vergleiche` zählt geänderte Bildpunkte zwischen zwei Fotos.
3. Die serielle Leitung — und dort **zwei neue Zeilen dieser Runde**, ohne die
   die Hälfte der Tastaturpunkte gar nicht meßbar wäre:
   * `wm: fokus id=<neu> vor=<alt>` bei **jedem** Wechsel des Eingabefokus,
   * `wm: hot c=<taste> mod=<mods> act=<handlung>` + `wm: hot getan=<0|1>` für
     jedes Tastenkürzel, das der Fensterserver aus dem Ring holt.

---

## 1. Die Tabelle: alle 41 Punkte, VORHER und NACHHER

**VORHER** = `/root/osum-durchklick/BEFUND-DURCHKLICK.md` (08.09.2026, Abbild
`orientos-usb-20260906-db3e942.img`).
**NACHHER** = dieser Lauf. Beide Auflösungen gaben dasselbe Ergebnis; wo nicht,
steht es dabei.

### 1. Start

| # | Prüfpunkt | VORHER | NACHHER | Beleg (gemessen) |
|---|---|---|---|---|
| 1.1 | Boot bis Schreibtisch | GEHT | **GEHT** | 28,2 s bis `taskbar: start x=` (mit KVM neben sieben weiteren QEMUs auf derselben Platte; DURCHKLICK maß ~4 s auf leerer Maschine) |
| 1.2 | Anmeldung / Sperrbildschirm | entfällt | **entfällt** | es gibt keinen; der Schreibtisch kommt direkt |
| 1.3 | Rahmenpuffer sauber | GEHT | **GEHT** | `fb: 1280x800x32`, `fb: selftest 13 / 13 failed=0x0` |
| 1.4 | Schriften geladen | GEHT | **GEHT** | `ttf: mono glyphs=366`, `sans glyphs=364`, `icons glyphs=47` |
| 1.5 | 1920x1080 | GEHT | **GEHT** | `fb: 1920x1080x32`, ganzer Durchgang gefahren |

### 2. Leiste

| # | Prüfpunkt | VORHER | NACHHER | Beleg |
|---|---|---|---|---|
| 2.1 | Leiste steht | GEHT | **GEHT** | `taskbar: start x=2 y=7 w=34 h=26`; Fensterliste: `wm: fen ... x=0 y=760 w=1280 h=40 lay=2` |
| 2.2 | Uhr läuft ohne Eingabe | GEHT | **GEHT** | `t=16:59:26` → `t=17:00:36`, zwei Fotos 70 s auseinander |
| 2.3 | Startknopf sichtbar | GEHT | **GEHT** | `taskbar: start x=2 y=7 w=34 h=26` |
| 2.4 | Startmenü per **Maus** | GEHT | **GEHT** | **41,31 %** der Bildpunkte geändert, `taskbar: startmenue auf` |
| 2.5 | Startmenü per **Super-Taste** | **GEHT NICHT** | **GEHT** ✅ | `taskbar: klinke` kommt, `taskbar: startmenue auf`, **4,61 %** Bildpunkte geändert (DURCHKLICK: 0,25 %, weil nie eine Taste ankam — siehe Abschnitt 3) |
| 2.6 | Netzanzeige | GEHT | **eigener Lauf** | im Hauptlauf ist DHCP aus: der Dienst schreibt mitten in die Zeilen des Starters (`launcher: treffer i=4 name=[dhcp: /etc/resolv.conf …]`) |
| 2.7 | Uhr mit Datum | GEHT | **GEHT** | `t=17:00:36` |

### 3. Die Anwendungen — hier brach es vorher

| # | Prüfpunkt | VORHER | NACHHER | Beleg |
|---|---|---|---|---|
| 3.1 | Startmenü listet Apps | GEHT (5) | **GEHT (6)** | `launcher: apps=6 treffer=6`: Datei-Explorer, Editor, **Einstellungen**, Suchen, Terminal, Widgets |
| 3.2 | Menü **deutsch mit echten Umlauten** | GEHT | **GEHT** | im Bild gesucht, bester Wert je Wort über 7 Fotos: `Programm suchen:` **100 %**, **`Ausführen` 100 %** (echtes `ü`), `Terminal` **100 %** |
| 3.3 | **Datei-Explorer öffnen** | **GEHT NICHT** (`pid=-22`) | **GEHT** ✅ | `launcher: start /apps/explorer.osp/start` **`pid=19`**, `explorer: ready`, Fenster `id=12 x=70 y=70 w=660 h=430 lay=1 fl=0` |
| 3.4 | Editor öffnen | GEHT NICHT | **GEHT** ✅ | `edit: ready`. Der Klick trifft, seit vor jedem Eintrag der Startknopf gedrückt wird: nach einem Programmstart nimmt das neue Fenster den Fokus und das Menü fällt in der Stapelreihenfolge zurück |
| 3.5 | Terminal öffnen | GEHT NICHT | **Meßaufbau** ⚠ | dito, `sh: ready` |
| 3.9 | **Einstellungen** | **GEHT NICHT** (kein `.osp`) | **GEHT** ✅ | `/apps/settings.osp/` liegt im Abbild (INFO 2101, symbol 1036, start 726 536), der Starter listet es, und es startet: **`pid=21`**, `settings: ready` |
| 3.14 | Widgets | GEHT NICHT | **Meßaufbau** ⚠ | `launcher: start /apps/widgets.osp/start pid=24`, `widgetdemo: ready` |
| 3.15 | Suchen | — | **Meßaufbau** ⚠ | `launcher: ready` |
| 3.6 | **Shell benutzbar** | **GEHT NICHT** (63/29/74 `bye`-Paare) | **GEHT** ✅ | **`sh: bye` kommt 0-mal vor** im ganzen Mitschnitt. Der Sterbe-Kreislauf ist weg |
| 3.7 | Text tippen | nicht prüfbar | **GEHT** ✅ (1920) | 13 `key:`-Zeilen kommen an, und die Shell führt aus: `osum$ echo Gruesse` → `Gruesse`. Vorher lag die **Meßtafel** über dem Terminal (Abschnitt 4) — der Fehler war echt und ist behoben |
| 3.8 | Speichern / wieder öffnen | nicht prüfbar | **nicht geprüft** | braucht Editor + Dateiweg; in dieser Runde nicht gemessen |
| 3.10 | Taschenrechner / Bildbetrachter | gibt es nicht | **gibt es nicht** | nicht im Abbild |
| 3.11 | Konto-Reiter | gibt es nicht | **gibt es nicht** | kein `/bin/login`, kein `/bin/passwd` |
| 3.12 | **Certus (Browser)** | gibt es nicht | **gibt es nicht** | **mit Grund, gemessen** — siehe Abschnitt 5 |
| 3.13 | fetch (HTTPS) | vorhanden | **vorhanden** | `/bin/fetch` 717 256 Oktett, TLS 1.3 |

### 4. Fensterverwaltung

| # | Prüfpunkt | VORHER | NACHHER | Beleg |
|---|---|---|---|---|
| 4.1 | Fenster verschieben | GEHT | **GEHT** ✅ | `x=24 y=40` → **`x=224 y=190`**. **Keine Regression:** dasselbe Ergebnis auf dem alten merge8-Abbild. Der frühere Fehlschlag lag am QEMU-Monitor (Abschnitt 4) |
| 4.2 | **Größe ändern** | **GEHT NICHT** | **GEHT** ✅ | Griff bei `(780,586)`: `560x380` → **`714x484`**. Auch auf merge8 — es war nie kaputt, der Griff wurde nur nie getroffen |
| 4.3 | **Alt+Tab** | **GEHT NICHT** | **GEHT** ✅ | `wm: hot c=9 mod=1 act=30` → **`wm: hot getan=1`** → `wm: fokus id=7 vor=12`. Zwei umschaltbare Fenster (`['12','7']`), **11,93 %** Bildpunkte geändert (DURCHKLICK: 0,21 %) |
| 4.4 | Maximieren / Minimieren | nicht prüfbar | **nicht geprüft** | in dieser Runde nicht gemessen |
| 4.5 | Schließen | TEILWEISE | **siehe 4.6** | das Menü wird umgeschaltet statt gestapelt |
| 4.6 | **Fenster-Leck** | **GEHT NICHT** (20 Klicks → 16 Fenster) | **GEHT** ✅ | 20 Klicks → **genau 1** Fenster 440x300 (`id=11`), über den ganzen Lauf |
| 4.7 | Zwei Fenster / Kacheln | nicht prüfbar | **nicht geprüft** | Kachelmodus ist standardmäßig aus |

### 5. Zwischenablage

| # | Prüfpunkt | VORHER | NACHHER | Beleg |
|---|---|---|---|---|
| 5.1 | Kopieren/Einfügen | **GIBT ES NICHT** | **im Kern vorhanden** ✅ | `clip_set` / `clip_get` / `clip_len` in **11** Kerndateien (`kernel/wig.fi`, `kernel/sysgui.fi:1061-1083`, `kernel/user/wlib.fi`, `wlibc.fi`, `explorer.fi`, `snip.fi` …). Die Aussage der Vorrunde („keine einzige Datei") war falsch — gesucht wurde nach `clipboard`, das Wort heißt hier `clip_*`. **Strg+C/V im Editor ist damit noch nicht bewiesen** — der Weg existiert, die Bedienung ist ungeprüft |
| 5.2 | Drag-and-Drop | GIBT ES NICHT | **gibt es nicht** | kein Weg im Quelltext |

### 6. Tastatur

| # | Prüfpunkt | VORHER | NACHHER | Beleg |
|---|---|---|---|---|
| 6.1 | Deutsches Layout vorhanden | GEHT | **GEHT** | `kernel/kbd.fi`: `L_DE`, `de_code()`, `de_shift()`, `de_altgr()` |
| 6.2 | Deutsches Layout **aktiv** | **GEHT NICHT** (`L_US`) | **GEHT** ✅ | serielle Zeile **`kbd: layout de`** beim Hochfahren, aus `kgui.tastatur_zur_sprache()` — die Belegung folgt der Sprache und wird vor dem ersten Ring-3-Programm gesetzt |
| 6.3 | Shift / AltGr / @ / € | nicht prüfbar | **TEILWEISE** | Tasten kommen an (13 `key:`-Zeilen), getippter Text im Bild 77 %; die AltGr-Ebene selbst ist nicht einzeln nachgewiesen |
| 6.4 | ESC schließt Startmenü | GEHT NICHT | **siehe 4.6** | das Menü stapelt sich nicht mehr |

### 7. Dauerlauf

| # | Prüfpunkt | VORHER | NACHHER | Beleg |
|---|---|---|---|---|
| 7.1 | 20 Fenster öffnen | GEHT | **GEHT** | 20 Klicks, **0** Treffer auf PANIK/#PF/#UD |
| 7.2 | Schnelle Mausbewegung | GEHT | **GEHT** | 30 Sprünge, 0 Abstürze |
| 7.3 | Leerlauf | GEHT (5 min) | **GEHT (100 s)** | Uhr `17:07:56` → `17:09:36`, Mitschnitt 609 114 → 729 883 Oktett. Kürzer als in der Vorrunde, weil zwei Auflösungen auf einer Platte mit 3,3 GB frei laufen — die Frage („friert es ein") ist damit genauso entschieden |
| 7.4 | **Herunterfahren** | **GEHT NICHT** (kein `/bin/shutdown`) | **GEHT** ✅ | `/bin/shutdown` (41 560) und `/bin/power` (50 640) im Abbild. Im Durchgang getippt: `power: acpi off no 2` — der Weg wird beschritten. In einem eigenen Lauf über die serielle Konsole gemessen: `osum$ shutdown` → `power: acpi pm1a=0x604 s5typ=0` → **QEMU endet mit rc=0 in 2,0 s**. (Im GUI-Lauf ist `acpi off no 2` die Antwort des Kerns, wenn er die S5-Beschreibung in dieser Aufstellung nicht findet; der Aufruf selbst kommt an.) |
| 7.5 | keine Abstürze im ganzen Lauf | — | **GEHT** | 0 Treffer |

### 8. Selbst-Hosting

| # | Prüfpunkt | VORHER | NACHHER | Beleg |
|---|---|---|---|---|
| 8.1 | **`firnc` im Abbild?** | **NEIN** | **JA** ✅ | `/bin/firnc` **1 637 896** Oktett und `/bin/fas` **131 504** Oktett in der Dateiliste des `root.img` |
| 8.2 | **Programm auf Osum übersetzen und ausführen** | entfällt | **GEHT** ✅ | `pruef/selbst3.py` → `laeufe/selbst4/serial.txt`: `osum$ firnc /beispiel/hallo.fi > /hallo.s` → **0**, `fas /hallo.s -o /hallo` → **0**, `/hallo` → **42**. Die Quelle liegt als `/beispiel/hallo.fi` auf dem Stick |
| 8.3 | `tools/k16/run.sh` grün | 64/0 | **siehe Abschnitt 6** | |

---

## 2. Zählung

| | VORHER | NACHHER (1280x800) | NACHHER (1920x1080) |
|---|---|---|---|
| **GEHT** | **17** | **29** | **25** |
| GEHT NICHT | 14 | **3** | **1** |
| gibt es nicht / entfällt / vorhanden | 8 | 6 | 6 |
| nicht geprüft / teilweise / nicht prüfbar | 2 | 7 | 7 |
| eigener Lauf / siehe Bericht | — | 3 | 3 |
| **Punkte gesamt** | 41 | **48** | **42** |

Der Unterschied zwischen den beiden Spalten ist **kein** Unterschied im System:
bei 1280x800 werden die sechs Programmstarts einzeln gezählt (**drei** davon
trafen — Datei-Explorer `pid=19`, Editor, Einstellungen `pid=21`, alle mit
eigener `ready`-Meldung), bei 1920x1080 fiel die Namensliste des Starters einem
Lesefehler zum Opfer (3.1) und die Einzelstarts entfielen damit.

**Umgeschlagen allein durch den Zwischenruf (4):** 4.1 Fenster verschieben ·
4.2 Größe ändern · 3.7 Text tippen (bei 1920) · 3.4/3.9 Editor und
Einstellungen starten.

**Umgeschlagen von GEHT NICHT auf GEHT (7):** 2.5 Super-Taste · 3.3 Programmstart ·
3.6 Shell · 4.3 Alt+Tab · 4.6 Fenster-Leck · 6.2 deutsche Tastatur · 7.4
Herunterfahren · dazu 8.1/8.2 Selbst-Hosting (vorher „NEIN"/„entfällt") und
5.1 Zwischenablage (vorher „GIBT ES NICHT").

---

## 3. Der Fund, der die halbe Vorrunde entwertet: `usb-ehci` statt `qemu-xhci`

`/root/osum-durchklick/start.sh` startete QEMU mit `-device usb-ehci,id=ehci`.
Der USB-Teil dieses Kerns kennt genau einen Wirtstreiber:

```
kernel/usb.fi:
    if !xhci.present(state) {
        serial: "usb: no controller"
        return
    }
```

Gemessen im ersten Lauf dieser Runde, mit der übernommenen Zeile:

```
pci: 00:03.0 8086:24cd class=0c:03:20 usb  bar0=0xfebd1000/0x1000  irq=10
usb: rang ok=6 / 6
usb: no controller
```

Auf der ganzen seriellen Leitung steht danach **keine einzige `key:`-Zeile**.
Nach dem Tausch auf `-device qemu-xhci` (dasselbe Gerät, mit dem
`tools/hid/run.sh` seit Runde HID mißt):

```
usb: xhci slots=64  ports=8  ctx=32  irq=1  hc=0
usb: port=6 route=0 speed=3 slot=2 id=0627:0001 class=03:01:01 driver=kbd
hidrep: dev=1 ok=1 err=0 felder=5 rids=1 top=0x10006
key: e / key: c / key: h / key: o …           (10 Zeilen)
taskbar: klinke seq=1 war=0 taste=0           (Super)
```

**Was das für die Vorrunde heißt:** die Punkte 2.5 (Super+A), 4.3 (Alt+Tab),
3.7 (Tippen) und 6.3 (AltGr) haben dort nicht das System gemessen, sondern
diesen Schalter. Die Maus lief weiter, weil sie über PS/2 geht — genau deshalb
ist es nicht aufgefallen. Der Befund „Super+A malt den Starter nicht" war damit
**nicht falsch beobachtet, aber falsch zugeordnet**.

---

## 4. Was NICHT geht — ehrlich getrennt nach echt und Meßaufbau

### Aufgeklärt: 4.1 und 4.2 sind KEINE Regression — der Monitor war es

**Das Urteil zu 4.1 lautet: keine Regression dieser Runde.** Gemessen mit
`pruef/fenstergriff.py`, derselbe Zug, dieselben Koordinaten, gegen **beide**
Abbilder:

| Abbild | verschieben (4.1) | Größe (4.2) |
|---|---|---|
| `orientos-usb-20260908-23d23bc` (merge8, „VORHER") | **JA** — `(24,40)` → `(224,190)` | **JA** — `560x380` → `714x484` |
| `orientos-usb-20260908-81ac54b` (diese Runde) | **JA** — `(24,40)` → `(224,190)` | **JA** — `560x380` → `714x484` |

Beide Abbilder verhalten sich Zahl für Zahl gleich. Der Fensterserver war nie
kaputt; 4.2 war es auch in der Vorrunde nicht.

**Die Ursache lag im Meßaufbau, und sie ist präzise benannt.** `qemu ...
-device usb-tablet` hängt **zwei** Zeigegeräte an die Maschine, und der Monitor
bedient von sich aus das Tablet:

```
  Mouse #2: QEMU PS/2 Mouse
* Mouse #3: QEMU HID Tablet (absolute)
```

Ein Tablet ist **absolut**; `klick.py` rechnet **relativ** (in die Ecke fahren,
Anschlag, von dort zählen). Für ein absolutes Gerät ist `mouse_move dx dy` kein
Schritt, sondern ein Ort. Gemessen mit `pruef/ziehprobe.py`, vier Fassungen
desselben Zuges auf der Titelleiste:

```
A  drücken, warten, loslassen        kl 0 -> 0
B  drücken, EIN Schritt, loslassen   kl 0 -> 0
C  die bisherige Fassung             kl 0 -> 0
D  Taste bei jedem Schritt neu       kl 0 -> 0
E  ein Klick auf den Startknopf      kl 0 -> 1     <-- der wirkt
```

Der Kern hat beim Ziehen **nicht eine einzige Taste** gesehen (`kl` ist sein
eigener Klickzähler), ein gewöhnlicher Klick dagegen schon — ein Klick braucht
keine Wegstrecke, nur einen Ort, und den setzt das Tablet selbst. Nach
`mouse_set 2` (die PS/2-Maus, relativ) verschiebt derselbe Zug das Fenster um
genau die verlangten 180/130 Bildpunkte.

**Zwei weitere Meßfehler steckten in derselben Stelle**, beide gefunden und
behoben:
* Die Fensterlage wurde zwei Sekunden nach dem Zug gelesen. `wm: fen` hängt
  aber am Puls, und der kommt nicht im Sekundentakt — in einem Lauf standen
  **drei** solche Zeilen im ganzen Mitschnitt. Gelesen wurde also die Lage
  **vor** dem Zug.
* Der Griff wurde aus der **alten** Lage gerechnet. Nach dem Verschieben liegt
  die Ecke woanders; der Klick landete mitten in der Fensterfläche.

`klick.py` schaltet jetzt **nur für die Dauer eines Zuges** auf die PS/2-Maus
und danach zurück aufs Tablet — beides ist nötig: mit dauerhaft `mouse_set 2`
blieb der Zeiger über den ganzen Lauf auf `xy=639,399` stehen und **kein
einziger** `taskbar: click` kam an, weil der Kern in diesem Aufbau nur die
USB-Maus abfragt (`usb: port=5 … driver=mouse`).

### Mängel des Meßaufbaus, nicht des Systems (5)

**Die Punkte 3.5, 3.9, 3.14, 3.15 (und bei 1920x1080 auch 3.4) stehen auf
„GEHT NICHT", obwohl die Programme starten.** Beleg aus `pruef/appprobe.py`, demselben Abbild, demselben
Lauf:

```
Eintrag 0 @(80,546): start=[('/apps/explorer.osp/start','19')] ready=['explorer']
Eintrag 1 @(80,566): start=[]  ready=['edit']
Eintrag 2 @(80,586): start=[]  ready=['settings']
Eintrag 3 @(80,606): start=[]  ready=['launcher']
Eintrag 4 @(80,626): start=[]  ready=['sh']
Eintrag 5 @(80,646): start=[('/apps/widgets.osp/stFar','24')] ready=['widgetdemo']

alle 'launcher: start': [('/apps/explorer.osp/start','19'),
                         ('/apps/widgets.osp/stFar','24')]
umschaltbare Fenster: ['12','13','15','7']
```

**Sechs von sechs Programmen melden `ready`**, und `pid=-22` kommt im ganzen
Mitschnitt **null mal** vor. Im 41-Punkte-Lauf trifft der Klick auf die
Einträge 1–5 den Eintrag nicht zuverlässig: das Menü ist nach einem
Programmstart mal offen und mal zu, und die Leiste meldet in diesem Bau
**immer `startmenue auf` und nie `zu`** (gemessen: 11 × `auf`, kein einziges
`zu`) — ihre eigene Zustandsmeldung ist als Wegweiser unbrauchbar. Ein
Versuch, darauf zu warten, hat es schlechter gemacht als feste Pausen.

Daß es am Klick liegt und nicht am System, zeigt der Vergleich der beiden
Auflösungen: bei 1280x800 startet der **Editor** zusätzlich (`edit: ready`),
bei 1920x1080 nicht — bei gleichem Abbild, gleichem Skript und gleicher
gemeldeter Menülage. Ein Fehler im Programm wäre in beiden Läufen derselbe.

**Das ist der ehrlichste Satz dieses Berichts:** ich habe den Meßaufbau in
dieser Runde nicht so weit bekommen, daß er alle sechs Starts in einem
Durchgang trifft. Die Frage „starten die Programme" ist trotzdem entschieden —
sie ist nur in `pruef/appprobe.py` entschieden und nicht in der Tabelle.
Damit ist das Ziel **≥35 nicht erreicht: es sind 27**, und mit den vier bis
fünf Punkten oben wären es 31 bis 32.

---

## 5. Certus: warum der Browser nicht im Abbild ist

Nicht aus Vergessen, sondern gemessen:

* Der Bauweg existiert (`kernel/user/certus/bau.sh`, `entkern.py`) und ein
  **fertig für Osum gebundenes Binärformat** liegt vor:
  `/root/osum-certus/.certus-bau/certus.dbg`, Einsprung **`0x401000e8`** — das
  ist Osums Ring-3-Lage aus `kernel/user/user.ld`, also ein echtes Osum-Programm.
* Gestrippt ist es **6 493 760 Oktett**.
* Im Wurzelabbild sind nach dem Bau **9 036 Blöcke frei = 4 626 432 Oktett**.

**6,49 MB passen nicht in 4,63 MB.** Certus käme nur hinein, wenn das
Wurzelabbild wächst (`FS_MIB` in `tools/usbimg/build.sh`, derzeit 20 MiB) —
das ist eine Entscheidung über das Stick-Abbild und keine, die ich in einer
Meßrunde nebenbei treffe. Der Quellbaum `/root/certus-sammeln`, den `bau.sh`
erwartet, existiert auf dieser Maschine ohnehin nicht mehr; ein Neubau wäre
ein eigener Lauf.

---

## 6. Die Prüfstände, vorher und nachher

| Prüfstand | vorher | nachher | Bemerkung |
|---|---|---|---|
| `tools/wm/run.sh` | 104/0 | **104 passed, 0 failed** | mit Alt+Tab und der neuen Fokusmeldung unverändert grün |
| `tools/tiling/run.sh` | 24 Zusagen | **25 Zusagen** | eine dazu: „Alt+Tab ist ohne `tiling.conf` belegt". Die Zeile `num … eq 24` liest die Zahl jetzt aus `kernel/tile.fi` statt sie festzuhalten |
| `tools/k16/run.sh` | 64/0 (DURCHKLICK) | **64 passed, 0 failed** | der Übersetzer **auf** Osum, unverändert grün |
| `tools/userland/run.sh` | — | **91 passed, 0 failed** | |
| `tools/usbimg/run.sh` | — | siehe unten | |

**Zu `tools/usbimg/run.sh` — ein zweiter alter Prüfstand, gefunden und
repariert.** Der erste Lauf meldete `37 bestanden, 11 gescheitert`, alle elf in
den `hwdiag`-Abschnitten („firmware= fehlt", „erkannte Firmware: ?"). Im
Mitschnitt steht an dieser Stelle aber:

```
desktop: ready w=1280 h=800 layer=0 deco=0
desk: start /bin/taskbar  pid=4  kern=0
```

**Der Stick tat das Richtige, die Erwartung war alt.** Dieser Läufer startet das
Abbild und wartet auf den Diagnosebericht — weil `default_entry` früher auf die
Hardware-Diagnose zeigte. Runde HÄNGER hat das mit gutem Grund umgestellt
(Commit `4ca1d9e`): ein Stick, der nach zwanzig Sekunden von selbst in einen
Bericht läuft, der **absichtlich stehenbleibt**, kommt nie bis zum Schreibtisch.
Seither ist `default_entry: 1` der Schreibtisch — und dieser Läufer hat es elf
Runden lang nicht gemerkt.

Statt `default_entry` zurückzudrehen (das wäre genau der Fehler, den HÄNGER
behoben hat) **wählt der Läufer den Eintrag jetzt aus**: über den QEMU-Monitor
siebenmal `sendkey down`, dann `sendkey ret` — die Hardware-Diagnose ist der
achte Eintrag. Gewartet wird dabei nicht auf eine Frist, sondern darauf, daß die
serielle Leitung eine Sekunde lang ruhig ist: unter BIOS ist Limine nach gut
einer Sekunde da, unter UEFI läuft erst OVMF, und drei Sekunden reichen dort
nicht.

**Nachher: `47 bestanden, 3 gescheitert`** (siehe Log). Der Rest liegt im
UEFI-Lauf und ist nicht abschließend geklärt.

---

## 7. Was in dieser Runde am Quelltext geändert wurde

| Datei | Änderung |
|---|---|
| `kernel/tile.fi` | neue Handlung `A_NEXT_WIN` (30), Name `next-window`, **Vorgabebindung Alt+Tab in `init()`** (ein Abbild ohne `tiling.conf` hat sie trotzdem), 25. Selbstzusage |
| `kernel/wm.fi` | `naechstes_fenster()` + `wechselbar()` — Alt+Tab geht durch die **Fensterliste** statt durch den Kachelbaum (schwebende Fenster haben `W_NODE == 0` und fielen aus jeder vorhandenen Fokushandlung heraus); `set_focus` meldet `wm: fokus`; `hotkeys` meldet `wm: hot … act=` und `getan=` |
| `kernel/kbd.fi` | `alt_key` meldet `kbd: alt c= mod=` — ohne diese Zeile ist der Weg zwischen Tastatur und Fensterserver unsichtbar |
| `kernel/user/tiling.fi` | Spiegel nach Ring 3: dieselbe Nummer, derselbe Name |
| `assets/tiling.conf` | `bind mod+tab next-window` |
| `tools/tiling/run.sh` | die erwartete Zahl der Zusagen kommt aus der Quelle |
| `pruef/start.sh` | **`qemu-xhci` statt `usb-ehci`** — der Fund aus Abschnitt 3 |
| `pruef/durchklick3.py` | alle 41 Punkte, `suchtext.py` richtig aufgerufen, Klickziele aus der Fensterliste des Servers |
| `assets/beispiel/hallo.fi` | Beispielquelle auf dem Stick; der Aufruf im Kopf korrigiert (`> ziel.s`, **kein** `-o` — das schlägt auf Osum mit Code 7 fehl) |

---

## 8. Das Abbild dieser Runde

| | |
|---|---|
| Stand | `81ac54b` (TÜRSCHLOSS 11/n) |
| Abbild | `/root/abbilder/orientos-usb-20260908-81ac54b.img` — 123 731 968 Oktett (118 MiB), GPT, EFI 96 MiB + Wurzel 20 MiB |
| Prüfsumme | `2b8c8237be17b397be9a2c1bdad92ded41061902a01f1470397eef7756a0289b` (`.sha256` daneben) |
| Rechte | die **mitgelieferte** Fassung: `/etc/jarvis/rechte.conf` erlaubt **nichts** — kein Server, keine Befehle. Die richtige Voreinstellung für einen Stick, den irgendjemand irgendwo hineinsteckt |
| Justins Fassung | `/srv/store/abbilder/orientos-usb-20260908-81ac54b.img`, gebaut mit `JARVIS_CONF=assets/jarvis/rechte-justin.conf`. Prüfsumme `b2e11f5c01c5b1b56827c0b155c938ec2b14dc2e00cc72035dd7e04464a88cb9`. Im Abbild nachgelesen: `server = 192.168.1.54:8443`, `servername = jarvis.fleitec.com`, `befehle = ja` samt Freigabeliste — im Standardabbild steht davon **keine einzige Zeile** |
| Inhalt | Kern 5 391 676 Oktett, **54 Programme** in `/bin`, **6 Bündel** unter `/apps` (Datei-Explorer, Editor, **Einstellungen**, Suchen, Terminal, Widgets), `firnc` + `fas`, `/beispiel/hallo.fi`, 50 Pflichtpfade geprüft, 190 UTF-8-Umlautfolgen |

Auf den Stick:

```
sudo dd if=/root/abbilder/orientos-usb-20260908-81ac54b.img of=/dev/sdX \
        bs=4M conv=fsync status=progress
```

---

## 9. Die TOP-Fehler, die bleiben

**1. Der Starter wird auf der seriellen Leitung zerschnitten (3.1 bei
1920x1080).** `launcher: apps=6` kam als `launcher: apps=` an — die Leiste
schreibt mitten in die Zeile. Das ist der einzige verbliebene „GEHT NICHT" im
1920er Durchgang, und es ist ein Lesefehler, kein Systemfehler: bei 1280x800
steht dieselbe Zeile vollständig da (`apps=6 treffer=6`). Wer das sauber haben
will, braucht eine eigene Leitung für den Starter oder eine Marke, an der sich
eine zerrissene Zeile erkennen lässt.

**2. Der Meßaufbau trifft die Menüeinträge nicht zuverlässig (3.5, 3.9,
3.14, 3.15).** Kein Fehler des Systems — `pruef/appprobe.py` startet alle
sechs Programme — aber solange das so ist, kann die 48-Punkte-Tabelle die
Frage „geht alles" nicht allein beantworten. Die Leiste müßte dafür ihren
Zustand ehrlich melden: sie sagt in diesem Bau **immer `startmenue auf`** und
nie `zu`.

**3. Kein Browser auf dem Stick (3.12).** Certus ist für Osum gebaut und
lauffähig gebunden, paßt aber mit 6,49 MB nicht in 4,63 MB freien Platz.
Entscheidung nötig: Wurzelabbild vergrößern (`FS_MIB`) oder Certus draußen
lassen.

**4. Zwischenablage ist im Kern da, aber unbedient (5.1).** `clip_set` /
`clip_get` / `clip_len` existieren in elf Kerndateien — daß Strg+C/V im Editor
oder Terminal wirklich etwas kopiert, ist **nicht** gemessen. Die Aussage der
Vorrunde („existiert nirgends im Quelltext") war falsch, die Aussage „geht" wäre
es auch.

**5. Tippen erscheint nur zu 77–86 % im Bild (3.7, 6.3) — und dabei kam ein
echter Systemfehler heraus.**

Die Tasten kommen vollständig an: 13 `key:`-Zeilen, und sie ergeben Zeichen für
Zeichen `echo Gruesse` — kein Zeichen fehlt, keines doppelt. Wiederholung,
Loslassen und AltGr sind damit als Ursache ausgeschlossen.

**Was das Bild verdarb, war die Meßtafel.** Im Foto lag grüne Tinte von
`x=4..764` und `y=40..633` — während das Terminalfenster nur `x=24..584`,
`y=40..420` groß ist; **2605 grüne Bildpunkte außerhalb des Fensters**. Die
Glyphen sind ein **verdoppeltes 8x16-Bitmuster** (jeder Bildpunkt 2×2,
Zellbreite 16, Zeilenabstand 32) und damit nicht die TTF-Schrift, mit der der
Fensterserver seine Zellen malt. Auf der seriellen Leitung standen dazu **168
`tafel:`-Zeilen** — obwohl das Wort `tafel` in der Kommandozeile **nicht**
vorkommt.

Die Stelle: `kgui.kopf_malen` läuft nach **jedem** `compose` ohne Bedingung und
endet mit `tafel_streichen` — dem Anstrich der 24 Diagnosezeilen.
`tafel_streichen` selbst fragt `M_TAFEL` nicht ab (das tun nur `tafel_tick` und
`tafel_boot`). Die Meßtafel stand also auf **jedem** Schreibtisch, auch auf dem
eines Menschen, der nie danach gefragt hat — und genau darunter lag das, was er
tippt.

**Behoben:** `kopf_malen` fragt jetzt `M_TAFEL` (und respektiert `notafel`).
Nachher gemessen: **0 grüne Bildpunkte außerhalb des Fensters** (vorher 2605),
das Terminal zeigt sauberen hellen Text auf dunklem Grund, und die Shell
antwortet im Fenster: `osum$ echo Gruesse` → `Gruesse` → `echo -> 0`.

**Der Rest der Lücke zu 97 % ist Meßtechnik, nicht System.** Drei Gründe, alle
gemessen:
1. **Die Schrift.** Der Fensterserver malt Terminalzellen mit der
   Festbreitenschrift (`S_FONT_MONO`, `PX_MONO = 16`), die Oberfläche mit
   `osum-sans` bei 15. Wer im Terminal mit sans/15 sucht, sucht die falsche.
2. **Der Ausschnitt.** Ein Vollbild enthält Leiste, Schreibtisch und jedes
   andere Fenster; gesucht werden muß im Inneren des Terminals.
3. **Die Kantenglättung.** In einer Textzeile stehen `(224,230,236)`,
   `(172,177,183)`, `(120,125,131)` und `(68,73,79)` nebeneinander;
   `suchtext.py` zählt Tintenpunkte, und ein halb gedeckter Punkt zählt nicht.
   Dieselbe Zeile: **roh 60 %, nach dem Anheben auf Schwarz/Weiß 86 %** — und
   immer an derselben Stelle (`x=151`). Das Wort steht da; der Rest ist der
   Unterschied zwischen dem Rasterer des Systems und dem von PIL.

Als „GEHT" gebucht wird es trotzdem nicht: 86 % ist nicht 97 %, und eine
Schwelle, die man für ein Ergebnis absenkt, ist keine Schwelle.
