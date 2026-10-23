# PLAN-HP-LAPTOP — Ziel-Hardware HP X3U19AV (21.10.2026)

## 1. Welche Hardware ist das?

**Belegt** (Händler-/Datenblatt-Quellen, kein Gerät vermessen):
- X3U19AV = **HP EliteBook x360 1030 G2**, Config i5-7200U, 8 GB RAM, 128 GB SSD (eBay-/Amazon-/itprice-Listings). Serial 5CG8070H3F = Werk 5CG, Baujahr 2018, KW 07 (Lesart der Seriennummer, unbelegt).
- CPU Kaby Lake-U (i5-7200U/7300U/7600U), iGPU **Intel HD 620**, RAM aufgelötet DDR4-2133 (max 16 GB).
- 13,3" Full-HD-Touch (UWVA, optional Sure View), Glas-Clickpad, Intel Dual Band AC **8265** + BT 4.2, B&O-Audio (4 Lautsprecher, Dual-Mikro), USB-C mit Thunderbolt, 2x USB-A 3.x, HDMI 1.4, TPM 1.2/2.0, Sure Start Gen 3, optional Fingerprint/NFC/WWAN.
- Storage laut Datenblatt: M.2 2280 **NVMe PCIe** (bis 512 GB) ODER M.2 **SATA** (256–512 GB). Welche Variante im X3U19AV steckt: **unbelegt**.

**Unbelegt** (kommt aus der Auto-Inventur, Abschnitt 3):
- Storage-Modus im BIOS (AHCI vs. Intel RST/RAID), SSD NVMe oder SATA.
- Touchpad/Tastatur-Bus (PS/2 vs. I2C-HID; Clickpad bei dieser Serie vermutlich I2C, Tastatur über EC/PS/2), Touchscreen-Bus (I2C-HID oder USB).
- Audio-Codec (HDA-Controller 8086:9d71 erwartet, Codec unbekannt), Kamera (USB UVC erwartet), Secure-Boot-Zustand, S3 vs. S0ix.
- Ethernet: keiner onboard (Dongle/Dock).

## 2. Lückenliste gegen den Dell 9020

Ampel: GRÜN = Code da und in QEMU gated, aber am HP **ungemessen**; GELB = Teil da; ROT = fehlt. Aufwand S/M/L wie STATUS-ALLTAG.

| Baustein | Ampel | Aufwand | Befund |
|---|---|---|---|
| UEFI-Boot vom Stick | GRÜN | S | Limine BOOTX64.EFI, tools/stick + usbimg laufen unter OVMF (tools/ovmfboot: q35/i440fx, EHCI/xHCI/NVMe/AHCI als Bootmedium, xHCI-Stick + AHCI- bzw. NVMe-Systemplatte; Gegenproben: leere AHCI-Platte bootet nicht, `acpiold` stürzt ab); echter Laptop ungemessen. Secure Boot muss aus sein (Lader unsigniert): das Limine-Menü trägt es im Kopf (`interface_branding`), ein Kernel-Absturz druckt `BIOS: Secure Boot OFF, SATA mode AHCI` auf den Schirm. Bei Secure Boot AN startet die Firmware den Lader gar nicht — dann erscheint nichts von uns |
| Storage NVMe | GRÜN | S | nvme.fi, s3dev-Gate; HP-SSD ungemessen |
| Storage SATA/AHCI | GRÜN | S | ahci.fi |
| Intel RST (RAID-Modus) | ROT | M | NVMe verschwindet hinter RAID-Controller (Klasse 0104). Kein Treiber. Workaround: BIOS auf AHCI. Inventur erkennt und meldet das (`storage_verdict=raid-rst-nvme-hidden`). Seit 23.10.: Bootzeile `storage: Intel RST (RAID) mode, NVMe disks may be hidden. BIOS: set SATA mode to AHCI` (pci.rst_nvme_hidden, ahci.fi) und `sysinfo --hwcheck` zeigt `storage: check BIOS: set SATA mode to AHCI`; gated mit Testwort `fakeraid` (hwinv/guest.sh, ovmfboot) samt Gegenprobe ohne Wort |
| Display HD 620 | GELB | M | nur UEFI-GOP-Framebuffer, kein Mode-Set, keine Helligkeit (r32/r33/r36); Panel läuft in nativer GOP-Auflösung |
| Tastatur | GELB | S–M | USB-HID und PS/2 da; interne Tastatur ist PS/2 (i8042) — ACPI/EC-Weg ungemessen. Ohne PS/2 (`-machine q35,i8042=off`) bootet das System bis zum Login (ovmfboot); Login nur mit Tastatur: tools/inputlogin |
| Touchpad | GELB | M | `i2chid.fi` gegen simulierten DesignWare-Controller 18/0; ECHT fehlt: LPSS-I2C-Controller aus PCI (8086:9d60..) ansprechen + ACPI-Gerät (_HID, I2C-Adresse, GPIO-IRQ). AML-Interpreter existiert (kernel/acpi/aml*.fi). HP-6 Stand: Regler-Suche wacht LPSS-Funktion auf (D0, MEM, DesignWare-Reset bei +0x204), nur Quelltext, ungemessen (ACPI-Modus ohne PCI-Funktion wuerde nicht gefunden) |
| Touchscreen | ROT | M | wie Touchpad (I2C-HID) oder USB-HID; Multitouch-Auswertung fehlt. Ohne I2C-Controller kein Hänger, Zeiger über USB-Maus (ovmfboot: usb-kbd + usb-mouse, kein PS/2) |
| Netz per USB-Dongle/Tethering | GELB | S | ECM, RNDIS (Android-Tethering), NCM in usbnet.fi verdrahtet; QEMU-Gates usbecm/usbrndis, NCM nur host-/Verdrahtungstest. ASIX AX88772/772B: Protokollhaelfte `lib/usbnet/ax88772.fi` (Rahmen, Setup-Pakete, `tools/usbvendor` 6/0 mit 4 Gegenproben), Treiber-Glue offen. Realtek RTL8153/CH336 ohne bzw. nur Protokoll, nichts am echten Geraet gemessen (Stand 23.10.) |
| WLAN Intel 8265 | ROT | L | iwl.fi/lib/wlan zielen auf AX200/AX201 (CNVi, Context-Info). 8265 = Familie 8000 (altes FH-Chunk-Laden, ucode `iwlwifi-8265-*`) = **anderer** Ladeweg. Praktisch zuerst USB-Netz. Robustheit gated (ovmfboot, Testwort `fakewlan` = Karte meldet sich als 8086:24fd): Probe lehnt ab, Login erreicht, keine Fault-Zeile |
| Bluetooth (Intel 8265 BT, USB) | ROT | L | r6; HCI + Firmware-Blob |
| Audio HDA | GELB | M | hda.fi Ausgabe+Mikro gated; Codec des HP unbekannt (Pin-Konfig/Verbs), Jack-Erkennung r624. HDA-Controller ohne Codec (`-device intel-hda`): Boot ohne Fault-Zeile (ovmfboot) |
| Kamera (UVC) | ROT | M–L | isochron fehlt in xHCI (r7) |
| Fingerprint/NFC | ROT | L | nicht vor PIN-Login |
| Akku/ACPI (Batterie, Deckel, Helligkeitstasten) | GELB | M | AML da (Dell hat Netzteil, kein Akku); _BIF/_BST und Lid-Event am Laptop ungemessen |
| Standby | GELB | M | S3 in QEMU grün (s3, s3dev); Kaby Lake-U mit „Windows“-S0ix-Default? ungemessen, BIOS-Option Legacy S3 prüfen |
| Thunderbolt/USB-C | ROT | L | nur als USB (xHCI); TB-Controller wird nur gelistet |
| TPM/Sure Start | — | — | nicht relevant bis Messkette existiert |

Hardware-Check (`sysinfo --hwcheck`) hat jetzt eine Zeile `storage` (ok / missing / BIOS-Hinweis bei Intel RST), host-gated in tools/hwcheck (43 Checks, 4 Mutationen).

Prioritäten: **(1) Boot+Inventur, (2) Storage ehrlich melden, (3) Tastatur/Touchpad, (4) Display, (5) Netz per Dongle, (6) WLAN 8265.**

## 3. Stick einstecken → Inventur kommt zum Server

Gebaut (dieser Lauf):
- `lib/hwinv/` (buf, scan, names, report): macht aus `/proc/pci`, `/proc/usb`, `/proc/firmware` einen Bericht `hwinv: key=value` (Firmware UEFI/BIOS, Storage-Arten + Urteil, GPU, WLAN mit Chipname + Treiberstand, Ethernet, Audio, Serial-IO-I2C-Controller, Zeigegerät-Weg, xHCI, ME, USB: Tastatur/Kamera/BT) plus Rohkopie.
- `/bin/hwinv [-d] [DATEI]` (kernel/user/hwinv.fi): ohne Argument stdout; mit Datei schreibt sie; `-d` wartet 15 s (USB-Enumeration) und schreibt nach weiteren 30 s noch einmal.
- Stick-inittab startet `hwinv -d /var/jarvis/hwinv.txt` beim Boot (tools/usbimg/build.sh). `/var/jarvis/` ist in `rechte.conf` lesbar, also holt die JARVIS-Brücke die Datei mit `read` — der Boss muss nur den Stick stecken.
- Nicht enthalten: Seriennummern/UUID/MAC (nur PCI/USB-IDs).
- Offen (HP-3): ACPI-Geräteliste (_HID, z. B. ELAN/SYNA/PNP0C50 für I2C-HID) und ACPI-Tabellen-Signaturen in den Bericht; Brücken-Zugang auf dem Laptop (WLAN fehlt → USB-Ethernet-Dongle oder Tethering nötig!). Ohne Netz bleibt die Datei auf dem Stick (`/var/jarvis/hwinv.txt`), Boss kann sie am Stick-Partitionsblatt oder per Foto vom Terminal (`hwinv`) liefern.

Gates: `bash tools/hwinv/run.sh` (Host, 28 Checks + 4 Mutationen), `bash tools/hwinv/guest.sh` (QEMU: IDE-Basis, +AHCI, +NVMe, +RAID/megasas als Gegenprobe).

## 4. Anleitung für den Boss (5 Zeilen)

1. Laptop ausschalten, Stick in USB-A stecken (nicht Hub), Netz-Dongle/Tethering-Handy dazu.
2. Einschalten, sofort **Esc** (Startmenü) → **F10** BIOS: *Secure Boot* **aus**, *Legacy Support* egal, Storage/SATA-Modus **AHCI** (nicht RAID/RST).
3. Speichern + Neustart, **F9** (Boot Device Options) → USB-Stick (UEFI) wählen.
4. Limine-Menü → Standardeintrag; Desktop abwarten (ca. 1 min).
5. Nach 1 min liegt `/var/jarvis/hwinv.txt` auf dem Stick; im Terminal `hwinv` zeigt dasselbe. Ergebnis schicken (oder Brücke holt es).

## 5. Roadmap (Gruppe HP-LAPTOP)

HP-1 Hardware-Doku + Plan (dieses Dokument) · HP-2 Inventur `hwinv` (Lib, Programm, Stick-Autostart, Gates) · HP-3 Inventur um ACPI-Geräte/Tabellen erweitern · HP-4 UEFI-Stick-Gate mit OVMF (AHCI + NVMe) · HP-5 Intel RST erkennen/melden im Boot (Kernelmeldung) · HP-6 I2C-HID real: LPSS-I2C (PCI 8086:9d60..) + ACPI-Gerät · HP-7 PS/2-Tastatur/EC-Weg am Laptop prüfen · HP-8 USB-Netz: RNDIS/NCM-Treiber verdrahten · HP-9 Intel 8265 (Familie 8000) Plan-Anpassung in PLAN-LAPTOP-WLAN (siehe Abschnitt dort) · HP-10 Display: Helligkeit/Mode-Set Intel HD 620 · HP-11 Akku/Lid/Standby am Gerät messen.
