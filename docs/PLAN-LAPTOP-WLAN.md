# PLAN-LAPTOP-WLAN — Netz auf dem Laptop (Surface Laptop 4, HOLO-LAPTOP-3)

Stand 21.10.2026. Boss-Auftrag: WLAN fuer OrientOS, zuerst planen, dann bauen. Roadmap-Gruppe `LAPTOP/WLAN`, Punkte LW-1.. (Vorarbeit: r21 N-005, r118, L-015/L-017, `docs/WLAN-AX201.md`, `docs/USBNET.md`, `docs/RUNDE-WLAN3.md`).

Regeln: Code nur Englisch, kleine Module, Registries, keine Kommentare. Keine Linux-iwlwifi-Kopie (GPL): eigene Umsetzung nach Spezifikation/Messung. Firmware-Blob nie einchecken, nur SHA-256 pinnen.

## 1. Referenzgeraet (gemessen unter Windows, `docs/WLAN-AX201.md`)

| Teil | Wert |
|---|---|
| WLAN | Intel AX201 160MHz, `PCI\VEN_8086&DEV_A0F0&SUBSYS_00748086&REV_20`, CNVi (MAC im PCH, nur RF auf dem M.2-Modul), Tiger-Lake-LP-PCH |
| Bluetooth | Teil desselben Moduls, haengt per USB am PCH (btusb-Klasse, Firmware noetig) |
| Ethernet | keine Buchse; vorhandener USB-Dongle `1A86:5394` (CH336, Vendor-Klasse FF/FF/FF) |
| Tastatur/Touchpad | Surface-Intel-Modelle haengen am Surface Aggregator (nicht USB-HID) — *aus Linux-surface-Wissen, hier ungemessen*: fuer den ersten Stick-Test externe USB-Tastatur einplanen |

Firmware-Wahl: Linux waehlt die Datei zur Laufzeit aus `CSR_HW_REV` (Qu-b0/Qu-c0/QuZ-a0). Die Annahme "QuZ" in `WLAN-AX201.md` ist fuer A0F0 (Tiger Lake) **nicht belegt** (QuZ gehoert zu Comet Lake); Qu-c0-hr-b0 ist wahrscheinlicher. Entscheidet die Boot-Zeile `iwl: hw_rev=..` auf dem echten Geraet. Treiber muss eine Tabelle `hw_rev -> Dateiname` haben, kein Fest-Name.

## 2. Ist-Stand (Quelltext gelesen, Gates aus Doku)

### 2.1 Netzstack
- `kernel/net/netdev.fi` (1485 Z.): Kartentabelle, KIND_* (virtio, e1000/I219, r8169, **KIND_USBNET**), einheitliche Zugriffe `rx_take_on/tx_frame_on/poll_on/...`. USB-NIC hat bereits eine Art (`usbnet.exists`); **genau eine Einheit** (ein Zustandsblock in `usbnet.fi`).
- DHCP/DNS/TCP/TLS: `kernel/net/inet.fi`, `netsvc.fi`, `netview.fi` (Kachel/Status), `netmon.fi`. Alle haengen an `netdev`-Karten, nicht an PCI — eine WLAN-Karte muss nur eine weitere `KIND_` mit denselben Accessoren sein (Plan Punkt LW-6).
- Settings: Route `settings://network` und `settings://network/connections` existieren in `kernel/user/settings.d/settings.routes` (Seiten ohne Funktion). Neue Seiten laufen ueber die Route-Registry (`lib/nav`), nicht ueber Sonderfaelle in `settings.fi` (Besitzer W-NAV).

### 2.2 PCI-Geruest
- `pci.scan`, MSI-X-Pfad im Netdev-Init (`irq_kind`, `msix_on`), `apic.map_device` fuer BAR0, DMA-Puffer wie bei e1000/r8169.
- `kernel/drv/net/iwl.fi` (206 Z., M1b): findet 8086:A0F0 etc., mappt BAR0, **liest** vier CSRs, schreibt nichts. QEMU-Gate nur fuer "kein Geraet".
- Firmware aus Dateisystem laden: **fehlt** (WLAN ist damit ein spaeter Dienst, nach dem VFS).

### 2.3 lib/wlan (18 Dateien, 6250 Z.) — hardwareunabhaengige Haelfte steht
`frame` (802.11-Codec), `beacon` (Beacon/RSN-Parser), `channel` (Regulatorik), `ccmp`, `wpa` (WPA2-PSK 4-Way), `llc`, `connect` (Sitzung), `state`, `scanfmt`, `device` (Treibertafel mit 4 Funktionen: senden/empfangen/kanal_setzen/schluessel_setzen), `testdevice`; Chipseiten: `ar9271`/`htc`/`usbchip` (USB, AR9271), `iwl_probe`/`iwl_fw`/`iwl_pwr`/`iwl_ctxt` (AX201 M1-M3 als Bibliothek).
Gates: `tools/wlan/run.sh` (184 Checks laut Doku), `tools/wlan-ax201-m2/run.sh` 27/0 + 9 Gegenproben, `tools/wlan-ax201/run.sh`, `-glue` (QEMU).
Bewiesen: voller Weg Scan -> Auth -> Assoc -> 4-Way (echte Capture) -> CCMP -> DHCP -> HTTP gegen Python-Gegenstelle (`tools/wlan/gegenstelle.py`, `vollweg.py`).
**Nicht** bewiesen: dass echtes Silizium mit unseren Layouts uebereinstimmt (TLV-Nummern, Context-Info-Offsets, Register aus dem Gedaechtnis).

### 2.4 USB-Netz (L-015) — weiter als die Doku in `LAPTOP-HW-FEASIBILITY.md` sagt
- `lib/usbnet/{rndis,ncm,ch397}.fi`, Treiber `kernel/drv/net/usbnet.fi` (Modus ECM/RNDIS/NCM), Einbindung in `kernel/usb/usb.fi` (`DRV_ECM/RNDIS/NCM`, Zwei-Durchgaenge-Konfigurationswahl, Wort `rndisonly`).
- Gates: `tools/usbecm` 8/0 (QEMU, usb-net), `tools/usbrndis` 12/0 (QEMU), `tools/ncm/run.sh` 74 (nur Host, QEMU kennt kein NCM), `tools/usbnet/run.sh` 53/0 (Protokollcode), `tools/ch397/run.sh` 20 (nur Host).
- Luecken: **RNDIS-Keepalive/Indications** (Android-Gadgets trennen sonst nach einigen Sekunden), Hot-Unplug, Link-Status/Notification-Endpoint, nur **eine** USB-NIC, **Vendor-Klasse-Chips fehlen in `usb.fi`**: CH336 (der echte Dongle des Boss), ASIX AX88772/AX88179, Realtek RTL8152/8153, Apple-ipheth (iPhone-Tethering).

## 3. Optionen (Aufwand / Risiko)

| # | Weg | Aufwand | Risiko | Test ohne HW | Nutzen fuer den Boss |
|---|---|---|---|---|---|
| 1 | USB-Tethering (RNDIS/ECM/NCM) + USB-Ethernet (CH336, ASIX, r8152) | Rest ~1 500-2 500 Z. | niedrig (Protokolle offen dokumentiert, xHCI-Bulk laeuft) | **QEMU `usb-net`** fuer ECM/RNDIS; Host-Orakel fuer NCM/Vendor-Chips | sofort online (Handy-Kabel, Dongle) |
| 2 | Intel AX201 (iwlwifi-Aequivalent, eigene Implementierung) | ~6 000-7 000 Z. nach Doku (Context-Info-Boot, Command-/RX-/TX-Ringe, MAC/PHY/Binding/Station, Scan, Auth/Assoc, Keys) | **hoch**: CNVi, proprietaere Firmware, jedes Detail braucht das echte Geraet, keine Emulation | nur CSR-Simulation + Fake-Firmware-Gegenstelle | das eigentliche Ziel, aber mehrere Hardware-Iterationen |
| 3 | Realtek rtw88/89, Broadcom | je ~4 000+ Z. | hoch, anderes Geraet | wie 2 | nicht Surface; spaeter |
| 4 | USB-WLAN-Stick (AR9271 vorhanden als Bibliothek, MT7612U) | ~2 000-3 000 Z. | mittel | Registerattrappe | Notnagel ohne PCIe/CNVi, ~10 EUR |
| 5 | Bluetooth-PAN | HCI/USB (Firmware ibt-*), L2CAP, BNEP, PAN-Profil | hoch, gehoert zu r6 (K-006) | HCI-Orakel | spaeter, nur Verweis |
| 6 | WPA3-SAE, 802.11w | ~900 + 350 Z. | Krypto ohne Vektoren (siehe 5) | RFC-9380/IEEE-Vektoren | nach WPA2 |

Empfehlung: Option 1 zuerst (liefert sofort Netz und reale Datenpfad-Erfahrung), parallel Option 2 nur soweit ohne Hardware pruefbar. AX201 bleibt bis zum ersten Stick-Boot `unproven`.

## 4. Teststrategie ohne Hardware
1. **QEMU**: `-device qemu-xhci -device usb-net` (ECM + RNDIS), Gates `usbecm`/`usbrndis`; fuer Vendor-Chips (CH336, ASIX, r8152) ein **Host-Orakel** wie `tools/usbnet/oracle.fi` (Python-Referenz fuer Rahmenformat + Registerfolgen) und, wo QEMU ein Modell hat, nichts erfinden.
2. **Host-Harness 802.11**: `tools/wlan/gegenstelle.py` (Fake-AP) bleibt; Erweiterung: Referenzvektoren aus IEEE 802.11-2020 (PBKDF2-PMK, PRF-PTK, CCMP, MIC, Key-Unwrap) und Gegenlauf mit `wpa_supplicant`/`hostapd` aus dem Server-Paket (vorhanden: `/usr/sbin/hostapd`, `/usr/sbin/wpa_supplicant`). `mac80211_hwsim` ist auf dem Server **nicht** ladbar (Modul fehlt) — hostapd nur ueber ein eigenes UDP/pcap-Frame-Gegenstueck oder `-Q`-Testmodus pruefen; Gegenprobe: ein verdrehtes Bit bricht jede Stufe.
3. **CSR-Simulation AX201**: bestehendes Modell aus `tools/wlan/iwlpwr.fi`; Erweiterung um ein Fake-ALIVE (Firmware-Zustand), Command-Ring + Notification-Ring, damit Ringindizes, Timeouts, Reset-Pfad vor dem Laptop laufen.
4. **Echte Abnahme**: erst wenn der Boss bootet. Live-Stick fuer Surface Laptop 4: `tools/usbimg/build.sh` (BIOS+UEFI, Limine). Surface-UEFI: Boot von USB mit Lautstaerke-Taste ab + Einschalten halten; Secure Boot ist fuer unseren unsignierten Lader auf "None" zu stellen (Surface-UEFI-Menue). Keyboard: externe USB-Tastatur bereithalten. Testheft `reports/TESTANLEITUNG-LAPTOP.md` bekommt einen WLAN-Abschnitt (LW-9).
5. **Gegenprobe-Pflicht**: jedes Gate hat eine Variante, die den neuen Code umgeht und rot wird.

## 5. UI (Netzwerk-Seite) — Route + Modul, nicht settings.fi
- Neue Zeilen in `settings.routes`: `settings://network/wifi` (Liste, Signal, Verbinden, Kennwort), `settings://network/usb` (Tethering/Dongle-Status) unter `settings://network`; `controls`/Suchbegriffe ueber i18n-Schluessel (kurz, msg SLOTS 1280 beachten).
- Logik in eigenem Modul `kernel/user/netpage.fi` (Seitenbild) + Modell `lib/netui/` (Liste sortieren nach Signal, Balken 0-4, Sicherheitsbezeichnung, Verbindungszustand, Passwort-Eingabe-Zustandsmaschine) — **host-testbar** (`tools/netui`).
- Datenquelle: `scanfmt`-Zeilen (`ssid ch=N sec=.. rssi=-NN`) aus `/proc/wlan`; Verbinden ueber ein Ring-3-Programm `wlan` (existiert als `/bin/wlan`, Runde WLAN) / spaeter RPC.
- Tray: Netz-Symbol in `taskbar.fi` (Besitzer W-STAB) — nur Wunsch an W-STAB melden: Zustaende aus `netdev.link_up_on` + Signal.
- Abstimmung noetig mit W-NAV (Route-Tabelle, Seitenindizes `settings.pagemap`) — bis dahin nur Modell + Gate, keine Eingriffe in `settings.fi`.

## 6. Meilensteine / Gates

| ID | Inhalt | Gate (Ziel) | HW |
|---|---|---|---|
| LW-1 | USB-Netz haerten: RNDIS-Keepalive, Hot-Unplug, Link-Status, mehrere NICs; ECM/RNDIS/NCM fertig; **Vendor-Chips**: CH336 (`1A86:5394`), ASIX AX88772/AX88179, Realtek RTL8153 (r8152-Familie), optional Apple ipheth | `usbecm`, `usbrndis` gruen + neues `tools/usbvendor` (Orakel je Chip, Gegenproben), `ncm` | Dongle/Handy: Boss |
| LW-2 | 802.11/WPA2 host-testbar abschliessen: IEEE-Vektoren, GTK-Rekey, Group-Handshake, Replay/Fragment-Haertung, Rate-/Capability-Parsing (HT/VHT/HE-Capabilities lesen), Roaming-Zustaende, Gegenlauf mit `wpa_supplicant`/`hostapd`-Referenz | `tools/wlan/run.sh` (+Vektor-Abschnitt), `tools/wlan/ref.sh` | nein |
| LW-3 | AX201-Skelett: PCI-Probe -> Firmware-Datei-Auswahl nach `hw_rev` -> Laden aus VFS -> Context-Info -> `fw_kick` -> ALIVE-Wait (Timeout, Fehlerzeilen); Fake-ALIVE in der CSR-Simulation | `tools/wlan-ax201-m2` (+Skelett-Abschnitt), `-glue` | echter ALIVE: Laptop |
| LW-4 | AX201 Kommando-Ebene: Command-Queue, INIT_COMPLETE, NVM/MAC, RX-Queue + Notifications | Simulation | Laptop |
| LW-5 | Netz-UI: Routen + `netpage.fi` + `lib/netui` + Tray-Wunsch | `tools/netui` (Host), Settings-Gate bleibt gruen | Sichtpruefung: Boss |
| LW-6 | WLAN als `netdev`-Art (`KIND_WLAN`), `/proc/wlan`-Scan, `wlan connect` bis DHCP | QEMU mit Software-Funkstrecke (Fake-Device) | Laptop |
| LW-7 | AX201 MAC/PHY/Binding/Station/Scan/Auth/Assoc/TX | Simulation | Laptop |
| LW-8 | WPA3-SAE + 802.11w, Bluetooth-PAN (nach r6) | Vektoren | Laptop |
| LW-9 | Live-Stick Surface Laptop 4: Testanleitung, Secure-Boot-Hinweis, serielle/`ODB`-Auslese, Boot-Zeile `iwl:` + `usb:` | Boss bootet | **Boss** |

Build-Reihenfolge dieser Runde: LW-1 und LW-2 parallel (Unterworker, disjunkte Dateien), dann LW-3. LW-5 nur Modell, nach Abstimmung mit W-NAV. Alles ab LW-4 braucht den echten Laptop.

## 7. Dateibesitz (Kollisionsregel)
- LW-1: `kernel/usb/usb.fi`, `kernel/drv/net/usbnet.fi`, `lib/usbnet/*`, `tools/usb*`, `tools/ncm`, `tools/ch397`.
- LW-2/3: `lib/wlan/*`, `tools/wlan*`, `kernel/drv/net/iwl.fi`.
- LW-5: `lib/netui/*`, `kernel/user/netpage.fi`, `tools/netui` (Route-Zeilen in `settings.routes` erst nach Absprache).
- Nicht anfassen: `settings.fi`, `explorer.fi`, `wm.fi`, `taskbar.fi`, `taskmgr.fi`.

## 8. Risiken
- AX201 ist CNVi und braucht unveroeffentlichte Details nur im Linux-Quelltext/echtem Geraet; Gruen im Host-Gate beweist nur interne Konsistenz.
- Firmware-Redistribution: Intel-Lizenz erlaubt unveraenderte Weitergabe; wir checken nichts ein (SHA-256-Pin), Datei vom Nutzer/Installer. Lizenztext vor einem Paket im Store neu lesen.
- Secure Boot und Surface-Tastatur koennen den ersten Test blockieren (siehe 4.4).
- RNDIS-Handys: manche brauchen Keepalive und Konfigurationswechsel; ohne echtes Handy nur gegen QEMU geprueft.

## Nachtrag 21.10.: Ziel-Laptop HP X3U19AV hat Intel 8265, nicht AX201

- Zielgerät laut HP-Datenblatt: Intel Dual Band Wireless-AC 8265 (PCI 8086:24fd, Familie „8000“). Details und Quellen: `docs/PLAN-HP-LAPTOP.md`.
- Unterschied zu AX201 (Qu): kein CNVi, kein Context-Info; Firmware (`iwlwifi-8265-*.ucode`) wird über das ältere Chunk-Verfahren (FH-Kanäle, Sektionen einzeln) geladen. `lib/wlan/iwl_probe.fi` kennt 8265 nicht (`family_of` = FAM_NONE) — die Inventur (`hwinv`) meldet `wlan=8086:24fd intel-8265 driver=none`.
- Folge: LW-1a/3a/2a (AX201) helfen dem HP nicht direkt; wiederverwendbar sind 802.11/WPA-Teile in `lib/wlan`. Für den HP zuerst USB-Ethernet/Tethering (LW-USB), 8265-Treiber als eigener Punkt (HP-9).
