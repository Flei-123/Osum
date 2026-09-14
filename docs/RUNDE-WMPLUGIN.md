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
| 2117 | `WM_PLUG_REG` | (abi, name, maske) → Platz |
| 2118 | `WM_PLUG_UNREG` | () → 0 |
| 2119 | `WM_PLUG_POLL` | (aus) → 1 geholt / 0 keines. **Kehrt immer sofort zurueck.** |
| 2120 | `WM_PLUG_SUB` | (maske) → 0 |
| 2121 | `WM_PLUG_INFO` | (platz, feld) → Zahl |
| 2122 | `WM_PLUG_ACT` | (handlung, id, wert) → 0 |
| 2123 | `WM_PLUG_KEY` | (taste, mods) → 0 |
| 2124 | `WM_PLUG_BAR` | (text, laenge) → 0 |
| 2125 | `WM_PLUG_BARGET` | (platz, aus, max) → Laenge — **nur die Leiste** |
| 2126 | `WM_PLUG_GRANT` | (name, rechte) → 0 — **nur root** |

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

Ein Lauf, ein Fensterserver (`wm: hold` steht genau **einmal** da):

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

`PL_FRAMES` und `PL_LATUS` kommen **nicht** aus einem Zaehler, der fuer
diese Runde erfunden wurde, sondern aus der Bilduhr, die `wm.compose`
seit der Runde VEKTOR ohnehin fuehrt. Ein zweiter Zaehler daneben
lieferte ein zweites Ergebnis, und dann glaubt man keinem von beiden.

Gelesen **im selben Lauf**, vor und nach der Plugin-Last — also derselbe
Kernel, dieselbe Maschine, dieselbe Minute:

| | Bilder (`PL_FRAMES`) | Latenz je Bild (`PL_LATUS`) |
|---|---|---|
| vor der Last | 18 | 1530 us |
| nach der Last | 64 | 859 us |

Die Latenz **faellt**, statt zu steigen. Das ist kein Verdienst der
Plugins: die ersten Bilder eines Hochlaufs sind die teuersten
(kalte Glyphen — `wmbench: glyph cold=6138 us warm=216 us`), und der
Mittelwert sinkt, sobald die Zwischenspeicher warm sind. **Die ehrliche
Aussage ist deshalb nicht "Plugins machen es schneller", sondern: in
diesen Zahlen ist von den Plugins nichts zu sehen.**

Der zweite, saubere Vergleich sind die Zusammensetzerrunden zweier
Laeufe desselben Abbilds, bei denen einmal ein Plugin abstuerzt und
einmal eines haengt: **163 gegen 165**. Kein Einbruch.

Woher die Ruhe kommt, ist kein Zufall, sondern die Bauform: der Kern
macht je Bild **acht Vergleiche** (der Kehrbesen) und legt Ereignisse in
Ringe. Er ruft **nie** in ein Plugin hinein und wartet **nie** auf eines.

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

1. **Das geborgte Leserecht.** Titel und Ort fremder Fenster gibt
   `WM_LIST` nur einer Taskleiste (`is_taskbar`). `plugregel` und
   `plugboese` brauchen diese Zahlen, also legen beide ein **verborgenes**
   Fenster von 32x16 mit einem Schirmrand von **einem** Bildpunkt an.
   `wm.recalc_work` ueberspringt verborgene Fenster (wm.fi:3376), die
   Arbeitsflaeche aendert sich um keinen Punkt, auf dem Schirm ist nichts
   zu sehen. **Richtig waere ein eigenes Leserecht** (`R_EV_WIN` als
   Leseschluessel fuer `WM_LIST`). Betrifft nur das *Messen*, nicht das
   Recht zum *Handeln*.
2. **`kernel/user/plugstart.fi`.** Der Kern startet auf dem
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
5. **Die Rechte-Gegenprobe misst den weiteren der beiden Faelle.**
   `plugboese` laeuft mit `R_DEFAULT` (0x1F) aus dem Kern, nicht mit den
   0x001 aus `/etc/wmplug.conf` — die wuerden erst durch
   `wmplug enable boese` wirksam. Beide haben **kein** Aktionsbit, die
   Zusage traegt also; gemessen ist aber der groessere Rechtesatz.
6. **Acht Plaetze und 32 Ereignisse je Ring** sind gesetzt und nicht
   hergeleitet. Laeuft ein Ring ueber, faellt das aelteste Ereignis
   heraus und `P_LOST` steigt — sichtbar, aber eben ein Verlust.

---

## 11. Offene Punkte

* **Kein eigenes Leserecht fuer `WM_LIST`.** Solange es fehlt, brauchen
  Plugins den Umweg aus Abkuerzung 1.
* **Keine Autostart-Liste** des Schreibtischs (Abkuerzung 2).
* **Die Frist ist eine Zahl fuer alle.** Ein Widget im Sekundentakt und
  eine Regel-Engine, die nur bei `E_WIN_OPEN` aufwacht, haben dieselbe
  halbe Sekunde. Eine Frist je Plugin waere richtiger.
* **`G_RIGHTS` (zu oft ohne Recht angeklopft) ist gebaut, aber in dieser
  Runde nicht ausgeloest worden.** Gemessen ist nur `PL_DENY`, das
  einzelne Abweisen. Die Schwelle selbst ist **ungemessen**.
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
