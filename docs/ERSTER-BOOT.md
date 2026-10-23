<!-- SPDX-License-Identifier: GPL-2.0-only -->
# ERSTER-BOOT -- die ersten 5 Minuten am HP EliteBook x360 1030 G2

Abbild: `orientos-usb.img` (GPT + EFI-Partition, startet unter UEFI und BIOS).
SHA256: `df4aa8bfeec83eb48a0c3f02dcc3ee16a90ea590607400cee9f8120408db819c`
Stand: Abbild gebaut aus origin/main `bbbc77c5` (Build-Commit `61fcf87e`, 23.10.2026 20:34 UTC). Gleiche Schritte gelten fuer den Dell 9020 (dort F12 statt F9).

## 0. Vorher (Rechner mit Linux/Windows, 2 Minuten)

1. Pruefsumme: `sha256sum orientos-usb.img` (Windows: `certutil -hashfile orientos-usb.img SHA256`) muss die Zeile oben ergeben.
2. Schreiben (Stick >= 1 GB, wird komplett ueberschrieben):
   - Linux: `dd if=orientos-usb.img of=/dev/sdX bs=4M conv=fsync status=progress` (`sdX` mit `lsblk` pruefen!)
   - Windows: Rufus, Abbild waehlen, **DD-Modus** (nicht ISO-Modus).

## 1. BIOS am HP (Minute 0-1)

1. Laptop aus, Stick direkt in USB-A (kein Hub). Optional: LAN-Dongle (USB-Ethernet) oder Handy-Tethering per USB -- WLAN geht noch nicht (Intel 8265, kein Treiber).
2. Einschalten, sofort **Esc** (Startmenue), dann **F10** = BIOS-Setup.
3. Einstellen:
   - **Secure Boot: AUS** (unter Advanced / Boot Options / Secure Boot Configuration)
   - **SATA/Storage-Modus: AHCI** (nicht RAID/Intel RST) -- sonst sieht OrientOS die interne Platte nicht
   - **USB-/UEFI-Boot: erlaubt**; Legacy-Boot egal
4. Speichern und Neustart (F10), sofort wieder **Esc**, dann **F9** (Boot Device Options) und den **USB-Stick (UEFI)** waehlen.
5. BIOS-Version notieren (steht im BIOS-Setup Hauptseite) -- gehoert in die Rueckmeldung.

## 2. Was du sehen sollst (Minute 1-3)

1. **Limine-Menue** (5 s Countdown). Eintrag 1 `OrientOS` (Standard) laufen lassen.
2. Bootzeilen, dann **Anmeldeschirm**. Konto `justin`, Startkennwort `startkennwort`.
3. **Desktop mit Leiste unten**. Maus/Touchpad und Tastatur sollen reagieren. Startmenue oeffnen, Terminal oeffnen.
4. Nach ca. 1 min liegt der Hardware-Bericht (siehe 4). Im Terminal `hwinv` zeigt dasselbe.

Erwartet auf dem HP, ist KEIN Fehler: **WLAN fehlt** (`wlan=8086:24fd intel-8265 driver=none`). **Touchpad (I2C) und Tastatur-Spezialtasten** koennen noch nicht gehen -- dafuer USB-Maus mitnehmen. Eine interne Platte erscheint nur im AHCI-Modus.

## 3. Wenn etwas schiefgeht (Minute 3-5)

1. **Schwarzer Schirm / Hang / Panik-Bild:** Schirm mit dem Handy **fotografieren** (ganzer Schirm, scharf, nicht wischen). Dort steht der Fehlerort.
2. **Neustart (Power 5 s halten, wieder einschalten):** der naechste Boot geht von selbst in den **sicheren Modus** (max. 3 Neustarts, dann Halt ohne Reset). Oben steht dann "SAFE MODE ...". Zustand in `/proc/safe`.
3. **Sicherer Modus von Hand:** im Limine-Menue (Pfeiltasten, vor Ablauf der 5 s) den Eintrag **`OrientOS (safe mode)`** waehlen -- ohne Netz, Audio, Zusatztreiber.
4. Weitere Limine-Eintraege bei Grafik-/Netzproblemen, in dieser Reihenfolge probieren:
   - `OrientOS (safe graphics)` -- einfacher Bildschirmpfad
   - `OrientOS (no network)` -- ohne Netzwerk-Treiber
   - `Hardware diagnostics` -- druckt nur die Hardware-Diagnose, startet keinen Desktop
   - `Command line` -- Textkonsole
5. **Nicht waehlen:** `OrientOS (install to SATA disk)` -- das installiert auf eine interne Platte. Der Stick schreibt sonst NICHTS auf andere Laufwerke (Schreibsperre); Installieren geht nur mit getipptem Plattennamen.
6. **Nichts reparieren, nichts neu flashen** -- erst Rueckmeldung (siehe 5).

## 4. Hardware-Bericht (hwinv)

- Beim Boot startet `hwinv -d /var/jarvis/hwinv.txt`: wartet 15 s (USB-Erkennung), schreibt die Datei, nach weiteren 30 s noch einmal.
- Inhalt: `hwinv: key=value` -- Firmware (UEFI/BIOS), Storage-Art + Urteil (`storage_verdict`; `raid-rst-nvme-hidden` = BIOS steht auf RAID/RST), GPU, WLAN (Chip + Treiberstand), Ethernet, Audio, I2C-Controller, Zeigegeraet-Weg, xHCI, USB (Tastatur/Kamera/BT) plus Rohkopie.
- **Rueckweg A -- Bruecke:** mit Netz (Kabel/Dongle/Tethering) meldet sich `jarvisd` am Server an; JARVIS liest `/var/jarvis/hwinv.txt` selbst (`read`, Pfad ist freigegeben). Dieses Stick-Abbild enthaelt keine persoenlichen Bruecken-Daten: ohne Bruecken-Konfiguration kommt nur Weg B.
- **Rueckweg B -- Stick:** Laptop aus, Stick am anderen Rechner mounten (Partition 1 = EFI, Partition 2 = OrientOS-Wurzel OFS; Linux liest OFS nicht ohne Werkzeug) -- einfacher: **Foto** vom Terminal mit `hwinv`.
- **Logs auf dem Stick:** `/var/jarvis/panic-N.txt` (N=1..32), `/var/jarvis/boot.log` (nach 20 s Uptime), `/var/jarvis/hwinv.txt`.

## 5. Rueckmeldung (Chat)

1. Klappt der Start? Ja/Nein, bis wohin (Limine / Bootzeilen / Anmeldung / Desktop).
2. Fotos (Panik-Bild, Desktop, `hwinv`-Ausgabe), Modell + BIOS-Version, welcher Limine-Eintrag.
3. Funktioniert: Tastatur? Touchpad? USB-Maus? Bildschirm-Aufloesung? Helligkeit?
4. Dateien aus `/var/jarvis/` falls moeglich.

## 6. Technik (fuer Entwickler)

- Bau: `OSUM_BUILD_JOBS=6 /root/jarvis/bin/heavy bash tools/usbimg/build.sh <dir>` (Cache `/root/.osum-bcache`, ~2-5 min).
- Gates: `STICK_IMG=<img> KERNEL=<osum.mb> heavy bash tools/ovmfboot/run.sh` (UEFI/OVMF, AHCI+NVMe), `bash tools/hwinv/run.sh`, `bash tools/hwinv/guest.sh`, `bash tools/install/abnahme.sh`, `bash tools/hwcheck/run.sh`.
- Zustandsdaten im Kern: `/proc/safe`, `/proc/firmware`, `/proc/pci`, `/proc/usb`.

## Fern-Test per USB-Tethering (Zwischenloesung bis WLAN laeuft)
1. **Handy vorbereiten:** Android: Einstellungen > Netzwerk > Hotspot und Tethering > **USB-Tethering einschalten** (das Handy braucht dafuer Mobilfunk oder WLAN). Alternativ ein USB-Ethernet-Dongle (ASIX AX88772, CDC-ECM) mit LAN-Kabel zum Router.
2. **Kabel einstecken:** Handy/Dongle in einen USB-Port des HP stecken. Beim Handy erst NACH dem Boot oder davor -- beides geht (Stecken im laufenden Betrieb ist eingebaut).
3. **Warten:** bis zu 1 Minute. OrientOS holt sich selbst eine Adresse (DHCP) und `jarvisd` meldet sich an der Bruecke an (nichts eintippen). DHCP versucht es nach Fehlschlag mit 5/10/20/40/60 s Abstand erneut.
4. **Pruefen:** im Terminal `dhcp status` (zeigt IP) oder Datei `/var/jarvis/hwinv.txt` auf dem Stick: Zeile `net: up ip=...`. Auf dem Handy erscheint "USB-Tethering aktiv".
5. **Melden:** "steht" in den Chat -- JARVIS testet dann aus der Ferne (Bruecke/ODB). Klappt es nicht: Foto vom Schirm + `/var/jarvis/*` und die Zeilen `usb: port=... driver=...` (steht dort `driver=none`, bitte Handy-Modell nennen; Android mit "Dateiuebertragung (MTP)" als erste USB-Konfiguration kann der Treiber noch nicht umschalten -- Tethering dann vor dem Einstecken einschalten).
