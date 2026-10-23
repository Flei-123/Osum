<!-- SPDX-License-Identifier: GPL-2.0-only -->
# ERSTER-BOOT -- Stick am echten Laptop (HP EliteBook x360 1030 G2 / Dell 9020)

1. **BIOS/UEFI:** Secure Boot AUS; SATA-Modus = AHCI (nicht RST/RAID); USB-Boot erlaubt. HP: Esc, dann F9 = Bootmenue; Dell: F12.
2. **Stick schreiben:** `dd if=orientos-usb.img of=/dev/sdX bs=4M conv=fsync` (Linux) oder Rufus im DD-Modus (Windows). SHA256 vorher gegen den Bericht pruefen.
3. **Start:** Limine-Menue, Eintrag 1 = Schreibtisch. Erwartet: Bootzeilen, Anmeldeschirm, nach Anmeldung Desktop + Leiste, Maus und Tastatur reagieren.
4. **Fremde Platten:** der Stick schreibt NICHTS auf andere Laufwerke (Schreibsperre). Installieren geht nur mit getipptem Plattennamen (`--name <hdX>`).
5. **Sicherer Modus:** im Limine-Menue den Eintrag `(safe mode)` waehlen (ohne Netz/WLAN/Audio/Zusatztreiber). Nach Absturz oder Hang startet der naechste Boot von selbst im sicheren Modus (max. 3 Neustarts, dann Halt ohne Reset).
6. **Zeigt der Schirm "SAFE MODE ...":** der letzte Boot wurde nicht fertig. Zustand steht in `/proc/safe`.
7. **Logs vom Stick:** Stick am anderen Rechner mounten, Ordner `/var/jarvis/` in der Wurzel: `panic-N.txt` (N=1..32), `boot.log` (nach 20 s Uptime geschrieben).
8. **Panik-Bild:** immer FOTOGRAFIEREN (ganzer Schirm, scharf) -- dort steht der Fehlerort. Dazu `panic-N.txt` mitschicken.
9. **Bridge:** mit Netz (Kabel; WLAN 8265 nur mit Firmware) meldet sich `jarvisd` am Server an. Ohne Netz (safe mode) laeuft alles lokal, keine Bridge.
10. **Rueckmeldung:** Foto + `/var/jarvis/*` + Modell/BIOS-Version (HP: F10 BIOS-Setup) an den Chat, nichts selbst reparieren.

## Fern-Test per USB-Tethering (Zwischenloesung bis WLAN laeuft)
1. **Handy vorbereiten:** Android: Einstellungen > Netzwerk > Hotspot und Tethering > **USB-Tethering einschalten** (das Handy braucht dafuer Mobilfunk oder WLAN). Alternativ ein USB-Ethernet-Dongle (ASIX AX88772, CDC-ECM) mit LAN-Kabel zum Router.
2. **Kabel einstecken:** Handy/Dongle in einen USB-Port des HP stecken. Beim Handy erst NACH dem Boot oder davor -- beides geht (Stecken im laufenden Betrieb ist eingebaut).
3. **Warten:** bis zu 1 Minute. OrientOS holt sich selbst eine Adresse (DHCP) und `jarvisd` meldet sich an der Bruecke an (nichts eintippen). DHCP versucht es nach Fehlschlag mit 5/10/20/40/60 s Abstand erneut.
4. **Pruefen:** im Terminal `dhcp status` (zeigt IP) oder Datei `/var/jarvis/hwinv.txt` auf dem Stick: Zeile `net: up ip=...`. Auf dem Handy erscheint "USB-Tethering aktiv".
5. **Melden:** "steht" in den Chat -- JARVIS testet dann aus der Ferne (Bruecke/ODB). Klappt es nicht: Foto vom Schirm + `/var/jarvis/*` und die Zeilen `usb: port=... driver=...` (steht dort `driver=none`, bitte Handy-Modell nennen; Android mit "Dateiuebertragung (MTP)" als erste USB-Konfiguration kann der Treiber noch nicht umschalten -- Tethering dann vor dem Einstecken einschalten).
