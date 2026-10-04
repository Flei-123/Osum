# OrientOS auf eine Platte installieren (Stand 03.10.2026, main b6999e41)

Gemessen mit `bash tools/install/abnahme.sh` (49 gruen / 0 rot): Installation in
der VM, Start von der Platte ohne Stick (UEFI/OVMF), Datei ueberlebt Neustart,
eigenes Konto, Anmeldung. **Echte Hardware ist damit nicht bewiesen.**

## Anleitung (10 Schritte)

1. Abbild laden und entpacken: `orientos-usb-<datum>-<commit>-<profil>.img.xz` -> `orientos-usb.img` (xz / 7-Zip).
2. Auf den Stick schreiben (Stick wird komplett geloescht, mind. 256 MB):
   Linux `sudo dd if=orientos-usb.img of=/dev/sdX bs=4M conv=fsync status=progress`,
   Windows Rufus (DD-Image-Modus) oder balenaEtcher.
3. Im BIOS/UEFI: **Secure Boot AUS**, USB-Boot erlaubt. SATA-Modus am besten **AHCI**; "RAID On" (Intel RST) wird seit 04.10. ebenfalls als AHCI angesprochen (nur in der VM nachgestellt, am Dell noch nicht bestaetigt).
4. Stick einstecken, Rechner starten, Bootmenue oeffnen (Dell: **F12**), den **UEFI-Eintrag des Sticks** waehlen (nicht "Legacy").
5. Limine-Menue: der **Standard-Eintrag genuegt** (seit 04.10.2026 holt der Installer SATA/AHCI und NVMe selbst hoch,
   kein Sonder-Eintrag und kein Kernel-Wort `sata` mehr). Im Startmenue **"OrientOS installieren"** waehlen.
   Der Eintrag "OrientOS (install to SATA disk)" des persoenlichen Sticks bleibt als Zweitweg und startet SATA schon beim Boot.
   Fuer die Installation mit eigenem Konto beim Public-Stick **"Install OrientOS"** (Eintrag 2).
6. Das Fenster "OrientOS installieren" oeffnet sich. In der Liste die **Zielplatte anklicken**
   (Spalten: Geraet, Anschlussart, Groesse, Belegung `leer`/`Partitionen`).
7. Reiter **"Ganze Platte"** (loescht alles, rote Warnung) oder **"Daneben installieren"** (freier Platz + vorhandene EFI-Partition, z. B. neben Windows).
8. Benutzername, Passwort, Passwort wiederholen eintragen (Name: Kleinbuchstaben/Ziffern; Passwort mind. 4 Zeichen). Der Knopf bleibt grau, bis alles stimmt.
9. **Installieren** druecken, zwei Bestaetigungen ("Platte ueberschreiben?" / "Wirklich loeschen?") mit Ja. Fortschritt 1/5 bis 5/5, nicht ausschalten (in der VM rund 10 Minuten, auf echter Hardware nicht gemessen).
10. "Fertig": ausschalten, **Stick abziehen**, einschalten, mit dem neuen Konto anmelden.

## Was geprueft ist, was nicht (ehrlich)

| Punkt | Stand |
|---|---|
| Plattenauswahl mit Groesse/Belegung, Warnung, 2 Bestaetigungen | ja (`installer.fi`) |
| Boot-Stick in der Liste | nein: der Stick laeuft als RAM-Modul, ist kein Plattengeraet und nicht waehlbar |
| Echte Modellbezeichnung der Platte | **nein**, nur Anschlussart (ATA/NVMe) -> Roadmap r308 |
| Bootloader der installierten Platte | **nur UEFI** (GPT + EFI-Partition + Limine) |
| BIOS/Legacy-Start der installierten Platte | **nein**: Schutz-MBR ohne Startcode, SeaBIOS bleibt bei "Booting from Hard Disk..." stehen -> r309. (Der Stick selbst startet unter BIOS.) |
| UEFI-Start von der Platte ohne Stick | ja (OVMF, VM) |
| Secure Boot | **nein**, Limine unsigniert, muss aus sein -> r310 |
| Ganze Platte | ja |
| Neben vorhandenem System (freier Platz, fremde EFI-Partition mitbenutzt, Windows-Eintrag im Menue) | ja in VM (`tools/dual`), **kein Verkleinern** vorhandener Partitionen -- Platz vorher im anderen System freimachen |
| Konto bei Installation | ja, nur wenn der Installer als root laeuft (Boot-Eintrag "Install OrientOS"); Live-Schreibtisch-Fenster installiert ohne Konto und sagt es |
| Auto-Update nach Installation | an (Standard), Feed `store.fleitec.com/osum/aktuell` (Fassung 4 vom 25.09.) -> siehe r311 |
| Netzwerk | Kabel: e1000 in der VM ja (DHCP, Uhr per SNTP); I217/I219 am echten Dell noch zu pruefen; **WLAN nein** (kein Funktreiber, r21) |
| Grafik | nur Framebuffer (UEFI-GOP), kein GPU-Treiber, kein OpenGL (r36) |
| Standby | S3 in VM gemessen, auf echter Hardware oft schwarzes Bild (r4) |
| Bluetooth, Kamera, SMB | nein (r6, r7, r24) |

## Abdeckung der Plattentypen im STANDARD-Boot (Stand 04.10.2026, VM-Matrix mit Abbild `installer-default`)

Standard-Boot = erster Menue-Eintrag, **ohne** Kernel-Wort `sata`/`nvme`. Der Installer ruft beim Oeffnen einen
Syscall (`SYS_OSUM_DISKUP` 1601, jeder Benutzer; der Bring-up laeuft einmal je Start), der AHCI und NVMe hochfaehrt; `/dev` kommt mit `vfs` (Eintrag 1 hat es jetzt).
"VM" = QEMU 7.2 mit KVM, Installer per `wigapp=/bin/installer,now` geoeffnet, Ergebnis aus der seriellen Zeile `installer: disk ...`.
"Dell" = am echten OptiPlex 9020 geprueft (der Dell war bei dieser Messung offline: **nirgends bestaetigt**).

| Controller-Typ | Treiber | Im Standard-Boot erkannt | VM-getestet | Dell |
|---|---|---|---|---|
| SATA, AHCI (ich9-ahci) | `ahci.fi` | ja, `/dev/sda` | ja, UEFI **und** BIOS (SeaBIOS) | offen |
| SATA, Intel "RAID On" (Klasse 01:04, 8086:2822/2826) | `ahci.fi` (nimmt RAID-Klasse als AHCI) | ja, `/dev/sda` | nur mit Testwort `fakeraid` (QEMU meldet sich als RAID) | **offen -- der wichtigste Test** |
| IDE / PIIX (Legacy, `-M pc`) | ATA-PIO (`blk.fi`) | ja, `/dev/hda` `/dev/hdb` | ja | n/a (der 9020 hat kein IDE) |
| NVMe (M.2/PCIe) | `nvme.fi` | ja, `/dev/nvme0` | ja, UEFI **und** BIOS | offen (der 9020 hat meist kein NVMe) |
| Mehrere Platten gleichzeitig (Auswahl mit Anschlussart + Groesse) | AHCI 1x + NVMe 1x + IDE 2x | ja, bis zu 4 Eintraege: hda, hdb, nvme0, sda | ja: AHCI + NVMe = 2 Eintraege | offen |
| **Zweite** SATA-Platte / zweiter AHCI-Controller | -- (Treiber haelt eine Platte, nur den ersten Controller) | **nein** | ja (gemessen: bleibt unsichtbar) | -- |
| USB-Platte / -SSD (usb-storage) | Treiber `usb.fi` (`DEV_USB0-3`) vorhanden, Installer scannt sie nicht | **nein** | ja (gemessen: n=0) | -- |
| virtio-blk / virtio-scsi | **kein Treiber** | **nein** | ja (gemessen: n=0) | -- |
| eMMC / SD (SDHCI) | **kein Treiber** | **nein** | ja (gemessen: n=0) | -- |
| Intel VMD / RST-NVMe hinter dem Controller | **kein Treiber** | **nein** | nicht nachstellbar | -- |
| Hotplug (Platte nach dem Start des Installers anstecken) | -- | **nein** (Suche nur beim Oeffnen) | nicht getestet | -- |
| Boot-Stick als Ziel | -- | wird nie angeboten: der Stick laeuft als RAM-Modul, hat kein Plattengeraet in der Liste | ja (Liste enthaelt ihn nicht) | -- |

**UEFI und BIOS:** der Installer findet SATA und NVMe unter beiden Startarten. Die installierte Platte bootet unter UEFI und
unter SeaBIOS (`tools/install/bios.sh`, r309). Vor dem Loeschen fragt der Installer zweimal; die Boot-Quelle wird nie ueberschrieben.

**Fehlt (Roadmap):** zweite SATA-Platte/zweiter Controller, USB-Platten als Ziel, virtio-blk/-scsi, eMMC/SD, Intel VMD, Hotplug.

## Wenn etwas schiefgeht

* Stick bootet nicht: anderen USB-Port (USB 2) versuchen, Secure Boot pruefen.
* Keine Platte in der Liste: SATA-Modus im BIOS auf AHCI stellen ("RAID On" geht seit 04.10. auch, am Dell aber noch nicht bestaetigt), "Neu suchen". Die Zeile "Keine Platte" im Installer nennt die gesehenen Controller; im Kernel-Protokoll steht `ahci: ...` mit dem Grund.
* Neben Windows startet nur Windows: Bootreihenfolge im BIOS (die Datei `\EFI\BOOT\BOOTX64.EFI` gehoert dann OrientOS' Menue).
