# DAILY-DRIVER — Alltags-Lückenliste

Stand 02.10.2026, Zweig `daily-driver` (Basis `main` 632ed76c).
Ziel des Boss: OrientOS **täglich benutzen**, mit **Auto-Update**.

**Wie diese Liste entstand:** Ist-Stand aus Roadmap (Projekt OrientOS, r1–r265), `docs/RUNDE-*.md`, `STATUS-*.md`, `docs/BLECH-BEREIT.md`, `docs/REALHW.md` und Stichproben im Code (`kernel/user/installer.fi`, `ota.fi`, `tools/ota/*`). Nichts davon ist heute neu am Gerät gemessen. Stufen: **OK** = in QEMU/KVM durch eine Abnahme belegt · **TEIL** = Prototyp oder Teilstück · **FEHLT** = nicht da.
"Blech" = echtes Gerät. Alles, was nur dort prüfbar ist, steht in Teil B.

Kennzahl-Konvention: `Wichtigkeit 5` = ohne das kein Alltag, `1` = Komfort.

---

## TEIL A — Lücken, nach Wichtigkeit

### Stufe 5 — ohne das kein Alltag

| # | Bereich | Stand | Beleg / Lücke | In VM testbar? | Nächster Schritt |
|---|---|---|---|---|---|
| A1 | **Dateisystem hält** | TEIL | OFS mit Journal (`docs/OFS-JOURNAL.md`), fsck. ABER r200: Daten-Wettlauf im Kern nullt zufällig ~128 Oktette in Sektoren (SATA, QEMU q35); Installer fängt es durch Prüfen+Nachschreiben ab, das **laufende** System nicht. r211/r212/r213 SMP-Zustände ohne Sperre. | ja | Ursache r200 finden (Verdacht: gemeinsamer Umschlagpuffer `BLOCK_OFF` bei Präemption), Dauertest mit Prüfsummen |
| A2 | **Installation auf Platte, benutzbar** | TEIL | P-001 fertig (`tools/install/abnahme.sh` 35/0), Dual-Boot neben Windows gemessen (`RUNDE-DUALBOOT.md`). Lücken: r172 Installer legt **kein eigenes Konto** an (Platte erbt `live`/Autologin bzw. Justins Konto), r202/r175 Plattenliste leer gezeichnet, r203 nur UEFI/GPT, Verkleinern einer Partition geht nicht. | ja | Konto + Kennwort im Installer, danach Abnahme „installieren → neu starten → anmelden" |
| A3 | **Auto-Update** | TEIL | OTA 107/0: signiert (Ed25519, Schlüsselbund), Rückschrittsschutz, Wiederaufnahme, Wachhund, Rückfall auf vorige Generation, Stromausfall 30×. Fehlt: Kanäle, Anzeige in den Einstellungen, Update beim Neustart, Kern im A/B (r104), O-013 (14 Pakete ≈ 25 min in QEMU). | ja | → Teil C |
| A4 | **Start auf dem echten Rechner** | TEIL | Justins PC (AMD, NVIDIA GA106): UEFI-Stick startet (BLECH-ECHT). Dell 9020: Panik/DHCP/Maus offen (r153, r189, r206, r210). | nein | Teil B |
| A5 | **Anmeldung/Sperre** | OK | Login + Sperrbildschirm direkt auf fUi (`main` b3e4a65b), PBKDF2 `$osum1$`, Mehrbenutzer. Fehlt: PIN/Passkey (r253), r170 Taskleisten-Fenster schluckt Klicks unter dem Login. | ja | r170, danach PIN |
| A6 | **Netzwerk Ethernet** | OK/TEIL | DHCP, DNS-Resolver (r17), TLS 1.3, e1000/I217/I219/RTL (BLECH). Dell: kein Netz (r182/r189), I219-Ringe (r155). | VM ja, Dell nein | Teil B |
| A7 | **Uhr/Zeit** | FEHLT | r19 kein NTP, r20 keine Zeitzonen-DB, r79 RTC-Zeitzone ist Annahme (`tz=120` fest in der Startzeile, Sommerzeit nicht berücksichtigt). Folge: Zertifikatsprüfung scheitert bei falscher Uhr → auch **Update** scheitert. Dell zeigt 2016 (r184). | ja | SNTP + Zeitzonentabelle (Europe/Vienna) + `tz` aus Einstellung |
| A8 | **Sicherheit der Daten (Backup)** | TEIL | `/bin/backup` + Explorer „Backup hierhin sichern", Schnappschüsse, 61+ Zusagen (`tools/vault`). Fehlt: Wiederherstellung auf leeres Blech (r60), kein Zeitplan. | ja | Zeitplan + Restore-aus-Backup-Abnahme |

### Stufe 4 — man hält es ein paar Tage aus, dann nervt es

| # | Bereich | Stand | Beleg / Lücke | VM? | Nächster Schritt |
|---|---|---|---|---|---|
| B1 | **Browser (Certus)** | TEIL | Läuft als Ring-3-Programm mit wlib-Leinwand (`STATUS-CERTUS.md`), aus dem Laden installierbar. Glass-Konformität lückenhaft (r120–r124), Video-Dekodierung in Certus nicht angebunden. | ja | Webstandard-Prüfstand, Download/Tabs prüfen |
| B2 | **Verschlüsselung der Platte** | TEIL | K-019 Prototyp `tools/krypto` 61/0 (XTS, Argon2, Schlüsselplatz). **Nicht im Installer/Start verdrahtet.** Diebstahl-Schutz nur als Konzept (`CRYPTO-ERASE.md`). | ja | Installer-Option + Entsperren im Start |
| B3 | **Fremde Datenträger** | TEIL | FAT lesen+schreiben, ext4/NTFS **nur lesen** (131/0). r208 FAT-Kopieren innerhalb einer Partition ≈ 3,5 KB/s. exFAT: nicht gefunden. | ja | r208, exFAT lesen |
| B4 | **Energie/Standby** | TEIL | ACPI-Aus/Neustart, Akku/Deckel (K-003), CPU-Takt (K-005), S3 in QEMU 28/0 (r4). Offen: r143 Menüpunkt/Deckel, r144 Geräte nach S3, r145 UEFI. Ruhezustand: nur Träger. | teils | r143 Menüpunkt + Taste |
| B5 | **Grafik** | TEIL | Nur Framebuffer + Software-3D, virtio-gpu in VM (GPU3D). **Kein NVIDIA/AMD/Intel-Treiber** (r36), kein echtes Vsync (r33), EDID/Multi-Monitor/Skalierung fehlt (r32). Justins Ultrawide läuft über UEFI-Framebuffer. | teils | EDID lesen, Skalierungsfaktor |
| B6 | **Office/PDF** | FEHLT | Texteditor (`edit`, `nedit`), Rechner, ZIP, Notizen da. Kein PDF-Betrachter (r55), kein Office (r64). | ja | PDF-Betrachter (Text + Bilder) |
| B7 | **Medien** | TEIL | WAV/MP3 (`play`), H.264 bitgenau, 640×480 mit 25 Bildern/s (`RUNDE-H264T.md`), Bildbetrachter PNG/JPEG/BMP/GIF. Roadmap r56 steht noch offen, obwohl Dekoder da ist — Player-Oberfläche + AAC/Container prüfen. | ja | Videoplayer-Fenster |
| B8 | **App-Store** | TEIL | Inhalt da (14 Programme, `store.fleitec.com`), Installation per `ota`/`opk` auf der Konsole. **Keine Store-Oberfläche** (r54), Auslieferung wird nicht automatisch nachgezogen (r178). | ja | Store-Seite in den Einstellungen |
| B9 | **Einstellungen vollständig** | TEIL | 14 Reiter. Fehlt: Updates (CLI `ota einstellungen`), Zeit/Zeitzone, Datenträger (r59), Drucker, Bluetooth. fUi-Umbau läuft parallel. | ja | Reiter „Updates", „Datum & Zeit" |
| B10 | **Tastatur/Sprache DE** | OK/TEIL | Deutsche Oberfläche, Umlaute (`umlaut`-Läufer), Layout. H-001: schnelles Tippen auf USB vertauscht Tasten (r157). | ja | r157 beheben |
| B11 | **Terminal** | OK | `/bin/term`, Shell, ~100 Programme. r217 Debugzeilen beim Start. | ja | r217 |
| B12 | **Explorer** | OK | Kopieren, Papierkorb je Datenträger, Suche, ZIP, USB ein-/auswerfen, Drag&Drop. | ja | — |

### Stufe 3 — vermisst man, aber es geht ohne

| # | Bereich | Stand | Beleg / Lücke |
|---|---|---|---|
| C1 | WLAN | FEHLT (Treiber) | Ganze Strecke oberhalb des Treibers gemessen gegen simuliertes Gerät (`RUNDE-WLAN3.md`), **kein Funktreiber** (r21, r118). QEMU hat keine WLAN-Karte → nur auf Blech. Für Desktop-PC mit LAN unkritisch, für Laptop Pflicht. |
| C2 | VPN | TEIL | `vpn.fi`/WireGuard-Tunnel (`docs/TUNNEL.md`); kein OpenVPN, keine Oberfläche. |
| C3 | Drucker | TEIL | IPP-Druck (K-008). Kein CUPS/Treiberwelt. |
| C4 | Bluetooth | FEHLT | r6. Maus/Tastatur über USB gehen. |
| C5 | Kamera | FEHLT | r7 (UVC). |
| C6 | SMB/Netzwerkfreigaben | FEHLT | r24. |
| C7 | Datenträgerverwaltung | FEHLT | r59 (Partitionieren, Formatieren in GUI). |
| C8 | Kalender/Kontakte | FEHLT | r58. |
| C9 | Programm-Sandbox | FEHLT | r47. Rechte über Aktions-Bus, aber keine Prozess-Isolierung. |
| C10 | Bildschirmtastatur, Sprachausgabe | FEHLT | r57, r63. |
| C11 | Secure Boot | FEHLT | Limine nicht signiert (`docs/USBSTICK.md`): Secure Boot muss **aus** sein. |
| C12 | Emoji/Sonderzeichen-Werkzeug | FEHLT | r62. |

---

## TEIL B — Hardware-Prüfpunkte (nur am echten Gerät)

Reihenfolge = was zuerst am Dell/Justins PC angeschaut werden sollte.

1. **Neues Abbild auf Dell-Stick**: Login mit Startkennwort, bewegt sich die Maus (r153), Tippen sichtbar, `|` und Ziffernblock, Netz (r182/r189) — die vier offenen Nachfragen an Justin.
2. **Dell-Panik** (r206/r210): kommt sie noch, Absturzbericht über Reset (K-011) lesen.
3. **Installation auf SATA/NVMe-Platte am echten Gerät**, danach Neustart ohne Stick: kommt der Login, hat man USB-Tastatur (r173).
4. **DHCP/Link** am I217/I219 (r155, r182, r189).
5. **Zeit**: stimmt die Uhr nach NTP, stimmt die Zeitzone (r79, r184).
6. **Auto-Update am Gerät**: `ota suchen` → `einspielen` → Neustart → bestätigt; danach absichtlich kaputtes Update → Rückfall (nur mit Freigabe des Boss).
7. **Standby (S3)** Deckel zu/auf, Bild zurück (r145; auf UEFI-Rechnern ohne GPU-Treiber oft schwarz).
8. **Mehrfach-Monitor/Skalierung** am Ultrawide (r32), Vsync/Zerreißen (r75).
9. **Audio** HDA (Realtek/NVIDIA-HDMI): Ton, Lautstärketasten.
10. **Trackpad/I²C-HID** auf einem Laptop (nur Maus/USB gemessen).
11. **AVX-512-Rechner**: Update-Weg läuft (K-001 gelöst, B-002 in der Roadmap abgehakt) — am echten Gerät mit AVX-512 gegenprüfen.
12. **WLAN**: erst wenn ein Funktreiber existiert (Chipsatz des Laptops klären).
13. **Secure Boot aus**/Boot-Reihenfolge nach Installation neben Windows (Bootmenü zeigt beide).

---

## TEIL C — Auto-Update (OTA): Stand und Plan

**Vorhanden** (alles in QEMU/KVM gemessen, `tools/ota/run.sh`, Zusagen 107/0):

* `/bin/ota`: `suchen`, `zeigen`, `einspielen`, `bestaetigen`, `zurueck`, `wachhund`, `dienst`, `einstellungen`, `einstellen`.
* Signiertes `VERZEICHNIS` (Ed25519), zweite Prüfung durch `opk`, Rückschrittsschutz (`/system/FASSUNG`), Wiederaufnahme (Range), Platzprüfung.
* Rückfall: Erprobungszähler im Kern (`kernel/ab.fi`-Linie, `/system/ERPROBUNG`), nach 3 Fehlstarts vorige Generation; Wachhund für „hochgekommen und hängt".
* Server-Seite: `veroeffentlichen.py` (Fassungsregister, Vorrat, alte Fassungen, Rücknahme, Sperrliste), `schluesselbund.py` (Haupt-/Ersatzschlüssel, Kettensatz).
* Live-Store `store.fleitec.com` Fassung 4 (14 Programme).

**Fehlt für „Auto-Update im Alltag"** (Anforderung des Boss ↔ Stand):

| Anforderung | Stand | Plan |
|---|---|---|
| Signierte Updates | OK | — |
| Hintergrund-Download | TEIL (`ota dienst`, `auto=ja`) | Dienst in Standard-`inittab`/Abbild, Drosselung, Wiederholung bei Netzausfall prüfen |
| A/B bzw. Rollback | TEIL: Generationen + Zähler. **Kern nicht im Wechsel** (r104) | Zwei Kernabbilder auf der ESP + Lader-Umschaltung (eigene Runde); bis dahin ESP-Kern nur ersetzen, wenn Kern unverändert |
| Update beim Neustart | TEIL: `einspielen` legt Generation an, nie Auto-Neustart | „Beim nächsten Neustart aktivieren" als Standard, Hinweis in der Leiste |
| Anzeige in Einstellungen | FEHLT (nur CLI) | Reiter „Updates" (Fassung, Kanal, letzte Suche, Knopf Suchen/Installieren/Zurück) |
| Kanäle stabil/test | FEHLT | `kanal=` in `/etc/ota.conf`, getrennte Auslieferungsbäume `stabil/` und `test/`, Test: Gerät auf `test` sieht höhere Fassung, `stabil` nicht |
| E2E alt→neu→Rollback in VM | OK für Pakete (Abschnitte 2, 4, 5) | erweitern um Kanalwechsel und Rollback per `ota zurueck` über Neustart |
| Update-Dauer | O-013: 14 Pakete ≈ 25 min | messen, wo die Zeit bleibt |
| Uhr | A7 | NTP, sonst scheitert die Zertifikatsprüfung |
| Store automatisch nachziehen | r178 | Veröffentlichen als Schritt nach main-Merge |

**Nicht ohne Freigabe des Boss:** echte Auslieferung an Geräte, Schlüsselwechsel, Veröffentlichen einer Fassung auf `store.fleitec.com`.

---

## TEIL D — Reihenfolge der Arbeit (VM-machbar zuerst)

1. **OTA-Kanäle + Einstellungsseite „Updates" + E2E-Rollback-Test** (A3).
2. **Zeit**: SNTP, Zeitzonen, `tz` aus Einstellung (A7) — Voraussetzung für verlässliches Update.
3. **Dateisystem-Wettlauf r200** (A1).
4. **Installer legt Konto an** (A2/r172) + Abnahme „Installation → Neustart → Anmeldung".
5. Standby-Menüpunkt (B4/r143), Store-Oberfläche (B8), PDF-Betrachter (B6).
6. Verschlüsselung im Installer (B2).

Pflege: Roadmap (Projekt OrientOS) bleibt die einzige Punktliste; diese Datei ist die Sicht nach Alltagsrelevanz. Bei Abschluss eines Punkts hier die Zeile aktualisieren.
