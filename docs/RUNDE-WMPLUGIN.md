# Runde WMPLUGIN — Erweiterungen fuer den Fensterserver, in Ring 3

Ein Erweiterungssystem fuer den Fensterserver nach dem Vorbild von
Hyprlands Plugins, aber ohne deren Grundfehler: **bei uns laeuft kein
Fremdcode im Kern.**

Alles in diesem Papier ist an einem wirklich gebooteten Kernel gemessen.
Der Laeufer, der es nachfaehrt, ist `tools/wmplug/run.sh`.

---

## 1. Warum nicht so wie Hyprland

Hyprland laedt eine Erweiterung als `.so` **in den Compositor-Prozess**
und laesst sie Funktionen umhaengen. Das ist bequem, und es ist der
Grund, warum dort ein fehlerhaftes Plugin den ganzen Schirm mitnimmt.

Bei uns waere derselbe Weg schlimmer. Unser Fensterserver ist kein
Prozess, sondern **`kernel/wm.fi`, 9265 Zeilen im Kern**. Eine geladene
`.so` waere Fremdcode in **Ring 0** — mit vollem Zugriff auf jede
Seitentabelle, jede Aufgabentafel und jedes Geraet der Maschine. Die
Hausregel dazu ist kurz, und sie steht in
`/root/osum-roadmap/FREMDSOFTWARE.md`, Regel 4:

> Kein Fremdcode im Kern.

Also laufen Plugins als **gewoehnliche Ring-3-Prozesse**. Sie wirken am
Fensterserver ueber eine schmale, versionierte Schnittstelle mit, und der
Kern weiss von ihnen genau das, was in `kernel/wmplug.fi` steht: eine
Tafel mit acht Plaetzen, je einen Ereignisring, eine Rechtemaske, eine
Frist.

Was der Unterschied kostet und was er bringt:

| | Hyprland (`.so` im Prozess) | hier (Ring-3-Prozess) |
|---|---|---|
| Plugin stuerzt ab | Compositor stirbt mit | Prozess stirbt, Schirm laeuft weiter (Abschnitt 5a) |
| Plugin haengt | Compositor haengt mit | Frist wirft es hinaus, Bildrate bleibt (5b) |
| Plugin greift zu weit | kann alles, es ist im Prozess | Recht fehlt, Handlung unterbleibt (5c) |
| Aufrufkosten | ein Funktionsaufruf | ein Syscall je Handlung |
| Schnittstelle | C++-ABI, bricht bei jedem Umbau | Nummern + Felder, versioniert |

Der Preis ist der Syscall. Der Gewinn ist, dass die drei Zeilen rechts
**gemessen** sind und nicht gehofft.

### Die zwei Zusagen, an denen alles haengt

1. **Nirgendwo wird Fremdcode in den Kernel geladen, gelinkt oder
   angesprungen.** `kernel/wmplug.fi` enthaelt keinen einzigen
   indirekten Sprung. Nachgeprueft wird das am ELF des Kerns: kein
   Symbol von `plugregel__`, `pluguhr__`, `plugboese__`, `plugprobe__`
   steht darin (run.sh, Abschnitt 2) — und, als Gegenprobe zur
   Gegenprobe, `wmplug__reg` steht darin, damit die Symbolprobe nicht
   auf einer leeren Tafel gruen wird.
2. **Der Kern wartet nie auf ein Plugin.** `notify` legt ein Ereignis in
   einen Ring und geht weiter; ist der Ring voll, faellt das aelteste
   heraus und `P_LOST` steigt. Es gibt in dem Modul keine Schleife, die
   auf einen Ring-3-Prozess wartet — weder mit noch ohne Zeitschranke.
   `WM_PLUG_POLL` kehrt sofort zurueck, mit 1 (ein Ereignis geholt) oder
   0 (keines da).

---

## 2. Die Schnittstelle

### 2.1 Versionierung

`WMP_ABI` ist **eine Zahl, die steigt, wenn sich die Bedeutung aendert**.
Heute ist sie **1**.

* Abfragbar mit `WM_PLUG_INFO(_, PL_ABI)` — und zwar **ohne** angemeldet
  zu sein und sogar ohne aufgesetzte Plugintafel. Genau dafuer ist das
  Feld gemacht: ein Plugin soll fragen koennen, bevor es sich bindet.
* Beim Anmelden nennt das Plugin die Zahl: `WM_PLUG_REG(abi, name,
  maske)`. Stimmt sie nicht, gibt es **keinen Platz** — und kein
  "irgendwie weitermachen". Nachgeben waere schlimmer als Abweisen: ein
  Plugin, das die Felder anders deutet als der Kern, schickt Unsinn an
  fremde Fenster.

Alle vier Ring-3-Programme dieser Runde fragen `PL_ABI` **vor** der
Anmeldung ab. Gemessen: `plugboese: abi=1`, `probe: abi=1`.

### 2.2 Die Aufrufe (`kernel/sys.fi`, bedient in `kernel/sysgui.fi`)

Neu ab 2117; `WM_MAXNR` ist von 2116 auf **2126** mitgewachsen.

| Nr | Name | Argumente → Rueckgabe |
|---|---|---|
| 2117 | `WM_PLUG_REG` | (abi, name, maske, **frist**) → Platz |
| 2118 | `WM_PLUG_UNREG` | () → 0 |
| 2119 | `WM_PLUG_POLL` | (aus) → 1 geholt / 0 keines. **Kehrt immer sofort zurueck.** |
| 2120 | `WM_PLUG_SUB` | (maske) → 0 |
| 2121 | `WM_PLUG_INFO` | (platz, feld) → Zahl |
| 2122 | `WM_PLUG_ACT` | (handlung, id, wert) → 0 |
| 2123 | `WM_PLUG_KEY` | (taste, mods) → 0 |
| 2124 | `WM_PLUG_BAR` | (text, laenge) → 0 |
| 2125 | `WM_PLUG_BARGET` | (platz, aus, max) → Laenge — **nur die Leiste** |
| 2126 | `WM_PLUG_GRANT` | (name, rechte \| **frist**<<32) → 0 — **nur root** |

Das vierte Argument von `WM_PLUG_REG` und die oberen Bits von
`WM_PLUG_GRANT` sind in der Nachbesserung R2-2 dazugekommen: die
**Frist je Plugin** in Ticks (Abschnitt 14.3). Wer mit drei Argumenten
ruft, uebergibt eine Null und bekommt genau das Verhalten von vorher.
Ebenfalls neu sind die Felder `PL_PFRIST = 20` (Frist eines Platzes),
`PL_DENYS = 21` (abgewiesene Handlungen dieses Platzes) und
`PL_WORKX/Y/W/H = 22..25` (die Arbeitsflaeche ohne eigenes Fenster);
`PL_MAXNR` ist **26**.

**Kein neuer Zeichenweg.** Ein Plugin malt nicht. Ein Leistenwidget
schickt **Text** (`WM_PLUG_BAR`), und gemalt wird er von der Taskleiste
mit `wlib.draw_board`/`wlib.draw_text` — also ueber fUi/wlib wie alles
andere. `tools/check-ui.sh` meldet **PASSED**.

Aktionen gehen ueber **vorhandene** WM-Wege: `WM_PLUG_ACT` reicht an
denselben Code durch, den ein Fenster fuer sich selbst benutzt, nur mit
einer Rechtepruefung davor.

### 2.3 Ereignisse

Das Abonnement ist eine Maske ueber **Ereignisarten**, `(1 << typ)`:

| Bit | Typ | wann |
|---|---|---|
| 1 | `E_WIN_OPEN` | Fenster geht auf |
| 2 | `E_WIN_CLOSE` | Fenster geht zu |
| 3 | `E_FOCUS` | Fokus wechselt |
| 4 | `E_DESK` | Arbeitsflaeche gewechselt |
| 5 | `E_TILE` | Kachelbaum geaendert (Knoten, Blaetter) |
| 6 | `E_KEY` | ein belegtes Kuerzel gedrueckt |
| 7 | `E_STOP` | **das letzte Ereignis**: du wirst abgemeldet, hier ist der Grund |

`E_STOP` ist der Grund, warum ein Platz nach der Abmeldung nicht sofort
frei wird, sondern in den **Abschied** (`U_ZOMBIE`) geht: lesen ja, alles
andere nein. Ein Plugin, dem die Frist oder die Rechte genommen wurden,
soll den Grund **erfahren** und nicht ueber einen nichtssagenden
`E_NOTFOUND` raten. Gewartet wird darauf nicht — der Kehrbesen raeumt den
Abschiedsplatz weg, sobald der Ring leer oder die Frist um ist.

### 2.4 Rechte

| Bit | Recht | |
|---|---|---|
| 0x001 | `R_EV_WIN` | Fenster auf/zu sehen |
| 0x002 | `R_EV_FOCUS` | Fokuswechsel sehen |
| 0x004 | `R_EV_DESK` | Flaechenwechsel sehen |
| 0x008 | `R_EV_TILE` | Kachelbaum sehen |
| 0x010 | `R_EV_KEY` | Kuerzel sehen |
| 0x100 | `R_ACT_WIN` | fremde Fenster setzen (Ort, Groesse, Ebene, Flaeche) |
| 0x200 | `R_ACT_FOCUS` | Fokus setzen |
| 0x400 | `R_ACT_KEY` | ein Kuerzel belegen |
| 0x800 | `R_ACT_BAR` | Text in die Leiste schicken |

* **Vorgabe ist `R_DEFAULT` = 0x1F**: alles sehen, **nichts anfassen**.
  Das bekommt jedes Plugin, das in `/etc/wmplug.conf` nicht steht.
* **Jedes Bit wird einzeln geprueft**, und zwar im Kern **vor** der
  Handlung. Wer ein Recht nicht hat, bekommt `-E_RIGHTS` **und die
  Handlung unterbleibt** — nachzurechnen an `PL_DENY` und am Fenster
  selbst.
* Das Rechtemuster ist das vorhandene: `WM_PLUG_BARGET` darf nur, wer
  eine Taskleiste ist (`is_taskbar`, eigenes Fenster auf `L_TOP` mit
  Schirmrand) — dasselbe Muster wie `WM_LIST`. Ein Plugin darf die Texte
  der anderen Plugins **nicht** lesen; gemessen:
  `pluguhr: barget verweigert r=-2`.

### 2.5 Gruende einer Abmeldung

Sie stehen auf der seriellen Leitung, weil eine Abmeldung ohne Grund im
Protokoll nicht von einem Absturz des Fensterservers zu unterscheiden
waere.

| | | |
|---|---|---|
| `G_OK` = 0 | selbst abgemeldet | |
| `G_CRASH` = 1 | Prozess ist weg | **5a** |
| `G_FRIST` = 2 | Frist ueberschritten | **5b** |
| `G_RIGHTS` = 3 | zu oft ohne Recht angeklopft | |
| `G_USER` = 4 | `wmplug disable` | **6** |

---

## 3. Wo es im Kern liegt

* `kernel/wmplug.fi` — die Buchhaltung. Acht Plaetze, je ein Ring von 32
  Ereignissen. **Keine Rekursion**, ueberall Schleifen ueber hoechstens
  acht Plaetze (der Kernstapel ist 16 KiB und war schon einmal fast
  voll).
* `kernel/kstate.fi` — `WMP_OFF` auf einer freien Seite.
  `python3 tools/kernel/memmap.py` sagt: **111 Bereiche, 0 Kollisionen**.
* `kernel/sysgui.fi` — `plug_call`, die Vermittlung, und die
  Rechtepruefung vor jeder Handlung.
* `kernel/wm.fi` — `notify` an den Stellen, an denen die Ereignisse
  ohnehin entstehen, und der Kehrbesen an **zwei** Stellen:
  * einmal je Bild in `compose` — die einzige Stelle im
    Zusammensetzpfad, die ueberhaupt etwas von Plugins weiss;
  * einmal je Tick in `poll`. **Warum beides:** auf einem ruhigen
    Schreibtisch wird gar nicht zusammengesetzt, `compose` erreichte
    seinen Kehrbesen also nie, und ein haengendes Plugin blieb stehen.
    Eine Frist, die nur greift, solange sich etwas bewegt, ist keine.

Modusworte auf der Kommandozeile: `wmplug` (Tafel aufsetzen), `plugaus`,
`plugtest` (Selbsttest beim Hochlauf), `plugfrist` (Frist kuerzen, damit
der Abnahmelauf nicht wartet). Absichtlich lange, eindeutige Woerter —
kurze treffen Teilwoerter.

---

## 4. Die Plugins

Alle vier sind Ring-3-Prozesse, keiner steht im Kernabbild.

| Programm | was es tut |
|---|---|
| `/bin/plugregel` | **Fensterregel-Engine.** Liest `/etc/wmregeln.conf`, abonniert `E_WIN_OPEN`/`E_FOCUS` und setzt Fenster an ihren Platz: `app=rechner flaeche=2 schwebend zentriert zeigen`, `titel=Terminal kacheln`. |
| `/bin/pluguhr` | **Leistenwidget.** Uhr und CPU, je Sekunde ≤31 Oktette mit `WM_PLUG_BAR`. Die Taktlaenge kommt aus der **vom Kern erfragten Frist** (`PL_FRIST`), nicht aus einer getippten Zahl. |
| `/bin/plugboese` | **Die Gegenprobe.** Absichtlich boesartig: `segv`, `hang`, `greif`. Traegt die drei harten Grenzen in Abschnitt 5. |
| `/bin/plugprobe` | **Der Prueflauf der Schnittstelle.** Geht sie einmal ganz durch: Fassung, Kuerzel ohne und mit Gewaehrung, Ereignisse, Tempo vor und nach. |

**Die Mitte wird ausgerechnet, nicht abgeschrieben.** `plugregel` holt
die Arbeitsflaeche mit `WM_INFO` vom Server (800x570 bei 30 Punkt
Taskleiste) und rechnet fuer ein Fenster von 340x430: x=230, y=70. Der
Server sagt beim Herunterfahren dasselbe:
`wm: win ... x=230 y=70 ... t=[Rechner]`.

---

## 5. Die drei harten Grenzen, jede einzeln gemessen

Je ein **eigener Lauf**, derselbe Kernel, dasselbe Abbild, Exitcode 21.

### 5a. Absturz — das Plugin macht absichtlich SIGSEGV

```
plugboese: abi=1
wmplug: reg boese platz=0 rechte=0x1f
plugboese: platz=0 rechte=31
plugboese: gleich stuerze ich ab
user fault: pid=6  vector=14  err=0x7  cr2=0x0  rip=0x401037bb  -- process killed
wmplug: tot platz=0 pid=6
wmplug: unreg boese grund=1 holte=0 verlor=0
```

* Der Kern holt den Toten **selbst** ab (`reap`, ueber `sched.tget`
  `T_STATE` **und** `T_PID` — sonst erbte ein spaeterer Prozess auf
  demselben Platz der Aufgabentafel stillschweigend die Rechte und das
  Kuerzel des Abgestuerzten).
* **Der Grund steht auf der Leitung**: `grund=1` = `G_CRASH`.
* **Der Schreibtisch laeuft nachweislich weiter:** der Zusammensetzer
  lief in diesem Lauf **163 Runden** (`wm: comp=163`), und das Foto
  danach (`docs/shots/wmplug/nach-absturz.png`) ist 800x600 mit
  **479819 von 480000** nicht-schwarzen Bildpunkten. Kein Panik.
* **Und genau einmal**: eine Zeile `wmplug: tot`, `kicks=1`. Das ist
  nicht selbstverstaendlich, siehe Abschnitt 9, Punkt 2.

### 5b. Haenger — das Plugin holt nichts mehr ab

Mit `plugfrist` (Frist 3 Ticks = 30 ms statt der Vorgabe 50 Ticks =
500 ms), damit der Lauf nicht wartet.

```
plugboese: platz=0 rechte=31
plugboese: ab jetzt hole ich nichts
wmplug: unreg boese grund=2 holte=0 verlor=0
```

* `grund=2` = `G_FRIST`. Das Plugin ist abgemeldet, **holte=0**.
* **Keine Bildrate verloren:** Zusammensetzerrunden im Haengerlauf
  **165** gegen **163** im Absturzlauf — derselbe Kernel, dasselbe
  Abbild.
* **Die Frist ist keine Wartezeit, sondern ein Kehrbesen.** Der Kern
  blockiert an keiner Stelle auf das Plugin; er schaut einmal je Bild
  und einmal je Tick auf acht Plaetze und wirft den hinaus, der
  **gerufen wurde und nicht kommt**. Wer nichts abonniert hat und dem
  nichts liegt, ist **still und nicht traege** und fliegt nicht.

### 5c. Rechte — das Plugin greift nach einem fremden Fenster

```
plugboese: platz=0 rechte=31
plugboese: suche ein fremdes Fenster
plugboese: vorher id=7 x=24 y=40
plugboese: griff nach fremdem id=7 fehler=2 deny=1
plugboese: nachher id=7 x=24 y=40
plugboese: rechteprobe: abgewiesen UND nichts bewegt
```

* Fehlercode: `-E_RIGHTS` (`cap.E_RIGHTS` = 2), und `PL_DENY` steigt um 1.
* **Am Zustand gemessen, nicht am Rueckgabewert:** der Ort wird
  **vorher** gelesen, der Griff getan, der Ort **nachher** noch einmal
  gelesen. (24,40) vorher = (24,40) nachher. Das Ziel des Griffs war
  (7,7) — dort steht es nachweislich nicht.
* `plugregel` zeigt dieselbe Zusage von der anderen Seite: derselbe
  Kernel, dieselbe Regel, dasselbe Fenster, einmal mit und einmal ohne
  `R_ACT_WIN` — mit Recht steht der Rechner auf (230,70) auf Flaeche 2,
  ohne Recht unveraendert auf (80,60), und `PA_DESK` wird mit `-2`
  abgewiesen.

---

## 6. An und aus zur Laufzeit, ohne Neustart

Ein Lauf, ein Fensterserver (`wm: hold` steht genau **einmal** da). Der
Auszug stammt aus dem Lauf VOR der Nachbesserung R2-2; die Zeilen
heissen seither `wmprobe: list vorher` statt `plugstart: list vorher`
(der Starthelfer ist geloescht, die Verwaltung befragt sich selbst mit
`wmplug probe` — Abschnitt 14.1). Die Zahlen und die Aussage sind
dieselben:

```
wmplug: reg uhr platz=0 rechte=0x807
pluguhr: text 18:06 cpu 0%
plugstart: list vorher
wmplug: abi=1  Plugins 1 von 8  Frist 50 Ticks  Flaeche 0
plugstart: info uhr
plugstart: disable uhr
wmplug: unreg uhr grund=4 holte=19 verlor=0
pluguhr: ende runden=4 ereig=1
plugstart: list nachher
wmplug: abi=1  Plugins 0 von 8  Frist 50 Ticks  Flaeche 0
```

**Am Zustand gemessen:** die Tafel zaehlt vorher 1 Plugin und nachher 0,
der Grund ist `G_USER` (4) und damit von Absturz (1) und Frist (2) zu
unterscheiden, und das Widget ist wirklich gegangen.

Dazu zwei Fotos in `docs/shots/wmplug/`, **maschinell** auseinander
gerechnet (nicht "sieht anders aus"): `widget-an.png` und
`widget-aus-laufzeit.png` aus **demselben Lauf** — derselbe
Fensterserver, dieselbe Leiste, nur das Plugin ist gegangen. Die
Koordinate kommt dabei aus der Leiste selbst (`taskbar: plug nr=0 x= y=
w= h=` plus `taskbar: geom`), nicht aus dem Skript; gerechnet wird die
Mitte dieses Kastens. Ebenso `regel-mit-recht.png` gegen
`regel-ohne-recht.png`.

### 6.1 Und EINSCHALTEN zur Laufzeit

Das Abschalten war gemessen, das Einschalten nicht -- und es ging auch
nicht: `WM_PLUG_GRANT` schrieb die Rechte nur in die Gewaehrungstafel,
und die liest der Kern **beim Anmelden** (`reg`). Ein Widget, das schon
lief, blieb ohne Recht. Seit dieser Nachbesserung uebertraegt
`do_pluggrant` eine von null verschiedene Maske auch auf **laufende**
Plaetze (`wmplug.set_rights`); null bleibt, was es war: Abmeldung mit
`G_USER`.

Gemessen in `tools/wmplug/run.sh`, Abschnitt 7c (`/bin/uhrspaet`:
Widget starten **ohne** Gewaehrung, Foto, gewaehren, Foto):

```
OK  das Widget startet OHNE R_ACT_BAR -- der Text wird abgewiesen
OK  danach wird gewaehrt (WM_PLUG_GRANT -- derselbe Ruf wie 'wmplug enable uhr')
OK  und die Leiste malt den Widget-Text
OK  genau EINE Anmeldung (wmplug: reg uhr) -- kein Prozessneustart
OK  und der Fensterserver lief durch (genau ein 'wm: hold')
OK  im Widget-Kasten unterscheiden sich 2184 Bildpunkte zwischen vorher und nachher
OK  checkshot punkt (632,572): vor dem Gewaehren [30 41 59], danach [38 48 60]
OK  im Widget-Kasten stehen nach dem Einschalten 391 Bildpunkte Tinte
```

Die Koordinate ist **nicht getippt**: der Kasten kommt aus der Leiste
(`taskbar: plug nr=0 x=632 y=2 w=84 h=26` plus `taskbar: geom`), und
gerechnet wird am **ersten Bildpunkt, der sich unterscheidet** -- die
Mitte des Kastens liegt bei kurzem Text zwischen zwei Buchstaben und
zeigt in beiden Bildern dieselbe Farbe (auch das ist gemessen, es hat
diese Zusage einmal falsch gruen gemacht). Die Bilder liegen als
`docs/shots/wmplug/enable-vorher.png` und `enable-nachher.png`.

---

## 7. Verwaltung

`/bin/wmplug` — `list | info <name> | enable <name> | disable <name>`.
Alle Zahlen kommen aus dem Kern (`WM_PLUG_INFO`), keine aus dem Programm.

`/etc/wmplug.conf` haelt die Rechte, **eine Zeile je Erweiterung**:

```
uhr   rechte=0x807     # sehen, was noetig ist; genau eine Sache tun: Text abliefern
regel rechte=0x301     # das Gegenteil: sieht nur Fenster aufgehen, setzt sie
boese rechte=0x001     # ABSICHTLICH nur Zusehen -- traegt die Rechte-Gegenprobe
```

**Der Kern liest diese Datei nicht.** Beim Hochlauf kennt er noch kein
Dateisystem und soll auch keine Namenspolitik machen; `wmplug enable`
schickt die Maske mit `WM_PLUG_GRANT` hinunter, und das geht nur als
root.

Pakete im vorhandenen PLAN/opk-Format: `pakete/wmplug-werkzeug/rezept`,
`pakete/wmplug-uhr/rezept`, `pakete/wmplug-regel/rezept`, gebaut mit
`pakete/bauen.sh` ueber `pkg/opk.py` / `kernel/user/opk.fi`.

---

## 8. Tempo: vor und nach dem Laden

### 8.1 Warum die erste Messung dieser Runde keine war

Sie stand hier als Tabelle und sie sah ordentlich aus: `PL_FRAMES` und
`PL_LATUS`, vor und nach der Last gelesen, 1530 us gegen 859 us. Die
Zahlen waren echt und die Messung war trotzdem falsch, aus zwei
Gruenden, die beide benannt gehoeren:

1. **`PL_LATUS` ist der Mittelwert SEIT DEM HOCHLAUF.** Nach einer
   Minute bewegt er sich kaum noch; ein Einbruch, der drei Sekunden
   dauert, ist darin nicht zu sehen. Was die Tabelle zeigte, war das
   Warmwerden der Glyphen (`wmbench: glyph cold=6138 us warm=216 us`)
   und nicht die Wirkung eines Plugins.
2. **Die "Last" war in beiden Fenstern verschieden.** Im Stillhalten
   (`wmhold`) setzt der Server nur zusammen, wenn etwas schmutzig ist --
   gemessen **41 Bilder in vierzig Sekunden**. Eine Bildrate daraus ist
   die Rate der Langeweile.

### 8.2 Die saubere Messung: /bin/plugtempo

Also ein Ring-3-Programm, das beides behebt (`kernel/user/plugtempo.fi`,
gefahren in `tools/wmplug/run.sh`, Abschnitt 7b):

* Es macht **seine eigene Last**: ein Fenster 200x120, in jedem
  Zeitschnitt (50 ms) neu gefuellt -- in **beiden** Messfenstern
  derselbe Takt, dieselbe Flaeche.
* Es misst erst nach einem **Warmlauf** (8 s vor dem ersten Fenster,
  4 s nach dem Laden -- das Widgetfeld bringt neue Glyphen mit).
* Es rechnet die Bildzeit ueber ein **Fenster** und nicht ueber den
  Hochlauf: `PL_FRSUM`/`PL_FRN` sind Summe und Anzahl der Bildzeiten,
  `(sum2-sum1)/(n2-n1)` ist der Mittelwert genau dazwischen. Beide
  Zahlen fuehrt `wm.compose` ohnehin (S_FRUS, S_FRN); es kommt kein
  Zaehler hinzu.
* Es laedt **dasselbe** Plugin, das auch der Widgetlauf nimmt:
  `WM_PLUG_GRANT("uhr", 0x807)`, dann `/bin/pluguhr`.

**Ein Lauf, EIN Kernel, dieselbe Maschine** (`gfx wm wig desk wmhold
wiglong ... wmplug wighalt=50 wigapp=/bin/plugtempo,...,bilder=60`,
Exitcode 21; die Zahlen unten stammen aus dem Abnahmelauf
`tools/wmplug/run.sh`, Abschnitt 7b):

| | Bilder | Bildrate | Bildzeit (Mittel) | min | max |
|---|---|---|---|---|---|
| **vor** dem Laden | 60 | 20,0 /s | **407 us** | 362 us | 555 us |
| **nach** dem Laden | 60 | 21,0 /s | **427 us** | 352 us | 881 us |

Wortlaut des Laeufers:

```
OK  beide Fenster haben wirklich 60 Bilder (vor 60, nach 60)
OK  Bildzeit vor dem Laden 407 us (min 362, max 555),
    nach dem Laden 427 us (min 352, max 881)
OK  Bildrate vor dem Laden 200 (x10), nach dem Laden 210 (x10)
OK  kein Tempoeinbruch: 210 ist mindestens zwei Drittel von 200
```

und die Leitung desselben Laufs, der Reihe nach:

```
tempo: vor  bilder=60 ... us=407 min=362 max=555 gezaehlt=60 fps10=200
tempo: grant r=0
wmplug: reg uhr platz=0 rechte=0x807
taskbar: text plug ... t=cpu 100%
tempo: nach bilder=60 ... us=427 min=352 max=881 gezaehlt=60 fps10=210
```

**Die Abweichung, ausdruecklich benannt:** die mittlere Bildzeit steigt
um **20 us (+4,9 %)**, die Bildrate nicht (sie haengt am Takt der
kuenstlichen Last, 20 Bilder je Sekunde, und den haelt sie in beiden
Fenstern; 21,0 gegen 20,0 ist die Aufloesung der Tickuhr und kein
Gewinn). Der Ausreisser steht im `max`: **881 us gegen 555 us**. Das
ist das eine Bild je Sekunde, in dem die Leiste ihr Widgetfeld neu malt
-- mehr kostet ein Plugin in dieser Bauform nicht.

Zwei weitere Laeufe desselben Programms auf derselben Maschine lagen
bei 439 us gegen 472 us (+7,5 %) und 365 us gegen 411 us (+12,6 %).
**Alle drei Zahlenpaare sind gemessen, und sie sagen zusammen mehr als
jedes einzelne:** die Streuung zwischen zwei Laeufen (365..439 us im
Fenster VOR dem Laden) ist groesser als der Abstand zwischen "mit" und
"ohne" Plugin innerhalb eines Laufs (20..46 us). Wer aus diesen Zahlen
eine Prozentzahl auf die Nachkommastelle machen will, misst Rauschen.
Was sie tragen, ist die schwaechere und wahre Aussage: **ein geladenes
Leistenwidget kostet in der Groessenordnung von fuenf bis zehn Prozent
Bildzeit und keine Bildrate.**

### 8.3 Was `WM_PLUG_BAR` kostet, getrennt ausgewiesen

Bis zu dieser Nachbesserung rief jeder `WM_PLUG_BAR` **`wm.damage_all`**
-- 800x600 = **480000 Bildpunkte fuer 31 Oktette Text**, sekuendlich,
auch wenn das Widget dieselbe Zahl noch einmal schickte. Zwei
Aenderungen in `kernel/sysgui.fi`:

* **Teilschaden statt Vollschaden:** gemeldet wird das Rechteck der
  Leiste (`damage_bar`, gefunden am selben Merkmal wie `is_taskbar`:
  reservierter Schirmrand) -- bei 800x600 sind das **24000** statt
  480000 Bildpunkte, ein Zwanzigstel.
* **Gar nichts, wenn sich nichts aendert:** `wmplug.bar_same` vergleicht
  den neuen Text mit dem alten; ist er gleich, wird nichts schmutzig
  gemeldet. Ein Widget im Sekundentakt kostet damit einen Systemaufruf
  und **kein Bild**.

Der Rest der Ruhe ist die Bauform und kein Zufall: der Kern macht je
Bild **acht Vergleiche** (der Kehrbesen) und legt Ereignisse in Ringe.
Er ruft **nie** in ein Plugin hinein und wartet **nie** auf eines.

### 8.4 Der zweite Vergleich: zwei Laeufe, ein Abbild

Zusammensetzerrunden zweier Laeufe desselben Abbilds, bei denen einmal
ein Plugin abstuerzt und einmal eines haengt: **163 gegen 165**. Kein
Einbruch.

---

## 9. Was der Abnahmelauf gefunden hat

Vier Fehler, die ohne Messung durchgegangen waeren. Sie stehen hier,
weil ein Bericht, der nur die gruenen Zeilen zeigt, nichts wert ist.

1. **`wmplug disable` hat nicht abgeschaltet.** Es schrieb nur eine Null
   in die Gewaehrungstafel — und die liest der Kern erst beim
   *Anmelden*. Ein Plugin, das schon lief, lief weiter, und `list` zeigte
   `Plugins 1 von 8` vor **und** nach dem Abschalten. Das war kein
   Schalter, sondern eine Notiz. Behoben in `do_pluggrant`: Rechte auf
   null melden den Platz mit `G_USER` ab.
2. **Der Kehrbesen lief in sich selbst.** `reap` redet, bevor es raeumt,
   und `serial.puts` ist langsam; faellt der Zeitgeber herein, laeuft
   `poll` → `sweep` → `reap` ein zweites Mal und sieht den Platz noch als
   `U_LEBT`. Auf der Leitung stand `wmplug: tot platz=0 pid=6` **zweimal**
   und die Bilanz meldete `kicks=2` fuer **einen** Absturz. Das Ergebnis
   war nie falsch, die Zahl schon. Behoben mit `S_BUSY` — kein Sperren,
   kein Warten.
3. **Das Abonnement ist eine Maske ueber Ereignis*arten*, nicht ueber
   Rechte.** `plugboese` meldete sich mit `0x01` an (einem Rechtebit);
   Bit 0 ist gar keine Ereignisart. Es war auf **nichts** abonniert, ihm
   lag nie etwas, und `sweep` konnte gar nicht greifen — der Haengerlauf
   endete still mit `G_CRASH` statt mit `G_FRIST` und **sah aus wie eine
   Messung**.
4. **Eine gruene Zusage, die nichts geprueft hat.** Unter
   `set -o pipefail` beendet `grep -q` die Roehre beim ersten Treffer,
   `nm` bekommt SIGPIPE, und die Roehre gilt als gescheitert — der Fund
   wurde zum Fehlschlag. Deshalb liegt die Symboltafel jetzt als Datei
   vor, und die Gegenprobe zur Gegenprobe (`wmplug__reg` **muss** da
   sein) steht ausdruecklich im Laeufer.

---

## 10. Ausdruecklich benannte Abkuerzungen

> **GESTRICHEN in der Nachbesserung R2-2:** die Nummern 1, 2 und 5 gelten
> nicht mehr — das Leserecht `R_EV_WIN`, die Autostart-Liste und die
> Rechte-Gegenprobe mit `0x001` stehen in **Abschnitt 14**, jede mit der
> Zeile, die sie belegt. Die Eintraege bleiben hier stehen, damit
> nachlesbar ist, was sie waren.

1. ~~**Das geborgte Leserecht.**~~ (gestrichen, siehe 14.2) Titel und Ort fremder Fenster gibt
   `WM_LIST` nur einer Taskleiste (`is_taskbar`). `plugregel` und
   `plugboese` brauchen diese Zahlen, also legen beide ein **verborgenes**
   Fenster von 32x16 mit einem Schirmrand von **einem** Bildpunkt an.
   `wm.recalc_work` ueberspringt verborgene Fenster (wm.fi:3376), die
   Arbeitsflaeche aendert sich um keinen Punkt, auf dem Schirm ist nichts
   zu sehen. **Richtig waere ein eigenes Leserecht** (`R_EV_WIN` als
   Leseschluessel fuer `WM_LIST`). Betrifft nur das *Messen*, nicht das
   Recht zum *Handeln*.
2. ~~**`kernel/user/plugstart.fi`.**~~ (gestrichen, siehe 14.1; die Datei
   ist geloescht) Der Kern startet auf dem
   Schreibtischweg genau **ein** zusaetzliches Programm (`wigapp=`), der
   Abnahmelauf braucht aber zwei Schritte (Rechte gewaehren, dann
   starten). Faellt weg, sobald der Schreibtisch eine **Autostart-Liste**
   hat. Deshalb liegt das Widget im Abbild unter `/bin/uhrstart`.
3. **Die senkrechte Leiste bekommt kein Widget-Feld.** Eine Spalte ist
   80 Punkte breit, `17:10 cpu 100%` passt nicht hinein, ohne die Uhr zu
   verdraengen. Steht so im Code, **nicht gemessen**.
4. **Der Namenspuffer.** `WM_PLUG_REG` kopiert **immer** 15 Oktette, egal
   wie kurz der Name ist. Wer ein `[u8; 4]` hinlegt, schickt seinen
   halben Stapel als Namen mit — im ersten Lauf dieser Runde stand dort
   `runden=30`, und der Kern meldete `reg uhr rund`. Siehe
   `BEFUND-WMPLUG-NAMENSPUFFER.md`. Die Laenge gehoerte besser als
   Argument mitgegeben.
5. ~~**Die Rechte-Gegenprobe misst den weiteren der beiden Faelle.**~~
   (gestrichen, siehe 14.2 -- gemessen wird jetzt `rechte=0x001`)
   `plugboese` laeuft mit `R_DEFAULT` (0x1F) aus dem Kern, nicht mit den
   0x001 aus `/etc/wmplug.conf` — die wuerden erst durch
   `wmplug enable boese` wirksam. Beide haben **kein** Aktionsbit, die
   Zusage traegt also; gemessen ist aber der groessere Rechtesatz.
6. **Acht Plaetze und 32 Ereignisse je Ring** sind gesetzt und nicht
   hergeleitet. Laeuft ein Ring ueber, faellt das aelteste Ereignis
   heraus und `P_LOST` steigt — sichtbar, aber eben ein Verlust.

---

## 11. Offene Punkte

* ~~**Kein eigenes Leserecht fuer `WM_LIST`.**~~ ERLEDIGT in R2-2:
  `R_EV_WIN` oeffnet `WM_LIST` (14.2).
* ~~**Keine Autostart-Liste** des Schreibtischs.~~ ERLEDIGT in R2-2:
  `/etc/wmplug.autostart` (14.1).
* ~~**Die Frist ist eine Zahl fuer alle.**~~ ERLEDIGT in R2-2:
  `P_FRIST` je Platz, `frist=` in /etc/wmplug.conf (14.3).
* ~~**`G_RIGHTS` ... nicht ausgeloest worden.**~~ ERLEDIGT in R2-2:
  Schwelle `DENY_MAX = 8`, `grund=3` auf der Leitung (14.4).
* **Der Autostart wartet zwei Sekunden**, bevor er die erste Zeile
  ausfuehrt -- ein Plugin bekommt sonst die Ladezeit fremder Programme
  auf seine Frist angerechnet (14.1).
* **Kein Plugin ueberlebt einen Neustart des Fensterservers.** Die Tafel
  ist Hauptspeicher; wer nach `wm: hold` wieder da sein will, muss neu
  gestartet werden.
* **Die Tempozahlen sind an QEMU/KVM gemessen**, nicht an Blech.

---

## 12. Nachfahren

```
bash tools/wmplug/run.sh
```

Faehrt alles selbst nach — baut den Kernel, prueft die Symboltafel,
bootet sechs Laeufe, ruft die beiden Modullaeufer, legt die Bilder nach
`docs/shots/wmplug/` und druckt am Ende `N bestanden, M gescheitert`.

`WMPLUG_SCHNELL=1` laesst die zwei Modullaeufer aus (nur die Kernseite).
`WMPLUG_KEEP=1` behaelt das Arbeitsverzeichnis mit allen seriellen
Mitschnitten.

Stand dieses Papiers — voller Lauf, KVM, Exitcode 0:

```
REGEL:  38 bestanden, 0 gescheitert
WIDGET: 30 bestanden, 0 gescheitert
WMPLUG: 139 bestanden, 0 gescheitert
```

Alle Zahlen in diesem Papier stammen aus genau diesem Lauf.

---

## 13. Nachbesserung R2-1: die Uhr, die Spalten und der CPU-Wert

Vier Befunde der Jury betrafen das, was man SIEHT — und sie waren
berechtigt: eine Messung, die man nicht lesen kann, ist nur halb
gemessen. Alle Zahlen hier stammen aus einem Lauf von
`bash tools/wmplug/widget.sh` (KVM, gebooteter Kernel) und aus einem
QEMU-Lauf mit dem Wort `verwaltung`.

### 13.1 Zwei Uhrzeiten nebeneinander — jetzt eine

Das Widget schickte `HH:MM cpu NN%`, und die Leiste hat rechts daneben
ihre eigene Uhr. Beide Uhren kommen aus verschiedenen Quellen und
konnten um eine Minute auseinanderlaufen; bei 640x480 stiessen die
Kaesten ausserdem aneinander. **Das Widget schickt jetzt nur noch
`cpu NN%`** (`kernel/user/pluguhr.fi`, `bauen`) — die Uhrzeit gehoert
der Leiste, die Last zeigt die Leiste nicht.

```
pluguhr: text cpu 0%
pluguhr: text cpu 100%
```

Und die Leiste haelt zwischen Widgetfeld und ihrem linkesten eigenen
Feld **mindestens acht Bildpunkte** frei (`kernel/user/taskbar.fi`,
Layoutschleife der Widgets). `gap()` ist `wlibc.space(1)` und faellt bei
kleinen Schirmen auf vier — genau dort klebte es. Der Abzug geschieht
nur, wenn ueberhaupt ein Widget Text hat: eine Leiste ohne Erweiterung
soll ihre Fensterknoepfe nicht verschoben bekommen.

Gemessen bei **640x480** an den Zahlen, die die Leiste selbst meldet
(`taskbar: plug nr=0 x= w=` gegen `taskbar: field <name> x=`), nicht am
Augenmass:

```
6c. der Abstand zwischen Widgetfeld und Uhr, bei 640x480
  OK  bei 640x480 hat die Leiste ein Widget-Feld
  OK  Abstand Widgetfeld -> linkestes Leistenfeld: 8 px (>= 8), 640x480
```

Bild: `docs/shots/wmplug/widget-eng-640x480.png`.

### 13.2 Woher kommt der CPU-Wert im Bild?

Die Frage war richtig gestellt: eine Zahl im Foto belegt nichts, solange
niemand zeigt, dass sie aus dem Plugin stammt. Das Widget meldet jetzt
**jeden** geschickten Text auf der Leitung, und zwar **nach** dem Ruf
`WM_PLUG_BAR` — steht die Zeile da, hat der Kern den Text schon, und die
Leiste holt ihn erst danach (`WM_PLUG_BARGET`). Also muss jede gemalte
Zeichenfolge gleich der zuletzt gemeldeten sein, und `widget.sh` rechnet
das Paar fuer Paar nach:

```
6b. WOHER KOMMT DIE ZAHL IN DER LEISTE?
  OK  alle 2 gemalten Widget-Texte sind genau der zuletzt geschickte (cpu-Wert belegt)
  OK  das Widget schickt keine Uhrzeit mehr (nur Last), die Uhr bleibt der Leiste
  OK  der Text hat die Form 'cpu NN%' (pluguhr: text cpu 100%)
```

**Was die 100 % bedeuten, und warum sie stimmen:** `cpu_last()` rechnet
aus zwei Messungen `CS_TICKS` und `CS_IDLE` (`cpu.C_IDLETICKS`). Der
Abnahmelauf faehrt mit `nosched noproc` — es gibt keinen Leerlauffaden,
der Leerlaufzaehler bleibt 0, und die ehrliche Antwort darauf ist 100 %.
Das ist kein Fehler des Widgets und auch nicht seine eigene Last (es
schlaeft zwischen zwei Abholungen, `pollms = PL_FRIST/3`, **mindestens
50 und hoechstens 250 Millisekunden** -- die Untergrenze stand vorher
bei 20, und bei kurzer Frist wachte das Widget damit fuenfzigmal je
Sekunde auf, um danach die Last zu melden, die es selbst erzeugt
hatte), sondern die
Eigenschaft dieses Aufbaus. Auf einem Lauf mit Scheduler zeigt dasselbe
Widget die wirkliche Auslastung. **Benannt und nicht schoengerechnet.**

### 13.3 Die Beschriftungen von `wmplug info`

`"  Leistentext\0"` hatte kein Trennzeichen — im Bild stand
`Leistentext13`, Wort und Wert zusammengelaufen. Alle zehn
Beschriftungen stehen jetzt auf **einer** Feldbreite (14 Oktette, zwei
davon Einzug, `LB_W`). Gemessen an der seriellen Leitung eines Laufes
mit `verwaltung` (`/bin/wmplug info uhr`, Ring 3):

```
plugstart: info uhr r=10
  Name        uhr
  Platz       0
  Rechte      0x807 (win fokus flaeche +leiste)
  Maske       0x8E
  liegt       0
  verloren    0
  eingelegt   1
  abgeholt    1
  Grund       0 selbst
  Leistentext  8
  im Kern gesamt: Verstoesse 0, abgewiesen 0
```

Foto desselben Laufes: `docs/shots/wmplug/info-uhr-spalten.png` — jede
Beschriftung endet in derselben Spalte, `Leistentext` und die `8` sind
getrennt, und die Statuszeile von `list` steht in zwei kurzen Zeilen
(`wmplug: abi=1  Plugins 0 von 8` / `  Frist 50 Ticks  Flaeche 0`), die
auch in ein 640x480-Terminal passen.

**Nachtrag zu den aelteren Abschnitten:** die in 5. und 6. zitierten
Zeilen `pluguhr: text 18:06 cpu 0%` stammen aus dem Lauf VOR dieser
Nachbesserung; die Form heisst seither `pluguhr: text cpu 0%`. Die
Aussage der Abschnitte aendert sich dadurch nicht.

---

## 14. Nachbesserung R2-2: der Autostart, das Leserecht, die Frist je Plugin und die Schwelle

Vier Maengel, vier Belege. Alle Zeilen unten stammen aus
`bash tools/wmplug/run.sh` auf diesem Stand -- **193 bestanden, 0
gescheitert** im ganzen Lauf (117 davon auf der Kernseite, der Rest aus
den beiden Modullaeufern `regel.sh` und `widget.sh`). Die Abbilder baut
der Laeufer je Lauf neu, weil die Autostart-Liste jetzt IM Abbild
liegt.

### 14.1 Autostart statt Starthelfer — Abkuerzung 2 ist weg

`kernel/user/plugstart.fi` (`/bin/uhrstart`) ist **geloescht**. An seine
Stelle treten zwei Dinge:

* **`/etc/wmplug.autostart`**, gelesen vom Schreibtisch
  (`kernel/user/desktop.fi`, `fn autostart`). Eine Zeile je Erweiterung:
  der erste Name geht an `wmplug enable`, die restlichen Woerter gehen
  **durch** an das Plugin. Alles hinter `#` ist Bemerkung; fehlt die
  Datei, passiert nichts.
* **`wmplug enable` startet jetzt wirklich**: steht in der Zeile von
  `/etc/wmplug.conf` ein `prog=`, wird es nach der Gewaehrung mit
  `SYS_EXEC` gestartet. Die Reihenfolge ist gemessen und nicht beliebig
  — der Kern legt die Rechte beim **Anmelden** auf den Platz, wer sich
  vor der Gewaehrung anmeldet, sieht nur zu.

Aus dem Lauf `verw` (eine Zeile `uhr runden=40`):

```
desktop: autostart [uhr runden=40] pid=9
wmplug: uhr rechte=0x807
  Frist 100 Ticks
wmplug: reg uhr platz=0 rechte=0x807 frist=100
wmplug: start /bin/pluguhr rc=8
```

**Zwei Sekunden Vorlauf, und die Zahl ist gemessen.** `desk` startet
nach dem Schreibtisch noch Leiste und Starter, und ein `SYS_EXEC` laedt
das ganze Abbild IM Systemaufruf (`elf: start ... pages=432`, 1,4
Megaoktett). Waehrenddessen kommt kein anderer Prozess dran: ein Plugin,
das sich vorher angemeldet hat, holt in dieser Zeit **nichts** ab, und
der Kehrbesen hat recht, wenn er es hinauswirft — gemessen stand dort
`wmplug: unreg uhr grund=2 holte=1`. Der Autostart wartet deshalb, bis
die Sitzung steht. Das ist kein Fehler der Frist, sondern der Preis
eines synchronen Programmstarts, und es steht hier, weil es sonst
niemand sieht.

Der vierte Aufrufweg der Verwaltung, `wmplug probe <name>`, ersetzt den
zweiten Zweck des alten Starthelfers (list/info/disable/list an einem
wirklich angemeldeten Plugin). Mit Woertern hinter dem Namen startet er
das Plugin vorher selbst — dafuer braucht `wigapp=` kein Hilfsprogramm
mehr.

Nebenbefund, der eine Stunde gekostet hat: die Leseschranke von
`maske_aus_datei` lag bei 2000 Oktetten, `/etc/wmplug.conf` ist mit
`frist=` und `prog=` **3133** Oktette lang — `wmplug enable uhr`
antwortete "steht nicht in /etc/wmplug.conf", obwohl die Zeile dastand.
Die Meldung nennt jetzt `gelesen=`, und der Puffer fasst 4000.

### 14.2 `R_EV_WIN` ist der Schluessel zu `WM_LIST` — Abkuerzung 1 ist weg

Bis zu dieser Nachbesserung gab es genau einen Schluessel zur
Fenstertafel: eine Taskleiste sein (`is_taskbar`). `plugregel` und
`plugboese` legten dafuer je ein **verborgenes Fenster von 32x16** mit
einem Schirmrand von einem Punkt an. Beide Fenster sind **geloescht**;
der zweite Schluessel ist jetzt das Recht selbst
(`kernel/sysgui.fi`, `fn darf_listen`):

```
if is_taskbar(state, me) { return true }
let i = wmplug.slot_of(state, me)
return (wmplug.rights_at(state, i) & wmplug.R_EV_WIN) != 0
```

Wer Fensterereignisse sehen darf, darf auch die Fenstertafel lesen — er
erfaehrt ohnehin von jedem Fenster, das aufgeht. Gemessen im Lauf
`greif`, und zwar mit dem **engsten** Rechtesatz der Runde (das raeumt
zugleich Abkuerzung 5 ab):

```
wmplug: reg boese platz=0 rechte=0x1 frist=100
plugboese: platz=0 rechte=1
plugboese: vorher id=7 x=24 y=40
plugboese: griff nach fremdem id=7 fehler=2 deny=1
plugboese: nachher id=7 x=24 y=40
plugboese: rechteprobe: abgewiesen UND nichts bewegt
```

`rechte=1` ist genau `R_EV_WIN`: **lesen ja, handeln nein**. Der
Abnahmelauf prueft zusaetzlich, dass der Titel `plugboese-lese` in
keinem Protokoll mehr vorkommt.

Die vier Zahlen der Arbeitsflaeche, fuer die `plugregel` frueher ein
Handle brauchte (WM_INFO), beantwortet der Kern jetzt ohne Fenster:
`PL_WORKX/Y/W/H` (22..25), `PL_MAXNR = 26`.

**Nachzuegler-Suche, gemessen und nicht vorsichtshalber:** in etwa jedem
vierten Lauf kam das `E_WIN_OPEN` des Rechnerfensters nicht an — die
Bilanz zaehlte `evin=3` statt `evin=4`, das Fenster war da, das Ereignis
nicht. Ein Ereignisring ist ein schneller Weg und keine Wahrheit (er
kann ueberlaufen, und zwischen Anmeldung und erstem Abholen liegt immer
eine Luecke). `plugregel` liest deshalb alle zwei Sekunden einmal die
Fenstertafel und behandelt, was es noch nicht gesehen hat; jede Regel
wirkt je Fenster genau einmal.

### 14.3 Die Frist gehoert dem Plugin (`P_FRIST`)

Neu in `kernel/wmplug.fi`: `P_FRIST` (0xB0) je Platz, gesetzt

* beim Anmelden — **viertes Argument** von `WM_PLUG_REG`, hoechstens
  `FRIST_MAX_SELBST = 200` Ticks (2 s), damit sich kein Plugin selbst
  unsterblich macht, **oder**
* aus der Gewaehrungstafel — `frist=<ticks>` in `/etc/wmplug.conf`,
  von `WM_PLUG_GRANT` in den **oberen** Bits desselben Wortes
  uebertragen (Bits 32..47). Diese Zahl schlaegt den Wunsch, in beide
  Richtungen; sie kommt von root.

`PL_PFRIST` (20) beantwortet die Frist **eines Platzes**, `PL_FRIST`
(14) bleibt die des Kerns. Der Kehrbesen (`sweep_at`, `reap`) fragt je
Platz `frist_at`.

Gemessen in EINEM Lauf (`abbild frist 'regel demo laut' 'uhr runden=40'`):

```
wmplug: reg regel platz=0 rechte=0x301 frist=500
wmplug: reg uhr   platz=1 rechte=0x807 frist=100
plugregel: regel 0 id=12 app=rechner
plugregel: nachgemessen id=12 x=230 y=70 w=340 h=430 flaeche=2 sichtbar=1
pluguhr: text cpu 0%
wmplug: bilanz  plugs=2  evin=4  evout=4  kicks=0  deny=0  plugkeys=0
```

Widget mit **1 s**, Regel-Engine mit **5 s**, `kicks=0` — beide
ueberleben denselben Lauf. Der Selbsttest des Moduls hat dafuer zwei
neue Zusagen (jetzt **15**): eine eigene Frist gilt gegen die des Kerns
(der Platz ohne eigene fliegt, der mit eigener bleibt), und die
Schwelle unten.

### 14.4 `G_RIGHTS` ist nicht mehr nur gebaut, sondern ausgeloest

`deny()` zaehlt jetzt je Platz (`P_DENYS`, 0xB8) und meldet den Platz ab
`DENY_MAX = 8` mit `G_RIGHTS` ab. Einmal fragen ist eine Frage — der
Fehlercode ist die Antwort; achtmal greifen ist eine Absicht.
`plugboese greif` reizt die Schwelle in einer Schleife:

```
wmplug: unreg boese grund=3 holte=20 verlor=0
plugboese: schwelle: griffe=12 letzte=3 deny=8
wmplug: bilanz  plugs=0  evin=1  evout=0  kicks=1  deny=8  plugkeys=0
```

`letzte=3` ist `-E_NOTFOUND`: die letzten Griffe treffen keinen Platz
mehr, weil es ihn nicht mehr gibt — nicht `-E_RIGHTS`, das waere nur
"gesperrt". `deny=8` ist genau die Schwelle, und der Schreibtisch steht
danach weiter (`wm: hold`).

### 14.5 Der sichtbare Beleg im Absturzlauf

Der Absturzlauf macht jetzt **zwei** Fotos aus demselben Lauf: eines,
waehrend das Plugin sein Feld in der Leiste besetzt haelt, und eines,
nachdem der Kern den Toten abgeholt hat. Dafuer meldet sich
`plugboese segv` unter dem Namen `boesebar` an — diese Zeile in
`/etc/wmplug.conf` traegt zusaetzlich `R_ACT_BAR` (0x801) — schickt
`plugin lebt` in die Leiste und stuerzt erst fuenf Sekunden spaeter ab.

Die Koordinate kommt aus der Leiste selbst (`taskbar: plug nr=0 x= y=
w= h=` plus `taskbar: geom`), nicht aus dem Skript:

```
das Plugin-Feld der Leiste steht bei x=624 y=2 w=92 h=26, Mitte (670,585)
checkshot punkt (670,585): vorher [38 48 60], nach dem Absturz [30 41 59]
```

Vorher die Farbe des Widgetkastens, nachher die nackte Leiste: das Feld
ist weg, weil der Platz frei ist. Bilder:
`docs/shots/wmplug/vor-absturz.png` und `nach-absturz.png`. Dazu
weiterhin: `wm: comp=172` Bildrunden nach dem Absturz, 479819 von 480000
Bildpunkten nicht schwarz, `kicks=1`, `wmplug: tot` genau einmal.

### 14.6 Was damit aus den Abkuerzungen und offenen Punkten wird

* **Abkuerzung 1 (geborgtes Leserecht) — gestrichen**, siehe 14.2.
* **Abkuerzung 2 (`plugstart.fi`) — gestrichen**, siehe 14.1. Die Datei
  ist geloescht, `/bin/uhrstart` gibt es nicht mehr.
* **Abkuerzung 5 (Rechte-Gegenprobe misst den weiteren Fall) —
  gestrichen**: sie misst jetzt `rechte=0x001` aus der Datei.
* Offener Punkt "**Die Frist ist eine Zahl fuer alle**" — erledigt
  (14.3).
* Offener Punkt "**`G_RIGHTS` ungemessen**" — erledigt (14.4).

**Neu benannt, weil es sonst niemand sieht:** der Autostart wartet zwei
Sekunden, bevor er die erste Zeile ausfuehrt (14.1). Die Zahl ist an
diesem Abbild gemessen und nicht hergeleitet; richtig waere, dass ein
Plugin die Zeit eines fremden `SYS_EXEC` nicht auf seine Frist
angerechnet bekommt.
