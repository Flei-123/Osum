<!-- SPDX-License-Identifier: GPL-2.0-only -->
# Runde BLECH-HID — die erste Runde, die auf einer Messung von echter Hardware steht

Arbeitsbaum `/root/osum-blechhid`, Zweig `blechhid`, abgezweigt von
`main` (`4609ec9`, Ende Runde STICK). Gemessen am 03.09.2026 auf dem
üblichen Wirt (AMD EPYC 7571, 12 Kerne, `/dev/kvm`, QEMU 7.2.22) —
**und die Aufgabenstellung kommt zum ersten Mal in diesem Projekt nicht
aus QEMU, sondern von Blech.**

---

## 0. WAS SICH GEÄNDERT HAT, UND ES IST NICHT DER QUELLTEXT

Justin hat am 03.09.2026 das Abbild aus Runde STICK zum ersten Mal auf
einem echten Rechner gestartet. Bis zu diesem Tag stand in
`docs/BLECH-BEREIT.md` der Satz:

> Es gibt in diesem Repository **keine einzige Messung auf echter
> Hardware.**

Der Satz ist ab heute falsch, und das ist das Wichtigste an dieser
Runde.

**Der Rechner:** AMD-Plattform (PCI-Hersteller `1022`, unter anderem
`1482/1483/1484/1485/1486/1487/148a/149c/43c8/43d5`), NVIDIA GA106
(`10de:2504`) mit HDMI-Ton (`10de:228e`), Huawei-Ultrawide-Schirm,
Start über **UEFI** vom USB-Stick.

### 0.1 Was auf Anhieb ging — und das ist mehr, als zu erwarten war

| Befund vom Blech | Zeile |
|---|---|
| **NVMe erkannt** | `hwdiag: disk NVMe bdf=0x100 c0a9:5426` |
| **AHCI erkannt** | `hwdiag: disk AHCI bdf=0x201 1022:43c8` |
| **Wurzelsuche und Reihenfolge** | `blkdev: reihenfolge: nvme > ahci > usb > usb`, vier Blockgeräte `d0..d3` |
| **ZWEI xHCI-Regler gefunden** | `rootsel: usb xHCI bdf=0x200 1022:43d5`, `rootsel: usb xHCI bdf=0xc03 1022:149c` |
| **r8169 BINDET auf echtem Silizium** | `netdev: bestand 09:00.0 10ec:8168 RTL8111/8168/8411 -> r8169`, `bestand 1 geraete, 1 mit treiber, 0 ohne` |
| **Schutzbits, Vektoreinheit, Zeitgeber** | `guard: cr4=0x340620 smep=1 smap=1 cpu=1/1`, `fpu: mode=3 xcr0=0x7`, `ticks: 24 traps=25` |
| **Rahmenpuffer über die ganze Breite** | der blaue Hintergrund füllt den **ganzen** Ultrawide-Schirm — der 1024-Wand-Fix aus Runde STICK trägt auf Blech |
| **Fenster** | „Terminal -- sh" mit Rahmen, Titel und Schließknopf korrekt gezeichnet |
| kein Absturz, keine Panik, keine unbekannte Hardware | die Diagnose lief vollständig durch und hielt sauber an |

### 0.2 Und drei Dinge gingen nicht

1. **KEINE EINGABE.** Maus und Tastatur tot; die USB-Maus **leuchtete
   nicht einmal**. Kein PS/2 an diesem Brett. Das war der Sperrpunkt.
2. **DIE TASKLEISTE WAR UNSICHTBAR.** Vom Programm kam
   `taskbar: lang=de src=1 keys=200` und darunter `taskbar: icons=` —
   **mitten im Wort abgebrochen**. Unten am Schirm nichts.
3. **DER MAUSZEIGER WAR KEIN PFEIL.** Vergrößert: ein Dreieck, darunter
   eine Lücke, darunter zwei getrennte Stummel.

---

## 1. DIE EINGABE — DREI FEHLER, NICHT EINER

Justin hat den entscheidenden Hinweis mitgeliefert: **im Startmenü des
Laders funktionierte die Tastatur einwandfrei.** Damit ist Hardware,
Kabel, Buchse und Firmware freigesprochen und die Schuldfrage
beantwortet, bevor eine Zeile gelesen ist: es liegt an Osums eigener
Übernahme nach `ExitBootServices`. Drei Ursachen, alle drei echt.

### 1.1 Der Schreibtisch hat USB überhaupt nicht eingeschaltet

Die Kommandozeilen der Menüeinträge in `tools/usbimg/build.sh` lauteten:

```
cmdline: modfs osum gfx wm wig desk wmshell nic nip=… nosched noproc nofs
```

Kein `usb`, kein `hidgen`. `usb.stage` prüft als **erstes**
`kstate.M_USB`, druckt `usb: skipped` und kehrt zurück. **Der ganze
USB-Baum lief in diesem Eintrag nie.** Auf einem Desktop mit PS/2 fällt
das nicht auf; auf einem Brett ohne PS/2 ist es das Ende jeder Eingabe.

Behoben: `usb hidgen` steht jetzt in **jedem** Eintrag, der eine
Oberfläche oder eine Shell startet.

### 1.2 Der Regler gehörte noch der Firmware (xECP-Kennung 1)

Das ist die eigentliche Ursache und die Zeile, um die es in dieser Runde
geht. `kernel/xhci.fi` hatte **keine einzige Zeile** zum *USB Legacy
Support* — der Treiber schrieb nach `pci.enable_master` unmittelbar in
`USBCMD`, also in einen Regler, den das BIOS über die Semaphore
`HC BIOS Owned` noch besetzt hielt.

Der Ablauf aus xHCI 1.2, Abschnitt 4.22.1, steht jetzt in `handover()`:
die erweiterte Faehigkeitsliste wird durchlaufen (Zeiger in
`HCCPARAMS1` Bit 31..16, **in Doppelworten**), Kennung 1 gesucht,
`HC OS Owned` gesetzt, auf das Fallen von `HC BIOS Owned` gewartet
(bis 1000 ms) und danach werden in `USBLEGCTLSTS` alle SMI-Freigaben
gelöscht und die stehenden Meldungen quittiert — Maske für Maske die
aus Linux (`drivers/usb/host/pci-quirks.c`). Lässt die Firmware nicht
los, wird das BIOS-Bit nach Fristablauf von Hand gelöscht; auch das tut
Linux, und der Bericht sagt, welcher der beiden Fälle eingetreten ist.

**Und diese zwanzig Zeilen sind in QEMU nicht messbar:** weder
`qemu-xhci` noch `nec-usb-xhci` trägt einen Legacy-Abschnitt, beide
melden `legsup=KEINE`. Deshalb gibt es `xhci.legtest` (Kernwort
`usbleg`): eine **gebaute** Fähigkeitsliste im freien Speicher, und
derselbe Quelltext läuft dagegen.

```
usbleg: fall 0 cap=x0110 soll=x0110 vor=x00010001 nach=x01000001 bios=0 os=1 ms=1000 hart=1 ctl=xe000000e OK
usbleg: fall 1 cap=x0110 soll=x0110 vor=x01000001 nach=x01000001 bios=0 os=1 ms=0    hart=0 ctl=xe000000e OK
usbleg: gut=2 schlecht=0
```

**Der Prüffall hat sofort einen echten Fehler gefunden**, und er ist
genau die Sorte, die man auf Blech nie wieder loswird: die Schleife
verließ sich mit `ms = LEG_MS`, und damit meldete eine Übernahme, die
nach drei Millisekunden durch war, **tausend**. Zwei Zähler statt
einem; Fall 1 misst es (`ms=0`).

### 1.3 Es gibt zwei xHCI-Regler, und der Treiber sah nur den ersten

`rootsel` hat auf Justins Brett **beide** gemeldet. `xhci.init` nahm
`pci.find_class(…)` — den ersten. Steckt die Tastatur am anderen, gibt
es keine Eingabe **und keine Zeile darüber**.

Jetzt: `count_hc`/`nth_hc`/`init_at`, und `usb.stage` probiert die
Regler der Reihe nach durch; der erste, an dem ein Eingabegerät hängt,
bleibt stehen. **Gemessen, mit zwei Reglern und HID am zweiten:**

| Kern | Kommandozeile | Ergebnis |
|---|---|---|
| `main` 4609ec9 | `usb hidgen`, `-device qemu-xhci -device nec-usb-xhci -device usb-kbd,bus=x1.0 -device usb-mouse,bus=x1.0` | **`usb: devices=0 kbd=0 mouse=0`** |
| diese Runde | dieselbe Zeile | **`usb: devices=2 kbd=1 mouse=1`** |

Was diese Runde **nicht** tut: zwei Regler GLEICHZEITIG fahren. Der
Vorrat des Treibers (`0x50000..0x58000`) ist einmal da; ihn zu
verdoppeln ist eine eigene Runde. Hängen Tastatur und Maus an
verschiedenen Reglern, wird einer bedient — und der Bericht sagt für
**jeden** Regler, was an seinen Anschlüssen steht, damit ein Mensch
beide an dieselbe Seite stecken kann.

### 1.4 Und die Zeit, die ein Anschluss braucht

Dass die Maus **nicht leuchtete**, ist eine Aussage über die
Versorgungsspannung und über nichts sonst. `HCRST` setzt `PP` auf null
(xHCI 1.2, 5.4.8), und danach dauert es, bis Spannung anliegt. An der
Stelle stand:

```
fn settle(state: u64) {
    var i: u64 = 0
    while i < 200000 { i = i + 1 }
}
```

Eine Zählschleife misst keine Zeit, sie misst den Übersetzer. Jetzt:
`xhci.udelay` auf dem geeichten Zyklenzähler, **200 ms** nach dem
Einschalten der Anschlüsse (`power_all`, das zurückgibt, an wie vielen
`PP` danach wirklich steht), **100 ms** Prellzeit vor dem Zurücksetzen
(USB 2.0, 7.1.7.3), **20 ms** Erholung danach (7.1.7.5) und ein
**zweiter Durchgang** nach 300 ms für alles, was sich später meldet.

---

## 2. DER USB-BERICHT — EIN FOTO MUSS REICHEN

Zwei Ausgaben, und die Trennung ist Absicht.

**`xhci.uebersicht` LIEST NUR** und steht am Ende der Diagnose
(Menü 1). Sie kann nicht hängen, weil sie kein Bit schreibt:

```
usb: regler=2
usb: hc0 bdf=0x0200 id=1022:43d5 ports=10 besitz=BIOS strom=10 verbunden=2
usb: hc1 bdf=0x0c03 id=1022:149c ports=8  besitz=BIOS strom=8  verbunden=1
```

`besitz=BIOS` ist die Antwort auf Justins Frage, in einem Wort.

**`xhci.bericht`** steht nach der Übernahme (neuer Menüeintrag
*„USB-Diagnose"*) und sagt, was sich geändert hat:

```
usb: hc0 bdf=0x0020 id=1b36:000d bar=0xfebf0000 hciv=0100 slots=64 ports=8 ctx=32
usb: hc0 xecp=0x0020 id=2 usb2 p5..8 id=2 usb3 p1..4
usb: hc0 legsup=0x0110 vor=0x00010001 bios=1 os=0 nach=0x01000001 bios=0 os=1 nach 6ms halt=1 hcrst=1
usb: hc0 strom=8/8 verbunden=1 frei=1
usb: hc0 p01 psc=0x000002a0 pp=1 ccs=0 ped=0 pr=0 spd=0 p02 … p03 … p04 …
usb: hc0 p05 psc=0x00000e03 pp=1 ccs=1 ped=1 pr=0 spd=3 p06 … p07 … p08 …
```

Vier Anschlüsse je Zeile, davor eine Zusammenfassung — zwanzig
Anschlüsse brauchen damit sechs Zeilen und nicht zwanzig. Die Zeile
`id=2 usb2 p5..8 / usb3 p1..4` kommt aus der *Supported Protocol*-
Fähigkeit und sagt, welche Buchse an welchem Draht hängt.

**Warum ein eigener Menüeintrag und nicht Menü 1:** Menü 1 fasst nichts
an und hält **vor** jedem Treiber an. Es ist der Eintrag, der auf jeder
fremden Maschine bis zum Bericht kommt, und er bleibt Oktett für Oktett,
wie er war. Bleibt der neue Eintrag auf irgendeinem Brett stehen, ist
der alte immer noch da.

---

## 3. DER NOTAUSGANG — BEFEHLE OHNE TASTATUR

Solange die Eingabe klemmt, ist jeder der 52 Befehle auf dem Abbild
unerreichbar. Also führt die Shell beim Start ein **Skript** aus.

Das Kernwort `netlauf` gibt `/bin/sh` den Pfad `/etc/netlauf.sh` als
Argument mit (`kernel/kmain.fi`, `osum`; `argc` wird zwei), die Shell
kann seit Runde K11 ein Skript als Ganzes lesen, und danach hält
`hwdiag.park_after_shell` den Bildschirm an — sonst wäre das Ergebnis
eine Zehntelsekunde zu sehen.

**Gemessen, gegen den echten Server, ohne eine einzige Taste:**

```
-- 1. Adresse holen (dhcp)
dhcp: ack ip=10.0.2.15  lease=86400  weg=0
dhcp: /etc/resolv.conf geschrieben, dns 1
-- 3. Namen aufloesen: store.fleitec.com
109.69.172.199
-- 4. holen: https://store.fleitec.com/index.json
fetch: roots 11 / verify OK / certs 4 / depth 3 / code 200
-- 5. nach einer neuen Fassung sehen
ota: fassung hier 0 / fassung dort 2 / ota: NEUE FASSUNG verfuegbar
==================================================
  ENDE DES NETZ-SELBSTLAUFS
hwdiag: ANGEHALTEN. Der Bildschirm bleibt so stehen.
```

---

## 4. DIE TASKLEISTE

### 4.1 Was NICHT die Ursache war — und das ist gemessen

Der Verdacht lautete: die Symboldateien fehlen im Abbild, und eine leere
Symbolliste lässt die Leiste verschwinden. **Beides ist nachgeprüft und
beides stimmt nicht.**

* **Die Symbole sind auf dem Abbild.** `tools/usbimg/build.sh` baut sie
  mit `tools/netview/icons.py` und liest das **fertige** Dateisystem mit
  `mkfs.py list` zurück; alle elf `/etc/netview/*` stehen in der
  Pflichtliste, und ein Bau ohne sie bricht ab. Vom gebauten Abbild
  gemessen: `taskbar: icons=4 marks=3 sys=1 dateien=8 kleinste=588`.
* **Eine leere Liste lässt die Leiste stehen.** Gegenprobe mit einem
  Abbild **ohne** `/etc/netview` und **ohne** `/lib/icons.ttf`
  (`tools/look/shot.sh nvicons=no icons=no`): die Leiste steht, malt
  zwei Fensterknöpfe, „Start", „kein Netz" und die Uhr —
  `taskbar: geom edge=0 x=0 y=772 w=1280 h=28 shown=1`,
  `taskbar: state n=2 paints=2`. Eine fehlende Bilddatei ist ein
  Aussehen, kein Ausfall.

### 4.2 Was die Ursache sein kann — und was dagegen getan ist

Die Zeile brach **mitten im Wort** ab (`taskbar: icons=` ohne die Zahl
dahinter, und `ulib.sayn(0)` druckt nachweislich `0`). Das heißt: das
Programm ist zwischen zwei `write` stehengeblieben oder gestorben —
**bevor** es sein Fenster gebaut hatte.

Und genau darin lag der Konstruktionsfehler: **das Programm hat zuerst
über sich berichtet und erst danach seine Leiste gebaut.** Damit hing
die Sichtbarkeit der Leiste am Gelingen ihrer eigenen Ausgabe — und die
geht auf dem Stick nicht in ein Kabel, sondern in ein **Terminalfenster**,
das jedes Oktett rastern muss.

Umgestellt: Fenster, Ebene, Aufteilung, ein **stilles erstes Malen** —
und erst wenn die Leiste auf dem Schirm steht, wird geredet. Die
gedruckten Zeilen sind dieselben und in derselben Folge, sie kommen nur
nach dem Bild. Dazu:

* **Eine Leiste, die sich wegen einer Ebene selbst schließt, ist keine.**
  Bekam sie `L_TOP` nicht, machte sie ihr Fenster zu und endete. Jetzt
  nimmt sie `L_NORMAL` und ist eben eine Leiste, die ein Fenster
  verdecken kann — immer noch besser als keine.
* **Eine neue, kurze Zeile, die auf ein Foto passt:**
  `taskbar: STEHT x=0 y=872 w=1600 h=28`. Sie wird gedruckt, **nachdem**
  zum ersten Mal gemalt wurde. Steht sie da, steht die Leiste.
* **Zwei Zahlen mehr im Symbolbericht:** `dateien=` (wie viele der acht
  Bilddateien sich öffnen ließen) und `kleinste=` (die kleinste Länge).
  `icons=0 dateien=0` heißt „das Abbild trägt sie nicht",
  `icons=0 dateien=8 kleinste=0` heißt „sie sind da und leer". Ohne
  diese zwei Zahlen ist das nicht zu unterscheiden.

**Ehrlich, und das gehört in diesen Bericht:** ob damit die Ursache
behoben ist oder nur ihre Wirkung, ist ohne Justins Rechner nicht zu
entscheiden. Was entschieden ist: **die Leiste steht auf dem Schirm,
bevor irgendetwas gedruckt wird**, und der nächste Lauf sagt in einer
Zeile, ob sie steht. Der Testablauf dafür steht in Abschnitt 7.

---

## 5. DER MAUSZEIGER

Der Fehler stand in achtzehn von Hand geschriebenen Bitmasken in
`kernel/wm.fi` (`cursor_row_of`, Form 0): `innen[11] = 0x0400` — **ein
einziger Bildpunkt** genau unter der breitesten Zeile — und
`innen[12..16]` mit je **zwei getrennten Blöcken**. Gemeint war der
klassische X11-Zeiger, dessen Schwanz sich in zwei Beine gabelt; in
Hexadezimalzahlen geschrieben sieht das aus wie ein Pfeil und auf dem
Schirm wie Bruchstücke.

**Der neue Pfeil ist nicht von Hand gerechnet.** In `tools/wm/zeiger.py`
steht eine Silhouette — je Zeile genau ein Bereich —, und die Füllung
ist ihre **Erosion** um einen Bildpunkt in den vier Richtungen; was
übrigbleibt, ist der Rand und ist damit überall genau einen Bildpunkt
breit. Derselbe Läufer liest die Masken aus dem Quelltext zurück, malt
sie als Bild und rechnet sechs Zusagen nach.

```
ALT (was Justin fotografiert hat)      NEU
  0 |.           |                      0 |.           |
  1 |..          |                      1 |..          |
  2 |.#.         |                      2 |.#.         |
  …                                     …
  9 |.########.  |                      9 |.########.  |
 10 |.#########. |                     10 |.#######..  |
 11 |.#..........|   <- Abriss         11 |.######.    |
 12 |..##.###.   |   <- zwei Bloecke   12 | .#####.    |
 13 |. .##.##.   |                     13 |  .####.    |
 14 |  .##.##.   |                     14 |   .###.    |
 15 |   .##.##.  |                     15 |   .###.    |
 16 |   .##.##.  |                     16 |   .###.    |
 17 |    ......  |                     17 |   .....    |

  ZEIGER: 7 Beanstandungen              ZEIGER: 6 Pruefungen, 0 Beanstandungen
```

Und weil eine Zusage über ein Bild ein Bild braucht: derselbe Zeiger,
**aus einem Bildschirmfoto eines laufenden Systems** herausgeschnitten
(1600x900, Schreibtisch, `wmhold`):

```
   |..           |
   |.#.          |
   |.##.         |
   |.###.        |
   |.####.       |
   |.#####.      |
   |.######.     |
   |.#######.    |
   |.########.   |
   |.#######..   |
   |.######.     |
   | .#####.     |
   |  .####.     |
   |   .###.     |
   |   .###.     |
   |   .###.     |
   |   .....     |
```

Die sechs Zusagen: (a) die Füllung ist **eine** zusammenhängende Fläche
(4er-Nachbarschaft), (b) jeder Füllpunkt hat oben/unten/links/rechts
Füllung oder Rand — nirgends den Hintergrund und nicht den Bildrand,
(c) keine Zeile mit zwei getrennten Blöcken, (d) kein allein stehender
Punkt, (e) Füllung und Rand überschneiden sich nicht, (f) die Spitze
sitzt auf dem Griffpunkt (0,0). Der **alte** Zeiger fällt mit sieben
Beanstandungen durch dieselbe Prüfung — die Gegenprobe ist gefahren.

---

## 6. DAS MENÜ DES STICKS

| # | Eintrag | wozu |
|---|---|---|
| 1 | Hardware-Diagnose (bleibt stehen) | fasst **nichts** an, hält vor jedem Treiber an. Neu am Ende: die **lesende** USB-Übersicht (`usb: regler=`, `besitz=BIOS/OS/frei`) |
| 2 | **USB-Diagnose: Regler übernehmen und jeden Anschluss zeigen** | **neu.** Übernimmt, setzt zurück, schaltet Strom, zählt auf, prüft die Übernahme (`usbleg`) und hält an |
| 3 | Diagnose und danach der Schreibtisch | jetzt mit `usb hidgen` |
| 4 | nur der Schreibtisch (deutsch) | jetzt mit `usb hidgen` |
| 5 | Vektoreinheit prüfen | unverändert |
| 6 | Kommandozeile mit Netz | jetzt mit `usb hidgen` — sonst kann dort niemand tippen |
| 7 | **Netz-Selbstlauf ohne Tastatur** | **neu.** `dhcp`, `resolv.conf`, `host`, `fetch`, `ota suchen`, dann steht der Schirm |
| 8/9 | Schreibtisch auf WQHD / 4K | jetzt mit `usb hidgen` |

---

## 6a. DIE ABNAHME

| Läufer | diese Runde | Referenzbaum `main` 4609ec9 |
|---|---|---|
| `tools/k17/run.sh` (USB) | **158 bestanden, 0 gefallen** | 157 + 1 Zusage dieser Runde |
| `tools/hid/run.sh` | **57 bestanden, 0 gefallen** | 57/0 |
| `tools/wm/run.sh` | **104 bestanden, 0 gefallen** | **103/0** — der Unterschied ist genau die neue Zeigerprüfung |
| `tools/usbimg/run.sh` | **48 bestanden, 0 gescheitert** | 48/0 |
| `tools/desktop/run.sh` | 20 rot | **20 rot, Zeile für Zeile dieselben** |
| `tools/netview/run.sh` | 1 rot (siehe unten) | — |

**Zwei Zusagen sind unterwegs gefallen, und beide hatten recht.** Das
gehört in diesen Bericht, weil beide Fehler von dieser Runde waren:

1. `tools/hid/run.sh`: *„GEGENPROBE nurboot: usb-tablet wird wieder
   abgelehnt: erwartet 0, bekommen 0\n0"* — auf einer Maschine mit
   **einem** Regler wurde derselbe zweimal aufgesetzt und die Zeile
   `usb: devices=` zweimal gedruckt. Behoben (`anzahl > 1`).
2. `tools/k17/run.sh`: *„Anstecken im Betrieb im Regellauf (darf nicht
   anschlagen): 3"* — die neuen **echten** Wartezeiten geben dem
   Zeitgeber Gelegenheit, `unplug_check` zu rufen, während der Baum
   selbst aufzählt; der zählte Tastatur, Maus und Stick als „im Betrieb
   angesteckt". Behoben mit einem Schloss (`S_BUSY`) über der
   Aufzählung.

**Die 20 roten Zusagen von `tools/desktop/run.sh` gehören dieser Runde
NICHT.** Sie sind auf `main` 4609ec9 in einem eigenen Arbeitsbaum
nachgefahren worden und dort **dieselben, in derselben Reihenfolge, mit
denselben Zahlen** — der Läufer rechnet ab Abschnitt 2 mit einem
800x600-Schirm und bekommt 1280x800 (`the bar is at (0, 772, 1280, 28),
expected (0, 572, 800, 28)`). Deshalb fällt in Abschnitt 5 auch das
Ziehen: der Mausklick auf y=586 landet auf dem Schreibtisch statt auf
der Leiste.

**Der eine rote Punkt in `tools/netview/run.sh`** heißt *„faking: the
state icon went missing: falsch 40 von 82"*. Er ist **nachgeprüft und
kein Zeichenfehler**: dasselbe Bildschirmfoto, an derselben Stelle,
gegen alle vier Zustandsbilder gehalten —

```
state-online       falsch 40 von 82
state-noroute      ok 68 von 68 gleich      <-- das steht im Bild
state-noip         falsch 10 von 52
state-nocarrier    falsch 31 von 62
```

Die Leiste hat ein **vollständiges, richtiges** Symbol gemalt, nämlich
`noroute` — den Zustand, den sie in dem Augenblick kannte. Das
Protokoll sagt in seiner **letzten** Zeile `s=3` (online), weil das
Netz nach dem Foto hochkam. Das ist ein Wettlauf zwischen dem
Aufnehmen des Bildes und dem letzten Neuzeichnen, und er steckt im
Läufer, nicht im Programm.

---

## 6b. DAS AUSGELIEFERTE ABBILD

```
/srv/store/abbilder/osum-usb.img          123 731 968 Oktette
sha256  a37098b983784875e7e484a329d496ba63d7654c700d98800c2e6082c37e34c0
```

Selbst gemessen an der ausgelieferten Datei, nicht an der gebauten; die
Prüfsumme steht daneben in `osum-usb.img.sha256`. Ein zweiter Baulauf
aus demselben Baum gibt eine **andere** Prüfsumme — `mkfs.vfat` schreibt
eine Datenträgernummer aus der Uhr in die EFI-Partition. Wer eine
bestimmte Datei meint, meint ihren SHA.

Auf den Stick:

```
sudo dd if=osum-usb.img of=/dev/sdX bs=4M conv=fsync status=progress
```

---

## 7. DER TESTABLAUF FÜR JUSTIN — UND DIE EINE FRAGE

Wenn nach diesem Abbild **immer noch keine Eingabe** ankommt, dann
entscheidet **Menüeintrag 2** die Sache, und zwar in drei Zeilen. Ein
Foto genügt.

1. **Menüeintrag 2 starten** („USB-Diagnose"). Warten, bis
   `ANGEHALTEN` steht. Fotografieren.
2. Auf dem Foto stehen je Regler drei Dinge:
   * `legsup=… vor=… bios=1 os=0 nach=… bios=0 os=1 nach NNms` —
     **bios geht von 1 auf 0**: die Übernahme hat funktioniert.
     Bleibt `bios=1` und steht `BIOS-Bit von Hand geloescht` daneben,
     hat die Firmware nicht losgelassen.
   * `strom=N/M` — steht dort `0/M`, liegt an keiner Buchse Spannung,
     und **das** erklärt eine Maus, die nicht leuchtet.
   * `p05 psc=… pp=1 ccs=1 ped=1` — an diesem Anschluss steckt ein
     Gerät und es antwortet. Steht `ccs=0` überall, ist an keiner
     erkannten Buchse etwas angesteckt.
3. Darunter steht `usb: devices=N kbd=… mouse=…` und je Gerät eine
   Zeile `usb: port=… class=03:01:01 driver=kbd`.

**Die eine Frage, falls es dann immer noch nicht geht:** Steht auf dem
Foto bei **beiden** Reglern `verbunden=0`, obwohl Tastatur und Maus
gesteckt sind — dann hängen sie **hinter einem Nabenchip (USB-Hub)**,
und dafür hat dieses System keinen Treiber. Das wäre in einer Zeile
sichtbar: der Regler meldet ein Gerät mit `class=09:…` und
`driver=none`. In dem Fall: Tastatur und Maus **direkt** in eine
Buchse am Gehäuse stecken, nicht über einen Hub, nicht über den
Monitor, nicht über die Tastatur-Durchschleife.

Für die Taskleiste: im Terminalfenster muss jetzt **vor** allen anderen
`taskbar:`-Zeilen

```
taskbar: STEHT x=0 y=<Höhe-28> w=<Breite> h=28
```

stehen. Steht sie da und ist unten trotzdem nichts zu sehen, ist es ein
Zeichenfehler und kein Startfehler — dann bitte diese Zeile
fotografieren.
