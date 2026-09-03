<!-- SPDX-License-Identifier: GPL-2.0-only -->
# BLECH-BEREIT — was Osum auf einem echten Laptop kann, Geräteklasse für Geräteklasse

Stand **03.09.2026**, Zweig `main` nach Runde **BLECH-HID** (davor:
STICK, BLECH-ECHT). Gemessen auf dem üblichen Wirt (AMD EPYC 7571,
12 Kerne, 19 GiB, `/dev/kvm`, QEMU 7.2.22) — **und, zum ersten Mal in
diesem Projekt, auf einem echten Rechner.**

**Die Regel dieser Datei, und sie gilt ohne Ausnahme:** jede Zeile sagt
**GEHT**, **GEHT NICHT** oder **UNGEMESSEN**, und daneben steht, woher
das kommt. „GEHT" heißt: es ist gelaufen und die Zahl steht in einem
Protokoll. **„UNGEMESSEN" heißt ausdrücklich: nur QEMU, nie auf echtem
Blech gelaufen.** Neu seit dieser Runde: **„GEHT (BLECH)"** heißt, dass
es auf Justins Rechner gelaufen ist und die Zeile aus einem Foto seines
Bildschirms stammt.

---

## 0. DER ERSTE ECHTE RECHNER — 03.09.2026

Bis zu diesem Tag stand hier: *„Es gibt in diesem Repository keine
einzige Messung auf echter Hardware."* Der Satz ist nicht mehr wahr.

**Die Maschine:** AMD-Plattform (PCI-Hersteller `1022`, unter anderem
`1482/1483/1484/1485/1486/1487/148a/149c/43c8/43d5`), NVIDIA GA106
(`10de:2504`) mit HDMI-Ton (`10de:228e`), Huawei-Ultrawide-Bildschirm.
Start über **UEFI** vom USB-Stick, Abbild aus Runde STICK.

**Was gemessen wurde — jede Zeile ein Foto des Bildschirms:**

| Befund | Zeile vom Blech |
|---|---|
| NVMe erkannt | `hwdiag: disk NVMe bdf=0x100 c0a9:5426` |
| SATA/AHCI erkannt | `hwdiag: disk AHCI bdf=0x201 1022:43c8` |
| Wurzelsuche, vier Blockgeräte | `blkdev: reihenfolge: nvme > ahci > usb > usb`, `d0..d3` |
| **zwei** xHCI-Regler | `rootsel: usb xHCI bdf=0x200 1022:43d5`, `rootsel: usb xHCI bdf=0xc03 1022:149c` |
| **Realtek 8168, Treiber bindet** | `netdev: bestand 09:00.0 10ec:8168 RTL8111/8168/8411 -> r8169`, `bestand 1 geraete, 1 mit treiber, 0 ohne` |
| Schutzbits, Vektoreinheit, Zeitgeber | `guard: cr4=0x340620 smep=1 smap=1 cpu=1/1`, `fpu: mode=3 xcr0=0x7`, `ticks: 24 traps=25` |
| Rahmenpuffer über die volle Breite | der blaue Hintergrund füllt den **ganzen** Ultrawide-Schirm |
| Fenster | „Terminal -- sh" mit Rahmen, Titel und Schließknopf, korrekt gezeichnet |
| kein Absturz, keine Panik, keine unbekannte Hardware | die Diagnose lief vollständig durch und hielt sauber an |

**Und was nicht ging:** keine Eingabe (Maus leuchtete nicht einmal,
Tastatur tot — im Startmenü des Laders ging sie), die Taskleiste war
unsichtbar, und der Mauszeiger war kein Pfeil. Alle drei sind in Runde
BLECH-HID bearbeitet; was daran gemessen ist und was nicht, steht in
`docs/RUNDE-BLECH-HID.md`.

**Das Abbild, auf das sich diese Tafel bezieht:** gebaut aus dem Zweig
`blechhid` (Runde BLECH-HID), 123 731 968 Oktette,
SHA-256 `a37098b983784875e7e484a329d496ba63d7654c700d98800c2e6082c37e34c0`,
ausgeliefert als `/srv/store/abbilder/osum-usb.img` (daneben
`osum-usb.img.sha256`).
Ein zweiter Baulauf aus demselben Baum gibt eine andere Prüfsumme —
`mkfs.vfat` schreibt eine Datenträgernummer aus der Uhr in die
EFI-Partition (gemessen: sechs abweichende Oktette). Wer eine bestimmte
Datei meint, meint ihren SHA.

---

## 1. STARTEN — der Stick in einem fremden Rechner

| Was | Urteil | Beleg |
|---|---|---|
| **Vom Stick starten, BIOS/Legacy** | **GEHT** | Abbild als Platte gestartet (`-device ide-hd`), nicht mit `-kernel`: `hwdiag: firmware=BIOS`, voller Diagnosebericht. `tools/usbimg/run.sh`: **48 bestanden, 0 gescheitert** |
| **Vom Stick starten, UEFI** | **GEHT** | derselbe Stick unter OVMF: `hwdiag: firmware=UEFI`, kein „Cannot use text mode with UEFI", Rahmenpuffer von der Firmware (`fb 1280x800 src=multiboot`) |
| **Vom Stick starten, wenn der Stick an NVMe hängt** | **GEHT** | UEFI + `-device nvme,drive=stick`: gestartet, und der Kern meldet danach `hwdiag: disk NVMe bdf=0x20 1b36:0010` |
| **Vom Stick starten, wenn er an einem AHCI-Anschluss hängt** | **GEHT** | UEFI + `-device ahci` + `ide-hd,bus=ahci0.0`: gestartet, `hwdiag: disk AHCI bdf=0x20 8086:2922` |
| Partitionierung, die eine fremde Firmware akzeptiert | **GEHT** | GPT, EFI-Partition (EF00) mit `EFI/BOOT/BOOTX64.EFI`, `limine.conf`, `osum.mb`, `root.img`, `limine-bios.sys`; BIOS-Startteil im MBR-Bereich |
| **Eine Kommandozeile auf dem Stick** | **GEHT** | Runde STICK: Menüeintrag 5 *„Kommandozeile mit Netz“*. `console=ttyS0` macht COM1 zu einem Terminal, `vfs` gibt die Einhängetafel, `nic` die Karte. Gemessen unter BIOS **und** UEFI, vom Abbild über Limine: `tools/stick/run.sh`, **42 bestanden, 0 gescheitert** |
| Ein zweiter Datenträger (FAT32) | **GEHT** | mit `vfs` hängt der Kern die FAT-Partition der zweiten Platte beim Start selbst unter `/mnt` ein — gemessen im Lauf `sbr` der Runde STICK. **OFS lässt sich nicht zweimal einhängen** (`tools/e2e/run.sh`), für einen zweiten Datenträger also FAT |
| **Auf einem echten Rechner starten** | **GEHT (BLECH)** | **03.09.2026, Justins AMD-Brett, UEFI vom USB-Stick.** Der Kern startete, die Diagnose lief vollständig durch, der Schreibtisch kam hoch und füllte einen Ultrawide-Schirm. Kein Absturz, keine unbekannte Hardware |
| **Ein Menüeintrag, der ohne Tastatur etwas TUT** | **GEHT** | Runde BLECH-HID: *„Netz-Selbstlauf ohne Tastatur"*. Kernwort `netlauf` gibt `/bin/sh` das Skript `/etc/netlauf.sh` mit, danach hält der Schirm an. Gemessen gegen den echten Server: `dhcp: ack ip=…` → `host store.fleitec.com` → `fetch: verify OK`, `code 200` → `ota: NEUE FASSUNG verfuegbar`, ohne eine einzige Taste |

---

## 2. NETZ

| Klasse | Urteil | Beleg / was fehlt |
|---|---|---|
| **Intel e1000 / 82540EM / 82574L** | **GEHT** (QEMU) | `netdev: bestand 00:03.0 8086:100e 82540EM (1G) -> e1000`; zwei Karten gleichzeitig: `c0=e1000`, `c1=e1000`. Ping, TCP, TLS 1.3 gemessen (`tools/hwnet/*`) |
| **Realtek RTL8168/8169/8111/8101** | **GEHT** (QEMU) / **ERKANNT UND GEBUNDEN (BLECH)** | `-device rtl8139` → `netdev: c1=r8169`. `tools/rtl/run.sh`: **67 bestanden, 0 gefallen** — 20/20 Pings, 262144 Oktett TCP, 6224 KiB/s, 0 Prüfsummenfehler. **Auf echtem Silizium, 03.09.2026:** `netdev: bestand 09:00.0 10ec:8168 RTL8111/8168/8411 -> r8169`, `bestand 1 geraete, 1 mit treiber, 0 ohne` — der Treiber BINDET. Ob er dort auch Pakete bewegt, ist noch **UNGEMESSEN**; dafür ist der Menüeintrag *„Netz-Selbstlauf ohne Tastatur"* gebaut |
| **Intel I217/I218/I219 (PCH, Business-Laptops)** | **UNGEMESSEN** | Der PCH-Zweig steht in `kernel/e1000.fi` (13 Gerätenummern), der Datenweg ist mit dem gemessenen e1000 geteilt, der Aufsetzweg kommt aus dem Datenblatt. **QEMU hat keinen I219** — nie gelaufen. Es fehlt `e1000_flush_desc_rings` (der bekannte Hänger auf Skylake+) |
| **Intel I225/I226 (2,5 G)** | **GEHT NICHT** | wird erkannt und **beim Namen genannt** (`-> none igc silicon, advanced descriptors`), aber es gibt keinen Treiber |
| **WLAN (alle)** | **GEHT NICHT** | Es gibt keine Zeile 802.11 in diesem Repository. AX200/AX201/AX210, MT7921, QCA6390 werden in der Tabelle als `wifi, needs 802.11 + fw` benannt und sonst nichts. **Du brauchst Kabel.** |
| **Adresse und Nameserver per DHCP** | **GEHT** (QEMU) | Runde STICK, und vorher ging es **nicht**: ein DISCOVER an 255.255.255.255 lief durch `next_hop` und ARP und blieb ohne eingetragenes Gateway liegen. `net_output` nimmt dafür jetzt ff:ff:ff:ff:ff:ff. Vom Abbild gemessen: `dhcp: ack ip=10.0.2.15 lease=86400`, `/etc/resolv.conf geschrieben, dns 1` |
| Netzkarte, die keiner kennt | **GEHT** | wird als `no driver for 0x…` gemeldet, mit Namen wenn bekannt, und **der Kern läuft danach weiter** (gemessen mit `ne2k_pci`) |

---

## 3. PLATTE

| Klasse | Urteil | Beleg / was fehlt |
|---|---|---|
| **NVMe (M.2)** | **GEHT** (QEMU) / **ERKANNT (BLECH)** | erkannt (`disk NVMe`), gestartet, gelesen; mehrere Namensräume in `tools/blech/run.sh` gemessen (**72 bestanden, 0 gefallen**). **Auf echter M.2, 03.09.2026:** `hwdiag: disk NVMe bdf=0x100 c0a9:5426` — gefunden und beim Namen genannt. Davon LESEN ist auf Blech noch **UNGEMESSEN** |
| **SATA/AHCI** | **GEHT** (QEMU) / **ERKANNT (BLECH)** | `disk AHCI bdf=0x20 8086:2922`, Gegenprobe: derselbe Bericht meldet mit `-device ide-hd` noch `IDE`. `tools/ahci/run.sh` ist in der Abnahme. **Auf echtem AMD-SATA, 03.09.2026:** `hwdiag: disk AHCI bdf=0x201 1022:43c8`, und `blkdev: reihenfolge: nvme > ahci > usb > usb` mit vier Blockgeräten. Davon LESEN: **UNGEMESSEN** |
| **SATA im RAID-Modus (Firmware-Einstellung)** | **GEHT** (als Meldung) | der Controller wird beim Namen genannt statt eine leere Plattenliste zu zeigen. Ein Treiber dafür gibt es nicht — **im BIOS auf AHCI stellen** |
| **IDE/ATA-PIO** | **GEHT** | `disk IDE bdf=0x9 8086:7010` |
| **Die Wurzel finden statt raten** | **GEHT** | `kernel/rootsel.fi`: NVMe, AHCI, USB, IDE der Reihe nach, und der erste, der wirklich trägt, gewinnt. Gegenprobe: mit einer IDE-Wurzel läuft die neue Suche **null** Mal |
| USB-Stick als Platte (EHCI/xHCI) | **GEHT** (QEMU) | EHCI als zweiter Regler neben xHCI, Blöcke vom Wirt nachgerechnet |
| **Zwei xHCI-Regler in einem Rechner** | **GEHT** (seit BLECH-HID) / **GEFUNDEN (BLECH)** | Auf Justins Brett stehen zwei (`1022:43d5` und `1022:149c`), und bis BLECH-HID sah der Treiber nur den ersten. Gemessen mit zwei Reglern und HID am zweiten: `main` 4609ec9 → `usb: devices=0`, diese Runde → `usb: devices=2 kbd=1 mouse=1` |

---

## 4. BILD

| Was | Urteil | Beleg |
|---|---|---|
| Rahmenpuffer von der Firmware (UEFI-GOP über Limine) | **GEHT** (QEMU) / **GEHT (BLECH)** | `hwdiag: fb 1280x800 bpp=32 pitch=5120 src=multiboot` — die Auflösung kommt vom Lader, nicht geraten. **Auf Blech, 03.09.2026:** über UEFI gestartet, Bild auf einem Ultrawide-Schirm, ganze Fläche bemalt |
| **Der Mauszeiger ist ein Pfeil** | **GEHT** (seit BLECH-HID) | Er war bis dahin **keiner**: `innen[11] = 0x0400` ist EIN Bildpunkt, `innen[12..16]` sind je zwei getrennte Blöcke — auf Justins Foto ein Dreieck, eine Lücke und zwei Stummel. Neu gemalt als Erosion einer Silhouette; `tools/wm/zeiger.py` malt die Masken als Bild und prüft sechs Zusagen, der alte Zeiger fällt mit sieben Beanstandungen durch dieselbe Prüfung |
| Rahmenpuffer ohne Lader (Bochs/VBE-Register) | **GEHT** | `src=vbe`, `fb: selftest 13 / 13` |
| **Die Oberfläche füllt einen großen Schirm** | **GEHT** (QEMU) / **GEHT (BLECH)** | **03.09.2026 auf einem Huawei-Ultrawide bestätigt: der blaue Hintergrund füllt den ganzen Schirm, das Fenster „Terminal -- sh" ist mit Rahmen, Titel und Schließknopf korrekt gezeichnet.** Der 1024-Wand-Fix aus Runde STICK trägt auf Blech. |
| dieselbe Frage in QEMU | **GEHT** | **Behoben in Runde STICK, gemessen 03.09.2026.** Der gezeichnete Inhalt füllt **100 % × 100 %** bei 800x600, 1280x800, 1920x1080 und 2048x1152, die Taskleiste ist sichtbar (Bilder: `docs/shots/schirm-nach-*.png`, vorher `schirm-vor-1280x800.png` mit 49 % × 50 %). Ursache war **nicht** die Auflösung: `wig.blit` hat jede Bildpunktzeile breiter als 1024 (`MAX_ROW`) stillschweigend abgelehnt, und Schreibtisch und Taskleiste sind so breit wie der Schirm. Jetzt wird sie zerlegt statt abgelehnt — `docs/RUNDE-STICK.md`, Teil 1 |
| Auflösung des Bildschirms erkennen (EDID) | **GEHT** (QEMU) | Zweig `schirm`, jetzt in `main`: alle vier Zeitlagensätze, CTA-Erweiterungen, Kurzsatz-Rückfall. 1024x768, 1920x1080, 2560x1440 übernommen; auf einem 4K-Schirm meldet QEMU keine Zeitlage, dann 2048x1152. **Unter einem Lader bestimmt der Lader** — dafür hat `limine.conf` Einträge für WQHD und 4K |
| **Die Taskleiste ist auf dem Schirm** | **GEHT** (QEMU) / **auf Blech OFFEN** | In QEMU gemessen, auch ohne jede Bilddatei (`nvicons=no icons=no`: die Leiste steht, malt zwei Fensterknöpfe, „Start", „kein Netz" und die Uhr). **Auf Justins Blech war sie am 03.09.2026 unsichtbar, und die Ausgabe brach mitten im Wort ab** (`taskbar: icons=`). Behoben ist der Konstruktionsfehler dahinter: das Programm hat ZUERST über sich berichtet und ERST DANACH seine Leiste gebaut — jetzt umgekehrt, mit einem stillen ersten Malen und der Zeile `taskbar: STEHT x= y= w= h=` danach. Ein `L_TOP`, das nicht zu bekommen ist, schließt die Leiste nicht mehr, sondern macht sie zu einer gewöhnlichen. Ob damit die URSACHE oder nur die Wirkung behoben ist, entscheidet der nächste Lauf auf Justins Rechner |
| Echter GPU-Treiber, Beschleunigung | **GEHT NICHT** | und ist auch nicht geplant: der Weg über den Firmware-Rahmenpuffer trägt auf Intel, AMD und Nvidia gleichermaßen |

---

## 5. EINGABE

| Klasse | Urteil | Beleg / was fehlt |
|---|---|---|
| **PS/2-Tastatur und -Maus** | **GEHT** (QEMU) | `kernel/kbd.fi`, `kernel/ps2m.fi`; auf Desktops meist noch vorhanden, **auf modernen AMD-Brettern und Laptops nicht** — Justins Rechner hat keinen |
| **USB-Tastatur/Maus, Boot-Protokoll** | **GEHT** (QEMU), auf Blech **NOCH UNGEMESSEN — aber drei echte Fehler behoben** | `-device usb-kbd`, Oktett für Oktett gegen den PS/2-Lauf. **Auf Justins Blech kam am 03.09.2026 nichts an, und die Ursachen sind gefunden:** (1) die Schreibtisch-Einträge des Sticks hatten **kein `usb`** auf der Kommandozeile — `usb.stage` druckte `usb: skipped` und der ganze Baum lief nie; (2) `xhci.fi` hatte **keine Zeile zum USB Legacy Support** (xECP-Kennung 1) und schrieb in einen Regler, den die Firmware noch besaß — genau das Bild „im Startmenü geht die Tastatur, danach nicht mehr"; (3) es wurde nur der **erste** von zwei xHCI-Reglern aufgesetzt. Dazu echte Wartezeiten statt Zählschleifen (200 ms Anschlussstrom, 100 ms Prellzeit, 20 ms Erholung). Die Übernahme ist an einer **gebauten** Fähigkeitsliste geprüft (`usbleg`, 2 Fälle, 0 Fehler), weil QEMU keinen Legacy-Abschnitt hat |
| **Sehen, WARUM keine Eingabe ankommt** | **GEHT** (seit BLECH-HID) | `xhci.uebersicht` (lesend, in Menü 1): `usb: regler=N`, je Regler `besitz=BIOS|OS|frei`, `strom=`, `verbunden=`. `xhci.bericht` (Menüeintrag *„USB-Diagnose"*): Semaphore vor/nach der Übernahme, HCRST, und jeder Anschluss mit `pp/ccs/ped/pr/spd`, vier je Zeile — ein Foto reicht |
| **USB-Nabenchip (Hub)** | **GEHT NICHT** | es gibt keinen Hub-Treiber. Ein Hub wird aufgezählt und mit `class=09:…  driver=none` benannt; was DAHINTER steckt, sieht dieses System nicht. Tastatur und Maus gehören direkt in eine Buchse am Gehäuse |
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
| **Update über das Netz (OTA), VOM STICK** | **GEHT** (QEMU) | Runde STICK, im laufenden System vom Abbild getippt, unter BIOS und UEFI: `dhcp` → `host store.fleitec.com` (dieselbe Adresse, die `dig` auf dem Wirt nennt) → `fetch https://store.fleitec.com/index.json`: **`fetch: roots 11`, `fetch: verify OK`, `fetch: certs 4`** — echte Let's-Encrypt-Kette gegen die Mozilla-Wurzeln **im Abbild** → `ota suchen`: `ota: fassung dort 2`, `ota: NEUE FASSUNG verfuegbar` |
| **`ota einspielen` vom Stick** | **UNGEMESSEN** | und zwar mit Ansage: die Wurzel des Sticks ist ein Boot-Modul im Arbeitsspeicher, ein eingespieltes Update überlebt den Neustart nicht. Für ein Update, das bleibt, muss Osum erst installiert sein (`/bin/install`). Gemessen ist `ota einspielen` auf einer PLATTE (Runde OTA/MERGE-5) |
| **JARVIS-Brücke (`/bin/jarvisd`), VOM STICK** | **GEHT** (QEMU) | Runde STICK: `jarvisd: verbunden` / `angemeldet`, und auf der Gegenseite (Python, nicht Osum) `TLSv1.3`, `BEWEIS gut` (Ed25519, von python-cryptography nachgerechnet), `ANGEMELDET`, **zwei Aufträge beantwortet** — `system` und `/bin/echo`, dessen Ausgabe auf dem Stick entstanden ist. Gegen `tools/bridge/gegenstelle.py`, **nicht** gegen den echten JARVIS-Server. Die Rechteliste des Prüfstands kam auf einer zweiten Platte herein; **das Abbild wurde dafür nicht angefasst** |

---

## 7. WAS AUF DEM STICK IST — die Liste aus Abschnitt 7 ist abgearbeitet

Der Stick trug **43** Ring-3-Programme. Er trägt jetzt **52**. Dazu
gekommen sind genau die sieben, die hier bis zum 03.09.2026 als fehlend
standen — `ota`, `fetch`, `host`, `jarvisd`, `jsig`, `jarvisctl`,
`pollbr` —, und dazu `dhcp` und `reboot`, ohne die die anderen nichts
können.

`fetch` und `jarvisd` sind `--profile=app` und bringen TLS 1.3 mit
(1 532 800 Oktette); die übrigen sind `profile kernel`. Der Bauweg dafür
steht seit dieser Runde in `tools/usbimg/build.sh` und ist wörtlich der
aus `tools/install/build.sh`.

**Und was sie brauchen, um etwas zu können, liegt auch drauf:**

| Pfad | was |
|---|---|
| `/etc/ssl/roots.pem` | 15 261 Oktette, **11 Mozilla-Wurzeln** — ohne sie vertraut `fetch` nichts |
| `/etc/ota.conf` | `quelle=https://store.fleitec.com/osum/aktuell`, **`auto=nein`** |
| `/system/schluessel.pub` | der Schlüssel der Auslieferung, 32 Oktette |
| `/system/FASSUNG`, `/system/SCHLUESSELGEN` | je neun Oktette fester Breite |
| `/etc/jarvis/rechte.conf` | die Rechteliste — **ab Werk ist alles aus** |

Zwei Vorgaben sind ausdrücklich so gewählt und stehen so im Bauskript:
**`auto=nein`** (ein Stick, der ab Werk von selbst irgendwo nachfragt,
wäre eine Entscheidung, die niemand getroffen hat) und eine **leere
Rechteliste** (kein Server, keine Befehle, kein Bildschirmfoto, keine
Pfade — so gestartet meldet sich `jarvisd` nirgends an).

**Was jetzt noch fehlt, ist kurz und steht in `docs/RUNDE-STICK.md`:**
ein Rechner aus Blech, ein Lauf gegen den echten JARVIS-Server statt
gegen den Prüfstand, und `ota einspielen` von einem Stick — was, siehe
oben, ohne Installation ohnehin nicht bleiben würde.

---

## 8. DIE ANTWORT AUF DIE FRAGE

**„Kann ich den Stick jetzt in einen Laptop stecken und es läuft?“**

**Er STARTET — das ist seit dem 03.09.2026 keine Hoffnung mehr, sondern
gemessen.** Auf einem echten AMD-Brett über UEFI: Diagnose vollständig,
NVMe und SATA erkannt, die Netzkarte erkannt UND vom Treiber genommen,
Schutzbits und Vektoreinheit in Ordnung, Bild über den ganzen
Ultrawide-Schirm, Fenster korrekt gezeichnet, kein Absturz.

**Womit man noch nicht arbeiten kann, ist die EINGABE.** Sie kam auf
diesem Rechner nicht an; drei Ursachen sind gefunden und behoben
(kein `usb` auf der Kommandozeile, keine Übernahme vom BIOS, nur ein
Regler von zweien), aber ob es damit geht, entscheidet der nächste Lauf
auf demselben Brett. Bis dahin gibt es den Menüeintrag *„Netz-Selbstlauf
ohne Tastatur"*, der ohne eine einzige Taste `dhcp`, `host`, `fetch` und
`ota suchen` fährt und das Ergebnis stehen lässt.

Was du erwarten darfst, wenn du es probierst:

* **Starten** wird er wahrscheinlich: BIOS und UEFI, von einem
  USB-Stick, von SATA und von NVMe — alle vier Wege sind mit demselben
  Abbild gefahren worden.
* **Bild:** Du bekommst ein Bild in der Auflösung, die die Firmware
  setzt, **und die Oberfläche füllt es jetzt auch** — samt Taskleiste
  unten. Das war gestern der hässlichste Satz dieser Datei und ist
  erledigt. Auf einem WQHD- oder 4K-Bildschirm nimm die beiden
  Menüeinträge, die die Auflösung dem Lader vorgeben.
* **Etwas tun:** Menüeintrag 5, *„Kommandozeile mit Netz“*. Dort gibt es
  eine Shell — auf dem Bildschirm und auf der seriellen Leitung — und
  darin `dhcp`, `host`, `fetch`, `ota`, `jarvisd`, `mount` und die
  übrigen 45 Programme.
* **Netz:** nur mit **Kabel**. WLAN geht nicht, gar nicht. Hat der
  Laptop einen Realtek- oder Intel-e1000-Anschluss, stehen die Chancen
  gut; ein I225/I226 (2,5 Gbit) wird erkannt, aber **nicht gefahren**.
  Mit Kabel: `dhcp` holt Adresse und Nameserver selbst.
* **Sich aktualisieren:** `ota suchen` findet den Update-Server über
  seinen **Namen** und liest das signierte Verzeichnis. **Einspielen
  bringt vom Stick nichts** — die Wurzel liegt im Arbeitsspeicher und ist
  nach dem Neustart wieder die alte.
* **Platte:** NVMe und SATA/AHCI werden gefunden. Steht das BIOS auf
  **RAID** statt AHCI, siehst du keine Platte — dann im BIOS umstellen.
  Eine **FAT32**-Platte oder ein zweiter Stick hängt beim Start unter
  `/mnt`.
* **Tastatur/Touchpad:** Am Desktop mit PS/2 oder USB: geht. **Auf einem
  Ultrabook, dessen Touchpad an I²C hängt, ist es Glückssache** — der
  Weg ist gebaut, aber nie an echter Hardware gelaufen. Für den Fall,
  dass gar keine Tastatur ankommt: die Kommandozeile geht auch über ein
  serielles Terminal.
* **Ton, TPM, Beschleunigung, S3:** nein.

**Kurz:** zum Anschauen, Ausprobieren und für einen ersten echten
Bericht von Blech — ja, und dafür ist er jetzt gemacht. Als System, auf
dem man arbeitet — nein.
