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
`tools/metal/run.sh` in Python. Der Kernel ist an dieser Stelle nicht
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
trägt — `tools/metal/fb.sh`, **9 bestanden, 0 gefallen**.

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
| `tools/metal/run.sh` | **381** | neu. Der Läufer, 52 Zusagen, mit dem alten Kern als Vergleichsmaß |
| `tools/metal/fb.sh` | **172** | neu. Der Rahmenpuffer über sieben Karten |
| `kernel/nvme.fi` | +219 | Namensraumliste, `run_io_ns`, `ns_verify` |
| `kernel/kmain.fi` | +81 | Modusworte, die EHCI-Stufe, die Wurzelsuche als letzter Weg |
| `tools/kernel/memmap.py` | +70 | zwei neue Bereiche und die **innere** Nachrechnung des EHCI-Bereichs |
| `kernel/tasks.fi` | +19 | zwei Zeilen Abfragen in der Leerlaufaufgabe (+ Begründung) |
| `test.sh` | +14 | Abschnitt 34 |
| `kernel/kstate.fi` | +11 | zwei Modusworte in Wort 12 |
| `kernel/hwdiag.fi` | +9 | `rootsel.report` im Bericht |
| `kernel/hw.fi` | +5 | die Namensräume im NVMe-Bericht |
| `tools/i18n/spalten.py` | +19/−4 | der Pufferprüfer zählt `\xNN` jetzt als **ein** Oktett |

**3454 Zeilen eingefügt, 12 gelöscht, 13 Dateien.** Abbild:
3 313 608 → **3 406 500 Oktett** (+92 892, **+2,8 %**).

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

### Der volle Lauf, roh

`OSUM_JOBS=4`, `accel=auto`, 02.09.2026 10:30–12:59 (**2 h 29 min**),
Protokoll `/root/blechlogs/ABNAHME-voll.log`:

```
50 Abschnitte bestanden, 6 FEHLGESCHLAGEN (4124 Zusagen)
```

| | Abschnitte | grün | rot |
|---|---:|---:|---:|
| `main` **vorher** (`163984d`, Zahlen aus `docs/RUNDE-MERGE3.md`) | 54 | 53 | 1 (`netview`) |
| `blech`, **roh unter Fremdlast** | **56** | **50** | **6** |
| `blech`, **nach der Einzelnachmessung** | **56** | **54** | **2** |

Die zwei, die bleiben, sind `arm` und `netview` — und beide sind auf
`main` genauso rot (siehe die Tabelle darunter). **Diese Runde hat
keinen Abschnitt rot gemacht, der vorher grün war.**

### Die roten aus dem vollen Lauf, einzeln nachgemessen

| Abschnitt | voller Lauf (Last 8–19) | einzeln | Urteil |
|---|---|---|---|
| `pci` | 97 / 1 — `DMA against PIO … 995, expected ge 1200` | **98 / 0**, `bench: faster=1415 permil` | **Lastphantom.** Die Zusage ist ein Durchsatz*verhältnis* (NVMe-DMA gegen ATA-PIO); unter drei gleichzeitigen Abnahmen bricht es ein. |
| `async` | 106 / 1 — `Speicher je Auftrag in Oktett: 0, erwartet eq 112` | **108 / 0** | **Lastphantom.** Die 0 heißt „die Zeile kam nicht", nicht „der Wert ist falsch" — der Lauf, der sie druckt, lief in sein Zeitlimit. Zur Sicherheit auch auf `main` gefahren: dort ebenfalls 108 / 0. |
| `theme` | 1 / 2 — `themetest hat keine brauchbare Zeile fuer gpx geliefert` | **91 / 0** | **Lastphantom**, und wieder derselbe Bauart: „keine brauchbare Zeile" heißt „der Lauf kam nicht so weit", nicht „der Wert ist falsch". |
| `arm` | 47 / 1 — `_F0.amain__kexception is missing` | 47 / 1 | **Gehört nicht dieser Runde.** Derselbe Abschnitt auf `main` (`163984d`), gefahren in `/root/osum-basecheck`: **dieselbe Zahl, derselbe einzelne Fehler.** Diese Runde hat `kernel/arch/aarch64/` nicht angefasst (`git diff main...HEAD` darauf ist leer). |
| `umlaut` | 47 / 1 — `ZU ENG kernel/ehci.fi:1319 t: das Literal ist 78 Oktette, der Puffer 26` | **48 / 0** | **ECHT, und der Fehler gehörte dem Prüfer.** Siehe unten. |
| `netview` | 3 rote Zusagen | — | **Gehört nicht dieser Runde**, und das ist nachlesbar: `docs/RUNDE-MERGE3.md` führt genau diese Zusagen als die EINE offene Regression von `main` auf, wörtlich — `faking: the state icon went missing: falsch 40 von 82` und `9a: both Super+A presses became hotkeys: 1, expected eq 2`. Diese Runde hat `netview.fi` nicht angefasst. |

Der `arm`-Punkt hätte auch anders ausgehen können, und deshalb ist er
zusätzlich geprüft worden: diese Runde fügt der **Leerlaufaufgabe** eine
Zeile hinzu (`ehci.poll`), und `tools/arch/order.sh` prüft unter anderem
`x86-64: idle -> hlt`. Das ist eine andere Sache — geprüft wird dort die
Maschinenanweisung hinter `machine__idle`, nicht die Aufgabe. Auf
`blech` einzeln gefahren: **`ORDER: 15 passed, 0 failed`.**

### Der eine echte rote Haken — und er gehörte dem Prüfer

Das ist die einzige rote Zusage dieser Runde, die keine Last und kein
Erbe war. Sie ist es wert, ausgeschrieben zu werden:

```
puffer:  5836 Zeichenketten, 1 passen nicht
    ZU ENG  kernel/ehci.fi:1319  t: das Literal ist 78 Oktette, der Puffer 26
  FAIL  spalten rc: '2', erwartet '0'
```

Zeile 1319 ist die Tabelle, die einen HID-Gebrauchscode in einen
PS/2-Abtastcode übersetzt: **sechsundzwanzig Oktette, keines davon ein
druckbares Zeichen**, also `"\x1e\x30\x2e…"`. Sie ist 26 Oktette breit,
und der Kern beweist es selbst — die Messung aus Teil 3 liest daraus
`23 1e 26 26 18 1c`, also genau die richtigen Codes.

`tools/i18n/spalten.py::oktette` sprang über **jeden** Escape mit
`i += 2`. Richtig für `\0`, `\n`, `\t` und `\\`; falsch für die
hexadezimale Form: von `\x1e` wurde `\x` als ein Oktett gezählt und `1`
und `e` danach als zwei weitere. Sechsundzwanzig davon ergeben 78.

**`kernel/ehci.fi` ist das erste Literal dieses Baums in dieser Form** —
deshalb ist der Fehler bis heute niemandem aufgefallen.

Behoben: `\x` gefolgt von zwei Hexziffern überspringt vier Zeichen.
Nachgerechnet an vier Fällen (26 × `\xNN` → 26 statt 78; `"abc\0"` → 4;
`"Größe\0"` → 8, das UTF-8 zählt weiter mit; `"a\\b\0"` → 4, der
doppelte Rückstrich bleibt ein Oktett). Der ganze Baum: **5836
Zeichenketten, 0 passen nicht, rc=0.**

**Und die Gegenprobe ist nicht entschärft.** Dasselbe Feld ein Oktett zu
klein deklariert (`[u8; 25]`), und der Prüfer wird sofort wieder rot:

```
ZU ENG  kernel/ehci.fi:1319  t: das Literal ist 26 Oktette, der Puffer 25
rc = 2
```

Er zählt jetzt richtig, und er zählt immer noch. Am Kern ändert sich
dabei nichts: das Abbild ist vor und nach der Reparatur 3 406 500
Oktett.

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

Und der neue Abschnitt der Runde, **im vollen Lauf**:
**`BLECH: 59 bestanden, 0 gefallen`** — dazu **`FB: 9 bestanden, 0
gefallen`** (`/root/blechlogs/FB-sweep.log`), **`SOFTUI: 25 / 0`**,
**`AHCI: 62 / 0`**, **`UPDATE: 49 / 0`**, **`PAINT: 36 / 0`**,
**`icons: 25 / 0`**, **`CORE: 46 / 0`**.

**Wie lange die Netzsperre gekostet hat**, weil es die Zahl erklärt, die
sonst niemand glaubt: der Abschnitt `tunnel` brauchte **3675 s, davon
3404 s Warten auf `/tmp/osum-netz.lock`** — 93 % der Zeit hat er auf
eine andere Runde gewartet.

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

### Am Prüfwerk

* `tools/metal/fb.sh` ist **nicht** in `test.sh` angemeldet. Der Läufer
  ist gebaut, gemessen und protokolliert, aber er fährt neun QEMU-Starts
  für eine Frage, die sich in der Abnahme nur selten ändert. Ob er dort
  hingehört, gehört in die Runde, die ihn zum ersten Mal braucht.
* Der EHCI-Tastaturteil des Läufers braucht **30 Sekunden Wartezeit**
  (acht Sekunden bis zum Fenster, sechs Tasten, zweiundzwanzig Sekunden
  Auslauf). Das ist mit dem QEMU-Monitor über `stdio` gemacht; die
  Runden K17 und WM benutzen dafür einen Monitor-**Socket** und ein
  Python-Skript (`tools/wm/monitor.py`), das auf eine gedruckte Marke
  wartet statt auf die Uhr. Der bessere Weg, und diese Runde ist ihn
  nicht gegangen.

### Und das Wichtigste

* **`rtl` und `hid` sind nicht in `main`.** Solange das so ist, hat ein
  gewöhnliches Consumer-Brett kein Netz und ein neueres Notebook keine
  eingebaute Tastatur — obwohl beide Treiber im Repository liegen und
  beide grün gemessen sind (67/0 und 57/0, siehe Teil 0). Das ist die
  billigste Verbesserung, die dieses Projekt gerade zu vergeben hat.

---

## DIE COMMITS DIESER RUNDE

| Commit | Was |
|---|---|
| `22d5756` | 1/n — `rootsel.fi`: die Wurzel wird gesucht statt geraten, und der RAID-Modus wird beim Namen genannt |
| `0fbe671` | 2/n — `ehci.fi`: der USB-2.0-Anschluss, mit einem Stick und einer Tastatur daran |
| `69851d8` | 3/n — NVMe mit mehr als einem Namensraum |
| `2d371e2` | 4/n — der Läufer der Runde, mit dem alten Kern als Vergleichsmaß |
| `3050776` | 5/n — der Rahmenpuffer über sieben Grafikkarten |
| `d521a26` | 6/n — `docs/RUNDE-BLECH.md` und `docs/REALHW.md` Teil C |
| `8851a72` | 7/n — zwei eigene Fehler im EHCI, beide erst mit ZWEI Geräten sichtbar |
| `0669796` | 11/n — der Pufferprüfer zählte `\xNN` als drei Oktette |
| *(übrige)* | 8–13/n — Messungen und Bericht, siehe `git log` |

**Kein Merge nach `main`.** Der Zweig `blech` bleibt stehen; das
Zusammenführen macht eine spätere Runde — zusammen mit `rtl` und `hid`,
die dringender sind als alles in dieser Runde.

---

# NACHTRAG: DIE VIER AUFTRAEGE DES EIGNERS

Nach der Abnahme oben hat der Eigner vier Dinge nachgeschoben. Drei
sind gebaut, einer ist BEGRUENDET ABBESTELLT worden -- von ihm selbst,
nachdem ich widersprochen hatte. Der Reihe nach.

## 1. RTL-Zweig geholt, und dabei fiel ein echter Fehler auf

Der Zweig `rtl` (RTL8169/8168) ist nach `blech` gebracht: 67 Pruefungen
gruen. Beim anschliessenden Anheben von `MAX_CARDS` von 2 auf 8 kam ein
Fehler heraus, den vorher niemand sehen konnte:

**JEDER Netztreiber rechnete seinen Meldevektor als `45 + u` mit SEINER
EIGENEN Einheitennummer.** Solange nur virtio existierte, war das
dieselbe Zahl wie die Kartennummer. Sobald aber zwei VERSCHIEDENE
Treiber je eine Karte haben -- ein Intel-Anschluss auf dem Brett und
eine Realtek-Karte im Steckplatz, der haeufigste Fall ueberhaupt --
waeren beide Einheit 0 und beide haetten Vektor 45 verlangt. `trap.fi`
gibt aber 45 an KARTE 0 und 46 an KARTE 1. Die zweite Karte haette ihre
Meldungen an die erste geschickt.

Behoben ueber `netdev.vector_for(c)`, das den Vektor nach KARTENNUMMER
vergibt und ihn in `init_on` durchreicht. Geaendert: vier Dateien.
NICHT geaendert: `inet.fi`, `netsvc.fi`, `share.fi`, `wg.fi`,
`netview.fi`, `trap.fi` -- also keine der 63 Aufrufstellen.

Gemessen, dieselbe Maschine, vier Karten:

    MAX_CARDS 2:   c0=e1000, c1=e1000, dann STILLE
    MAX_CARDS 8:   c0=e1000 vec=45
                   c1=e1000 vec=46
                   c2=r8169 abgefragt (kein Vektor frei)
                   c3=virtio-net abgefragt (kein Vektor frei)

Die zwei verschwundenen Karten sind der eigentliche Befund: `probe`
hoerte nach der zweiten auf zu zaehlen, OHNE es zu sagen.

`isr.s` hat weiter nur zwei Stuempfe (45, 46). Karte 2 bis 7 bekommen
deshalb KEINE Unterbrechung -- sie laufen trotzdem, weil `netd` den
Ring ohnehin abfragt, nur langsamer, UND DER KERN SAGT ES. Auf einem
fremden Brett ist "die dritte Karte ist langsam" ein Befund; "die
dritte Karte ist kaputt" waere ein Irrtum.

## 2. RTL8125/8126 als dritte Spielart -- mit sechs benannten Quellen

Keine neue Datei: der 8125 teilt mit dem 8169 den Deskriptor, beide
Ringe, das Ruecksetzen, den Empfangsfilter und die C+-Betriebsart --
also genau die achtzig Prozent, in denen die Fehler sitzen, und die
sind ueber VAR_CP in QEMU GEMESSEN.

Sechs Unterschiede, jeder mit seiner Quelle im Quelltext:
IMR/ISR 32 Bit auf 0x38/0x3C; Sendeanstoss auf 0x90; INT_CFG0 Bit 0;
MAC-OCP 0xEB58 Bit 0 zurueck auf das alte 16-Oktett-Deskriptorformat;
RSS_CTRL und Q_NUM_CTRL auf null; PHY hinter OCP.

Der letzte Punkt ist eine **bewusste Luecke**: dieser Treiber geht den
OCP-PHY-Weg NICHT, er liest die Verbindung nur aus PHYstatus. Ein
PHY-Weg, den niemand ausprobieren kann, ist schlimmer als keiner --
er schickt beim ersten Fehler die Suche in die falsche Richtung.

## 3. kernel/blkdev.fi -- Speicher bekommt die Form von netdev.fi

Der Eigner: *"Die Struktur ist bei Netz schon richtig -- bei Speicher
NICHT. Halte beide gleich."* Und: das sei mehr wert als ein weiterer
Netztreiber. Er hatte recht, und der Beweis stand im eigenen Bericht
der Runde MERGE-3: *"die automatische Treiberwahl beim Start ist nicht
gebaut"* -- es gab niemanden, der sie haette treffen koennen.

`kernel/blkdev.fi` ist die fehlende Schicht, Punkt fuer Punkt gegen
`netdev.fi` gebaut: `driver_for` (Tabelle), `reason_for` (warum nicht),
`probe`, `print_disks` (mit Nummern), `print_table` (Wort `blktab`,
ohne Platte), und ein Verteiler mit je Treiber DENSELBEN Namen.

Entschieden wird an der PCI-KLASSE und nicht an Hersteller/Geraet --
das ist der Unterschied zu Netz und der Grund dafuer: ein NVMe-Riegel
von Samsung und einer von WD haben verschiedene Nummern und DIESELBE
Klasse. Ein Treiber, der Nummern sammelt, kennt genau die Riegel, die
sein Schreiber besass.

Gemessen mit `blktab`, ohne eine einzige Platte im Rechner:

    blkdev: tab 01:08:02 -> nvme
    blkdev: tab 01:06:01 -> ahci
    blkdev: tab 01:06:00 -> none  SATA, aber nicht AHCI
    blkdev: tab 01:04:00 -> none  RAID-Modus -- im BIOS "SATA Mode" auf AHCI stellen
    blkdev: tab 01:07:00 -> none  SAS, kein Treiber
    blkdev: tab 08:05:01 -> none  SD/eMMC-Regler, kein Treiber

Und **eine Doppelung ist verschwunden**: `rootsel.fi` lief den Bus bis
dahin SELBST ab und fuehrte eine zweite Liste derselben Platten. Zwei
Listen laufen frueher oder spaeter auseinander. Jetzt findet und ordnet
`blkdev`, und `rootsel` entscheidet nur noch, welcher Bewerber
tatsaechlich eine Wurzel traegt.

`blk.fi`, `fs.fi`, `vfs.fi`, `fat.fi`, `part.fi`: keine Zeile geaendert.

## 4. igc/igb -- ABBESTELLT, und das war richtig

Der Eigner hatte I225/I226 und I210/I211 als Treiber bestellt. Ich habe
widersprochen, weil seine Reihenfolge seinem eigenen Satz widersprach
("lieber vier Karten, die wirklich laufen, als acht halbe"):

* Beim RTL8125 ging der Kompromiss auf -- er teilt ~80 % mit dem
  gemessenen 8169-Ring.
* Bei igc teilt er **nichts**: anderes Deskriptorformat (Advanced),
  andere Warteschlangenregister, anderer Unterbrechungsblock.
* QEMU 7.2 kennt weder `igb` noch `igc`. Es waere zu **100 % ungemessen**
  gewesen -- achthundert Zeilen ungepruefter KERNcode an der Stelle, an
  der ein Fehler das ganze System mitnimmt.

Er hat entschieden: **Nummern ja, Treiber nein.** Umgesetzt in
`kernel/chipname.fi`. Aus

    netdev: no driver for 0x8086:0x125c

wurde

    netdev: kein Treiber fuer I226-V (2,5G) (8086:125c)
      igc-Silizium: erweiterte Deskriptoren und anderer
      Warteschlangensatz -- eigener Treiber noetig, e1000 passt NICHT

Das ist keine Kosmetik. Wer vor einem fremden Brett steht, hat drei
Fragen: WAS steckt da, WARUM laeuft es nicht, KANN ICH ETWAS TUN. Die
Nummer allein beantwortet keine davon -- sie verlangt ein zweites Geraet
mit Netz, um sie nachzuschlagen, und genau das fehlt oft gerade dann.

Drei Regeln halten die Datei ehrlich:

1. **Die Nummern werden IMMER gedruckt**, auch wenn der Name bekannt
   ist. Der Name ist die Beigabe, die Nummer ist der Beweis -- irrt die
   Tabelle, sieht man es sofort.
2. **Wo der Name unsicher ist, steht nur der Hersteller.** "Broadcom
   (14e4:1686)" ist ehrlich und trotzdem brauchbar; ein erfundener
   Modellname waere schlimmer als gar keiner.
3. **Diese Datei entscheidet nichts.** Sie druckt. Eine Namenstabelle,
   die anfaengt mitzureden, ist ein Treiber im Versteck.

Gemessen mit echten Karten (`-device ne2k_pci -device pcnet
-device vmxnet3 -device tulip`):

    netdev: kein Treiber fuer Realtek (10ec:8029)
    netdev: kein Treiber fuer AMD (1022:2000)  fremder Hersteller, ...
    netdev: kein Treiber fuer VMware (15ad:07b0)  fremder Hersteller, ...
    netdev: kein Treiber fuer DEC/Intel tulip (1011:0019)  fremder Hersteller, ...

Und fuer Speicher:

    blkdev: d0=ahci bdf=0x30 Intel (8086:2922)
    blkdev: kein Treiber fuer MegaRAID (1000:0060)  -- RAID-Modus -- ...
    blkdev: kein Treiber fuer QEMU (1b36:0007)  -- SD/eMMC-Regler, ...

Fuer I225/I226/I210/I211 gibt es kein QEMU-Modell; dort ist `nictab`
der einzige moegliche Beweis -- und der laeuft (siehe
`blechlogs/NICTAB.txt`).

### Der Bauplan fuer igc, falls die Karte spaeter da ist

Damit die Arbeit nicht verloren ist, hier was ein igc-Treiber braucht
und was ihn vom gemessenen `e1000.fi` trennt:

* **Empfangsdeskriptor (Advanced, 16 Oktett):** Lesen `{ pkt_addr:u64,
  hdr_addr:u64 }`, Zurueckschreiben `{ info:u32, len_status:u32, ... }`.
  Der Legacy-Deskriptor von `e1000.fi` passt NICHT.
* **Sendedeskriptor (Advanced):** `{ addr:u64, cmd_type_len:u32,
  olinfo_status:u32 }` mit DTYP=3 und DEXT=1.
* **SRRCTL** je Warteschlange muss DESCTYPE auf "advanced one buffer"
  stellen -- ohne das liest der Chip den Legacy-Ring.
* **Warteschlangenregister** liegen bei 0x0C000 (Empfang) und 0x0E000
  (Senden) statt bei 0x02800/0x03800, mit RXDCTL/TXDCTL je Ring, deren
  ENABLE-Bit erst gesetzt UND zurueckgelesen werden muss.
* **Der Unterbrechungsblock** liegt bei igc auf 0x01500 ff. und nicht
  auf 0x000C0.

Ohne eine Karte oder ein QEMU mit `igc`-Modell bleibt das ungeprueft --
und ungeprueft gehoert es nicht in diesen Kern.

---

# NACHTRAG 2: DIE NAMENSTABELLE IST NACHGERECHNET — UND HAT EINEN TREIBERFEHLER MITGEBRACHT

Der Eigner hat auf meinen Widerspruch hin **Option 4 plus Option 2**
entschieden: vollständige PCI-Nummern mit Klarnamen, kein igc/igb-Treiber,
und die Ablehnung so nützlich wie möglich machen. Der Abschnitt „4.
igc/igb — ABBESTELLT" weiter oben beschreibt die Entscheidung. Dieser
Nachtrag beschreibt, was beim **Nachrechnen** herauskam — und das ist der
eigentliche Ertrag.

## Die Regel dieser Runde, in einem Satz

> Eine Tabelle, die niemand nachgerechnet hat, ist schlimmer als keine.
> Sie schickt den Menschen vor dem Brett in die falsche Richtung, und er
> glaubt ihr, weil sie so bestimmt klingt.

Deshalb hat jede Behauptung dieser Runde jetzt ein Werkzeug, das sie
widerlegen kann. Zwei sind neu.

## 1. `tools/metal/chipnames.py` — 14 falsche Namen gefunden

Das Werkzeug liest **jede** Namensbehauptung aus `kernel/chipname.fi`
und hält sie gegen `pci.ids` (Fassung 2026-09-02) und gegen die
Nummernlisten aus dem Linux-Quelltext.

**Erster Lauf: 40 richtig, 14 FALSCH, 6 ohne Beleg.** Die vier
schlimmsten:

| Nummer | stand da | ist wirklich | Quelle |
|---|---|---|---|
| `8086:02F0` u. 6 weitere | „Wi-Fi 6 AX201" | **CNVi-Anschluss**, nicht das Funkmodul | pci.ids |
| `1D6A:80B1` | „AQC107" | **AQC100S** | pci.ids + `aq_common.h` |
| `1969:E0B1` | „Killer E2600" | **Killer E2500** | pci.ids |
| `8086:125E` | „I225/I226" | **I221-V** | `igc_hw.h` |

Der CNVi-Fehler ist der gefährlichste. `8086:02F0` ist der
**Anschluss in der Brücke**, nicht die Karte: daran kann ein AX201, ein
AX203 oder ein Wireless-AC 9560 hängen, und *welches*, steht erst in der
Subsystemnummer — die dieser Kern nicht liest. Wer nach „AX201" sucht,
lädt die falsche Firmware. Jetzt sagt die Zeile, was wirklich bekannt
ist: `CNVi-WLAN (Modul erst am Subsystem lesbar)`.

**Der Prüfer prüft in beide Richtungen.** Mit den vier alten Namen wieder
eingesetzt fällt er mit Rückgabe 1 und nennt genau diese Zeilen; mit der
heilen Datei gibt er 0. Eine Lücke hat die Negativkontrolle dabei selbst
gezeigt: Nummern, die `pci.ids` nicht kennt, konnten beliebig heißen —
`8086:125E` ließ sich ungestraft „I226-V" nennen. Sie werden jetzt gegen
den **Linux**-Namen gehalten. Nach der Reparatur:

    Behauptungen im Quelltext : 181
    von pci.ids BESTAETIGT    : 173
    nur aus Linux belegt [L]  :   8
    igc-Nummern fehlend       :   0 von 16
    igb-Nummern fehlend       :   0 von 32
    I219-Nummern fehlend      :   0 von 53

Ein echter **Quellenkonflikt** bleibt und steht namentlich im Quelltext:
`8086:550B`. `pci.ids` trägt dort wortwörtlich denselben Text wie für
`550A` ein („Ethernet Connection (18) I219-LM") — für ein LM/V-Paar kann
das nicht stimmen. Linux sagt `I219_V18`. **Hier gilt Linux**, weil an
der LM/V-Unterscheidung im Treiber echtes Verhalten hängt (Management-
Engine) und diese Zeilen von Intel selbst kommen.

Nebenbei fand die Umstellung einen Fehler in `chipname.has_name`: sie
**druckte**, statt nur zu antworten. Die Namensfunktionen tragen jetzt
einen Schalter `say` — eine Nummernliste, zwei Verwendungen.

## 2. `tools/metal/r8125regs.py` — ein echter Treiberfehler

Für `VAR_8125` gibt es **keinen** Testlauf, der etwas widerlegen könnte:
QEMU 7.2 hat kein Modell des Chips. Es gibt nur eine Prüfmöglichkeit —
den Quelltext Zeile für Zeile gegen den Treiber halten, der auf echter
Hardware läuft. Das hat sich sofort gelohnt:

    r8169.fi, tx_kick:            w8(state, u, R_TPPOLL25, 64)
    Linux, rtl8169_doorbell:      RTL_W16(tp, TxPoll_8125, BIT(0))

Die **Adresse** war richtig aus Linux übernommen (0x90), **Breite und
Wert** aber vom alten Chip stehen geblieben (8 Bit, NPQ = Bit 6 = 0x40).

**Was das auf echtem Blech geheißen hätte:** Der Chip läuft an, die
Verbindung steht, der Empfang funktioniert — und es verlässt **kein
einziges Paket** die Karte, weil der Sendeanstoß nie ankommt. Kein
Absturz, keine Meldung, nur ein halb totes Gerät. Die unangenehmste
Sorte Fehler.

Und er ist ein Musterbeispiel für die Entscheidung des Eigners: Er
konnte hier **nicht** auffallen, weil dieser Zweig in QEMU nicht laufen
kann. Gefunden hat ihn erst der zeilenweise Abgleich — also genau das
Verfahren, das ungemessener Code *immer* braucht und **das bei 800 Zeilen
igc niemand durchhält.**

Der Prüfer vergleicht jetzt dauerhaft Adresse **und** Zugriffsbreite
**und** Wert:

    R_INTCFG0_25   0x34    INT_CFG0_8125     0x34    ok
    R_IMR25        0x38    IntrMask_8125     0x38    ok
    R_ISR25        0x3c    IntrStatus_8125   0x3c    ok
    R_TPPOLL25     0x90    TxPoll_8125       0x90    ok
    R_RSSCTRL25    0x4500  RSS_CTRL_8125     0x4500  ok
    R_QNUMCTRL25   0x4800  Q_NUM_CTRL_8125   0x4800  ok
    tx_kick  R_TPPOLL25  16 Bit  Wert 1   ok

**Eine Stelle bleibt ausdrücklich offen** und steht so im Werkzeug:
Wir schreiben `INT_CFG0` (0x34) Bit 0 = 1. Linux *upstream* definiert
`INT_CFG0_ENABLE_8125` als `BIT(0)`, **benutzt es aber nirgends** und
schreibt dort sogar `0x00`. Unser Wert stammt aus Realteks eigenem
r8125-Treiber. Ohne echte Karte ist nicht zu entscheiden, wer recht hat.
**Wenn eine RTL8125 später keine Unterbrechungen liefert, ist das die
erste Stelle zum Nachsehen.**

## 3. Wieviel vom Realtek-Treiber ist gemessen — die ehrliche Zahl

`kernel/r8169.fi`: **1413 Zeilen, davon 851 Code** (ohne Kommentar und
Leerzeile). Aufgeteilt nach Spielart:

| Spielart | eigene Blöcke | eigene Zeilen | Stand |
|---|---|---|---|
| `VAR_CP` (RTL8139C+) | 5 | 43 | **in QEMU gemessen**, Oktett für Oktett |
| `VAR_8169` (8168/8169/8111/8101) | 2 | 6 | aus dem Datenblatt |
| `VAR_8125` (8125/8126) | 7 | 42 | aus Linux, **nicht messbar** |
| gemeinsam | — | **≈ 760** | über `VAR_CP` gemessen |

**Was das heißt, ohne Beschönigung:**

* **RTL8168/8169:** Nur **6 Zeilen** in 2 Blöcken sind spielartspezifisch
  (MDIO-Zugriff über PHYAR statt über den 8139-internen PHY). Alles
  andere — Ringe, Deskriptorfelder, Rücksetzen, Empfangsfilter,
  Adressweg über IDR0/IDR4, C+-Betriebsart, Sende- und Empfangsweg — ist
  über `VAR_CP` **wirklich gemessen**. Das ist der Grund, warum ich diesen
  Zweig für belastbar halte. Er ist trotzdem **nie an einem echten 8168
  gelaufen**; was fehlt, ist die PHY-Initialisierung, die echte
  8168-Revisionen erwarten.
* **RTL8125:** **42 Zeilen in 7 Blöcken sind zu 100 % ungemessen.**
  Konkret sind es **sieben Registerzugriffe und ein MAC-OCP-Wort**:
  Deskriptorformat-Umschaltung (OCP 0xEB58 Bit 0), `RSS_CTRL`,
  `Q_NUM_CTRL`, `INT_CFG0`, `IMR` (32 Bit), `ISR` (32 Bit, zweimal),
  Sendeanstoß. Sechs Adressen sind gegen Linux geprüft, eine Breite und
  ein Wert waren **falsch** (siehe oben), eine Stelle bleibt offen. Die
  übrigen ~760 Zeilen, die der 8125 mitbenutzt, sind gemessen.

Also: **beim 8125 ist der Rahmen gemessen und der chipspezifische Kern
nicht.** Das ist besser als „alles ungemessen", und es ist deutlich
schlechter als „gemessen". Genau so steht es auch auf der seriellen
Leitung — `(8125/8126, Quelle, NICHT gemessen)`.

## 4. Ein Fund beim Bauen: `probe` war blind für WLAN

Beim Schreiben der Bestandsliste ist aufgefallen, dass `netdev.probe`
nur über **Klasse 02 Unterklasse 00** (Ethernet) läuft. Eine WLAN-Karte
ist **Klasse 02 Unterklasse 80** — sie kam in *keiner* Liste vor, weder
bei den Treibern noch bei den Abgelehnten. Sie wurde schlicht
**verschwiegen**. In einem Notebook ist sie oft das einzige Netzgerät.

`netdev.print_inventory` läuft deshalb über die **ganze** Klasse 02 und
fasst nichts an — `probe` bleibt, wie es ist, denn eine Suche, die
plötzlich WLAN-Karten beansprucht, wäre eine Regression in 54 grünen
Abschnitten. Gemessen mit `-device rocker`, dem einzigen
Klasse-02:80-Gerät in QEMU 7.2:

    netdev: bestand 00:03.0 8086:10d3 82574L (1G) -> e1000
    netdev: bestand 00:04.0 1b36:0006 QEMU -> kein Treiber (kein Ethernet-Port)
    netdev: bestand 2 geraete, 1 mit treiber, 1 ohne

Und mit gemischten Karten:

    netdev: bestand 00:03.0 10ec:8139 RTL8139 (100 MBit) -> r8169
    netdev: bestand 00:04.0 1022:2000 PCnet32 -> kein Treiber: other vendor, ...
    netdev: bestand 00:05.0 15ad:07b0 vmxnet3 -> kein Treiber: other vendor, ...
    netdev: bestand 3 geraete, 1 mit treiber, 2 ohne

## 5. Was mich zweimal erwischt hat — und die Regel daraus

Ich hatte in dieser Runde **zwei Zeilenanfänge eingedeutscht**:
`netdev: no driver for` → `netdev: kein Treiber fuer`, und die Gründe
von `igc silicon, ...` → `igc-Silizium: ...`. Hübscher — und **neun
grüne Zusagen in drei fremden Testdateien rot**
(`tools/rtl/run.sh`, `tools/hwnet/run.sh`, `tools/usbimg/run.sh`), ohne
dass sich am Verhalten das Geringste geändert hätte.

**Die Regel steht jetzt als Kommentar an beiden Zeichenketten:**

> Der Anfang der Zeile bleibt Wort für Wort der von Runde HWNET.
> Alles Neue hängt **hinten** dran. Wer die Liste für Menschen will,
> liest `print_inventory`.

Ergebnis — der Name ist da, und die Zusage auch:

    netdev: no driver for 0x10ec:0x8029  other vendor, no driver -- kein
    Treiber in diesem Kern  [RTL8029 (ne2000)]

Eine dritte Zusage kam dazu: für eine **erfundene** Nummer darf weder ein
Grund **noch ein Name** behauptet werden. `[unbekannter Hersteller]` ist
zwar wahr, aber es ist Text hinter `-> none`, und die RTL-Runde verbietet
das ausdrücklich. Wo nichts bekannt ist, gehört nichts hin.

## 6. BAUPLAN igc — was ein Treiber braucht

**Alle 16 Nummern** stehen bereits in `chipname.intel_igc` (Quelle:
`drivers/net/ethernet/intel/igc/igc_hw.h`). Ein Treiber müsste in
`netdev.driver_for` eine Zeile bekommen und `kernel/igc.fi` anlegen.
Verifiziert gegen `igc_regs.h`:

| Sache | e1000 (gemessen) | igc | Folge |
|---|---|---|---|
| Empfangsring | `RDBAL 0x02800` | **`0x0C000 + n*0x40`** | anderer Ort |
| Sendering | `TDBAL 0x03800` | **`0x0E000 + n*0x40`** | anderer Ort |
| `RXDCTL`/`TXDCTL` | — | `0x0C028` / `0x0E028` | ENABLE setzen **und zurücklesen** |
| `SRRCTL` | — | `0x0C00C + n*0x40` | DESCTYPE auf „advanced one buffer" |
| Unterbrechungen | `ICR 0x00C0`, `IMS 0x00D0` | **`EICR 0x01580`, `EIMS 0x01524`, `EIMC 0x01528`, `GPIE 0x01514`, `IVAR0 0x01700`** | anderer Block |
| MAC-Adresse | `RAL/RAH 0x05400/0x05404` | **gleich** | übernehmbar |
| PHY | `MDIC 0x00020` | **gleich** | übernehmbar |
| Deskriptoren | Legacy, 16 Oktett | **Advanced**: RX lesen `{pkt_addr:u64, hdr_addr:u64}`, zurückschreiben `{info:u32, len_status:u32,…}`; TX `{addr:u64, cmd_type_len:u32, olinfo_status:u32}` mit DTYP=3, DEXT=1 | **komplett neu** |

## 7. BAUPLAN igb — und der Befund, der ihn deutlich billiger macht

**Alle 32 Nummern** stehen in `chipname.intel_igb` (Quelle:
`drivers/net/ethernet/intel/igb/e1000_hw.h`).

**Wichtige Korrektur an meiner eigenen früheren Aussage:** Ich hatte
geschrieben, die Warteschlangenregister lägen bei igb wie bei igc auf
`0x0C000`/`0x0E000`. **Das stimmt nur für igc.** `igb/e1000_regs.h` sagt:

    #define E1000_RDBAL(_n)  ((_n) < 4 ? (0x02800 + ((_n) * 0x100)) : ...)
    #define E1000_TDBAL(_n)  ((_n) < 4 ? (0x03800 + ((_n) * 0x100)) : ...)
    #define E1000_SRRCTL(_n) ((_n) < 4 ? (0x0280C + ((_n) * 0x100)) : ...)
    #define E1000_RXDCTL(_n) ((_n) < 4 ? (0x02828 + ((_n) * 0x100)) : ...)

Für **Warteschlange 0** — und dieser Kern hat nur eine — liegen
Empfangs- und Senderingregister bei igb **an genau denselben Adressen
wie beim gemessenen e1000**. Dazu kommen `MDIC` und `RAL/RAH`
unverändert.

**Daraus folgt die Reihenfolge für später:** igb ist der deutlich
nähere Verwandte von `e1000.fi`. Es bleiben im Wesentlichen zwei
Unterschiede statt fünf:

1. **Der Unterbrechungsblock** — wie bei igc `EICR/EIMS/EIMC/GPIE/IVAR0`
   statt `ICR/IMS`.
2. **Die Deskriptoren** — Linux' igb setzt
   `E1000_SRRCTL_DESCTYPE_ADV_ONEBUF`, fährt also advanced. Ob die
   82576/I210-Reihe daneben noch einen Legacy-Modus beherrscht, habe ich
   **nicht** belegen können und behaupte es deshalb nicht.

Dazu eine Eigenheit, die einen Menschen sonst Stunden kostet: **I211 hat
keinen Flash** (iNVM), und **I210 gibt es flashlos** (`157B`/`157C`).
Wo die MAC-Adresse herkommt, ist dort nicht dasselbe wie beim e1000.

## 8. WAS AN MESSMÖGLICHKEIT FEHLT — der wichtigste Punkt

Für **beide** Familien gilt: In diesem Verzeichnis ist **kein Bit davon
prüfbar.**

* **QEMU 7.2.22** (die hier installierte Fassung, `qemu-system-x86_64
  --version`) hat **weder ein `igb`- noch ein `igc`-Modell**.
  `-device help` listet unter „Network devices" keines von beiden.
* **`igb` kam mit QEMU 8.0** als Gerät hinzu. Damit wäre der igb-Zweig
  messbar — Ringe, Deskriptoren, Unterbrechungen, gegen ein Wirtsabbild
  nachgerechnet, so wie es diese Runde mit EHCI und NVMe gemacht hat.
* **`igc` hat QEMU bis heute nicht.** Für I225/I226 bleibt nur **echte
  Hardware**.

**Daraus die zwei Aufträge, die jetzt fertig zugeschnitten sind:**

1. **Eigene Runde „QEMU 8.x bauen".** Voraussetzung für alles Weitere bei
   igb. In dieser Runde **nicht** gemacht, und das war richtig: die
   Platte stand auf 97 %, es liefen elf Runden parallel, ein QEMU-Bau
   hätte sie umgeworfen.
2. **Danach Runde „igb"** — mit QEMU 8.x als Messgerät, nach dem Bauplan
   in Abschnitt 7. **igc erst, wenn eine echte I225/I226 auf dem Tisch
   liegt.** Vorher wäre es genau der Blindflug, den der Eigner zu Recht
   abbestellt hat.

## 9. Zur Arbeitsweise: diese Aufgabe lief doppelt

Ehrlichkeitshalber und weil es Geld gekostet hat: **Derselbe Auftrag
wurde in zwei Chats parallel im selben Arbeitsbaum `/root/osum-blech`
bearbeitet.** Der andere Chat hat um 14:05 den Commit `19d31c8`
abgesetzt, der meine damals offenen Änderungen mitgenommen hat; beide
Commits tragen die Nummer „BLECH 20/n".

Inhaltlich ist nichts verloren gegangen — die Bäume waren
widerspruchsfrei zu vereinigen, und beide Fassungen kamen zur selben
Entscheidung. Aber: die falschen Chipnamen (`Killer E2600`,
`AQC107` für `80B1`) stehen noch in der **Commit-Nachricht** von
`19d31c8`; im Quelltext sind sie korrigiert. Für die Zukunft: **ein
Arbeitsbaum, ein Chat.**

## 10. DIE ABNAHME DES NACHTRAGS

Vier Abschnitte, alle einzeln gefahren, **keiner rot**:

| Abschnitt | vor dem Nachtrag | nach dem Nachtrag | Δ |
|---|---|---|---|
| `tools/metal/run.sh` | 60 / 0 | **72 / 0** | +12 Zusagen (Abschnitte 10 und 11) |
| `tools/rtl/run.sh` | 67 / 0 → zwischenzeitlich 66 / 1 | **67 / 0** | wiederhergestellt |
| `tools/hwnet/run.sh` | 54 / 1 | **56 / 0** | +2 Zusagen, rote weg |
| `tools/usbimg/run.sh` | 46 / 0 → seit dem `rtl`-Merge 45 / 1 | **48 / 0** | +3 Zusagen, Altlast repariert |

Belege: `blechlogs/NACHTRAG-ABNAHME-{blech,rtl,hwnet,usbimg}.log`

### Die zwei roten Haken, die der Nachtrag gefunden hat

**1. `usbimg` war seit dem `rtl`-Merge kaputt, und niemand hatte es
gesehen.** Die Zusage „eine fremde Karte wird als `no driver for`
gemeldet" benutzte `-device rtl8139`. QEMUs rtl8139 meldet
PCI-Revision 0x20, also den C+-Modus — **und genau den fährt
`r8169.fi` seit Runde RTL**, er ist dort sogar der einzige in QEMU
gemessene Zweig. Die Zusage verlangte seitdem „kein Treiber" von einer
Karte, für die es einen gibt.

Die volle Abnahme um 12:59 lief noch **vor** dem Merge und war deshalb
grün; danach ist `usbimg` bis jetzt nicht mehr einzeln gelaufen. Ein
Merge kann eine Zusage in einer *anderen* Runde entwerten, ohne dass
irgendetwas rot wird — das ist die eigentliche Lehre.

Repariert mit `ne2k_pci` (10EC:8029): derselbe Hersteller, aber ein Chip
ohne Ringe, den dieser Kern nie fahren wird. Dazu **eine Gegenprobe**,
die denselben rtl8139 als *gefahren* nachweist — ohne sie stünde dort
wieder eine Zusage, die nur zufällig grün ist.

**2. Die Zeilenanfänge sind dreimal gesprungen.** Siehe Abschnitt 5 und 9.

### Was jetzt bei jeder Abnahme mitläuft

`tools/metal/run.sh` Abschnitt 10 ruft die beiden Nachrechner auf. Ohne
sie wären beide Werkzeuge nach dieser Runde tote Dateien im Verzeichnis
— derselbe Fehler, den sich der Bericht bei `fb.sh` schon einmal
vorgeworfen hat. Ohne Netz **und** ohne zwischengespeicherte Vorlage
werden sie übersprungen und sagen das; ein Abnahmelauf darf nicht an
einer fehlenden Internetverbindung scheitern, aber er darf sie auch
nicht verschweigen.

Abschnitt 11 fährt den Bestand über `-device rocker` (Klasse 02:80) und
prüft die beiden Vertragszeilen **im eigenen Lauf** — ab jetzt fällt ein
versehentliches Übersetzen sofort hier auf und nicht erst in drei
fremden Testdateien.
