# WLAN-TREIBER — Plan und Start (Roadmap r21 / r118)

Stand 02.10.2026, Zweig `daily-driver`. Aufbauend auf `docs/WLAN-BEFUND.md`,
`docs/WLAN.md` und `docs/RUNDE-WLAN3.md`. **Jede Aussage ist gekennzeichnet:**
**[Quelle]** (aus Dateien/Docs des Baums gelesen), **[gemessen]** (hier ausgeführt),
**[unbekannt]** (niemand hat es nachgesehen).

## 1. Wo wir stehen

* **[Quelle]** Der ganze Weg oberhalb des Treibers läuft gegen ein simuliertes Gerät
  durch: Suchlauf, Netzwahl, Authentifizierung, Assoziation, 4-Wege-Handschlag, CCMP,
  DHCP, HTTP (`lib/wlan/*.fi`, 4665 Zeilen, `lib/wlan/testdevice.fi`).
* **[Quelle]** Ein Treiber muss **genau vier Funktionen** füllen (`lib/wlan/device.fi`):
  `senden`, `empfangen`, `kanal_setzen`, `schluessel_setzen` — plus die eigene
  Adresse und das Kennzeichen `kann_ccmp`. Firmware, Ringe, Interrupts, Raten,
  Stromsparen sind Privatsache des Treibers.
* **[Quelle]** Ein Ring-3-Programm `wlan` (`kernel/user/wlan.fi`) bedient den Weg;
  `kernel/usb/usb.fi` schreibt für jeden erkannten USB-WLAN-Chip eine Zeile
  `wifi-usb: <Name> (<vid>:<pid>), kein Treiber`; `kernel/lib/chipname.fi` benennt
  Intel-WLAN-Karten am PCI-Bus (AX200/AX201/AX210/7265/8260/8265).
* **[Quelle]** Es gibt **keinen Funktreiber** (r21). QEMU hat kein WLAN-Gerät, der Server
  ist ein Container ohne PCI/USB-Durchreichung (`RUNDE-WLAN3.md` §1, 10 Fragen gemessen).
  Ein Treiber ist deshalb **nur am echten Gerät prüfbar**.

## 2. Das fehlende Wissen — und warum alles daran hängt

Welcher WLAN-Chip in welchem Gerät des Boss steckt, steht **nirgends**:

* **[Quelle]** Justins PC ist ein Desktop (Ryzen 7 3800X, Gigabyte B450M S2H, RTX 3060) —
  ohne bekannte WLAN-Karte; der Dell 9020 ist ein OptiPlex-Desktop (nur Ethernet).
* **[Quelle]** `lib/wlan/usbchip.fi` sagt: „In Justins Rechner steckt ein USB-WLAN-Stick,
  dessen Chip niemand kennt."
* **[unbekannt]** ob ein Laptop (und welcher) als Alltagsgerät gemeint ist.

**Ohne diese Angabe wäre jeder Treiber ein Ratespiel** — die USB-WLAN-Welt hat mindestens
sechs Familien, die nichts gemeinsam haben.

### Was der Boss tun muss (5 Minuten, am Zielgerät)

Eine der drei Möglichkeiten genügt:

1. **Windows:** `Get-PnpDevice -Class Net | Format-List FriendlyName,InstanceId` (PowerShell)
   — die Zeile mit `PCI\VEN_xxxx&DEV_xxxx` oder `USB\VID_xxxx&PID_xxxx` für das WLAN.
2. **Linux-Stick/anderer Rechner:** `lspci -nn | grep -i -E 'network|wireless'` bzw. `lsusb`.
3. **OrientOS:** Stick starten, im Terminal `wlan` — es zeigt die erkannten Chips; bei
   unbekannten erscheint die Zeile `wifi-usb: ...` bzw. die PCI-Zeile auf der seriellen
   Leitung / im Foto.

## 3. Entscheidungsbaum (Aufwand je Chip-Familie)

Aufwandszahlen **[Quelle]** `RUNDE-WLAN3.md` §7.2, Rest Einschätzung.

| Chip | Weg | Firmware | Aufwand | Bemerkung |
|---|---|---|---|---|
| **Intel AX200** (PCIe, `8086:2723`) | PCIe-Ringe + Kommando-API | proprietäres `.ucode` (1,37 MB) von der Platte | ~6 700 Zeilen (Punkte 1–3, 5, 6) | **braucht Brett mit M.2-Karte**; AX201 = CNVi, deutlich schwerer |
| Intel 7265/8260/8265 | wie AX200, andere Befehle | `.ucode` | ähnlich | Lizenz linux-firmware: Weitergabe erlaubt, nicht ändern |
| **MediaTek MT7601U / MT76x0U/x2U** (USB) | xHCI-Bulk (vorhanden) + Registerzugriff per Vendor-Request | kleine `.bin` (~20–80 KB) | **kleinster Einstieg**, grob 2 000–3 000 Zeilen | offenster der USB-Chips |
| Atheros **AR9271** (`ath9k_htc`, USB) | HTC-Protokoll über Bulk | **freie** Firmware (`htc_9271.fw`) | ~3 000 Zeilen | Firmware unter freier Lizenz — am saubersten |
| Realtek RTL8188/8192/8812 (USB) | Vendor-Requests + H2C | `.bin` | 3 000–4 000 Zeilen | am häufigsten bei billigen Sticks; viele Varianten |
| Broadcom brcmfmac | FullMAC über SDIO/USB/PCIe | `.bin` + NVRAM-Text | hoch | selten am PC |

## 4. Empfehlung

1. **Sofort (ohne Hardware):** nichts am Treiber — Raten wäre Verschwendung (§2).
2. **Wenn der Chip bekannt ist:** den **kleinsten gangbaren Weg** gehen. Hat der Boss
   keinen WLAN-Chip, der sich lohnt: ein **USB-Stick mit MT7612U oder AR9271 (~10 €)**
   als erster Treiber — USB-Bulk läuft über den vorhandenen xHCI-Pfad (kein PCIe-Ring,
   kein IOMMU), die Firmware ist klein bzw. frei, und die vier Funktionen der Tafel
   lassen sich gegen `testdevice.fi`-ähnliche Registerattrappen vorab prüfen.
3. **Danach** den PCIe-Chip des Alltagsgeräts (AX200 o. Ä.), wenn er sich vom Brett
   des Boss bedienen lässt.

## 5. Meilensteine mit Prüfung

| # | Meilenstein | Prüfung | Hardware |
|---|---|---|---|
| M0 | Chip des Geräts bestimmt (§2) | Zeile `wifi-usb:`/PCI-Name im Foto/auf der Leitung | **ja** |
| M1 | Treibergerüst: erkennen, Firmware prüfen (Signatur) und laden, Registerzugriff, `wlan`-Diagnose | Registerattrappe im Test; am Gerät: Chip antwortet (ID-Register) | teils |
| M2 | `empfangen`/`senden`/`kanal_setzen`: Suchlauf zeigt echte Netze | `wlan scan` zeigt SSIDs der Umgebung (Foto) | **ja** |
| M3 | `schluessel_setzen` + Handschlag gegen echten Router | WPA2-Verbindung, DHCP-Adresse, `ping` | **ja** |
| M4 | Stack andocken (`inet.fi` unter echter Karte), `netview`-Kachel, Auto-Verbinden | Alltagstest: Update über WLAN | **ja** |
| M5 | WPA3-SAE, 802.11w | **nicht ohne veröffentlichte Testvektoren** (bleibt abgelehnt, `RUNDE-WLAN3.md` §7.4) | — |

Firmware wird **nie erfunden und nie ungeprüft aus dem Netz geladen**: Quelle ist
`linux-firmware` (Lizenzdatei prüfen), die Datei kommt als signiertes Paket in den Store.

## 6. Hardware-Prüfpunkte für den Boss

* [ ] Welcher WLAN-Chip steckt im Alltagsgerät? (Zeile aus §2)
* [ ] Gibt es ein Gerät mit eigenständiger M.2-WLAN-Karte (AX200, **nicht** AX201)?
* [ ] Serielle Leitung oder zweiter Rechner zum Mitlesen beim Treiberbau.
* [ ] Ersatzweise einen USB-WLAN-Stick mit AR9271 oder MT7612U kaufen (~10 €).

## 7. Was in dieser Runde NICHT gemacht wurde und warum

Kein Treibercode: ohne bekannten Chip wäre er nicht prüfbar und nicht begründbar (§2). Die
Entscheidung steht in der Projektliste („Welcher WLAN-Chip?"). Sobald die Antwort da ist,
beginnt M1 mit dem passenden Zweig der Tabelle in §3.
