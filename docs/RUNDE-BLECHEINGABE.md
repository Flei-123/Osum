# RUNDE BLECHEINGABE — was der Kern sieht, und ob er ueberhaupt noch lebt

Ausgangslage: Justins Brett (Ryzen-Klasse, RTX 3060, **keine** eingebaute
Grafik) zeigt seit der Vorrunde den vollstaendigen Schreibtisch —
Terminalfenster mit dem ganzen Protokoll, Taskleiste mit Startknopf,
`169.254.10.1`, „kein Akku", Uhr. Und dann steht alles.

Der entscheidende neue Befund kam von Justin selbst: **die Uhr steht.**
Um 14:51 zeigte sie 14:50, um 14:54 zeigte sie immer noch 14:50. Das ist
kein „einmal gezeichnet und die Uhr laeuft" — das Bild ist seit dem
ersten Vollbild **eingefroren**.

## Was gemessen ist, und was nicht

### GEMESSEN: die Messtafel funktioniert in QEMU, mit Schreibtisch

Das veroeffentlichte Abbild (`39e3d10d`) wurde ueber den Lader gestartet,
3440x1440, Menueeintrag 1 (WC) **und** Menueeintrag 2 (`fbuc`), je ein
Bildschirmfoto 75 s nach dem Start:

| | y=100 | y=300 | y=470 | y=800 |
|---|---|---|---|---|
| Eintrag 1 (WC) | 100 % schwarz | 99 % | 0 % | 0 % |
| Eintrag 2 (`fbuc`) | 100 % schwarz | 99 % | 0 % | 0 % |

Der schwarze Balken der Tafel steht in **beiden** Faellen, mit laufendem
Schreibtisch. Der Fensterserver malt sie also **nicht** zu. Dass sie auf
Justins Foto fehlt, heisst damit: **`tafel_tick` lief dort nicht mehr** —
und `tafel_tick` haengt am Zeitgeberbehandler.

### GEMESSEN: der Zeitgeber schlaegt beim Start, mit abgeschaltetem PIC

`hw.stage` (kmain.fi:328) schaltet den alten Regler ab (`apic.pic_off`),
und **danach** wartet `kmain.ticks` (kmain.fi:~425) auf 20 Marken mit
`hlt`. Justins Brett kommt bis zum Schreibtisch — also sind diese 20
Marken angekommen, mit bereits abgeschaltetem PIC. **Ein von Anfang an
toter LAPIC-Zeitgeber ist damit ausgeschlossen.** Er muss spaeter
stehengeblieben sein oder der Behandler kehrt nicht mehr zurueck.

### UNGEMESSEN: welcher Menueeintrag bei Justin lief

Das laesst sich aus dem Foto **nicht** entscheiden, und ich behaupte es
deshalb nicht. `default_entry: 1` und `timeout: 20` sprechen fuer den
ersten Eintrag (WC) — mehr als ein Indiz ist das nicht. Ab dieser
Fassung steht die Abbildungsart in Zeile 9 der Tafel (`FB WC/WB/UC`) und
im USB-Bericht im Terminalfenster; damit entscheidet es das naechste
Foto.

### UNGEMESSEN: ob die Abbildungsart die Ursache der Vorrunde war

Zwei Aenderungen gingen im selben Abbild aus (Write-Combining **und**
die Zeitgrenze in `serial.put`). Welche davon das Bild zurueckgebracht
hat, trennt das Foto nicht.

## Der Herzschlag: zwei Felder, zwei getrennte Wege

`kernel/fb.fi`, `fb.herz` — am rechten Bildrand, senkrecht mittig, zwei
Quadrate zu 56x56 Bildpunkten. Beide werden **aus dem
Zeitgeberbehandler** umgelegt (`gfx.herz_tick`, viermal je Sekunde), an
Fensterserver, Schreibtischschleife und Ring 3 vorbei.

* **links, gruen** — ueber den **normalen** Weg: Zweitpuffer, Schmutz,
  `flush`. Genau der Weg, den Taskleiste und Messtafel nehmen.
* **rechts, gelb** — **direkt** in das Fenster der Karte (`S_ADDR`), am
  Zweitpuffer und am `flush` vorbei, mit `sfence` (und mit `fbflush`
  zusaetzlich `wbinvd`) dahinter.

| was Justin sieht | was es heisst |
|---|---|
| beide blinken | Zeitgeber laeuft, Bildweg in Ordnung — der Fehler liegt darueber |
| nur rechts blinkt | Zeitgeber laeuft, der normale Bildweg kommt nicht an → Zwischenspeicher |
| keines blinkt | Zeitgeber schlaegt nicht mehr, oder der Behandler kehrt nicht zurueck |
| nur links blinkt | die direkte Abbildung stimmt nicht (Streifenbetrieb) |

Dazu als dritter, vom Bild voellig unabhaengiger Kanal die
**Rollen-Lampe der Tastatur**, zweimal je Sekunde umgelegt
(`usb.herz_leds`). Sie braucht weder Rahmenpuffer noch serielle Leitung.

## SET_REPORT — der Kern konnte eine Lampe nicht setzen

`grep 'SET_REPORT|LED|numlock' kernel/` hatte **null Treffer**. Es gab
`SET_PROTOCOL` und `SET_IDLE`, aber keinen Ausgabebericht. Eine Tastatur
schaltet ihre Lampen nicht selbst.

Jetzt: `usb.set_leds` — Steuertransfer `0x21` / `0x09`, Wert `(2<<8)|0`,
Ziel die Schnittstellennummer, ein Oktett Bitmaske (Bit 0 Num, 1 Caps,
2 Rollen). Der **Zustand** liegt in `kernel/kbd.fi` (`locks`), der einen
Stelle, durch die PS/2 und USB beide gehen — zwei Zustaende waeren zwei
Wahrheiten. `usb.led_service` schickt ihn nach jedem Bericht hinaus.

**Justins Pruefstein:** Num-Lock druecken → Lampe wechselt = die Kette
Tastatur → Kern → Tastatur steht komplett.

## Der Hub-Treiber

`grep -i hub kernel/usb.fi kernel/xhci.fi` hatte **null Treffer**. Der
Kern sah ausschliesslich Geraete an einem **Wurzelanschluss**. Auf einem
heutigen Brett haengen die hinteren Buchsen regelmaessig an internen
Hubs, und eine Spieletastatur bringt oft ihren eigenen mit.

Neu in `kernel/usb.fi`: `hub_desc` (Deskriptor 0x29/0x2A, Anschlusszahl,
`bPwrOn2PwrGood`), `hub_slot_update` (Hub-Fahne und Anschlusszahl im
Steckplatzzusammenhang, ueber `Configure Endpoint` — `Evaluate Context`
kann das laut xHCI 1.2, 4.6.7 nicht), `hub_scan` (Port Power, warten,
Zustand lesen, Port Reset, Geschwindigkeit ablesen) und `attach_at` mit
**Wegweiser** (Route String, ein Nibble je Etage) und **Uebersetzer**
(TT Hub Slot ID / TT Port Number fuer langsame Geraete hinter einem
schnellen Hub).

**Gemessen**, QEMU, Tastatur und Maus hinter einem `usb-hub`:

```
usb: hub p=5 ports=8 slot=1
usb: port=5 route=0 speed=1 slot=1 id=0409:55aa class=09:00:00 driver=hub
usb: port=5 route=1 speed=1 slot=2 id=0627:0001 class=03:01:01 driver=kbd
usb: port=5 route=2 speed=1 slot=3 id=0627:0001 class=03:01:02 driver=mouse
```

Vor dieser Runde fand derselbe Aufbau **nichts** — der Hub wurde
abgelehnt und alles dahinter war unerreichbar.

## Die Fundliste — „devices=0" ist keine Auskunft

`attach` rief `drop_dev`, sobald `configure` fehlschlug, und `configure`
schlaegt fehl, sobald **keine** Schnittstelle passt. Ein Hub, eine
unbekannte Tastatur, ein Kartenleser: alle spurlos weg.

Die Fundliste (`FUND_OFF`, 10 Eintraege) haelt **jedes** Geraet fest,
das ueberhaupt geantwortet hat, und wird nie geleert. Sie steht im
**Terminalfenster** — der einzigen Flaeche, von der bewiesen ist, dass
sie bei Justin ankommt:

```
USB  hc=1 ports=8 dev=3 fund=3 hubs=1 hbprt=8 fails=0
 P1 ccs=1 en=1 sp=2 psc=...
 D0 @5.0 sp=1 id=0409.55aa dev=09:00:00 if=09:00:00 n=1 f=7 drv=5
 D1 @5.1 sp=1 id=0627.0001 dev=00:00:00 if=03:01:01 n=1 f=15 drv=1
```

`f=` sind die Stufen: 1 Adresse, 2 Deskriptor, 4 `SET_CONFIGURATION`
quittiert, 8 ein Treiber hat es genommen. **`f=7` ohne 8** heisst: der
Kern hat mit dem Geraet geredet und konnte nichts damit anfangen —
steht dort `if=09:...`, ist es ein Hub.

## Der Fehler, den ich dabei gefunden habe

`kernel/arch/x86_64/trap.fi:265` rief viermal je Sekunde
`usb.unplug_check` **aus dem Zeitgeberbehandler**, mit abgeschalteten
Unterbrechungen. `unplug_check` ruft `attach`, `attach` ruft
`xhci.port_reset`, und darin stehen `udelay(100000)`, eine Warteschleife
von bis zu 500 ms und noch einmal `udelay(20000)`.

Das sind **Zehntelsekunden bis Sekunden mit abgeschalteten
Unterbrechungen**. In dieser Zeit schlaegt der Zeitgeber nicht, niemand
weckt einen Schlaefer, die Uhr steht und kein Bild entsteht. Der
Kommentar darueber hat es selbst zugegeben („EHRLICH GESAGT: eine
Aufzaehlung im Zeitgeberbehandler ist nicht schoen").

Jetzt liest der Zeitgeber nur noch je Anschluss **ein** Register
(`usb.port_watch`) und merkt sich, wo sich etwas geaendert hat. Die
Arbeit macht `usb.hotplug_work` in der Schreibtischschleife, in
Aufgabenkontext, wo sie dauern darf.

**Das ist ein echter Fehler und er ist behoben. Ob es Justins Fehler
war, ist damit nicht bewiesen** — das entscheiden die zwei
Herzschlagfelder.

## Schlaf an einem toten Zeitgeber

`sched.sleep_ticks` legt eine Aufgabe hin; geweckt wird nur in
`sched.on_tick`, und das kommt nur aus dem Zeitgeber. Steht der, schlafen
`wait_wm` und die Taskleiste (`ulib.sleep_ms(25)`) **fuer immer**.

`sched.timer_tot` misst jetzt am Zyklenzaehler: bewegt sich die
Markenzahl 300 ms lang nicht, wird **nicht** geschlafen — die Aufgabe
gibt den Prozessor einmal ab und kehrt zurueck. Die Zahl der abgelehnten
Schlaefe steht als `TOT` in Zeile 10 der Tafel; ist sie groesser als
null, **stand der Zeitgeber wirklich** — gemessen, nicht vermutet.

## Zeitgeber-Lebendigkeit

`apic.init` misst jetzt nach, ob der Zaehler des oertlichen Zeitgebers
in einem am Zyklenzaehler abgelesenen Fenster wirklich laeuft
(`apic.timer_running`). Tut er es nicht, gibt `init` false zurueck — und
`hw.stage` laesst den **alten Regler an**, genau so, wie es der Kommentar
ueber `init` seit Runde 59 verspricht. Und `kmain.ticks` wartet nicht
mehr ohne Ausweg: nach drei Sekunden ohne Marke geht es mit einer
lesbaren Zeile weiter, statt schwarz stehenzubleiben.

## Die zwei neuen Menueeintraege

| # | Eintrag | Kommandozeile (Auszug) |
|---|---|---|
| 1 | Schreibtisch | `gfx wm wig desk wmshell wmdauer tafel herz usb hidgen ...` |
| 2 | Schreibtisch (Rahmenpuffer uncached, Test) | `gfx fbuc ...` |
| 3 | Schreibtisch (Zwischenspeicher nach jedem Bild leeren, Test) | `gfx fbflush ...` |
| 4 | Desktop (English) | `... lang=en` |
| 5 | Kommandozeile mit Netz | `modfs osum vfs usb hidgen nic ... console=ttyS0` |

`fbuc` aendert die **Abbildung**, `fbflush` laesst sie stehen und raeumt
nach jedem Blit den Zwischenspeicher mit `wbinvd` hinaus. Zwei
verschiedene Mittel gegen dieselbe Ursache — hilft eines und das andere
nicht, war es der Zwischenspeicher.

## Neue Woerter auf der Kommandozeile

* `herz` — die zwei Blinkfelder und die Lampe der Tastatur.
* `fbflush` — `wbinvd` nach jedem Blit.
* `nohub` — den Hub-Treiber stilllegen (Gegenprobe).
* `usbsafe` — der Zeitgeber sieht gar nicht mehr nach Anschluessen.

## Die A/B-Gegenprobe zum Hub-Treiber

Derselbe QEMU-Aufbau (Tastatur und Maus hinter einem `usb-hub`), einmal
mit und einmal ohne `nohub` — also der Zustand des Baums **vor** dieser
Runde:

| | Bericht |
|---|---|
| **mit** Hub-Treiber | `USB hc=1 ports=8 dev=3 fund=3 hubs=1 hbprt=8 fails=0` |
| **ohne** (`nohub`) | `USB hc=1 ports=8 dev=0 fund=1 hubs=0 hbprt=0 fails=0` |

Ohne Hub-Treiber: **`dev=0`**. Der Hub steht als einziger Eintrag da
(`D0 @5.0 id=0409.55AA dev=09:00:00 if=09:00:00 n=1 f=3 drv=0` — Adresse
und Deskriptor geglueckt, kein `SET_CONFIGURATION`, kein Treiber), und
Tastatur und Maus dahinter sind **vollstaendig unsichtbar**.

Das ist Justins Symptom, Wort fuer Wort: „Maus und Tastatur gehen nicht,
es leuchtet auch nicht mehr."

## Am fertigen Abbild belegt

`/srv/store/abbilder/orientos-usb.img`, ueber den Lader (OVMF), zwei
xHCI-Regler, 3440x1440:

```
USB  hc=2 ports=8 dev=2 fund=3 hubs=0 hbprt=0 fails=0
 P5 ccs=1 en=1 sp=3 psc=00000E03
 D0 @1.0 sp=4 id=46F4.0001 dev=00:00:00 if=08:06:50 n=1 f=15 drv=3
 D1 @5.0 sp=3 id=0627.0001 dev=00:00:00 if=03:01:01 n=1 f=15 drv=1
 D2 @6.0 sp=3 id=0627.0001 dev=00:00:00 if=03:01:02 n=1 f=15 drv=2
tafel: 9 KABEL  LSR 60 SCR A5 VERW 0 AUS 0 FB WC
tafel: 10 HERZ  HZ 5789 TOT 0 LED 114 HELL 116
tafel: 11 USB   DEV 2 FUND 3 HUB 0 KBD 0 FAIL 0
```

SHA-256 `7fdb350f43f004a3afba59954c6fb804992e3a74e8328553b2e497f4f4cada49`,
Commit `6fa8996`. Regression `tools/wm/run.sh`: **104 passed, 0 failed**.
`tools/kernel/memmap.py`: 91 Bereiche, **0 Kollisionen**.
