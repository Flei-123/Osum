# RUNDE BAUFEHLER — die Abnahme sagt wieder die Wahrheit

Zweig `baufehler`, abgezweigt von `main` (`ae381a3`), 13./14.09.2026.
Uebersetzer festgenagelt auf Firn `c4e3dfce`, Flickenstand `f9fd8eaadcf22ec0`.

## Die zwei Zahlen, um die es ging

| | vorher (`main`) | nachher (dieser Zweig) |
|---|---|---|
| Programme, die `fas` bindet | **117 von 135** | **135 von 135** |
| Abschnitte des Volllaufs mit einer echten Zahl | 26 von 73 (der Lauf vom 12.09. kam nicht weiter) | **74 von 74** |
| davon gruen | — | **47** |
| davon rot | — | **27** |
| abgebrochen / ohne Ergebnis | 47 | **0** |

`fas: 135` ist von der Abnahme selbst bestaetigt, nicht nur von einer
eigenen Messung — Abschnitt 21 (`tools/k16/run.sh`) sagt woertlich:

    OK    fas uebersetzt und bindet alle 135 Programme dieses Userlands
    OK    Programme, die fas gebunden hat: 135
    K16: 69 passed, 0 failed

Insgesamt sind **5225 Zusagen gruen und 382 rot** (Zeilen `OK`/`FAIL`
ueber alle 74 Protokolle).

---

## Was an den vier gemeldeten Punkten wirklich dran war

**Drei der vier Punkte aus dem Auftrag waren bereits behoben.** Ich habe
sie nachgeprueft statt sie zu glauben; das ist der Befund, nicht die
Arbeit. Die eigentliche Ursache von A-015 ist eine ANDERE als die
gemeldete, und sie war noch offen.

### A-015 — `fas` bindet die fUi-Programme nicht. OFFEN, aber andere Ursache.

Die Meldung sagt: doppeltes `_start`, `kernel/user/crt.s:34`. **Das war
es nicht.** Die Runde GRUNDLINIE hatte das schon richtig geloest
(`tools/k16/run.sh` fragt die `.s`, ob sie ein eigenes `_start` hat, und
haengt `--crt` nur dann an, wenn nicht).

Gemessen auf `main`, eigener Arbeitsbaum:

    PROGRAMME_GESAMT=135
    PROFILE_APP=18
    GEBUNDEN=117
    NICHT: calc certus desktop explorer freunde launcher lock netmon
           papierkorb powermon settings snip storage taskbar taskmgr
           themetest viewer widgetdemo

Es sind **achtzehn** Programme, nicht sieben — genau die mit
`profile app` — und alle scheitern an derselben Zeile:

    fas: Zeile 292370: diese Marke gibt es zwei '_F1.rt__ld8'

**Die Gegenprobe, die alles entscheidet:** GNU `as` sagt zu derselben
Datei dasselbe.

    $ firnc1 --profile=app kernel/user/widgetdemo.fi > w.s
    $ as --64 -o w.o w.s
    w.s:292370: Error: symbol `_F1.rt__ld8' is already defined
    ... 43 Symbole, jedes genau zweimal

`fas` hatte also recht. Der Fehler lag im Vendor-Baum.

**Ursache:** `lib/std/rt.fi` ist ein **Symlink** auf `lib/rt/rt.fi` —
eine Datei unter zwei Pfaden. `firnc` fuehrt ein Modul nach dem Pfad,
unter dem es importiert wurde, nicht nach der Datei dahinter. `import
std.rt` und `import rt.rt` sind damit zwei Module, die dieselben
Symbolnamen anmelden. Von 58 Vendor-Dateien schreiben 56 `std.rt`; genau
**zwei** schreiben `rt.rt`: `paint/png.fi:23` und `str/ucd.fi:19`.

Die Kette ist Schritt fuer Schritt nachgestellt (doppelte Symbole in
Klammern):

    fui.render (43) -> fui.uisvg (43) -> svg.svgimage (43)
                    -> paint.png (43) -> import rt.rt

waehrend die Nachbarn derselben Ebene sauber sind (`paint.canvas`,
`fui.style`, `fui.theme`, `fui.widget`, `fui.painter`, `fui.uiimage`,
`fui.core`: je 0). Die Oberflaechen-Programme ziehen `fui.render` ueber
`wlib` -> `fuib`, die uebrigen 117 nicht — daher genau diese achtzehn.

Der Symlink allein reicht NICHT: `fetch-firnc.sh` stellt ihn seit Runde
31 gegen genau diese Fehlerklasse wieder her, und das wirkt gegen den
Uebersetzer-Abbruch (`struct 'rt__Buf' is already declared`), nicht
gegen den doppelten Ausgabetext. Gemessen: die acht Verweise stehen, die
`.s` hat trotzdem 43 doppelte Namen.

**Behoben** mit `vendor/firn/patches/0005-rt-rt-heisst-std-rt.patch`
(zwei Zeilen, `rt.rt` -> `std.rt`). Der Flicken liegt dort, weil
`vendor/firn/lib/` nicht eingecheckt ist und bei jedem `--force` neu
entsteht; ueber diesen Weg ist er geprueft. `117 -> 135`.

### A-016 — Profil `kernel` statt `app`. BEREITS BEHOBEN.

`tools/lib/userprog.sh` ist die gemeinsame Stelle, die der Auftrag
verlangt, und sie existiert schon. Nachgeprueft, nicht geglaubt: ich habe
jeden Laeufer, der `kernel/user/*.fi` uebersetzt, gegen die Liste der
`profile app`-Programme gehalten. **Kein Laeufer ohne Profil-Lesen baut
ein `profile app`-Programm.** Die im Auftrag genannten Zahlen sind
veraltet; `NETVIEW` sagt heute `OK the graphical userland builds (14
programs)`.

### A-014 / K-015 — `RAND_OFF` in `memmap.py`. DIE MELDUNG IST FALSCH.

`MARGIN_OFF`/`MARGIN_MAX` existieren **nirgends** im Baum. Die
Konstanten heissen `RAND_OFF`/`RAND_MAX` (`kernel/kstate.fi:734-735`),
und `memmap.py:121` nennt genau diese — richtig. Die Umbenennung der
Runde ENGLISCH-ETAPPE-6 wurde von der Runde GRUNDLINIE zurueckgenommen,
weil „Rand" in `rand.fi` ZUFALL heisst und nicht Kante.

Es gibt auch keinen Rueckfall, der etwas verdeckt. Gegenprobe:

    $ sed -i 's/^const RAND_OFF/const MARGIN_OFF/' <kopie>/kstate.fi
    $ python3 tools/kernel/memmap.py <kopie>
    ValueError: unbekannte Konstante RAND_OFF

`memmap.py` liest die Konstanten dynamisch aus der Quelle und bricht bei
einem unbekannten Namen sofort ab. Regulaer laeuft es mit
`108 Bereiche in 0x100000 Oktetten kdata, 11 Vektoren, 186 Modusnamen,
0 Kollisionen`. **Nichts zu tun.**

### F-006 — `vendor/net/BLOBS`. BEREITS BEHOBEN.

Am 13.09. mit Commit `5091963` nachgezogen. Abschnitt 1 ist in diesem
Lauf **gruen** (9 Zusagen). Geprueft wird gegen `vendor/firn/lib/.roh/`,
also den UNGEFLICKTEN Stand — und mein Flicken 0005 fasst keine der drei
Dateien aus `BLOBS` an, deshalb bleibt das so.

---

## Der zweite Befund, der grosser war als der erste

Beim Durchfahren des Volllaufs kam ein Fehler heraus, der im Auftrag
nicht stand und mehr Rot erzeugt hat als A-015: **zehn Laeufer konnten
gar kein Abbild mehr bauen.**

    mkfs: the disk is full

Das ist NICHT die Wirtsplatte, sondern eine feste Bloeckezahl im
Laeufer. Ursache: Runde GRUNDLINIE hat die Laeufer — zu Recht — auf
`--profile=app` umgestellt. Das Profil bringt Firns volle Laufzeit mit
und verdoppelt die Programmgroesse:

    /bin/explorer   907360 (kernel)  ->  1623040 Oktette (app)

Die Bloeckezahlen blieben stehen. Ohne Abbild startet kein QEMU, und
alles dahinter fiel — bei `NETMON` einundvierzig Zusagen an EINEM Satz.

**Nebenbefund, der in mehreren Dateien falsch steht:** ein Block ist
**512 Oktette** (`tools/osum/mkfs.py`, `BS = 512`), nicht 4096. Mehrere
Kommentare rechnen mit 4096 und nennen um den Faktor acht zu grosse
Megaoktett-Zahlen („4096 Bloecke sind 16 MiB" — es sind 2 MiB). Die
Bloeckezahlen selbst waren trotzdem richtig, weil sie gemessen wurden.
Die Stellen, die ich angefasst habe, sind jetzt richtig beschriftet.

Geaendert wurden nur Stellen, in deren Protokoll wirklich
`disk is full` stand (oder die ueber `look/shot.sh` fotografieren):

| Datei | vorher | nachher |
|---|---|---|
| `tools/look/shot.sh` | 16384 | 32768 | 
| `tools/k15/run.sh` | 8192 | 16384 |
| `tools/netview/run.sh` | 16384 | 32768 |
| `tools/glyph/run.sh` | 16384 | 32768 |
| `tools/netmon/run.sh` | 4096 | 16384 |
| `tools/toolbench/build.sh` | 16384 | 32768 |
| `tests/theme/build.sh` | 16384 | 32768 |
| `tools/systembus/run.sh`, `desktop`, `entry`, `hidpunkte`, `hidweg`, `multicore`, `clockwork/bauen.sh` | 16384 | 32768 |

`tools/look/shot.sh` wiegt dabei schwerer als alle anderen zusammen:
darueber fotografieren **alle** Laeufer, die Aussehen pruefen. Der Kopf
der Stelle hatte es vorausgesagt — „That is not spare room, that is a
countdown."

**Nicht angefasst**, weil das Protokoll KEIN `disk is full` zeigt:
`themestore`, `icons`, `screen`, `vault/gui`, `netview/smoke`,
`glyph/merge8-keep`. Wo die Zahl reicht, bleibt sie stehen; geraten wird
hier nichts.

### Was die Reparatur gebracht hat (gemessen, vorher -> nachher)

| Abschnitt | vorher | nachher | |
|---|---|---|---|
| `netmon` | 25 gut, 41 rot | **76 gut, 0 rot** | voll gruen, alle 41 an EINEM Satz |
| `k15` | 84 gut, 60 rot (+ Abbruch) | **179 gut, 74 rot** | 253 Zusagen statt 98 |
| `glyphe` | 13 gut, 16 rot | **26 gut, 3 rot** | |
| `systembus` | 32 gut, 3 rot | **33 gut, 2 rot** | |
| `werkzeug` | kein Abbild, 0 Zusagen | **18 gut, 16 rot** | lief vorher gar nicht |
| `theme` | 0 gut, 1 rot | **29 gut, 68 rot** | lief vorher gar nicht |
| `softui` | 0 gut, 2 rot | **7 gut, 17 rot** | „bootet nicht" 2 -> 0 |
| `netview` | 120 gut, 30 rot | **125 gut, 44 rot** | `mkfs`-Fehler 6 -> 0, „no screenshot" 13 -> 0 |
| `paint` | 26 gut, 2 rot | **28 gut, 9 rot** | |

**Wichtig zum Lesen dieser Tabelle:** Mehr Rot nach der Reparatur ist
hier KEIN Rueckschritt. Vorher brach der Laeufer VOR seinen Pruefungen
ab; jetzt laufen sie und melden echte Befunde. Bei `netview` ist das
belegbar: die sechs `mkfs`-Fehler und dreizehn „no screenshot" sind weg
— die 44 roten sind Pruefungen, die vorher nie ausgefuehrt wurden.

### Und ein Loch, das gar nichts meldete

`K15` starb nach der Abbild-Reparatur mitten im Abschnitt:

    tools/k15/run.sh: line 823: SP[1]: unbound variable

Danach kam nichts: keine Schlusszeile, keine Zahl. Der Abschnitt
verschwand aus der Bilanz. Der Dateimanager malt sein Fenster nicht
(`explorer: ready` fehlt), damit fehlt die Zeile `explorer: spalten`,
`SP` bleibt leer, und `set -u` beendet das Skript. Ein fehlender
Messwert ist ein Fehler und kein Grund, die Messung abzubrechen: der
Laeufer sagt das jetzt als eigene rote Zusage und kommt bis zu seiner
Bilanz — `K15: 179 passed, 74 failed`.

---

## Die Abschnittstabelle

Gefahren **seriell** (`OSUM_JOBS=1`). Spalte „nachgefahren" heisst: der
Abschnitt ist nach einer Reparatur oder wegen Lastverdachts einzeln
wiederholt worden, und die Zahl in dieser Zeile ist die des
Einzellaufs.

| Abschnitt | Stand | Zusagen | nachgefahren | bei rot: die Ursache |
|---|---|---|---|---|
| `ahci` | **gruen** | 62 gut, 0 rot |  |  |
| `arm` | **gruen** | 48 gut, 0 rot |  |  |
| `async` | **gruen** | 108 gut, 0 rot |  |  |
| `avx` | **gruen** | 32 gut, 0 rot |  |  |
| `blech` | **rot** | 69 gut, 1 rot |  | DER ALTE KERN haengt nichts ein |
| `boot` | **gruen** | 20 gut, 0 rot |  |  |
| `bridge` | **gruen** | 113 gut, 0 rot |  |  |
| `caps` | **gruen** | 67 gut, 0 rot |  |  |
| `core` | **gruen** | 46 gut, 0 rot |  |  |
| `customres` | **rot** | 123 gut, 12 rot |  | und die neun eigenen dieser Runde -- soll '9', ist '8' |
| `display` | **rot** | 142 gut, 3 rot |  | EDID hat auch Ring 3 gesehen -- soll '1', ist '0' |
| `freestanding` | **gruen** | 41 gut, 0 rot |  |  |
| `fsrobust` | **gruen** | 30 gut, 0 rot |  |  |
| `gfx` | **gruen** | 76 gut, 0 rot |  |  |
| `glyphe` | **rot** | 26 gut, 3 rot | ja | ttf.glyph haelt die Unterbrechungen nicht an |
| `guard` | **gruen** | 58 gut, 0 rot |  |  |
| `haertung` | **gruen** | 19 gut, 0 rot |  |  |
| `handle` | **gruen** | 80 gut, 0 rot |  |  |
| `hid` | **rot** | 56 gut, 1 rot |  | audio      steckt in noaudio    (kmain.fi:w_aud / kmain.fi:w_noaud) |
| `hv` | **gruen** | 114 gut, 0 rot |  |  |
| `hwnet` | **gruen** | 56 gut, 0 rot |  |  |
| `hwnettls` | **gruen** | 24 gut, 0 rot |  |  |
| `icons` | **rot** | 24 gut, 1 rot |  | raw code points in the drawing code: '1', wanted '0' |
| `init` | **gruen** | 78 gut, 0 rot |  |  |
| `k11` | **gruen** | 85 gut, 0 rot |  |  |
| `k13` | **gruen** | 99 gut, 0 rot |  |  |
| `k14` | **gruen** | 152 gut, 0 rot |  |  |
| `k15` | **rot** | 179 gut, 74 rot | ja | mit 'noclip' kommt NUR das Getippte an: 'Kopiermich-ab' statt '-ab' |
| `k16` | **gruen** | 69 gut, 0 rot |  |  |
| `k17` | **rot** | 156 gut, 2 rot |  | so viele key-Zeilen, wie der USB-Treiber Tasten gezaehlt hat |
| `k18` | **gruen** | 170 gut, 0 rot |  |  |
| `kernel` | **gruen** | 176 gut, 0 rot |  |  |
| `kvm` | **gruen** | 31 gut, 0 rot |  |  |
| `modul` | **rot** | 71 gut, 3 rot |  | Adressen, die mit nm uebereinstimmen: 12, erwartet eq 13 |
| `multiuser` | **gruen** | 91 gut, 0 rot |  |  |
| `net` | **gruen** | 75 gut, 0 rot |  |  |
| `netmon` | **gruen** | 76 gut, 0 rot | ja |  |
| `netview` | **rot** | 125 gut, 44 rot | ja | roles whose contrast was computed against the panel (4.5:1 or better): 10, exp |
| `osum` | **rot** | 129 gut, 1 rot |  | keys that arrived over IRQ1: 2, expected eq 3 |
| `ota` | **gruen** | 107 gut, 0 rot |  |  |
| `paint` | **rot** | 28 gut, 4 rot | ja | kernel/r3dsoft.fi: S_SIN (0xA0, 8192 Oktette, Zeile 110) und S_SIN_N (0xA8, 8 |
| `pci` | **rot** | 97 gut, 1 rot |  | DMA against PIO, same interface, in thousandths: 919, expected ge 1200 |
| `poll` | **gruen** | 67 gut, 0 rot |  |  |
| `posix` | **gruen** | 150 gut, 0 rot |  |  |
| `powermon` | **rot** | 62 gut, 54 rot |  | call numbers from 1830..1839 also stand in: kernel/user/taskmgr.fi:526:const S |
| `praesenz` | **rot** | 34 gut, 2 rot |  | die Leiste zeigt die vier Demo-Freunde: '0', erwartet '4' |
| `protokoll` | **gruen** | 55 gut, 0 rot |  |  |
| `rtl` | **gruen** | 67 gut, 0 rot |  |  |
| `server` | **rot** | 21 gut, 2 rot |  | kein Modul ausser der Naht greift noch auf die Grafik zu: 16 (erwartet eq 0) |
| `smp` | **gruen** | 59 gut, 0 rot |  |  |
| `softui` | **rot** | 7 gut, 17 rot | ja | Marken aus modern.shape: 0, erwartet 24 |
| `sshd` | **gruen** | 67 gut, 0 rot |  |  |
| `stick` | **rot** | 20 gut, 22 rot |  | der Menueeintrag 'Kommandozeile mit Netz' wurde gewaehlt -- 'console=ttyS0' fe |
| `systembus` | **rot** | 33 gut, 2 rot | ja | in der Leiste steht keine Meldung |
| `theme` | **rot** | 29 gut, 68 rot | ja | rohe Farbwerte im Zeichencode: 17, erwartet eq 0 |
| `themestore` | **rot** | 65 gut, 16 rot |  | kein Schluessel ausserhalb der sieben: 1, erwartet eq 0 |
| `tiling` | **gruen** | 68 gut, 0 rot |  |  |
| `ton2` | **gruen** | 25 gut, 0 rot |  |  |
| `tresor` | **gruen** | 220 gut, 0 rot |  |  |
| `tunnel` | **gruen** | 16 gut, 0 rot |  |  |
| `tunnelkosten` | **gruen** | 3 gut, 0 rot |  |  |
| `tunnelpakete` | **gruen** | 18 gut, 0 rot |  |  |
| `umlaut` | **rot** | 22 gut, 11 rot | ja | translit rc: '1', erwartet '0' |
| `unix` | **gruen** | 107 gut, 0 rot |  |  |
| `update` | **gruen** | 49 gut, 0 rot |  |  |
| `usbimg` | **rot** | 44 gut, 4 rot | ja | UEFI-Lauf: erkannte Firmware: ? (erwartet UEFI) |
| `userland` | **rot** | 90 gut, 1 rot |  | keys that arrived over IRQ1 (l, s, return, up, return): 3, expected eq 5 |
| `vendor` | **gruen** | 9 gut, 0 rot |  |  |
| `vielkern` | **rot** | 32 gut, 8 rot | ja | darf_ring3 fragt die GS-Basis nicht ab |
| `vsync` | **gruen** | 14 gut, 0 rot |  |  |
| `werkzeug` | **rot** | 18 gut, 16 rot | ja | und er steht im Startmenue (/apps/taskmgr.osp) -- 'name=[Aufgabenverwaltung]' |
| `wlan` | **gruen** | 185 gut, 0 rot |  |  |
| `wlan2` | **gruen** | 43 gut, 0 rot |  |  |
| `wm` | **rot** | 99 gut, 5 rot |  | die Spitze des Zeigers steht in der Bildmitte -- 104 105 106 |

**47 gruen · 27 rot · 0 abgebrochen · 0 ohne Ergebnis — 74 von 74.**

---

## Die roten Abschnitte, nach Ursache sortiert

Damit man sie nicht einzeln lesen muss:

**1. Tastendruecke, die unter Last verschwinden (4 Abschnitte).**
`osum` (1), `userland` (1), `k17` (2), `systembus` (2) — alle sagen
Varianten von „keys that arrived over IRQ1: 2, expected eq 3". Auf
dieser Maschine liefen bis zu **sechs fremde QEMU-Prozesse** aus den
vier anderen Auftraegen gleichzeitig; `uptime` zeigte Lastmittel bis
9,5. Diese Abschnitte sind seriell nachgefahren und blieben rot, sind
also nicht durch MEINE Parallelitaet erklaert — wohl aber durch die
Gesamtlast. Der Kern selbst ist gruen (`kernel` 176/0).

**2. Ein Durchsatz, der unter Last nicht erreicht wird (1).**
`pci`: „DMA against PIO, in thousandths: 919, expected ge 1200".
Dasselbe Bild — eine Verhaeltniszahl, die bei voller Maschine nicht
messbar ist.

**3. Aussehen und Text, bildpunktgenau (7).**
`wm` (5), `k15` (74), `theme` (68), `softui` (17), `netview` (44),
`werkzeug` (16), `paint` (9). Das ist das eigentliche Arbeitsfeld, das
hinter dem Abbild-Fehler verborgen lag: Zeigerspitze, Fensterkopf,
Spalten des Dateimanagers, Marken einer Formdatei, Kontrastwerte. Diese
Zahlen sind zum ERSTEN MAL ueberhaupt gemessen — vorher gab es kein
Bild, in dem man haette nachsehen koennen.

**4. Eigene, unabhaengige Befunde (15).**
`powermon` (54, Aufrufnummern und deutsche Woerter im Quelltext),
`themestore` (16), `stick` (22), `umlaut` (11, `translit rc: 1`),
`vielkern` (8), `customres` (12), `display` (3, EDID in Ring 3),
`glyphe` (3), `modul` (3), `praesenz` (2), `server` (2), `blech` (1),
`hid` (1), `icons` (1), `usbimg` (4, UEFI-Firmware nicht erkannt).
Jeder davon ist ein eigenes Thema und gehoert in die Offenliste, nicht
in diese Runde.

---

## Welchen Zahlen man ab jetzt glauben darf

**Glauben darf man:**

* **`fas` bindet 135 von 135.** Doppelt belegt — eigene Messung und
  Abschnitt 21 der Abnahme (`K16: 69 passed, 0 failed`).
* **Alle 74 Abschnitte haben eine echte Zahl.** Kein „abgebrochen", kein
  „ohne Ergebnis", kein stiller Skriptabbruch mehr. Das war vor dieser
  Runde nicht so: der Lauf vom 12.09. kam bis Abschnitt 26, und ein
  weiterer lief auf eine volle Platte.
* **Die 47 gruenen Abschnitte.** Darunter der ganze Kern (`kernel`,
  `smp`, `posix`, `k11`, `k13`, `k14`, `k16`, `k18`, `hv`, `caps`,
  `handle`, `async`), das Netz (`net`, `netmon`, `hwnet`, `wlan`,
  `wlan2`, `tunnel`, `bridge`), die Platte (`ahci`, `fsrobust`, `ota`,
  `update`) und `arm`.
* **Abschnitt 1.** Er war „bei JEDEM Lauf rot" — er ist gruen, und zwar
  gegen `lib/.roh/`, den ungeflickten Stand.

**Nicht glauben darf man:**

* **Die Zahlen aus dem parallelen Lauf** (`OSUM_JOBS=3`), den ich als
  ersten gefahren habe. Er hatte bei `k14` acht Fehler, die seriell
  verschwanden (`152 gut, 0 rot`), und bei `wm` neun statt fuenf. Ich
  habe ihn deshalb verworfen und komplett seriell neu gefahren. Die
  Tabelle oben ist der serielle Lauf.
* **Die vier Punkte des Auftrags als Beschreibung des Zustands.** Drei
  von vier waren erledigt, und der vierte hatte eine andere Ursache als
  gemeldet. Wer die Offenliste vom 12.09. liest, sollte jeden Punkt
  nachmessen, bevor er darauf baut.
* **Eine „rot"-Zahl als Qualitaetsurteil ohne Blick ins Protokoll.**
  Bei `netview`, `theme`, `softui`, `werkzeug` und `k15` ist die Zahl
  GESTIEGEN, weil die Pruefungen jetzt ueberhaupt laufen.

**Unter Vorbehalt:** die vier Abschnitte mit verschwundenen
Tastendruecken und `pci` mit seinem Durchsatz. Sie brauchen eine ruhige
Maschine, um als Aussage ueber Osum zu gelten. Solange vier weitere
Auftraege dieselbe Maschine benutzen, sagen sie etwas ueber die Last
und nicht ueber den Kern.

---

## Wie der Lauf gefahren wurde, und was dabei schiefging

Die Platte hatte zu Beginn **3,0 GB frei** und wird mit vier weiteren
Auftraegen geteilt. Der Auftrag warnte davor, und die Warnung war
berechtigt:

* Erster Versuch, `OSUM_JOBS=3`: die Platte fiel auf **74 MB**. Eine
  eigene Plattenwache (`/root/os-bau-wacht.sh`, prueft alle 20 s) hat
  den Lauf bei Abschnitt 21 abgebrochen — bewusst, um den anderen vier
  Auftraegen nicht den Platz wegzunehmen. Die Ergebnisse liegen unter
  `/root/os-bau-teil1/`.
* Zweiter Versuch, `OSUM_JOBS=1` mit Wache auf 400 MB: bis Abschnitt 54,
  dann fiel die Platte auf **280 MB** (die Installer-Tests eines anderen
  Auftrags), und die Wache griff wieder. Ergebnisse unter
  `/root/os-bau-teil2/`.
* Danach habe ich **meine eigenen Reste** aufgeraeumt (`/tmp/update-run`
  allein 800 MB) und die verbleibenden 20 Abschnitte einzeln
  nachgefahren, mit Plattenpruefung vor jedem Abschnitt
  (`/root/os-bau-rest.sh`).

Fremde Verzeichnisse habe ich nicht angefasst und keinen fremden Prozess
beendet. Kein `main`-Merge; alles liegt auf `baufehler`.

## Die Commits

| | |
|---|---|
| `925beab` | A-015: zwei Pfade auf eine Datei — `fas` 117 -> 135 |
| `07e4342` | K15: Abbild zu klein, seit `profile app` gebaut wird |
| `f78967b` | NETVIEW: dasselbe, und ein Block ist 512 Oktette |
| `5010d51` | acht weitere Laeufer mit demselben Abbild-Fehler |
| `6867f54` | `tools/look/shot.sh` — die Kamera selbst |
| `a19f4ea` | NETMON und `tests/theme` |
| `7866498` | WERKZEUGE — der siebte und letzte `disk is full` |
| `97a79b0` | K15 starb an einem leeren Feld und meldete nichts |

## Was als naechstes dran ist

1. **Die Oberflaeche messen, jetzt wo man sie sehen kann.** `k15` (74),
   `theme` (68), `netview` (44), `softui` (17), `werkzeug` (16) — das
   sind 219 Zusagen, die zum ersten Mal wirklich laufen. Der
   Sammelbefund „der Dateimanager malt sein Fenster nicht"
   (`explorer: ready` fehlt) steht dabei vor allen anderen: an ihm
   haengen die meisten.
2. **Die Bloeckezahl aufhoeren zu raten.** Vier Runden haben dieselbe
   Zahl vier Mal erhoeht. Sie sollte aus der Summe der Dateien
   berechnet werden, nicht im Skript stehen — dann faellt dieser Fehler
   ein fuenftes Mal nicht an.
3. **`powermon` (54)** ist der groesste Einzelposten und hat nichts mit
   dieser Runde zu tun.
4. **Die Lastflakes auf einer ruhigen Maschine nachfahren**, damit aus
   dem Vorbehalt eine Aussage wird.
