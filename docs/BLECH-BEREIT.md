<!-- SPDX-License-Identifier: GPL-2.0-only -->
# BLECH-BEREIT — was Osum auf einem echten Laptop kann, Geräteklasse für Geräteklasse

Stand **03.09.2026**, Zweig `main` nach Runde BLECH-ECHT. Gemessen auf dem
üblichen Wirt (AMD EPYC 7571, 12 Kerne, 19 GiB, `/dev/kvm`, QEMU 7.2.22).

**Die Regel dieser Datei, und sie gilt ohne Ausnahme:** jede Zeile sagt
**GEHT**, **GEHT NICHT** oder **UNGEMESSEN**, und daneben steht, woher
das kommt. „GEHT" heißt: es ist auf diesem Rechner gelaufen und die Zahl
steht in einem Protokoll. **„UNGEMESSEN" heißt ausdrücklich: nur QEMU,
nie auf echtem Blech gelaufen** — dieses Projekt hat kein Testbrett.

> Es gibt in diesem Repository **keine einzige Messung auf echter
> Hardware.** Alles unten ist QEMU, Quelltext oder Datenblatt. Wo eine
> Zeile „GEHT" sagt, heißt das „geht in QEMU, gemessen"; ob derselbe Chip
> in einem echten Laptop antwortet, steht in der Spalte daneben.

---

## 1. STARTEN — der Stick in einem fremden Rechner

| Was | Urteil | Beleg |
|---|---|---|
| **Vom Stick starten, BIOS/Legacy** | **GEHT** | Abbild als Platte gestartet (`-device ide-hd`), nicht mit `-kernel`: `hwdiag: firmware=BIOS`, voller Diagnosebericht. `tools/usbimg/run.sh`: **48 bestanden, 0 gescheitert** |
| **Vom Stick starten, UEFI** | **GEHT** | derselbe Stick unter OVMF: `hwdiag: firmware=UEFI`, kein „Cannot use text mode with UEFI", Rahmenpuffer von der Firmware (`fb 1280x800 src=multiboot`) |
| **Vom Stick starten, wenn der Stick an NVMe hängt** | **GEHT** | UEFI + `-device nvme,drive=stick`: gestartet, und der Kern meldet danach `hwdiag: disk NVMe bdf=0x20 1b36:0010` |
| **Vom Stick starten, wenn er an einem AHCI-Anschluss hängt** | **GEHT** | UEFI + `-device ahci` + `ide-hd,bus=ahci0.0`: gestartet, `hwdiag: disk AHCI bdf=0x20 8086:2922` |
| Partitionierung, die eine fremde Firmware akzeptiert | **GEHT** | GPT, EFI-Partition (EF00) mit `EFI/BOOT/BOOTX64.EFI`, `limine.conf`, `osum.mb`, `root.img`, `limine-bios.sys`; BIOS-Startteil im MBR-Bereich |
| **Auf einem echten Laptop starten** | **UNGEMESSEN** | **nur QEMU, nie auf echtem Blech gelaufen.** Es gibt keinen Rechner in diesem Projekt, auf dem der Stick je gesteckt hat |

---

## 2. NETZ

| Klasse | Urteil | Beleg / was fehlt |
|---|---|---|
| **Intel e1000 / 82540EM / 82574L** | **GEHT** (QEMU) | `netdev: bestand 00:03.0 8086:100e 82540EM (1G) -> e1000`; zwei Karten gleichzeitig: `c0=e1000`, `c1=e1000`. Ping, TCP, TLS 1.3 gemessen (`tools/hwnet/*`) |
| **Realtek RTL8168/8169/8111/8101** | **GEHT** (QEMU, über den C+-Modus des RTL8139) | `-device rtl8139` → `netdev: c1=r8169`. `tools/rtl/run.sh`: **67 bestanden, 0 gefallen** — 20/20 Pings, 262144 Oktett TCP, 6224 KiB/s, 0 Prüfsummenfehler. **Auf einem echten 8168: UNGEMESSEN** (der C+-Ringteil ist derselbe, die PHY-Firmwaretabellen der 8168-Ausführungen fehlen) |
| **Intel I217/I218/I219 (PCH, Business-Laptops)** | **UNGEMESSEN** | Der PCH-Zweig steht in `kernel/e1000.fi` (13 Gerätenummern), der Datenweg ist mit dem gemessenen e1000 geteilt, der Aufsetzweg kommt aus dem Datenblatt. **QEMU hat keinen I219** — nie gelaufen. Es fehlt `e1000_flush_desc_rings` (der bekannte Hänger auf Skylake+) |
| **Intel I225/I226 (2,5 G)** | **GEHT NICHT** | wird erkannt und **beim Namen genannt** (`-> none igc silicon, advanced descriptors`), aber es gibt keinen Treiber |
| **WLAN (alle)** | **GEHT NICHT** | Es gibt keine Zeile 802.11 in diesem Repository. AX200/AX201/AX210, MT7921, QCA6390 werden in der Tabelle als `wifi, needs 802.11 + fw` benannt und sonst nichts. **Du brauchst Kabel.** |
| Netzkarte, die keiner kennt | **GEHT** | wird als `no driver for 0x…` gemeldet, mit Namen wenn bekannt, und **der Kern läuft danach weiter** (gemessen mit `ne2k_pci`) |

---

## 3. PLATTE

| Klasse | Urteil | Beleg / was fehlt |
|---|---|---|
| **NVMe (M.2)** | **GEHT** (QEMU) | erkannt (`disk NVMe`), gestartet, gelesen; mehrere Namensräume in `tools/blech/run.sh` gemessen (**72 bestanden, 0 gefallen**). Auf echter M.2: **UNGEMESSEN** |
| **SATA/AHCI** | **GEHT** (QEMU) | `disk AHCI bdf=0x20 8086:2922`, Gegenprobe: derselbe Bericht meldet mit `-device ide-hd` noch `IDE`. `tools/ahci/run.sh` ist in der Abnahme. Auf echtem PCH-SATA: **UNGEMESSEN** |
| **SATA im RAID-Modus (Firmware-Einstellung)** | **GEHT** (als Meldung) | der Controller wird beim Namen genannt statt eine leere Plattenliste zu zeigen. Ein Treiber dafür gibt es nicht — **im BIOS auf AHCI stellen** |
| **IDE/ATA-PIO** | **GEHT** | `disk IDE bdf=0x9 8086:7010` |
| **Die Wurzel finden statt raten** | **GEHT** | `kernel/rootsel.fi`: NVMe, AHCI, USB, IDE der Reihe nach, und der erste, der wirklich trägt, gewinnt. Gegenprobe: mit einer IDE-Wurzel läuft die neue Suche **null** Mal |
| USB-Stick als Platte (EHCI/xHCI) | **GEHT** (QEMU) | EHCI als zweiter Regler neben xHCI, Blöcke vom Wirt nachgerechnet |

---

## 4. BILD

| Was | Urteil | Beleg |
|---|---|---|
| Rahmenpuffer von der Firmware (UEFI-GOP über Limine) | **GEHT** | `hwdiag: fb 1280x800 bpp=32 pitch=5120 src=multiboot` — die Auflösung kommt vom Lader, nicht geraten |
| Rahmenpuffer ohne Lader (Bochs/VBE-Register) | **GEHT** | `src=vbe`, `fb: selftest 13 / 13` |
| **Die Oberfläche füllt einen großen Schirm** | **GEHT NICHT** | **gemessen, 03.09.2026:** bei 1280x800 liegt der gezeichnete Inhalt nur in `24..650 × 40..443` — **49 % der Breite, 50 % der Höhe** —, und die Taskleiste ist unsichtbar, obwohl sie sich selbst richtig ausrechnet (`taskbar: geom edge=0 x=0 y=772 w=1280 h=28 shown=1`). Mit `fbres=800x600` füllt dieselbe Oberfläche den Schirm zu 100 %. Deshalb ist der Zweig `schirm` in dieser Runde **nicht** nach `main` gekommen — siehe `docs/RUNDE-BLECH-ECHT.md` |
| Echter GPU-Treiber, Beschleunigung | **GEHT NICHT** | und ist auch nicht geplant: der Weg über den Firmware-Rahmenpuffer trägt auf Intel, AMD und Nvidia gleichermaßen |

---

## 5. EINGABE

| Klasse | Urteil | Beleg / was fehlt |
|---|---|---|
| **PS/2-Tastatur und -Maus** | **GEHT** (QEMU) | `kernel/kbd.fi`, `kernel/ps2m.fi`; auf Desktops meist noch vorhanden, **auf vielen modernen Laptops nicht** |
| **USB-Tastatur/Maus, Boot-Protokoll** | **GEHT** (QEMU) | `-device usb-kbd`, Oktett für Oktett gegen den PS/2-Lauf |
| **USB-HID mit Berichtsbeschreibung** (NKRO, Zusatztasten, Geräte ohne Boot-Protokoll) | **GEHT** (QEMU) | `tools/hid/run.sh`: **57 bestanden, 0 gefallen**; der Zerleger wird gegen einen **zweiten** Zerleger gehalten |
| **Präzisions-Touchpad (Berichte)** | **GEHT** als Weg, **UNGEMESSEN** als Gerät | 34 Felder aus der von Microsoft vorgeschriebenen Beschreibung, +300 Geräteeinheiten → 100 Bildpunkte. **Kein QEMU-Gerät kann das** — gemessen ist der Weg, nicht ein Touchpad |
| **I²C-HID (Touchpad an I²C, viele Ultrabooks)** | **UNGEMESSEN** | `kernel/i2chid.fi` ist gebaut, **der ganze Designware-Registerteil stammt aus der Spezifikation**: QEMU hat keinen LPSS-I²C. Ohne AML-Interpreter wird das Gerät über einen Ersatzweg gesucht (0x0001, dann 0x0020) statt über `_DSM`/`_CRS` |
| Tastatur-LEDs, Feature-Reports | **GEHT NICHT** | keine Output-Reports |

---

## 6. REST

| Klasse | Urteil | Beleg / was fehlt |
|---|---|---|
| **ACPI: Tabellen, MADT, Abschalten** | **GEHT** (QEMU) | RSDP/RSDT/XSDT, Prozessoren, I/O-APIC, FADT |
| **ACPI: AML-Interpreter** | **GEHT NICHT** | kein `_PRT`, kein `_CRS`, kein `_DSM`, kein Deckelschalter, kein S3. Das PCI-Interrupt-Routing kommt aus dem Interrupt-Line-Register, das die Firmware gefüllt hat — **auf den meisten Brettern richtig, auf manchen nicht** |
| **Akku / Stromzustände** | **GEHT** (QEMU) | `kernel/batt.fi`, `kernel/pwr.fi`; `tools/powermon/run.sh` in der Abnahme |
| **Ton** | **GEHT NICHT** | kein HDA, kein AC97, keine Zeile |
| **TPM** | **GEHT NICHT** | für den Zweck nicht nötig |
| **Treiber nachladen (`.omod`, signiert)** | **GEHT** (QEMU) | `tools/modul/run.sh`: **74 bestanden, 0 gefallen** — Kern ohne PS/2-Maustreiber, Modul von der Platte geladen, Maus bewegt sich, Modul wieder entladen |
| **Update über das Netz (OTA)** | **GEHT** (QEMU) | Runde BETRIEB/MERGE-5: über den **Namen** `store.fleitec.com`, eigener DNS-Auflöser, echte Let's-Encrypt-Kette, signiertes Verzeichnis. **Aber nicht vom Stick** — siehe unten |
| **JARVIS-Brücke (`/bin/jarvisd`)** | **GEHT** (QEMU) | `tools/bridge/run.sh`: **113 bestanden, 0 durchgefallen**, gegen einen TLS-Server in Python, nicht gegen den echten Server. **Aber nicht vom Stick** |

---

## 7. WAS AUF DEM STICK FEHLT — und das ist eine kurze, konkrete Liste

Der Stick trägt **43 Ring-3-Programme**. Nicht darunter:
`ota`, `fetch`, `host`, `jarvisd`, `jsig`, `jarvisctl`, `pollbr`.

Das heißt in Klartext: **vom Stick aus kann Osum sich nicht selbst
aktualisieren, keine HTTPS-Seite holen und die JARVIS-Brücke nicht
starten** — obwohl der Kern das Netz kann und alle drei Programme im
Repository stehen und gemessen sind. Es fehlt eine Zeile Bauliste
(`PROGS` in `tools/usbimg/build.sh`) und der App-Bauweg, den
`tools/install/build.sh` schon hat. Das ist die kleinste und lohnendste
nächste Runde.

---

## 8. DIE ANTWORT AUF DIE FRAGE

**„Kann ich den Stick jetzt in einen Laptop stecken und es läuft?"**

**Nein — nicht verlässlich, und niemand kann heute sagen, ob es auf
deinem Laptop läuft, weil Osum noch auf keinem einzigen echten Rechner
gestartet ist.** Was gemessen ist, ist QEMU.

Was du erwarten darfst, wenn du es probierst:

* **Starten** wird er wahrscheinlich: BIOS und UEFI, von einem
  USB-Stick, von SATA und von NVMe — alle vier Wege sind mit demselben
  Abbild gefahren worden.
* **Netz:** nur mit **Kabel**. WLAN geht nicht, gar nicht. Hat der
  Laptop einen Realtek- oder Intel-e1000-Anschluss, stehen die Chancen
  gut; ein I225/I226 (2,5 Gbit) wird erkannt, aber **nicht gefahren**.
* **Platte:** NVMe und SATA/AHCI werden gefunden. Steht das BIOS auf
  **RAID** statt AHCI, siehst du keine Platte — dann im BIOS umstellen.
* **Tastatur/Touchpad:** Am Desktop mit PS/2 oder USB: geht. **Auf einem
  Ultrabook, dessen Touchpad an I²C hängt, ist es Glückssache** — der
  Weg ist gebaut, aber nie an echter Hardware gelaufen, und ohne
  AML-Interpreter wird das Gerät geraten statt gefragt.
* **Bild:** Du bekommst ein Bild in der Auflösung, die die Firmware
  setzt. **Die Oberfläche füllt es aber nicht** — sie sitzt in der
  oberen linken Ecke, und die Taskleiste ist nicht zu sehen (gemessen:
  49 % × 50 % bei 1280x800). Das ist der ehrlichste Satz dieser Datei:
  **so wie es heute ist, sieht der Schreibtisch auf einem großen Schirm
  kaputt aus.**
* **Selbst aktualisieren oder die JARVIS-Brücke starten:** vom Stick
  aus **nicht** — die Programme sind nicht drauf.

**Kurz:** zum Anschauen und Ausprobieren mit Kabelnetz ja; als System,
auf dem man arbeitet, nein.
