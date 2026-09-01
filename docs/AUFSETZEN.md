# Osum auf einen echten Rechner bringen

Diese Seite ist für **den Menschen vor dem Rechner** geschrieben, nicht
für einen Testläufer. Sie führt einmal von vorn bis hinten: Abbild
bauen, Stick schreiben, Firmware einstellen, starten, auf die Platte
installieren — und was zu tun ist, wenn der Bildschirm schwarz bleibt.

Der technische Hintergrund steht in `docs/USBSTICK.md` (Aufbau des
Abbilds, jede Zeile der Diagnose) und in `docs/REALHW.md` (welche
Hardware Osum bedienen kann). Diese Seite wiederholt davon nur, was man
**in der Hand** braucht.

> **Vorher lesen: Abschnitt 8.** Dort steht, welche Hardware Osum
> *nicht* bedienen kann. Wer eine Realtek-Netzkarte, ein Laptop mit
> I²C-Tastatur oder einen SATA-Controller im RAID-Modus hat, sollte das
> **vor** dem ersten Versuch wissen und nicht danach.

---

## 1. Was gebraucht wird

| | |
|---|---|
| USB-Stick | mindestens **256 MiB**; alles darauf wird gelöscht |
| Zielrechner | x86-64, mit BIOS **oder** UEFI |
| Zum Bauen | ein Linux mit `sgdisk`, `mkfs.vfat`, `mtools` (`mcopy`, `mmd`), `python3`, `as`, `ld` und Limine |
| Optional | Nullmodemkabel oder ein Mainboard mit COM1-Pfostenstecker — dann lässt sich der Bericht mitlesen statt abfotografieren |

---

## 2. Das Abbild bauen

```sh
cd /pfad/zu/osum
bash tools/usbimg/build.sh /tmp/usbimg
```

Heraus kommt `/tmp/usbimg/osum-usb.img`.

Das Skript baut **alles** neu: den Übersetzer, den Kern, die Programme
für Ring 3, die Symbole, das OFS-Dateisystem — und liest das fertige
Dateisystem danach mit `mkfs.py list` zurück und bricht ab, wenn auch
nur einer der Pflichtpfade fehlt (Sprachdateien, die drei Schriften, die
elf Symbole, `/bin/desktop`, `/boot/osum.mb`). Das ist Absicht: in der
Runde davor fehlten die Sprachdateien im Abbild, und der Fehler sah wie
einer des Zeichenwerks aus.

Liegt Limine woanders:

```sh
LIMINE_DIR=/pfad/zu/limine bash tools/usbimg/build.sh /tmp/usbimg
```

**Gemessen in dieser Runde (MERGE-3, 01.09.2026), Stand `main` nach dem
Merge:**

| | |
|---|---|
| Abbild | `osum-usb.img`, **123 731 968 Oktette** (118 MiB) |
| SHA-256 | `1bf0609d12be8830f7ed59580f1a77a5e79ff83c1aaf117a6b914981b4df1031` |
| Kern | 3 313 608 Oktette |
| Programme in Ring 3 | 43 |
| Wurzeldateisystem | 20 971 520 Oktette, OFS v3 |
| Aufteilung | GPT: EFI-Partition 96 MiB (`OSUM-EFI`, EF00) + Wurzel 21 MiB (`OSUM-ROOT`, 8300) |
| Pflichtpfade nachgezaehlt | 24 |
| Umlaute im Wurzelabbild | 126 UTF-8-Folgen |

Der Streuwert gilt fuer **dieses** Abbild. Wer neu baut, bekommt einen
anderen, sobald sich eine Zeile Quelltext geaendert hat -- das ist kein
Fehler, sondern der Zweck der Zahl.

---

## 3. Auf den Stick schreiben

**Erst nachsehen, welches Gerät der Stick ist.** `dd` auf die falsche
Platte ist nicht rückgängig zu machen — es gibt keine Rückfrage und
keinen Papierkorb.

```sh
lsblk -o NAME,SIZE,MODEL,TRAN,MOUNTPOINTS
```

Der Stick ist der mit `TRAN=usb` und der passenden Größe. Zur Sicherheit
ein zweites Mal schauen, **nachdem** man ihn abgezogen und wieder
eingesteckt hat: das Gerät, das dazukommt, ist er.

```sh
sudo umount /dev/sdX*            # falls etwas eingehängt ist
sudo dd if=/tmp/usbimg/osum-usb.img of=/dev/sdX \
        bs=4M conv=fsync oflag=direct status=progress
sync
```

Die Merkzeichen, und warum jedes davon dasteht:

| Merkzeichen | Wozu |
|---|---|
| `of=/dev/sdX` | die **ganze Platte**, nicht `/dev/sdX1`. Das Abbild bringt seine eigene Partitionstafel mit; auf eine Partition geschrieben startet es nie |
| `bs=4M` | ohne das schreibt `dd` in 512-Oktett-Häppchen und braucht das Zehnfache an Zeit |
| `conv=fsync` | `dd` kehrt erst zurück, wenn die Oktette wirklich auf dem Stick sind, nicht wenn der Kern sie angenommen hat |
| `oflag=direct` | am Seitenzwischenspeicher vorbei; zusammen mit `conv=fsync` ist der Fortschrittsbalken dann auch die Wahrheit |
| `status=progress` | zeigt den Fortschritt |
| `sync` danach | der Gürtel zum Hosenträger. Erst danach den Stick abziehen |

**Windows:** Rufus im Modus „DD-Image" oder balenaEtcher. Nicht „ISO-Modus" —
das Abbild ist kein ISO.

**Gegenprobe, wenn man ganz sicher gehen will** (liest zurück, was
geschrieben wurde, und vergleicht):

```sh
sudo dd if=/dev/sdX bs=4M count=<Größe in MiB> iflag=direct 2>/dev/null \
  | head -c $(stat -c%s /tmp/usbimg/osum-usb.img) | sha256sum
```

Der Streuwert muss der des Abbilds sein.

---

## 4. Was in der Firmware eingestellt sein muss

Ins Firmware-Menü kommt man beim Einschalten mit `Entf`, `F2`, `F10`
oder `Esc` — je nach Hersteller. **Vier Punkte**, und der dritte ist
der, den die meisten vergessen:

| Einstellung | Wert | Warum |
|---|---|---|
| **Secure Boot** | **Disabled** | Limine ist nicht von Microsoft signiert. Bleibt Secure Boot an, weigert sich die Firmware, `BOOTX64.EFI` zu starten — meist wortlos oder mit „Security Violation" |
| **CSM / Legacy Boot** | nach Bedarf | Der Stick kann **beides**. Steht er im Bootmenü zweimal, einmal mit `UEFI:` davor und einmal ohne, funktionieren beide. Startet auf dem UEFI-Weg nichts, CSM einschalten und den Eintrag **ohne** `UEFI:` nehmen |
| **SATA Mode** | **AHCI** | Der wichtigste Punkt, wenn die Platte gefunden werden soll. `RAID` (Intel RST) kann Osum **nicht** — dann findet es keine Platte. `IDE`/`Legacy` geht, ist aber langsam und deckt nur 128 GiB ab. **Achtung:** ein bereits installiertes Windows startet nach dem Wechsel von RAID auf AHCI unter Umständen nicht mehr, bis man ihm den Treiber beibringt |
| **Fast Boot** | aus | Sonst überspringt die Firmware die USB-Aufzählung, und der Stick taucht im Bootmenü gar nicht erst auf |

Dazu, wenn vorhanden: **USB Legacy Support / XHCI Hand-off** anlassen
(Standard). Osum bringt seinen eigenen xHCI-Treiber mit, aber der
Bootlader läuft noch mit der Firmware.

Das Bootmenü selbst öffnet man beim Einschalten mit `F12`, `F11`, `F8`
oder `Esc`.

---

## 5. Der erste Start

Nach dem Start kommt das Limine-Menü mit **drei Einträgen** und **10
Sekunden** Bedenkzeit:

| Eintrag | Was er tut |
|---|---|
| **1 — Hardware-Diagnose (bleibt stehen)** | *Der Eintrag, mit dem man anfängt.* Druckt den Bericht und hält an. Nichts läuft weiter, nichts wird geschrieben, keine Platte wird angefasst. Ablesen oder fotografieren, dann ausschalten |
| **2 — Diagnose und danach der Schreibtisch** | Derselbe Bericht, danach fährt die Oberfläche hoch. Der Bericht steht dann nur noch auf der seriellen Leitung |
| **3 — Nur der Schreibtisch (deutsch)** | Ohne Diagnose. Das ist der Vorgabe-Eintrag |

**Es wird nichts geschrieben und nichts installiert**, solange man nicht
selbst `install --ja` eintippt. Der Stick verändert die Festplatte des
Rechners von sich aus nicht.

### Was der Bericht sagt

```
hwdiag: ==================== OSUM HARDWARE-DIAGNOSE ====================
hwdiag: firmware=BIOS  vgarom=0xc0000  smbios=0xf59f0  rsdp=0xf59d0
hwdiag: cpu vendor=AuthenticAMD  hersteller=AMD
hwdiag: cpu family=23  model=1  stepping=2  maxleaf=0xd
hwdiag: mem usable=523775 KiB  top=0x1ffe0000  frames=131072
hwdiag: fb 800x600  bpp=32  pitch=3200  src=vbe  phys=0xfd000000
hwdiag: pci devices=6
hwdiag: pci 00:01.1 8086:7010  class=01 sub=01 prog=80
hwdiag: disk IDE    bdf=0x9 8086:7010
hwdiag: net -- was netdev daraus macht:
netdev: c0=e1000 bdf=0x18
hwdiag: ==================== ENDE DER DIAGNOSE ========================
hwdiag: ANGEHALTEN. Der Bildschirm bleibt so stehen.
```

Die fünf Zeilen, auf die es ankommt, und was sie bedeuten, stehen
ausführlich in `docs/USBSTICK.md`, Abschnitt 6. Kurz:

* **`firmware=`** — `BIOS` oder `UEFI`, gemessen an drei Spuren, die
  alle drei roh danebenstehen. Ein Befund, kein Beweis.
* **`fb …`** — steht dort `fb=KEINER`, hat die Oberfläche auf diesem
  Gerät nichts zum Zeichnen. Dann bleibt nur der serielle Weg.
* **`disk …`** — `NVMe` oder `AHCI`: Osum kann sie. `IDE`: geht, aber
  nur bis 128 GiB. `disk=KEINER`: SATA-Modus in der Firmware prüfen
  (Abschnitt 4).
* **`netdev: no driver for 0x….0x….`** — genau diese Zeile abschreiben.
  Sie nennt Hersteller und Gerät der Karte, für die ein Treiber fehlt.
* **Der Kern hängt in keinem dieser Fälle.** Findet er keine Platte und
  keine Karte, sagt er das und läuft weiter.

### Wo die serielle Ausgabe herauskommt

COM1, **0x3F8, 115200 8N1**, immer, ohne Schalter. Auf dem zweiten
Rechner `screen /dev/ttyUSB0 115200` oder `picocom -b 115200
/dev/ttyUSB0`. Ein USB-zu-Seriell-Adapter **am gemessenen Rechner**
nützt nichts — der Kern kennt nur das alte Tor 0x3F8.

---

## 6. Auf die Festplatte installieren

Erst wenn die Diagnose eine Platte gefunden hat (`disk NVMe` oder
`disk AHCI` oder `disk IDE`), lohnt der nächste Schritt. Eintrag 2 oder
3 im Menü wählen, im Terminalfenster des Schreibtischs:

```sh
install                     # zeigt die gefundenen Platten, schreibt NICHTS
install /dev/hda            # PROBELAUF: zeigt, was geschrieben würde
install /dev/hda --ja       # jetzt wirklich
```

**Ohne `--ja` wird nichts geschrieben.** Der Probelauf ist kein
Höflichkeitsschritt: er zeigt die Partitionsgrenzen, die geschrieben
würden, und die Platte bleibt dabei Oktett für Oktett unberührt (das ist
gemessen, `tools/install/run.sh`).

Was `install --ja` tut, in dieser Reihenfolge: Schutz-MBR, GPT-Tafel mit
beiden CRC32-Summen und Sicherungskopie am Plattenende, EFI-Partition
mit FAT32, Wurzelpartition mit dem Dateisystem, das gerade läuft, und
zum Schluss wächst das Dateisystem auf die Größe der Partition.

**Zwei Dinge, die man vorher wissen muss:**

1. **`install` schreibt KEINEN BIOS-Bootsektor.** Die installierte
   Platte startet **nur über UEFI** — die Firmware sucht
   `/EFI/BOOT/BOOTX64.EFI` auf der EFI-Partition. Wer den Rechner im
   CSM-Modus betreibt, startet danach nicht von der Platte. Der *Stick*
   kann beide Wege, die *Platte* nur einen.
2. **Die Platte wird vollständig überschrieben.** Es gibt kein
   „daneben installieren", keine Partitionsverkleinerung, kein
   Bootmenü mit dem alten System.

Nach dem Neustart (Stick abziehen, UEFI-Eintrag der Platte wählen) muss
in der seriellen Ausgabe eine Zeile wie

```
osum: rootpart=1  first=72048  blocks=452207
```

stehen, und `osum: from module` darf **nicht** mehr vorkommen — dann
läuft das System wirklich von der Platte und nicht mehr aus dem
Boot-Modul.

---

## 7. Wenn der Bildschirm schwarz bleibt

Der Reihe nach, von der wahrscheinlichsten Ursache zur
unwahrscheinlichsten. Nach jedem Schritt neu versuchen.

**a) Es kommt gar kein Limine-Menü.**

1. Steht der Stick überhaupt im Bootmenü? Wenn nein: **Fast Boot aus**,
   anderen USB-Anschluss nehmen (bei Desktops die **hinteren** Anschlüsse
   direkt am Brett, nicht die vorderen am Gehäuse), Stick neu schreiben.
2. **Secure Boot aus.** Das ist die häufigste Ursache dafür, dass ein
   UEFI-Eintrag da ist und trotzdem nichts passiert.
3. Steht der Stick zweimal da: den **anderen** Eintrag nehmen (mit bzw.
   ohne `UEFI:`).
4. Kein UEFI-Eintrag vorhanden: **CSM/Legacy einschalten** und den
   Eintrag ohne `UEFI:` nehmen.
5. Kam beim Schreiben eine Fehlermeldung, oder wurde auf `/dev/sdX1`
   statt `/dev/sdX` geschrieben? Dann noch einmal, Abschnitt 3.

**b) Das Limine-Menü kommt, danach bleibt es schwarz.**

Dann startet der Kern, und es ist eine Bildschirmfrage. Der Kern
schreibt in diesem Fall **trotzdem** alles auf COM1 — der Bildschirm ist
nur eine Kopie.

1. Eintrag **1 (Diagnose, bleibt stehen)** nehmen. Kommt dort Text, war
   es der Fensterserver und nicht der Start.
2. Steht im Bericht `fb=KEINER`, hat der Lader keinen Rahmenpuffer
   übergeben: über den **UEFI**-Weg starten statt über CSM. Der
   UEFI-GOP-Rahmenpuffer ist der zuverlässige Weg; unter reinem BIOS
   muss der Kern ihn sich über VBE selbst suchen, und das gelingt nicht
   auf jeder Karte.
3. Externen Bildschirm abziehen bzw. anstecken — Osum hat keinen
   GPU-Treiber und schaltet nichts um; es zeichnet in genau den
   Rahmenpuffer, den die Firmware hinterlassen hat. Bei Notebooks mit
   umschaltbarer Grafik im Firmware-Menü auf die **integrierte** Grafik
   stellen.

**c) Text kommt, aber die Maschine hängt an einer bestimmten Zeile.**

Die letzte Zeile ist der Befund — abfotografieren. Der Bericht steht
**vor** allem, was ein Gerät wirklich hochzieht (`hwdiag` läuft in
`kernel_main` vor `netsvc.stage`, `hw.disk` und `usb_stage`), also sagt
schon die Diagnose, welches Gerät als nächstes drankam.

**d) Tastatur tut nichts.**

Bei vielen neueren Notebooks hängt die Tastatur an einem **I²C-HID**-Gerät,
und dafür gibt es keinen Treiber (Abschnitt 8). Abhilfe: eine
**USB**-Tastatur anstecken — die geht über das HID-Boot-Protokoll. Für
den Diagnose-Eintrag braucht man gar keine Tastatur.

**e) Gar nichts hilft.**

Auch das ist ein Befund. Bitte notieren, **wie weit** es kam:
Firmware-Menü / Limine-Menü / schwarz nach dem Menü / eine Meldung von
Limine, und was auf dem Bildschirm zuletzt stand.

---

## 8. Was Osum an Hardware NICHT kann

Aus dem Quelltext gelesen, Stand dieser Runde. Die vollständige Fassung
mit Begründung je Zeile steht in `docs/REALHW.md`.

### Netzkarten

| | |
|---|---|
| **Geht** | virtio-net (`1AF4:1000`/`1041`, nur virtuell) und Intel 8254x/82574: **`8086:100E, 100F, 1015, 1026, 1028, 10D3`** — mehr nicht |
| **Geht NICHT** | **Realtek RTL8168/8169/8125** (`10EC:8168/8125`) — der häufigste Chip auf Consumer-Brettern überhaupt. **Intel I217/I218/I219** (`8086:153A, 155A, 15B7, 15B8, 0D4E …`) — auf fast jedem Business-Notebook; der PHY hängt an der Management-Engine und braucht einen Handschlag, den dieser Treiber nicht macht. **Intel I210/I211/I225/I226** (igb/igc, anderes Deskriptorformat). Broadcom, Aquantia, Marvell |
| **WLAN** | **gar nichts.** Kein 802.11, kein Firmwareladen, kein WPA. Intel AX200/AX201/AX210, MediaTek MT7921, Qualcomm QCA6390: alle nicht |
| **Bluetooth** | gar nichts |

Jede nicht unterstützte Karte wird **mit ihren Nummern genannt**
(`netdev: no driver for 0x10ec:0x8168`) — sie ist also nicht still,
sondern benannt.

### Massenspeicher

| | |
|---|---|
| **Geht** | NVMe (`01:08:02`, herstellerunabhängig durch die Spezifikation), SATA im **AHCI**-Modus (`01:06:01`), IDE/ATA-PIO (`01:01:xx`), USB-Massenspeicher (BOT + SCSI über xHCI) |
| **Geht NICHT** | **SATA im RAID-Modus** (`01:04:xx`, Intel RST / AMD RAIDXpert) — dann findet Osum keine Platte, Firmware auf AHCI stellen. **eMMC und SD-Karten** (viele billige Notebooks und Tablets booten von eMMC). **SCSI/SAS**. **NVMe mit mehr als einem Namespace** — nur der erste wird benutzt |
| **Grenze IDE** | LBA28, also **128 GiB**. Eine 1-TB-Platte im IDE-Modus erscheint als 128 GiB. Im AHCI-Modus gilt diese Grenze nicht |
| **Und** | die **automatische Treiberwahl beim Start ist nicht gebaut** — welches Gerät die Wurzel trägt, entscheidet die Kommandozeile bzw. das Installationsprogramm |

### Grafik

| | |
|---|---|
| **Geht** | genau **ein** Weg: der lineare Rahmenpuffer, den die Firmware hinterlässt (UEFI-GOP über Limine, Multiboot-Flag-Bit 12), ersatzweise die Bochs-/QEMU-Register `0x1CE/0x1CF` oder die PCI-BAR der Karte |
| **Geht NICHT** | **kein einziger GPU-Treiber.** Kein Intel i915, kein AMDGPU, kein Nouveau/Nvidia. Kein KMS, keine Modus-Umschaltung auf echter Hardware, keine 2D-/3D-Beschleunigung, kein Video-Dekoder, keine Helligkeitsregelung, kein Hot-Plug an DisplayPort/HDMI, **kein zweiter Bildschirm** |
| **Folge** | Die Auflösung ist die, die die Firmware gesetzt hat. Umschaltbare Grafik (Optimus/Switchable): auf die integrierte stellen |

### Eingabe

| | |
|---|---|
| **Geht** | PS/2-Tastatur und -Maus über den 8042 (Port 0x60, IRQ 1) — auf Desktops fast immer noch vorhanden. USB-Tastatur und -Maus über **xHCI** und das **HID-Boot-Protokoll** |
| **Geht NICHT** | **I²C-HID** — daran hängen bei vielen neueren Notebooks die eingebaute Tastatur **und** das Touchpad. **Präzisions-Touchpads** (melden über Report-Deskriptoren, nicht über das Boot-Protokoll). Keine HID-Report-Deskriptoren überhaupt. **EHCI/UHCI/OHCI** — reine USB-2.0-Anschlüsse an Rechnern vor etwa 2012 werden nicht bedient, nur xHCI |

### Sonstiges

| | |
|---|---|
| **Ton** | **gar nichts.** Kein HD-Audio, kein AC'97, kein Codec |
| **ACPI** | RSDP/RSDT/XSDT, MADT und FADT werden gelesen. **Kein AML-Interpreter** — also kein `_PRT` (das Interrupt-Routing der PCI-Steckplätze kommt stattdessen aus dem Interrupt-Line-Register, das die Firmware ausgefüllt hat: auf den meisten Brettern richtig, auf manchen nicht), kein `_CRS`, keine Thermalzonen-Ereignisse, **kein Deckelschalter**, **kein sauberes S3** |
| **TPM** | nichts. Weder TIS noch CRB, keine PCR, kein Versiegeln |
| **Akku** | wird über die ACPI-Tabellen gelesen (`kernel/batt.fi`); ohne AML fehlen die Ereignisse |
| **Drucken, Kamera, Fingerabdruck, Thunderbolt, SD-Leser** | nichts davon |

### Die kurze Antwort

Am besten stehen die Chancen auf einem **Desktop mit UEFI, NVMe- oder
SATA-Platte im AHCI-Modus, Intel-Netzkarte der 8254x-Familie oder gar
keinem Netz, PS/2- oder USB-Tastatur und der Grafik der Firmware**.

Am schlechtesten auf einem **neueren Notebook**: Realtek- oder
I219-Netzkarte, I²C-Tastatur und -Touchpad, umschaltbare Grafik. Dort
kommt die Diagnose durch — und genau dafür ist sie da —, aber Netz und
eingebaute Tastatur werden fehlen.
