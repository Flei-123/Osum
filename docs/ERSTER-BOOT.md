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

## Stick 9 HP (24.10.2026, Baustand 7f8c161e = main mit APMG-Fix)

- **Datei:** `orientos-usb-hp-20261024-7f8c161e.img` (146 MiB, GPT, UEFI+BIOS). SHA256 vorher pruefen: `6df57b6cd58d6b058336f8323ccf5067dbdb6e747b208d6ced37cae5be1db741`. Ersetzt Stick 8 (SHA 64881751...).
- **Neu gegenueber Stick 8:** WLAN-8265 (Familie 8000) schreibt keine APMG-Register mehr (0x300C ist dort RELEASE_CPU_RESET -> die alten Schreibzugriffe liessen CPU2 haengen), setzt CSR_GIO_REG L0S_DISABLED wie Linux.
- **Ehrlich:** Am echten 8265 UNVERIFIZIERT.
- **Foto-Checkliste:** `cat /proc/wlan` -- alle Zeilen (phase, err, failed_at, fail_alive, fail_regs, fail_fh). Laeuft WLAN: Einstellungen > WLAN verbinden, dann nochmal `cat /proc/wlan`.

## Stick 8 HP (24.10.2026, Baustand a494ab5d = main mit ALIVE-Fix)

- **Datei:** `orientos-usb-hp-20261024-a494ab5d.img` (146 MiB, GPT, UEFI+BIOS). SHA256 vorher pruefen: `648817516761259ae77f2f6d1c5bd33fe843380e00b2ed501283f5d98cfb645c`. Ersetzt Stick 7 (SHA 4daaae3b...).
- **Neu gegenueber Stick 7:** WLAN-8265 ALIVE-Wartezeit 2,5 s nach Tick-Uhr (vorher ~70 ms), ALIVE gilt bei CSR_INT Bit 0, Bit 31 oder Paket im RX-Ring (wie Linux). Das erste Fehlerfoto bleibt erhalten (vorher mit int=0 ueberschrieben). Neue Zeile `fail_alive=int= fhint= gp1= gp2= cpu1= cpu2= wfp= seen=` in `/proc/wlan`. Dazu EC-Treiber + `/proc/hotkeys`, Touchpad-Tipp-Sperre, WLAN-Link-Ueberwachung, PBKDF2 in Etappen.
- **Ehrlich:** Am echten 8265 UNVERIFIZIERT.
- **Foto-Checkliste:** (1) `cat /proc/wlan` -- alle Zeilen (phase, err, failed_at, fail_alive, fail_regs, fail_fh). (2) Fn+Helligkeit 3x, dann `cat /proc/hotkeys` und `cat /proc/backlight`. (3) Falls WLAN laeuft: Einstellungen > WLAN verbinden, dann `cat /proc/wlan`.

## Stick 7 HP (24.10.2026, Baustand 6f9bbf42 = main ohne Touchpad-Tipp-Sperre f7855e52) -- abgeloest durch Stick 8

- **Datei:** `orientos-usb-hp-20261024-6f9bbf42.img` (146 MiB, GPT, UEFI+BIOS). SHA256 vorher pruefen: `4daaae3b2ab0f42bd8ad4a9f943be4fcd15a7c234129c8e0b076472e92d7c714`. Ersetzt Stick 6 (SHA 0e21cfb0...).
- **Neu gegenueber Stick 6:** WLAN-8265-Firmware-Ladefehler `fw_load_init err=-45` (FH end-of-TFD timeout) behoben: PCI-Bus-Master wird vor dem Firmware-Laden gesetzt (vorher nie -> kein DMA), APMG-DMA-Takt + NIC-Funkkonfig fuer Familie 8000. `/proc/wlan` hat neue Diagnosezeilen `fail_hw=`, `fail_fhr=`, `fail_fh=`. Dazu: wlan.conf speichern als normaler Nutzer + Persistenz auf der Stick-EFI-Partition, Fn-Helligkeitstasten (`/proc/hotkeys`), Explorer-Rand ziehen ohne Flackern.
- **Ehrlich:** Wirkung am echten 8265 UNVERIFIZIERT -- das ist genau der Test. Scan-Anfrage der echten Firmware (v7) ist noch NICHT umgestellt (Worker W-WLAN18b); selbst wenn die Firmware jetzt laedt, kann der Scan noch scheitern.
- **Foto-Checkliste:** (1) Terminal `cat /proc/wlan` -- phase, err, failed_at und die neuen `fail_*`-Zeilen (alle Zeilen auf das Foto). (2) Fn+Helligkeit hoch/runter je 3x, dann `cat /proc/hotkeys` und `cat /proc/backlight` -- Foto; meldet: aendert sich die Helligkeit, eine Stufe pro Druck? (3) Einstellungen > WLAN: SSID + Passwort speichern, Neustart: Stehen SSID/Passwort wieder drin (`cat /etc/wlan.conf`)? (4) Explorer-Fensterrand ziehen: Flackern ja/nein?

## Stick 6 HP (24.10.2026, main e2bf91e6) -- abgeloest durch Stick 7

- **Datei:** `orientos-usb-hp-20261024-e2bf91e6.img` (146 MiB, GPT, UEFI+BIOS). SHA256 vorher pruefen: `0e21cfb022d7ef4796e61ff2007ca93a7fc09dfb4f2cfe828c39a605afa2e3b6`. Ersetzt Stick 5 (SHA 435a5f54...).
- **Neu gegenueber Stick 5:** Netzkarte `wlan0` (Task K_WLAN, DHCP aus dem Lease), Auto-Join aus `/etc/wlan.conf`, `/proc/wlan` mit `net <ssid> ch= sec= rssi=`, `auto=<state> rc= tries= driver=` und `ip= mask= gw=`. Fake-AP-Gegenstelle nur im Test.
- **Ehrlich:** Am echten 8265 UNVERIFIZIERT (Daten-TX ueber Cmd-Queue 0, kein Beacon-Loss, kein Scan waehrend verbunden). Ziel: sehen, wie weit phase/net/auto kommen.
- **Foto-Checkliste:** (1) Terminal `cat /proc/wlan` -- phase, err, fw, nvm, calib, net-Zeilen, auto=. (2) Einstellungen > Netzwerk > WLAN: Suchen, Netz waehlen, Verbinden (Passwort), danach nochmal `cat /proc/wlan` -- Foto. (3) Strg+Shift+F (Entwickler-Overlay) -- Foto. (4) Bei Haenger/Panik: Neustart mit Kernelwort `noiwl` (WLAN aus), Foto der Bootzeile.

## Stick 5 HP (24.10.2026, main 2380d6c4) -- abgeloest durch Stick 6

- **Datei:** `orientos-usb-hp-20261024-2380d6c4.img` (146 MiB, GPT, UEFI+BIOS). SHA256 vorher pruefen: `435a5f545d8207aebb6ffec2a22a9fb192f5c1e30636ed6d21321311c8c671c4`. Ersetzt Stick 4 (SHA 79dbb51a...).
- **Neu gegenueber Stick 4:** WLAN-Treiber 8265 mit Befehlswarteschlange, INIT-/RT-Firmware-Boot und Auto-Start auf 8086:24fd, `/proc/wlan` (phase, err, fw, nvm, calib), Einstellungen > **WLAN** schreibt `/etc/wlan.conf` (0600), SMP-/Helligkeits-/Touch-Korrekturen aus main. Kernelwort `noiwl` schaltet den WLAN-Autostart ab.
- **Ehrlich:** Verbinden ist am echten Silizium UNVERIFIZIERT (Firmware-Werte nur gegen Fake-Firmware geprueft). Ziel dieses Sticks: `/proc/wlan` zeigt, wie weit der Firmware-Boot am HP kommt.
- **Gates:** ovmfboot, hwinv-guest 57/0, touchsim 37/0; echte HP-Hardware nicht getestet.

## Stick 4 HP (24.10.2026, main b2937208) -- abgeloest durch Stick 5

- **Datei:** `orientos-usb-hp-20261024-b2937208.img` (146 MiB, GPT, UEFI+BIOS). SHA256 vorher pruefen: `79dbb51ac7af1e648794fd0aa65d768e6eca89c9a4cde496f230834e75078b10`. Ersetzt Stick 3 (SHA b6d20b62...).
- **Neu gegenueber Stick 3:** Touchscreen auf Geraeten mit mehreren I2C-Reglern (i2chid Mehr-Regler + AML-Geraetesuche, `/proc/inputdevs`), Touchpad-Gesten + Einstellungen-Seite **Touchpad**, Rechtsklick per Touchpad-Ecke (Ecke unten rechts), Touchscreen-Gesten (tippen/ziehen/zwei Finger/lang = Rechtsklick).
- **Weiterhin:** WLAN 8265 ist Sim (echtes Verbinden nicht zugesagt), Fn-Helligkeitstasten am HP unbekannt. Bekannte Flake: Einstellungen-Gate nav1 (nur Testproblem, nicht Stick).

## Stick 3 HP (23.10.2026, main 4977617c + Bundle-Fix 03a803f0) -- abgeloest durch Stick 4

- **Datei:** `orientos-usb-hp-20261023-03a803f0.img` (146 MiB, GPT, UEFI+BIOS). SHA256 vorher pruefen: `b6d20b625c057e6a323428556862da6319c9012a8c2c68ceb922d1100664aca9`. Ersetzt den Stick 30d66381 (SHA 654d7e03...).
- **Neu gegenueber Stick 2:** Mehrkern-Fix (SMP2 + Kick-IPI, `/proc/cpus`, Bootzeile `smp: N of M online`), Fallback-Icons (Buchstaben-Kachel in Leiste/Startmenue/Alt+Tab/Task-Manager), Fenster-Snap per Titelleisten-Ziehen, Tray-Chevron-Flyout (Raster/Hover/Rechtsklick), Taskleisten-Hover, Windows-11-Leiste.
- **Noch NICHT im Stick:** Touchscreen auf Geraeten mit mehreren I2C-Reglern (i2chid Mehr-Regler, TOUCH3) und die Touchpad-Gesten-Settings (TPSET3) -- beide noch in Arbeit, nicht in main.
- **Weiterhin:** WLAN 8265 ist Sim (echtes Verbinden nicht zugesagt), Fn-Helligkeitstasten am HP unbekannt.

## Zwischen-Stick HP (23.10.2026, main 30d66381) -- abgeloest durch Stick 3

- **Datei:** `orientos-usb-hp-<datum>-<commit>.img` (Pfad + SHA256 im Bericht `reports/*_w-stick2-*.md`). SHA256 vorher pruefen: `654d7e03d1e3cab95cf8db738ebda243558a8d793bd043ddc956eaa598f9f57c` (Datei `orientos-usb-hp-20261023-30d66381.img`, 146 MiB, GPT, UEFI+BIOS)
- **Neu im Stick:** Rechtsklick-Menue schliesst per Wegklick, USB-Tethering + Bridge-Auto-Login, Helligkeitskette (`/proc/backlight`), Overlay/fbperf/Resize-Fix, WLAN-8265-Treiber (Sim, Firmware `iwlwifi-8265-36.ucode` gebuendelt), Touch-Pfad (Touchscreen/Stift).

## Was der Boss fotografieren soll

0. **WLAN (Stick 6/7):** Terminal: `cat /proc/wlan` -- Foto (phase/err/err_text/fw/nvm/calib, net-Zeilen, auto=). Dann Einstellungen > WLAN: SSID + Passwort eintragen, speichern, nochmal `cat /proc/wlan` -- Foto. Bei Haenger/Panik Neustart mit Kernelwort `noiwl` (Foto der Bootzeile).
   - **WLAN-Persistenz (ab main 4b852a81):** gespeicherte SSID/Passwort wird vom Dienst `wlanpersist` auf die EFI-Partition (`wlan.cnf`) gespiegelt und beim Boot zurueckgespielt (nur wenn die Wurzel RAM ist). Settings zeigt sonst "Nur bis zum Neustart gespeichert".
0b. **Helligkeits-Tasten (Fn):** Fn+Helligkeit hoch/runter druecken (je 3x), danach Terminal: `cat /proc/hotkeys` -- Foto. Jede Taste, die nicht Helligkeit aendert, steht dort als `ext 0x.. unknown` / `key 0x.. unknown` / `acpi 0x.. unknown` (das ist der echte Code); dazu `cat /proc/backlight` (Zeilen `hotkeys`, `acpi.notifies`, `acpi.lastnt`, `ext.last0..3`). Meldung ja/nein: aendert sich die Helligkeit, und springt sie pro Tastendruck um GENAU eine Stufe (nicht zwei)?
1. **Overlay:** `Strg+Shift+F` -- Foto vom ganzen Schirm (Zeile `fb_write_mbs`, FPS, CPU, RAM).
2. **Terminal** (Win-Taste, "terminal"): je ein Foto der Ausgabe von
   - `cat /proc/backlight`
   - `cat /proc/frames`
   - `cat /proc/cpuinfo`
   - `cat /proc/inputdevs` (Touchpad/Touchscreen/I2C-Regler: welche Geraete erkannt, Treiber)
   - `cat /proc/cpus` (Mehrkern: `cpus_online`/`cpus_madt`, je Kern `why`/`esr` falls einer nicht hochkommt) und die Bootzeile `smp: N of M online`
   - `cat /var/jarvis/hwinv.txt`
3. **USB-Tethering:** Handy per Kabel an den HP, am Handy "USB-Tethering" einschalten. Foto vom Terminal nach `ip` bzw. der Zeile `net: up ip=` und ob `jarvisd` sich meldet.
4. **Rechtsklick:** Touchpad-Rechtsklick, Menue wegklicken, nochmal Rechtsklick -- muss wieder aufgehen. Kurz melden ja/nein.
5. **Touchscreen:** antippen, ziehen, zwei Finger scrollen, lange tippen (= Rechtsklick). Melden was geht. **Foto von `cat /proc/inputdevs`** (zeigt jedes Eingabegeraet: Touchpad, Touchscreen, Stift, I2C-Regler).
5b. **Touchpad-Einstellungen:** Einstellungen > **Touchpad** oeffnen (Tippen, Gesten, Scroll, Ecken-Rechtsklick) -- Foto der Seite; je eine Einstellung aendern und melden ob es wirkt.
5c. **Ecken-Rechtsklick:** Touchpad unten rechts antippen -- Kontextmenue? Ja/nein.
6. **WLAN (Sim-Hinweis):** der Treiber ist Sim, es kann sein, dass nichts verbindet -- das ist erwartet. `wlan verbinden <SSID> <Passwort>` -- Foto der Ausgabe. Der WLAN-Treiber ist noch Sim, **echtes Verbinden ist nicht zugesagt**.
7. **Absturz/Panik:** Schirm fotografieren, danach `/var/jarvis/*` wie oben (Punkt 7-8).
8. **Fenster-Snap:** ein Fenster an der Titelleiste an den linken/rechten/oberen Rand ziehen -- Vorschau + Einrasten? Foto.
9. **Tray:** den Chevron (^) rechts in der Taskleiste anklicken -- Flyout mit Symbol-Raster; Hover und Rechtsklick darin. Foto.
10. **Taskleisten-Hover:** Maus ueber Programmsymbole in der Leiste -- Hover-Hervorhebung/Vorschau da? Kurz melden.
11. **Fallback-Icons:** Programme ohne eigenes Symbol (Leiste, Startmenue, Alt+Tab, Task-Manager) -- Buchstaben-Kachel statt leer? Foto.
