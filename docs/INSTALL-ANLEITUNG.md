# OrientOS auf eine Platte installieren (Stand 03.10.2026, main b6999e41)

Gemessen mit `bash tools/install/abnahme.sh` (49 gruen / 0 rot): Installation in
der VM, Start von der Platte ohne Stick (UEFI/OVMF), Datei ueberlebt Neustart,
eigenes Konto, Anmeldung. **Echte Hardware ist damit nicht bewiesen.**

## Anleitung (10 Schritte)

1. Abbild laden und entpacken: `orientos-usb-<datum>-<commit>-<profil>.img.xz` -> `orientos-usb.img` (xz / 7-Zip).
2. Auf den Stick schreiben (Stick wird komplett geloescht, mind. 256 MB):
   Linux `sudo dd if=orientos-usb.img of=/dev/sdX bs=4M conv=fsync status=progress`,
   Windows Rufus (DD-Image-Modus) oder balenaEtcher.
3. Im BIOS/UEFI: **Secure Boot AUS**, SATA-Modus **AHCI** (nicht RAID/RST), USB-Boot erlaubt.
4. Stick einstecken, Rechner starten, Bootmenue oeffnen (Dell: **F12**), den **UEFI-Eintrag des Sticks** waehlen (nicht "Legacy").
5. Limine-Menue: fuer Installation mit eigenem Konto **"Install OrientOS"** waehlen
   (Public-Stick, Eintrag 2). Beim persoenlichen Test-Stick heisst er
   "OrientOS (install to SATA disk)" und installiert **ohne** eigenes Konto (Konten des Sticks werden uebernommen).
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

## Wenn etwas schiefgeht

* Stick bootet nicht: anderen USB-Port (USB 2) versuchen, Secure Boot pruefen.
* Keine Platte in der Liste: SATA-Modus im BIOS auf AHCI, "Neu suchen".
* Neben Windows startet nur Windows: Bootreihenfolge im BIOS (die Datei `\EFI\BOOT\BOOTX64.EFI` gehoert dann OrientOS' Menue).
