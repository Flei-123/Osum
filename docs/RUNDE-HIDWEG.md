<!-- SPDX-License-Identifier: GPL-2.0-only -->
# RUNDE HIDWEG — der Treiber war in Ordnung. Es rief ihn nur niemand.

**03.09.2026**, Zweig `hidweg`, auf `main` nach Runde BLECH-HID.
Abnahme: `bash tools/hidweg/run.sh` → **31 gehalten, 0 gefallen**.

---

## 0. WAS JUSTIN GEMESSEN HAT, UND WARUM DAS ALLES ÄNDERT

Justin hat das Abbild `a37098b9` auf seinem AMD-Brett gestartet und die
**USB-Diagnose (Menü 2)** fotografiert. Das steht darauf:

```
usbleg: fall 0 … bios=0 os=1 ms=1000 hart=1 OK
usbleg: fall 1 … bios=0 os=1 ms=0    hart=0 OK
usbleg: gut=2 schlecht=0
usb: xhci slots=64 ports=8 ctx=64 irq=1 hc=1
usb: port=3 speed=1 slot=1 id=046d:c08b class=03:01:02 driver=mouse
usb: port=4 speed=1 slot=2 id=046d:c336 class=03:01:01 driver=kbd
usb: hc1 bdf=0x0c03 id=1022:149c … strom=8/8 verbunden=2 frei=2
usb: devices=2 kbd=1 mouse=1 msc=0 enums=4 fails=0 events=36 irqs=23
```

Übernahme, Anschlussstrom, Zurücksetzen, Aufzählung, Bindung,
**Meldung** — der ganze Weg, um den Runde BLECH-HID gekämpft hat, steht
grün auf echtem Silizium. Und im Schreibtisch bewegte sich der Zeiger
trotzdem nicht.

**Damit war klar, dass der Fehler NICHT im USB-Baum liegt.** Diese Runde
hat den Weg von dort nach oben verfolgt und **drei** Fehler gefunden,
von denen jeder einzelne für sich schon „keine Eingabe" bedeutet
hätte. Alle drei liegen **über** dem Treiber.

---

## 1. DER SCHREIBTISCH HAT NACH 9,4 SEKUNDEN AUFGEHÖRT

Das ist der Sperrpunkt, und er ist eine Zahl.

In `kernel/kgui.fi` wartete `wait_wm` auf die Shell im Terminalfenster:

```
    var rounds: u64 = 0
    while rounds < 20000 {
        …
        wm.poll(state)
        wm.compose(state)
        sched.sleep_ticks(state, 1)
        rounds = rounds + 1
    }
    return 0xFFFFFFFFFFFFFFFE
```

**Diese Schleife IST der Schreibtisch.** `wm.poll` holt den Zeiger ab,
`wm.compose` setzt das Bild zusammen. Läuft sie nicht, bewegt sich
nichts — egal wie fehlerfrei alles darunter ist.

Die Grenze von 20000 Runden war als Notausgang für die **Testläufer**
gedacht: ein Läufer, der ewig auf eine Shell wartet, ist kein Läufer.
Auf dem Stick steht aber auf **jedem** Schreibtisch-Eintrag `nosched`,
und dann kostet eine Runde keine Zeitmarke, sondern nur einen Durchgang.

**Gemessen, mit genau der Kommandozeile von Menü 4:**

```
Schreibtisch lebte 9.4 s (Start bis wm: sh exit)
```

Danach kehrte `surface` zurück, der Kern lief durch `smp`, `hv`,
Messungen, `usb.report` — bis `kernel: done`. Der Bildschirm behielt das
letzte zusammengesetzte Bild. **Von außen sieht das aus wie ein kaputter
Eingabetreiber:** das Bild ist da, der Zeiger ist da, Tastatur und Maus
haben Strom — und nichts reagiert. Genau Justins Beschreibung, Wort für
Wort.

**Behoben:** neues Kernwort **`wmdauer`** (`kstate.M_WMDAUER`). Damit hat
die Schleife keine Rundengrenze mehr, und eine beendete Shell schließt
den Schreibtisch nicht mehr, sondern wird — mit einer Sekunde Abstand,
damit daraus kein Prozessgenerator wird — **neu gestartet**. Das Wort
steht jetzt auf allen vier Schreibtisch-Einträgen des Abbilds
(Menü 3, 4, 8, 9).

**Ohne das Wort bleibt alles, wie es war.** `tools/desktop/run.sh`,
`tools/wm/run.sh`, `tools/look/`, `tools/netview/` messen denselben
Kern, den sie vorher gemessen haben.

---

## 2. DIE UNTERBRECHUNGEN WAREN AUS — SEIT DEM AUSFLUG NACH RING 3

Der zweite Fehler ist älter und schlimmer, und er wäre ohne den
Eingabepuls (Abschnitt 4) nicht zu finden gewesen.

Der Puls zeigte im Schreibtisch:

```
eingabe: ber=6 irq=37 ev=40 sts=8 iman=2 mk=393 if=0 …
eingabe: ber=13 irq=37 ev=47 sts=8 iman=2 mk=393 if=0 …
```

Drei Zahlen, und zusammen sagen sie alles:

* **`if=0`** — im Schreibtisch sind die Unterbrechungen abgeschaltet.
* **`mk=393` steht still** — der Zeitgeber schlägt nicht mehr. Das ist
  nicht nur USB; das ist **alles**.
* **`sts=8`** — im USBSTS des Reglers steht `EINT`, unquittiert: der
  Regler HAT gemeldet, und niemand hat es abgeholt.

Eine Stufenmessung in `kmain` (`if=` nach jeder Stufe) fand die Stelle:

```
MKDBG  9 if=1 mk=159      nach smp.stage
MKDBG 10 if=1 mk=159      nach hv.stage
MKDBG 11 if=0 mk=160      nach ring3          <-- hier
```

**`ring3(state)`, der Ausflug nach Ring 3 aus Runde 59**, kehrt mit
abgeschalteten Unterbrechungen zurück. Der Weg hinaus geht über
`sysretq` mit `r11 = 0x202`, also **mit** IF. Der Weg zurück geht
ausdrücklich **nicht** über `sysret`, sondern über `leave_user` —
Kernstapel wiederherstellen, `ret`. Das ist ein Rücksprung **aus einem
`syscall` heraus**, und `syscall` löscht IF über `IA32_FMASK`. Auf
diesem Weg gibt es keine einzige Stelle, an der IF je wieder gesetzt
würde.

Und `ps2m.init`, das eine Stufe später läuft und ein `sti` enthält, half
nicht — es stellt nur wieder her, was es **vorfand**:

```
    let flags: u64 = asm("pushfq\npop rax\ncli", out("rax"))
    let r: bool = init_inner(state, w, h)
    if (flags & 0x200) != 0 { asm("sti") }
```

Es fand null vor.

**Behoben** in `kernel/arch/x86_64/user.fi`: der Ausflug rettet die
Flaggen vor `enter_user` und gibt zurück, was er vorfand — nicht mehr
und nicht weniger. Drei Zeilen.

**Nachher, dieselbe Kommandozeile, dieselben Monitorbefehle:**

| | `if` | `mk` (Marken) | `irq` | `sts` |
|---|---|---|---|---|
| vorher | **0** | **393 → 393** | **37 → 37** | **8** (unquittiert) |
| nachher | **1** | 427 → 3922 | 40 → 47 | 0 |

---

## 3. UND NIEMAND HAT NACHGEFRAGT

Der dritte Fehler ist der, der die beiden anderen so lange verdeckt hat:
**im Schreibtisch rief niemand `usb.poll`.** Der ganze Eingabeweg hing
an der Meldung. Ein Regler, dessen Meldung nicht ankommt, ist damit
stumm — und genau so einen hat Justin: `hc0` meldete
`events=50 irqs=0`, fünfzig fertige Übertragungen und keine einzige
Meldung.

`usb.poll` steht jetzt in der Schleife. Es liest ein 32-Bit-Wort des
Ereignisrings; wenn die Meldung läuft, findet es nichts mehr vor.

**Und das ist gemessen, nicht behauptet.** Die Gegenprobe `usbnoirq`
lässt den Vektor maskiert:

```
GEGENPROBE zur Meldung: mit usbnoirq traegt die Abfrage
  ok   der Vektor bleibt maskiert -- irq steht still: 0
  ok   und die Maus kommt TROTZDEM an (bew): 3 > 0
  ok   und der Klick auch (kl): 1 > 0
```

---

## 4. DER EINGABEPULS — GEBAUT FÜR EIN FOTO

Justin steht vor dem Rechner mit einem Mobiltelefon. Er kann die
serielle Leitung nicht mitlesen. Also schreibt der Kern alle fünf
Sekunden **eine Zeile ins Terminalfenster** (`wm.term_write`) und
zusätzlich auf die Leitung:

```
eingabe: ber=13 irq=47 ev=47 sts=0 iman=2 mk=3914 if=1 ta=3 lo=3 bew=5 pk=7 xy=799,539 wm=8 kl=1 sh=8
```

Sie beantwortet „wo bleibt mein Tastendruck" **von unten nach oben**:

| Feld | was es sagt |
|---|---|
| `ber` | HID-Berichte, die der USB-Baum entgegengenommen hat |
| `irq` / `ev` | Meldungen des xHCI / Einträge im Ereignisring |
| `sts` / `iman` | USBSTS und IMAN, **live gelesen** |
| `mk` | Zeitmarken — steht die Zahl still, sind die Unterbrechungen aus |
| `if` | das Unterbrechungsflag des Prozessors |
| `ta` / `lo` | Tasten gedrückt / losgelassen (`hidin`) |
| `bew` | Mausbewegungen aus HID-Berichten |
| `pk` / `xy` | Pakete beim Zeiger und seine Stelle |
| `wm` / `kl` | vom Fensterserver abgeholt / Klicks angekommen |
| `sh` | wie oft die Shell im Fenster neu gestartet wurde |

**Steht `ber=0`, kommt gar nichts an. Steht `ber` hoch und `pk=0`, hängt
es zwischen Bericht und Zeiger. Steht `pk` hoch und `wm=0`, hängt es im
Fensterserver.** Genau diese drei Fragen hat diese Runde gekostet.

Der Puls hängt an den **Marken** und nicht an Runden. Die Rundenzahl ist
nur der Rückfall für den Fall, dass die Marken **stehen** — und dann ist
der Puls das Wichtigste auf dem Schirm. (Die erste Fassung zählte immer
Runden und schrieb dem Menschen sein Terminalfenster in vierzig
Sekunden **238-mal** voll. Das ist keine Diagnose, das ist Rauschen.)

---

## 5. WAS SONST NOCH FALSCH WAR

### 5.1 `driver=none` war eine Lüge des Berichts

Justins Foto zeigte:

```
usb: port=10 speed=1 slot=3 id=0951:16df class=03:00:00 driver=none
hidrep: dev=1 ok=1 err=0 felder=15 rids=2 hasid=1 top=0xc0001 art=0 …
```

Zwei Zeilen, die sich widersprechen: der Zerleger hat die Beschreibung
sauber gelesen, der Bericht sagt „kein Treiber". Der Bericht hatte
unrecht, und zwar zweifach:

* Die Zeile stand **vor** `bind`. Darin stand also, was `driver_for`
  aus der Klasse **geraten** hatte, nicht, was der Baum daraus gemacht
  hat.
* `drv_name` kannte `DRV_HIDGEN` nicht und druckte den Rückfall.

Behoben: der Bericht steht jetzt **hinter** `bind` (und am Stück, weil
`bind` selbst druckt), und `hidgen` hat einen Namen.

### 5.2 Welche Schnittstelle eines Geräts genommen wird

Eine Spieletastatur bringt regelmäßig drei mit: eine ohne
Boot-Protokoll mit allen Tasten gleichzeitig, eine Boot-Tastatur, und
eine Verbrauchersteuerung für die Medientasten. Welche zuerst im
Konfigurationsdeskriptor steht, entscheidet der Hersteller.

`parse` nahm die **erste**, die durch `wanted` kam. Bei `0951:16df` war
das eine mit `top=0xc0001` — einer **Verbrauchersteuerung**. Das Gerät
lief und meldete Lautstärketasten statt Buchstaben.

Jetzt wird zweimal gelesen: der erste Durchgang sucht den besten Rang
(Boot-Tastatur 4 > Boot-Maus 3 > Massenspeicher 2 > HID ohne Boot 1),
der zweite nimmt die erste Schnittstelle mit genau diesem Rang.

**QEMU hat kein zusammengesetztes HID-Gerät** — `-device usb-kbd` hat
genau eine Schnittstelle. Die Auswahl wäre damit überhaupt nicht zu
messen. Also wird der Konfigurationsdeskriptor im Kern **gebaut**,
Oktett für Oktett, Verbrauchersteuerung zuerst, Boot-Tastatur danach,
und `usb.rangtest` prüft sechs Zusagen: den Rang, die
Schnittstellennummer (1, nicht 0), die Beschreibungslänge (63, nicht
52) und den Endpunkt (0x82 → DCI 5).

```
usb: rang ok=6 / 6
```

### 5.3 `hc0` meldete nie — MSI fehlte ganz

`events=50 irqs=0`. Dieser Treiber kannte **MSI-X** und den Stift durch
den I/O-APIC. Dazwischen fehlte **MSI** — die ältere Nachrichtenform,
die viele Chipsatz-xHCI können und MSI-X nicht. Der Stift half nicht:
`intx_arm` liest die Anschlussleitung aus dem PCI-Kopf und gibt auf,
wenn dort 0 oder etwas über 23 steht — und genau das steht auf einem
Brett, das über MSI meldet.

`msi_arm` ist dazugekommen (Adresse und Datum im Kopf, 64-Bit-Fall
beachtet, genau eine Nachricht bestellt, INTx abgeschaltet), und **was
genommen wurde, steht jetzt im Bericht**:

```
usb: hc0 melde=msi-x strom=8/8 verbunden=1 frei=1
usb: hc1 melde=msi-x strom=8/8 verbunden=2 frei=2
```

`irqs=0` ohne diese Angabe ist nicht zu deuten: ein Stift, den die
Firmware nicht eingetragen hat, sieht genauso aus wie eine Nachricht,
die nie eingerichtet wurde.

### 5.4 Der Anschlag des Zeigers war 1024×768

In `kmain.usb_stage` standen zwei feste Zahlen:
`gfx.mouse_adopt(state, 1024, 768)`. Auf Justins Ultrabreitbild wäre der
Zeiger damit in die linke obere Ecke eingesperrt. `ps2m.init` setzt die
richtigen Grenzen später noch einmal — **aber nur, wenn es läuft**, und
auf einem Brett ohne 8042 kommt es gar nicht so weit. Genau so ein Brett
ist Justins. Jetzt kommt der Anschlag aus `gfx.width`/`gfx.height`.

---

## 6. DIE ABNAHME

`bash tools/hidweg/run.sh` — **31 gehalten, 0 gefallen**, unter KVM.

```
== 2. DIE GEGENPROBE: ohne wmdauer hoert der Schreibtisch auf ==
  ok   ohne wmdauer HOERT der Schreibtisch auf (wm: sh exit=)
  ok   und der Kern laeuft danach durch bis zum Ende: 21
  ok   der Kern ist wirklich fertig -- das Bild ist ein Standbild
       (Lebensdauer bis zum Aufgeben: 12 s)

== 3. MIT wmdauer laeuft er weiter, und die Meldungen kommen an ==
  ok   mit wmdauer gibt der Schreibtisch NICHT auf
  ok   die Maschine lief noch, als der Laeufer sie abraeumte: 124
  ok   die Unterbrechungen sind AN (if): 1
  ok   der Zeitgeber schlaegt (mk): 4406 > 434
  ok   die xHCI-Meldung kommt an (irq): 47 > 40

== 4. und die Eingabe kommt oben an ==
  ok   HID-Berichte (ber): 13 > 6
  ok   Mausbewegungen aus den Berichten (bew): 5 > 0
  ok   Pakete beim Zeiger (pk): 7 > 0
  ok   vom Fensterserver abgeholt (wm): 8 > 1
  ok   Klicks im Fensterserver (kl): 1 > 0
  ok   der Zeiger ist gewandert: 639,399 -> 799,539

== 5. GEGENPROBE zur Meldung: mit usbnoirq traegt die Abfrage ==
  ok   der Vektor bleibt maskiert -- irq steht still: 0
  ok   und die Maus kommt TROTZDEM an (bew): 3 > 0
  ok   und der Klick auch (kl): 1 > 0

== 6. zwei Regler, HID am zweiten -- wie auf Justins Brett ==
  ok   Geraete am behaltenen Regler: 2 / Tastatur: 1 / Maus: 1
  ok   beide Regler melden ihre Meldeart: 2

== 7. die Rangfolge der Schnittstellen (gebauter Deskriptor) ==
  ok   Zusagen der Rangfolge: 6
```

Die Aufstellung ist Justins: **zwei xHCI-Regler, HID am zweiten**
(`-device qemu-xhci,id=x0 -device nec-usb-xhci,id=x1 -device
usb-kbd,bus=x1.0 -device usb-mouse,bus=x1.0`), Wurzel aus dem
Startmodul (`modfs`), dieselbe Kommandozeile wie Menü 4.

**Keine Regression:**

| Läufer | vorher | jetzt |
|---|---|---|
| `tools/hid/run.sh` | 57 / 0 | **57 / 0** |
| `tools/k17/run.sh` | 158 / 0 | **158 / 0** |
| `tools/desktop/run.sh` | 1 rote Zusage (`WM_MAXNR`) | **grün** — die Liste stand seit Runde PAINT auf 2115, `WM_APP` ist 2116. Eine rote Zusage, über die alle hinwegsteigen, ist schlimmer als keine; das steht drei Zeilen darüber im selben Läufer |

---

## 7. WAS DAMIT NOCH IMMER NICHT GEHT

* **Kein Hub-Treiber.** Hängen Tastatur und Maus hinter einem USB-Hub
  (auch im Monitor oder in der Tastatur selbst), sieht Osum sie nicht.
  Sie gehören direkt in eine Buchse am Gehäuse.
* **Nur ein Regler gleichzeitig.** Der Vorrat des Treibers
  (`0x50000..0x58000`) ist einmal da. Hängen Tastatur und Maus an
  verschiedenen Reglern, wird einer bedient — und der Bericht sagt für
  jeden, was an seinen Buchsen steht.
* **MSI ist geschrieben, aber nicht auf Blech gemessen.** QEMUs
  `qemu-xhci` und `nec-usb-xhci` haben beide MSI-X, also nimmt der
  Treiber dort immer MSI-X. Ob der MSI-Weg auf `1022:43d5` greift, sagt
  erst Justins nächstes Foto: `usb: hc0 melde=msi` und `irqs>0`.
* **Der Ring-3-Ausflug** ist repariert, aber die Ursache im
  Assembler (`leave_user` kommt aus einem `syscall` zurück) steht
  weiterhin so da. Die Reparatur ist in Firn und lokal; wer `isr.s`
  anfasst, sollte sie kennen.
