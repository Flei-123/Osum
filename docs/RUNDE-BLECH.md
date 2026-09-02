# Runde BLECH — Osum auf fremdem Blech

Arbeitsbaum `/root/osum-blech`, Zweig `blech`, abgezweigt von `main`
(`163984d`). Gemessen am 02.09.2026 auf dem üblichen Wirt (AMD EPYC
7571, 12 Kerne, 19 GiB, `/dev/kvm` vorhanden, QEMU 7.2.22).

Der Auftrag war: „Orient OS auf allem tauglich machen." Die Lückenliste
kam aus `docs/RUNDE-MERGE3.md`, Abschnitt „Was Osum auf echtem Blech
kann und was nicht", und aus `docs/REALHW.md`.

**Die wichtigste Erkenntnis dieser Runde steht am Anfang und nicht am
Ende: zwei der drei Aufträge waren schon erledigt, auf Zweigen, die
niemand gemerged hat.** Was danach kommt, ist das, was wirklich fehlte.

---

## TEIL 0 — WAS SCHON GEBAUT WAR, UND ES WUSSTE NIEMAND

Der Auftrag nannte als Punkt 1 den Realtek RTL8168/8169 („die wichtigste
einzelne Karte dieser Runde") und als Punkt 2 die HID-Report-Deskriptoren.
Beides liegt seit dem 30.08.2026 im Repository, auf zwei Zweigen, die
nicht in `main` sind und in keinem Bericht auftauchen.

Diese Runde hat sie **nicht geglaubt, sondern nachgemessen** — jeden in
einem eigenen Arbeitsbaum, mit seinem eigenen Läufer:

| Zweig | Was darin liegt | Nachgemessen | Ergebnis |
|---|---|---|---|
| `rtl` (`51b7cb2`) | `kernel/r8169.fi`, 1239 Z. — RTL8169/8168/8111/8101 **und** RTL8139C+; dazu `e1000.fi` +372 Z. für den **PCH-Zweig I217/I218/I219** | `bash tools/rtl/run.sh` in `/root/blech-rtl` | **67 bestanden, 0 gefallen** (rc 0) |
| `hid` (`46c85a4`) | `kernel/hidrep.fi` 1032 Z. (Zerleger für Berichtsbeschreibungen), `hidin.fi` 1503 Z., `i2chid.fi` 795 Z. (**I²C-HID**, Touchpad) | `bash tools/hid/run.sh` in `/root/blech-hid` | **57 bestanden, 0 gefallen** (rc 0) |

Protokolle: `/root/blechlogs/RTL-nachmessung.log`,
`/root/blechlogs/HID-nachmessung.log`.

**Die Konsequenz für diese Runde war eine Entscheidung, und sie ist die
wichtigste:** einen zweiten RTL8169-Treiber zu schreiben wäre 1239
Zeilen Doppelarbeit gewesen, die später jemand von Hand
auseinandersortieren müsste. Der Auftrag sagte „erst RTL8169/8168" — die
richtige Antwort darauf ist nicht „nochmal", sondern „liegt da, ist grün,
gehört gemerged". Das Gewicht dieser Runde ist deshalb auf das gegangen,
was **wirklich** fehlte.

**Was daraus für die nächste Merge-Runde folgt** (und was diese Runde
ausdrücklich NICHT getan hat, weil `main` von MERGE-5 belegt war):
`rtl` und `hid` gehören nach `main`. Beide sind von `mergeline2`
abgezweigt (`a919787` bzw. `b010f75`), also aus der Geschichte von
`main`, und beide sind einzeln grün gemessen. Danach kann `docs/REALHW.md`
für Realtek, I219 und I²C-HID von „geht nicht" auf „geht" umgeschrieben
werden — diese Runde hat es in ihrer eigenen Tabelle als **„gebaut,
gemessen, nicht in `main`"** eingetragen und nicht als „geht".

---

## TEIL 1 — DIE WURZEL WIRD GESUCHT STATT GERATEN

### Was nicht ging, im Quelltext nachgelesen

`docs/RUNDE-MERGE3.md` sagt: „Die automatische Treiberwahl beim Start ist
nicht gebaut." Nachgelesen, nicht geglaubt — `kmain.fi`, `osum_stage`:

```
blk.use_ata(state, kutil.root_blocks(state))
var mounted: bool = fs.mount(state)
if !mounted && !bootmod.ready(state) {
    mounted = root_from_part(state)      // und DAS ruft:
}                                        //   part.scan(state, blk.DEV_ATA)
```

Beide Wege nennen dasselbe Gerät beim Namen: `DEV_ATA`, die Portadresse
0x1F0 von 1986. Auf einem PC mit NVMe-Riegel oder einer SATA-Platte am
AHCI-Controller gibt es dort nichts.

### Die Messung, zwei Kerne auf derselben Maschine

Eine Maschine, deren **einzige** Platte ein NVMe-Riegel mit einem
OFS-Wurzelabbild darauf ist:

| | `main` (`163984d`, 3 313 608 Oktett) | `blech` (3 402 300 Oktett) |
|---|---|---|
| Serielle Ausgabe | `osum: no drive` — und dann nichts mehr | `rootsel: versuch nvme` |
| | | `rootsel: nvme -- WURZEL, Bloecke=8192  first=0` |
| Wurzel eingehängt | **nein** (`osum: mount=1` fehlt) | **ja**, `osum: mount=1` |
| `/bin` gelistet | — | `sh:1 ls:1 cat:1 echo:1` |
| Shell | — | `osum: sh exit=0` |

Der alte Kern wird vom Läufer **selbst gebaut** (`git merge-base HEAD
main` in einen eigenen Arbeitsbaum) und mit demselben QEMU-Aufruf
gefahren. Ohne ihn wäre „der neue kann es" die Behauptung, dass der alte
es nicht konnte.

### `kernel/rootsel.fi` (neu, 736 Zeilen)

Drei Dinge, und nur diese drei:

1. **Lesen** (`scan`). Die Bustabelle, die `pci.scan` schon gefüllt hat.
   Kein Register wird geschrieben. Heraus kommen die **Bewerber** in der
   Reihenfolge NVMe → AHCI → USB → IDE, die **Befunde** (Controller ohne
   Treiber, jeder mit seinen Nummern) und die **USB-Regler** mit ihrer
   Schnittstelle.
2. **Es sagen** (`report`, gerufen aus `hwdiag`).
3. **Es tun** (`mount_root`). Jeden Bewerber hochziehen, rohes OFS an
   Block 0 versuchen, sonst die Partitionstafel und `part.T_OFS` — und
   **den ersten nehmen, dessen Wurzel sich wirklich einhängen lässt**.

### Ein Bewerber, der nur DA ist, gewinnt nicht

Leere NVMe-Platte (kommt zuerst dran) neben einer AHCI-Platte mit dem
System darauf:

```
rootsel: versuch nvme
rootsel: nvme -- keine Wurzel darauf
rootsel: versuch ahci
rootsel: ahci -- WURZEL, Bloecke=8192  first=0
osum: mount=1
```

### Und der alte Weg bleibt der erste — gezählt, nicht angesehen

Die Zeile steht in `kmain.fi` **hinter** dem alten Weg und nicht davor.
Der Grund ist eine Zahl: alle bestehenden Abschnitte der Abnahme hängen
ihre Wurzel über ATA ein und sind grün. Eine Reihenfolge, die NVMe
zuerst probiert, wäre eine Änderung an bestehenden **Messungen** statt
an einem Startproblem.

Gemessen (Läufer, Abschnitt 3): IDE-Platte, die trägt, daneben eine
leere NVMe-Platte → **`grep -c 'rootsel: versuch'` = 0**. Die neue Suche
läuft kein einziges Mal.

Zwei Sperren, damit nichts zerstört wird: steht `nvme` oder `ahci` auf
der Kommandozeile, gehört der Controller der Stufe `hw.disk` — und die
**formatiert** ihn. Der Bewerber wird dann übersprungen, und die Zeile
sagt es.

---

## TEIL 2 — DER RAID-MODUS WIRD BEIM NAMEN GENANNT

Der häufigste Grund, aus dem ein Notebook mit Osum nicht startet, ist
**kein fehlender Treiber**: es ist ein SATA-Controller, den die Firmware
ab Werk in den RAID-Modus gestellt hat (Intel RST, AMD RAIDXpert). Er
meldet sich als Klasse **01:04** statt 01:06:01, der AHCI-Treiber findet
ihn korrekterweise nicht, und bis zu dieser Runde blieb der Schirm leer.

Gemessen mit `-device megasas` (LSI MegaRAID SAS, Klasse 01:04 — genau
das, was RST hinstellt) und `-device sdhci-pci`:

```
rootsel: reihenfolge: nvme > ahci > ide
rootsel: 1000:0060 steht im RAID-Modus (01:04)
rootsel: im BIOS "SATA Mode" von RAID/RST auf AHCI stellen, dann neu
rootsel: 1b36:0007 ist ein SD/eMMC-Regler -- kein Treiber
```

**Warum die Meldung und nicht der Treiber:** ein RST-Treiber müsste die
Metadaten des Herstellers verstehen, und die sind nicht dokumentiert.
Der Umschalter im BIOS sind zwei Klicks. Eine gute Fehlermeldung ist
hier mehr wert als ein halber Treiber — so stand es im Auftrag, und so
ist es gebaut.

Ebenfalls benannt statt verschwiegen: SAS (01:07), SCSI (01:00),
SD/eMMC (08:05), SATA mit einer anderen Schnittstelle als AHCI, und
jeder Speichercontroller in Klasse 01, für den es keinen Treiber gibt —
**jeder mit Hersteller- und Gerätenummer.**

---

## TEIL 3 — EHCI, DER USB-2.0-ANSCHLUSS

### Warum, obwohl MERGE-3 das Gegenteil sagt

`docs/RUNDE-MERGE3.md`: „Jeder Rechner seit ~2012 hat xHCI. Das ist der
richtige und einzige nötige Controller." Der erste Satz stimmt. Der
zweite nicht:

* Ein Rechner **vor** 2012 hat gar kein xHCI. Dort ist heute jeder
  USB-Anschluss tot — keine Tastatur, kein Stick.
* Auch danach ist EHCI nicht weg: auf den Chipsätzen der 7er-Reihe steht
  ein EHCI neben dem xHCI (`ich9-usb-ehci1/2`), und welche Buchse woran
  hängt, entscheidet die Firmware.

### Ein zweiter Treiber und keine zweite Hälfte von `usb.fi`

Der Grund ist eine Zahl: `usb.fi` ruft **40 verschiedene Funktionen** von
`xhci.fi` (`grep -o 'xhci\.[a-z_0-9]*' kernel/usb.fi | sort -u`), und die
heißen `slot_enable`, `dcbaa_set`, `in_ep`, `ctx_size`, `set_dequeue`.
Das sind keine USB-Begriffe, das sind xHCI-Begriffe. Ein EHCI hat keine
Steckplätze und keine Türklingeln — er hat **zwei verkettete Listen**.
Ein `ehci.fi`, das diese vierzig Namen nachbaut, müsste Steckplätze
erfinden, die es nicht gibt. Also derselbe Weg, den Runde RTL gegenüber
`e1000.fi` gegangen ist.

`kernel/ehci.fi`, **1581 Zeilen**.

### Gemessen: der Stick

```
ehci: bdf=0x20  caplen=32  hcc=0x6880  ports=6  legacy=0x68  handoff=1
ehci: port 0  portsc=0x1005  speed=2
ehci: dev 0  addr=1  klasse=3  46f4:0001
ehci: enum=1  ctrl=6  fehler=0
ehci: msc blocks=2048  bsize=512
ehci: selftest lba=0   ok=1  sum=16054338  first=100
ehci: selftest lba=1   ok=1  sum=16473626  first=250
ehci: selftest lba=64  ok=1  sum=17142038  first=124
```

**Und der Wirt rechnet dieselben drei Summen** aus dem Abbild aus, aus
dem QEMU liest — gewichtete Oktettsumme über die ersten 512 Oktett, in
`tools/blech/run.sh` in Python. Der Kernel ist an dieser Stelle nicht
sein eigener Zeuge. „Der Treiber meldet Erfolg" wäre keine Messung.

### Gemessen: die Tastatur

Sechs Tasten über den QEMU-Monitor, an einem `usb-kbd` am EHCI:

```
ehci: enum=1  ctrl=8  fehler=0  tasten=6  berichte=13  abfragen=1777
ehci: codes 23 1e 26 26 18 1c
```

`23 1e 26 26 18 1c` ist **h a l l o Eingabe im Abtastcodesatz 1**. Die
Erwartung steht als Zeichenkette im Läufer und kommt aus der AT-Tabelle,
nicht aus dem Kernel — sonst prüfte sich die Übersetzungstabelle selbst.
Also nicht „sechs Tasten kamen an", sondern „**es waren diese sechs**".

Sie gehen durch `kbd.on_code` — dieselbe Tür, durch die IRQ 1 geht und
durch die `usb.fi` seit K17 geht. Es gibt keinen zweiten Weg in die
Zeilendisziplin.

**Der Unterbrechungsendpunkt hängt in der PERIODISCHEN Liste**, nicht in
der asynchronen. Das ist der Punkt, an dem ein EHCI-Treiber typisch
falsch ist: QEMU würde die asynchrone Liste vermutlich verzeihen, ein
echter Regler nicht.

### Zwei eigene Fehler, beide von einer Messung gefunden

1. **Der Typ im Verkettungszeiger war um ein Bit verschoben.** Der Wert
   für einen QH ist 01 in Bit 1..2, also `0b010` = 2 — *fertig
   geschoben*. Der Quelltext hatte `LINK_QH << 1` = 4 = `0b100`, also
   Typ 10 = „isochroner Teilbaum". Das Bild dazu: `port 0 speed=2`, aber
   `enum=0 ctrl=1 fehler=1` — der Anschluss stand, der Regler ging die
   Liste ab und fand darin etwas, das kein Warteschlangenkopf war.
2. **RS und die Listen in einem Schreibzugriff.** `USBCMD` mit
   `RS|ASE|PSE` gleichzeitig lässt QEMU 7.2 nicht anlaufen: HCHalted
   blieb stehen (`warum=5`). Die Spezifikation 4.1 sagt es in zwei
   Schritten, und in zwei Schritten geht es. — Dass dieser Fehler
   überhaupt einen Namen bekam, liegt an einer Zahl im Quelltext: der
   Treiber merkt sich, **warum** `init` fehlgeschlagen ist, und druckt
   sie. „ehci: init failed" ohne Grund ist genau die Meldung, über die
   diese Runde sich beim Plattentreiber beschwert hat.

### Zwei weitere Fehler, beim Nachlesen gefunden — und beide erst mit ZWEI Geräten sichtbar

Keiner von beiden hat einen roten Haken erzeugt. Beide wären auf einem
echten Brett aufgetreten und in der Nachbildung nie, weil bis dahin in
jeder Messung genau **ein** Gerät am Regler hing.

3. **Der Gerätesatz war zu klein.** `DEV_BYTES` stand auf 64, und vier
   Felder lagen dahinter: `D_VEN` (0x40), `D_PROD` (0x48), `D_TOGOUT`
   (0x50), `D_MPSIN` (0x58). Gerät 0 hat damit in den Platz von Gerät 1
   geschrieben — mit einer Tastatur **und** einem Stick an derselben
   Buchsenleiste hätte die Tastatur die Herstellernummer des Sticks
   getragen. Die Karte in `tools/kernel/memmap.py` hätte es **nicht**
   gefunden: sie prüft Bereiche gegeneinander, nicht Felder *innerhalb*
   eines Bereichs.
4. **Das Umschaltbit hing an der Zahl der Übertragungen statt an der
   Zahl der Pakete.** `tin = 1 - tin` nach jedem Bulk-Zugriff — richtig
   für 512 Oktett bei 512 Oktett je Paket, also für genau die eine
   Größe, die in der Messung vorkommt. Bei einem Gerät mit 64 Oktett je
   Paket wären es acht Pakete, und der zweite Block wäre Müll. Jetzt
   `toggle_after(len, mps, t)`, und die Paketgröße des
   Ausgangs-Endpunkts kommt aus dem Deskriptor statt aus einer Annahme.

**Die Messung dazu** (Abschnitt 6b des Läufers) — Tastatur *und* Stick
an derselben Buchsenleiste:

```
ehci: port 0  portsc=0x1005  speed=2
ehci: port 1  portsc=0x1005  speed=2
ehci: dev 0  addr=1  klasse=1  0627:0001     <- die Tastatur
ehci: dev 1  addr=2  klasse=3  46f4:0001     <- der Stick
ehci: enum=2  ctrl=14  fehler=0  tasten=6
ehci: codes 23 1e 26 26 18 1c
ehci: selftest lba=0  ok=1  sum=16054338  first=100
```

Jedes Gerät trägt **seine** Nummern, die Tastatur liefert weiterhin die
richtigen Abtastcodes, und die Blocksummen sind dieselben.

### Die Gegenproben

| Gegenprobe | Ergebnis |
|---|---|
| ohne das Wort `ehci`, Regler steht da | `ehci: skipped`, kein Gerät aufgezählt |
| Wort da, kein Regler | `ehci: kein EHCI auf dem Bus` — eine Meldung statt eines Hängers |
| `-M q35 -device ich9-usb-ehci1` | derselbe Treiber, `bdf=0x18`, **dieselben drei Blocksummen** |

### Was NICHT gemessen ist, ausdrücklich

**Split-Übertragungen.** Ein Gerät mit voller oder niedriger
Geschwindigkeit (USB 1.1) an einem EHCI braucht Start-Split und
Complete-Split über einen Hochgeschwindigkeits-Hub. Dieser Treiber kann
das nicht und **gibt den Anschluss ab** (PORTSC Bit 13, Port Owner)
statt zu raten. Der Zweig lässt sich hier nicht auslösen: QEMU lehnt
`usb-kbd,usb_version=1` an einem EHCI-Bus schon beim Start ab
(`speed mismatch trying to attach usb device ... (full speed) to bus ...
(high speed)`). **Der Code steht aus der Spezifikation da und ist
ungeprüft.** Auf einem echten Brett mit Begleitreglern übernimmt dann
der UHCI/OHCI daneben — den hat dieser Kern nicht, also ist die Meldung
dort die ganze Wahrheit.

**Kein eigener Meldevektor.** Der Endpunkt wird aus der Leerlaufaufgabe
abgefragt (`kernel/tasks.fi`, zwei Zeilen). Ein eigener Vektor braucht
einen Stumpf in `isr.s`, und `isr.s` fasst diese Runde bewusst nicht an,
weil zwei weitere Runden gleichzeitig an diesem Baum arbeiten. **Preis:
ein Tastendruck kostet bis zu 10 ms mehr als über eine Meldung** (die
Leerlaufaufgabe kommt hundertmal je Sekunde dran). Für eine Tastatur
nicht spürbar; für einen Stick unter Last wäre es eine eigene Runde.

**Die Übergabe durch die Firmware dagegen IST gemessen.** QEMU stellt
eine erweiterte Fähigkeit hin (`legacy=0x68`), und `handoff=1` heißt,
dass das BIOS-Besitzbit gefallen ist. Auf echtem Blech ist das die
häufigste Ursache dafür, dass USB „manchmal" geht: solange das BIOS den
Regler besitzt, liegt auf jedem Registerzugriff eine SMI-Falle.

---

## TEIL 4 — NVMe MIT MEHR ALS EINEM NAMENSRAUM

In `identify` stand seit Runde K2: *„CNS 0 = this namespace. Namespace 1
is the one every NVMe device that has any namespace at all has."*
Richtig — und zu wenig.

Gemessen mit drei Namensräumen (8 MiB / 4 MiB / 2 MiB), und die letzte
Nummer **absichtlich 7 und nicht 3**: eine Liste, die „1,2,3,…" annimmt,
fällt hier auf.

```
nvme: ns count=3  in list=3
nvme: ns0 nsid=1  blocks=16384  lbasz=512
nvme: ns1 nsid=2  blocks=8192   lbasz=512
nvme: ns2 nsid=7  blocks=4096   lbasz=512
nvme: ns0 nsid=1  lba0=1  sum=16949504
nvme: ns1 nsid=2  lba0=1  sum=16646400
nvme: ns2 nsid=7  lba0=1  sum=16740608
```

**Und der Wirt rechnet auch hier dieselben drei Summen** aus den drei
Abbildern, in die er drei verschiedene Muster gelegt hat.

Zwei Stellen, an denen man das falsch macht, und beide sind im Quelltext
begründet:

* Die Nummern werden **zuerst in eine eigene Tafel kopiert**. Der
  Zielpuffer `ID_OFF` wird vom nächsten Befehl wieder gebraucht — wer die
  Liste dort stehen lässt, liest ab dem zweiten Namensraum die Antwort
  des ersten.
* **Bis zur ersten Null** und nicht bis 1024 (NVMe 1.4, Fig. 245). Sonst
  liest man hinter dem Ende weiter.

**Keine Änderung an bestehenden Läufen, und das ist nachgerechnet:**
`run_io` heißt jetzt `run_io_ns` und bekommt die Nummer als Argument;
die alte Funktion bleibt stehen und ruft sie mit einer festen 1. Jeder
bestehende Weg setzt Wort für Wort denselben Befehl ab wie vorher. Und
`ns_verify` — der Lesetest — läuft **nur bei mehr als einem
Namensraum**; alle bestehenden Läufe haben genau einen.

Kein neuer Speicher: die Tafel liegt in derselben Skalarseite
(`pci.K2_SCALARS`, Versatz 0x200).

---

## TEIL 5 — GRAFIK: KEIN TREIBER, ABER DIE ZAHLEN GEPRÜFT

Diese Runde baut ausdrücklich **keinen GPU-Treiber**, und das soll so
bleiben. Geprüft wurde stattdessen, ob der Weg über die Firmware wirklich
trägt — `tools/blech/fb.sh`, **9 bestanden, 0 gefallen**.

Gemessen wird nicht „es kommt ein Bild", sondern die Schlüssigkeit der
vier Zahlen, mit einer Rechnung, die eine Karte, die nur irgendetwas
meldet, nicht besteht:

```
pitch >= width * bpp/8      cols == width/8      rows == height/16      phys != 0
```

Ein Rahmenpuffer, dessen Zeilenlänge kleiner ist als seine Breite, zeigt
Schrägstreifen statt eines Bildes — und das sieht man auf fremdem Blech
zuerst und im Quelltext nie.

| Grafikkarte | Ergebnis |
|---|---|
| `-vga std` | 800x600 bpp=32 pitch=3200 src=vbe ✅ |
| `-vga qxl` | 800x600 bpp=32 pitch=3200 src=vbe ✅ |
| `-device bochs-display` | 800x600 bpp=32 pitch=3200 src=vbe ✅ |
| `-device VGA` | 800x600 bpp=32 pitch=3200 src=vbe ✅ |
| `-device virtio-vga` | 800x600 bpp=32 pitch=3200 src=vbe ✅ |
| `-vga cirrus` | **kein Rahmenpuffer** — `fb=KEINER`, Kern läuft weiter |
| `-vga vmware` | **kein Rahmenpuffer** — `fb=KEINER`, Kern läuft weiter |
| `-vga none` | kein Rahmenpuffer, **und der Bericht kommt trotzdem vollständig** |
| `fbbig` (1024x768) | 1024x768 bpp=32 pitch=4096 src=vbe ✅ |

**Der Befund zu Cirrus und VMware-SVGA ist echt und wird nicht
schöngeredet:** beide haben die Bochs-Erweiterung `0x1CE/0x1CF` nicht;
ihr eigener VBE-Weg läuft über INT 10h im realen Modus, und den gibt es
in einem 64-Bit-Kern nicht mehr. Auf echtem Blech spielt das keine
Rolle — dort kommt der Puffer von der Firmware —, in der Nachbildung ist
es der Unterschied zwischen „geht" und „geht nicht".

`src=vbe` bei allen Läufen mit `-kernel` ist erwartet und ist selbst eine
Gegenprobe: QEMU lädt dabei selbst und hinterlässt keinen Rahmenpuffer.
Unter UEFI mit Limine steht `src=multiboot` — das misst
`tools/usbimg/run.sh` (Abschnitt 31 der Abnahme, `fb 1280x800`).

**Umschaltbare Grafik: nicht gebaut, und die verständliche Meldung dafür
auch nicht.** Sie hätte eine Änderung am Kern gebraucht, während die
volle Abnahme schon lief; das wäre eine Messung gewesen, die ihren
eigenen Gegenstand ändert. Steht unter „was noch fehlt".

---

## WAS DIESE RUNDE GEBAUT HAT — DER UMFANG

| Datei | | Was |
|---|---:|---|
| `kernel/ehci.fi` | **1581** | neu. EHCI 1.0: Übergabe, Ringe, Aufzählung, Stick (BOT/SCSI), Tastatur |
| `kernel/rootsel.fi` | **736** | neu. Wurzelgerätewahl, RAID-Befund, USB-Reglerliste |
| `tools/blech/run.sh` | **381** | neu. Der Läufer, 52 Zusagen, mit dem alten Kern als Vergleichsmaß |
| `tools/blech/fb.sh` | **172** | neu. Der Rahmenpuffer über sieben Karten |
| `kernel/nvme.fi` | +219 | Namensraumliste, `run_io_ns`, `ns_verify` |
| `kernel/kmain.fi` | +81 | Modusworte, die EHCI-Stufe, die Wurzelsuche als letzter Weg |
| `tools/kernel/memmap.py` | +70 | zwei neue Bereiche und die **innere** Nachrechnung des EHCI-Bereichs |
| `kernel/tasks.fi` | +19 | zwei Zeilen Abfragen in der Leerlaufaufgabe (+ Begründung) |
| `test.sh` | +14 | Abschnitt 34 |
| `kernel/kstate.fi` | +11 | zwei Modusworte in Wort 12 |
| `kernel/hwdiag.fi` | +9 | `rootsel.report` im Bericht |
| `kernel/hw.fi` | +5 | die Namensräume im NVMe-Bericht |

**3291 Zeilen eingefügt, 7 gelöscht, 12 Dateien.** Abbild:
3 313 608 → 3 402 300 Oktett (**+88 692, +2,7 %**).

Speicher: **vier Seiten** in `kdata` — drei für den EHCI
(0x4D000..0x50000, genau das Stück, das die Karte bis heute als „frei
(12 KiB)" auswies) und eine für die Wurzelwahl (0x85000). Die Karte
rechnet jetzt auch die **innere** Aufteilung des EHCI-Bereichs nach
(Punkt 5b, nach dem Muster von K17) und prüft ausdrücklich, dass die
periodische Rahmenliste auf 4096 liegt: `PERIODICLISTBASE` hat unten
zwölf Bits, die es nicht gibt, und eine falsch liegende Liste sieht man
erst daran, dass die Tastatur nichts liefert. **83 Bereiche, 0
Kollisionen.**

---

## VIER BAUARTEN, ZWEI DAVON GEFAHREN

Der Kern lässt sich in vier Zuschnitten bauen, und diese Runde hat alle
vier gebaut — zwei davon auch gestartet, weil ein Bau, der nur übersetzt,
nichts über das Laufen sagt:

| Bauart | Abbild | gefahren |
|---|---:|---|
| `gui=on tunnel=on`, Stufe 0 | 3 406 500 | ja (alle Messungen oben) |
| `gui=off tunnel=on`, Stufe 0 (**Server**) | 2 535 964 | **ja** — EHCI mit Stick, dieselben drei Blocksummen |
| `gui=on tunnel=off`, Stufe 0 | 3 202 960 | nur gebaut |
| `gui=off tunnel=off`, Stufe 0 | 2 332 524 | nur gebaut |
| `gui=on tunnel=on`, **Stufe 1** (`firnc1`) | 8 168 008 | **ja** — NVMe-Wurzel über `rootsel` |

Stufe 1 heißt: der Kern ist vom **selbstgehosteten** Firn-Übersetzer
gebaut, nicht vom Rust-Übersetzer. Auch dort findet `rootsel` die
NVMe-Wurzel. Protokoll: `/root/blechlogs/BAUARTEN.log`.

---

## DAS USB-ABBILD, UNTER BIOS UND UNTER UEFI

`bash tools/usbimg/build.sh` aus dem Stand dieser Runde:

| | |
|---|---|
| Abbild | **123 731 968 Oktette** (118 MiB), GPT, EFI 96 MiB + Wurzel 20 MiB |
| SHA-256 | `b8b1fd3abb5e260dc8b865480c53603f88a11b7af1372db8c30408cc87c44b10` |
| Wurzeldateisystem | 20 971 520 Oktette, OFS v3, 24 Pflichtpfade, 125 Umlautfolgen |

Beide Startwege, jeweils mit `hwdiag` (Protokoll
`/root/blechlogs/USBIMG-bios-uefi.log`):

```
--- BIOS ---
hwdiag: firmware=BIOS  vgarom=0xc0000  smbios=0xf59f0  rsdp=0xf59d0
hwdiag: fb 1280x800  bpp=32  pitch=5120  src=multiboot  phys=0xfd000000  cols/rows=160/50
hwdiag: disk IDE    bdf=0x9 8086:7010
rootsel: reihenfolge: ide
netdev: c0=e1000 bdf=0x18
hwdiag: ANGEHALTEN. Der Bildschirm bleibt so stehen.

--- UEFI (OVMF) ---
hwdiag: firmware=UEFI  vgarom=nein  smbios=nein  rsdp=nein
hwdiag: fb 1280x800  bpp=32  pitch=5120  src=multiboot  phys=0x80000000  cols/rows=160/50
hwdiag: disk IDE    bdf=0x9 8086:7010
rootsel: reihenfolge: ide
netdev: c0=e1000 bdf=0x18
hwdiag: ANGEHALTEN. Der Bildschirm bleibt so stehen.
```

Drei Dinge stehen darin, die zusammengehören:

* **`src=multiboot`** in beiden Fällen — Limine gibt den GOP-Puffer
  weiter, und der Kern nimmt ihn. `pitch=5120` = 1280 · 4, `cols/rows`
  = 1280/8 und 800/16: die Rechnung aus Teil 5, hier auf dem echten
  Startweg statt mit `-kernel`.
* **`firmware=BIOS` / `firmware=UEFI`** — dieselben drei Spuren
  (VGA-ROM, SMBIOS, RSDP), zwei verschiedene Antworten. Der Befund ist
  ein Befund und keine Vermutung.
* **`rootsel: reihenfolge: ide`** — die neue Zeile ist auf dem echten
  Startweg da, unter beiden Firmwares. Auf dieser Maschine ist der
  IDE-Controller der einzige Bewerber, und der Kern sagt es, statt ihn
  stillschweigend zu nehmen.

---

## DIE ABNAHME

**Der Wirt war während des ganzen Laufs nicht allein**, und das gehört
in den Bericht, bevor eine Zahl kommt: die Runde MERGE-5 fuhr auf
demselben Rechner ihre eigene volle Abnahme, und ab 10:11 kam eine
dritte dazu (`/root/osum-modul`). Lastmittel zwischen 8 und **19**, bis
zu drei Läufe gleichzeitig, und die wirtweite Netzsperre
`/tmp/osum-netz.lock` war über weite Strecken von jemand anderem
gehalten.

Deshalb dasselbe Verfahren wie in MERGE-3 und MERGE-FINAL: **jeder rote
Abschnitt wird einzeln nachgemessen**, und erst diese Zahl zählt.

### Die drei roten aus dem vollen Lauf, einzeln nachgemessen

| Abschnitt | voller Lauf (Last 8–19) | einzeln | Urteil |
|---|---|---|---|
| `pci` | 97 / 1 — `DMA against PIO … 995, expected ge 1200` | **98 / 0**, `bench: faster=1415 permil` | **Lastphantom.** Die Zusage ist ein Durchsatz*verhältnis* (NVMe-DMA gegen ATA-PIO); unter drei gleichzeitigen Abnahmen bricht es ein. |
| `async` | 106 / 1 — `Speicher je Auftrag in Oktett: 0, erwartet eq 112` | **108 / 0** | **Lastphantom.** Die 0 heißt „die Zeile kam nicht", nicht „der Wert ist falsch" — der Lauf, der sie druckt, lief in sein Zeitlimit. Zur Sicherheit auch auf `main` gefahren: dort ebenfalls 108 / 0. |
| `arm` | 47 / 1 — `_F0.amain__kexception is missing` | 47 / 1 | **Gehört nicht dieser Runde.** Derselbe Abschnitt auf `main` (`163984d`), gefahren in `/root/osum-basecheck`: **dieselbe Zahl, derselbe einzelne Fehler.** Diese Runde hat `kernel/arch/aarch64/` nicht angefasst (`git diff main...HEAD` darauf ist leer). |

Der `arm`-Punkt hätte auch anders ausgehen können, und deshalb ist er
zusätzlich geprüft worden: diese Runde fügt der **Leerlaufaufgabe** eine
Zeile hinzu (`ehci.poll`), und `tools/arch/order.sh` prüft unter anderem
`x86-64: idle -> hlt`. Das ist eine andere Sache — geprüft wird dort die
Maschinenanweisung hinter `machine__idle`, nicht die Aufgabe. Auf
`blech` einzeln gefahren: **`ORDER: 15 passed, 0 failed`.**

### Die grünen Abschnitte, aus dem laufenden Vergleich

Aus den Abschnittsprotokollen unter `.test-work/` desselben Laufs, alle
mit 0 gefallenen Zusagen:

```
boot 20    caps 67    customres 135   display 145   freestanding 41
gfx 76     guard 55   handle 80       hv 114        k11 85
k13 99     k14 152    k16 64          k17 158       k18 170
kernel 176 osum 130   posix 134       smp 59        tiling 68
unix 107   userland 91                wm 103
```

Und der neue Abschnitt der Runde: **`BLECH: 52 bestanden, 0 gefallen`**
(einzeln gefahren, `accel=kvm`, Protokoll
`/root/blechlogs/BLECH-runner.log`), dazu **`FB: 9 bestanden, 0
gefallen`** (`/root/blechlogs/FB-sweep.log`).

Alle Protokolle dieser Runde liegen unter `/root/blechlogs/`:
`ABNAHME-voll.log`, `BLECH-runner.log`, `FB-sweep.log`,
`PCI-blech-einzeln.log`, `ASYNC-blech-einzeln.log`, `ASYNC-main.log`,
`ARM-main-vergleich.txt`, `RTL-nachmessung.log`, `HID-nachmessung.log`,
`USBIMG-bios-uefi.log`, `BAUARTEN.log`, `BUILD-usbimg.log`.

---

## WAS NOCH FEHLT — ehrlich benannt

### Netz

* **Intel I210/I211/I225/I226 (igb/igc): NICHT gebaut, und mit
  Begründung.** QEMU 7.2.22 ist die einzige Fassung auf diesem Wirt
  (Debian bookworm, `apt-cache policy qemu-system-x86` zeigt keine
  andere; kein Backport). `qemu-system-x86_64 -device help` kennt **kein
  `igb`** — das kam erst mit QEMU 8.0 —, und **`igc` gibt es bis heute in
  keiner QEMU-Fassung**. Ein solcher Treiber wäre hier zu keinem
  Zeitpunkt messbar gewesen, und das ist genau der Grund, aus dem Runde
  HWNET den Realtek nicht gebaut hat: *„Ein Treiber ohne eine einzige
  Messung ist eine Behauptung."* Diese Runde hätte denselben Fehler
  gemacht. Er gehört in eine Runde auf einem Wirt mit QEMU ≥ 8.0 — dann
  ist wenigstens `igb` (I210/I211) messbar, und das teilt mit igc das
  Deskriptorformat („advanced descriptors"), so wie der 8139C+ den Ring
  mit dem 8169 teilt.
* Broadcom, Aquantia, Marvell: nichts.
* **WLAN: nach wie vor gar nichts.**

### Eingabe

* **EHCI kann keine Split-Übertragungen** — ein USB-1.1-Gerät an einem
  EHCI ohne Begleitregler bleibt tot. Der Anschluss wird abgegeben und
  es wird gesagt; mehr geht ohne einen Hochgeschwindigkeits-Hub in der
  Nachbildung nicht messen.
* **UHCI und OHCI: nicht gebaut.** Sie werden seit dieser Runde
  wenigstens **benannt** (`usb UHCI ... (kein Treiber)`), statt still zu
  bleiben.
* **Der EHCI hat keinen eigenen Meldevektor.** Bis zu 10 ms mehr je
  Tastendruck. Ein Vektor braucht einen Stumpf in `isr.s`.
* Der EHCI-Treiber macht seine **eigene** Aufzählung, statt `usb.fi` zu
  benutzen. Das war die richtige Entscheidung für diese Runde (siehe
  Teil 3), aber es sind jetzt zwei Aufzählungen im Baum. Eine spätere
  Runde sollte die gemeinsame Hälfte (Deskriptoren lesen, Klassen
  zuordnen) aus beiden herausziehen — **nachdem** `hid` gemerged ist,
  denn der ändert `usb.fi` um 430 Zeilen.
* Der EHCI-Stick hängt **noch nicht** an `blk.fi` als eigenes
  Blockgerät. Er wird gelesen und die Oktette werden geprüft, aber
  `DEV_EHCI` gibt es nicht; das ist eine Funktion in `blk.fi` und eine
  Zeile in `rootsel.bring_up`.

### Massenspeicher

* **SATA im RAID-Modus wird benannt, aber nicht gelesen.** Bewusst.
* **eMMC/SD: kein Treiber** — seit dieser Runde immerhin benannt.
* **SCSI/SAS: kein Treiber**, benannt.
* Die NVMe-Namensräume werden **gefunden und gelesen**, aber es gibt
  noch keinen Weg, einen davon als `blk`-Gerät einzuhängen. `rootsel`
  probiert weiterhin Namensraum 1.
* **IDE bleibt bei LBA28** = 128 GiB.

### Grafik

* Kein GPU-Treiber, und das bleibt richtig so.
* **Umschaltbare Grafik: keine Meldung.** Die Erkennung wäre billig
  (zwei VGA-Klassen-Geräte auf dem Bus, eines davon Intel), die Meldung
  auch. Sie ist in dieser Runde nur deshalb nicht drin, weil zum
  Zeitpunkt der Entscheidung die volle Abnahme schon lief.
* Cirrus und VMware-SVGA liefern in der Nachbildung keinen Rahmenpuffer
  (siehe Teil 5).

### ACPI

* Unverändert **kein AML-Interpreter**: kein `_PRT`, kein `_CRS`, keine
  Thermalzonen, kein Deckelschalter, kein sauberes S3. Der Zweig `aml`
  existiert; diese Runde hat ihn nicht angefasst.

### Und das Wichtigste

* **`rtl` und `hid` sind nicht in `main`.** Solange das so ist, hat ein
  gewöhnliches Consumer-Brett kein Netz und ein neueres Notebook keine
  eingebaute Tastatur — obwohl beide Treiber im Repository liegen und
  beide grün gemessen sind (67/0 und 57/0, siehe Teil 0). Das ist die
  billigste Verbesserung, die dieses Projekt gerade zu vergeben hat.
