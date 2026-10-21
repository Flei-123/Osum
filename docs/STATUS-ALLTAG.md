# STATUS-ALLTAG — ehrliche Polish-Liste (Stand 21.10.2026, main 280e1fa6)

Ziel des Boss: OrientOS **täglich benutzen**. Diese Liste ist eine Bestandsaufnahme, keine Werbung.
Quellen: Projekt-Kennzahlen + Roadmap (project_get), `reports/*` (KB), `docs/DAILY-DRIVER.md`, `docs/LINUX-COMPAT*.md`, `docs/RUNDE-UNTERBAU-FIREFOX.md`.
Es wurde für dieses Dokument **nichts neu gemessen**. Jede Zahl trägt ihr Datum/ihren Gate-Namen; was nirgends gemessen ist, steht als **unmeasured**.

**Ampel:** GRÜN = Gate belegt und nichts Offenes im Alltag · GELB = Gate grün, aber Alltag-Lücke oder nur in QEMU belegt · ROT = fehlt oder bekannt kaputt.
**Aufwand:** S = Stunden · M = ca. 1 Tag · L = mehrere Tage / Umbau. (Schätzung des Schreibers, außer wo eine Quelle genannt ist.)
**Wichtig:** fast alle Gates laufen in **QEMU/KVM**. Echte Hardware: nur ein Dell 9020 (B-005 „nur eine Maschine gemessen“), der Laptop ist offline.

---

## 1. Übersicht nach Bereich

| Bereich | Ampel | Aufwand bis grün | Kurzbegründung |
|---|---|---|---|
| Desktop/Shell | GELB | M–L | Gates grün, aber **PRIO0: Taskleiste in der Boss-VM leer** (Ursache offen) |
| Apps | GELB | L | Kern-Apps gated; **kein Video, kein Office**; Explorer-Popups offen |
| Netz (Kabel) | GELB | M | TLS 1.2 + DHCP-Erneuerung grün; kein IPv6, Boss-VM-DNS ungeklärt |
| WLAN | ROT | L | kein Funktreiber; nur Vorarbeit ohne Hardware |
| Audio | GELB | M | HDA Ausgabe+Mikrofon gated; HDMI-Ton, USB-Audio, Ton-Einstellungen fehlen |
| Suspend (S3) | GELB | M | in QEMU grün; am echten Gerät **unmeasured**; Deckel/Taste fehlt |
| Installer/Update | GELB | M | Installer + OTA gated; Installer 7 min (Ziel < 3), Boss-VM-Update nie ausgeführt |
| Stabilität | GELB | M | QEMU: 0 Abstürze in Serien; VBox: Hänger/99-%-Burn, Gate-Rot auf altem main |
| Performance vs. Mint | GELB | M | RAM/Image/Latenz deutlich besser; Boot und VBox-Idle-CPU nicht |
| Linux-Apps (Firefox) | ROT | L | Unterbau 655/669 PASS, aber **kein echtes Firefox je gestartet** |

---

## 2. Bereiche im Detail

### 2.1 Desktop/Shell — GELB, Aufwand M–L

| Punkt | Beleg | Ampel |
|---|---|---|
| Desktop-Gate | `tools/desktop` 116/0 (3× grün, KB 21.10., Parser gehärtet r1350) | GRÜN |
| Look/Leiste/Menüs | look 41/0, barctx 10/0 (flakt selten: 9/1 → Wiederholung 10/0), Alt+Tab 17/0, win11bar 11/0, Startmenü-Lebendigkeit 9/0 | GRÜN |
| Bildzeit | Fenster ziehen 1,5 ms, Eingabe→Bild Median 2,2–2,3 ms (Ziel ≤ 16) | GRÜN |
| **Taskleiste in Boss-VM leer** (r1364, PRIO0) | W6-Bericht: in QEMU und VBox-Test-VM **nicht reproduzierbar**, nur Boss-VM; Ursache nicht bewiesen | ROT, Aufwand M–L (Ursache offen) |
| fUi-Anteil Szenenbaum | 80,1 % (Ziel 100, r263/r285) | GELB |
| wlib-Fensterplätze | MAXWN 9, `nwn` gibt Mittelplätze nie frei (r1353); Leiste mit MAXWN-Fehler (r1351) | GELB, S–M |
| Lock/Login-Gates | lockscene 13/2 + lockseal rot **auch auf altem main** (r1324) | GELB, M |
| Fenster-Ecken | 12 px vs Windows 11: 8 px — Designentscheidung offen | GELB, S |
| Kontextmenü-Registry | Start/Desktop/Leiste/Explorer-Zeile migriert; offen r1359 (Explorer bg/drive/restore/backup) | GELB, S–M |
| Bildschirmmodus VBox | r1325/r1336: Desktop füllt VM-Fenster nicht — QEMU grün, VBox **unmeasured** | GELB, M |

### 2.2 Apps — GELB, Aufwand L

| Punkt | Beleg | Ampel |
|---|---|---|
| Explorer / Paint | explorer2 49/0, paint 36/0, explctx 10/0 | GRÜN |
| Terminal | term 6/0 + vttest2 32/32, Tabs 23/0 | GRÜN |
| Store | Store-Fenster 71/0, Store live 39/0; „Systemdialog“ trustdlg 15/0. Offen: Test gegen echten Live-Store (r307) | GELB, S–M |
| PDF-Betrachter | 111/0 | GRÜN |
| Taskmanager/Speicher/Zeichentabelle | 38/0, 27/0, 25/0 | GRÜN |
| Dell-Durchklick (12 Apps) | **1/4** in letzter Messung (4 von 12 gemessen; Settings, Terminal FEHLER) — **veraltet**, QA-3…5 (r523–r525) offen | GELB, M (neu messen) |
| Video | **kein Dekoder** (r56, r874) | ROT, L |
| Office / Kalender / Kontakte | r64, r867, r868 offen; nur Kalender-Popup an der Uhr (calpop 15/0) | ROT, L |
| Browser | Certus-Binary vom ELF-Lader abgelehnt (r935), nativer Build kaputt (r936); Entscheidung Certus vs Firefox bei Boss (r572) | ROT, L |
| Bildschirmtastatur, Drucker, Bluetooth-Reiter | r57, r423 offen | ROT, M |

### 2.3 Netz (Kabel) — GELB, Aufwand M

| Punkt | Beleg | Ampel |
|---|---|---|
| TLS 1.2 | tls12 58/0 + Gast hwnet 24/0 | GRÜN |
| DHCP-Erneuerung | 15 Erneuerungen in 70 s (vorher 0, r362) | GRÜN |
| OTA über Netz | OTA-Gate 161/0 (nur QEMU) | GRÜN |
| Boss-VM Netz | `ota system search` scheiterte: kein DNS (r1310); Hypothese NAT-DNS-0x20 (r1317), Fix auf main, **am Laptop ungeprüft** | GELB, S |
| IPv6 | kein Stack (r406) | ROT, L |
| SMB/Freigaben, Zertifikats-Alterung | r24, r25 offen | ROT, L / M |
| USB-Tethering/-Ethernet | nur Protokoll-Modell, Gate 53/0 (Host), **kein Treiber** (r408) | ROT, M |
| jarvisd Leerlauf am echten Server | 3,5 % eines Kerns (Ziel ≤ 0,5; lokal 0,3) | GELB, S–M |

### 2.4 WLAN — ROT, Aufwand L

- Kein Funktreiber (r21). Vorarbeit **ohne Hardware** in main (844054ec): Firmware-Parser, Reset/Clock, Context-Info, Scan-Format; Gate `wlan-ax201-m2` 27/0 (KB). Registerwerte „aus Gedächtnis unbestätigt“.
- Offen: Firmware laden, ALIVE, Kommandos, RX, Assoc, WPA2 (r880, r881); Chip des Laptops noch nicht bestimmt (r296, r863).
- r771 sagt ehrlich: Intel AX2xx/MT7921/QCA6390 = **L, praktisch nicht geplant**. Ersatzweg: USB-Ethernet/Tethering (r408).
- Bis dahin: **Alltags-Blocker für jeden Laptop ohne Kabel.**

### 2.5 Audio — GELB, Aufwand M

| Punkt | Beleg | Ampel |
|---|---|---|
| Mikrofon (HDA Capture) | cap.sh 45/0 | GRÜN |
| Audio-Hub + Tray | Host-Test 104/0 | GRÜN |
| HDA-Gate gesamt | 141/2 (nur expected-red Aussetzer, KB r815-Notiz) | GELB |
| HDMI/DP-Ton | digitale Knoten übersprungen (r419) | ROT, M |
| USB-Audio, Jack-Erkennung, mehrere Codecs | r639, r624, r637 | ROT, M |
| Settings → Ton (Geräteliste, Pegel, Testton) | r640 offen | ROT, S–M |
| Ton am echten Gerät | `r571` (Dell prüfen) offen — **unmeasured** | — |

### 2.6 Suspend (S3) — GELB, Aufwand M

| Punkt | Beleg | Ampel |
|---|---|---|
| S3 in QEMU | s3 55/0 (2/4 Kerne), s3smp 23/0 (3 Zyklen), s3dev 24/0 (NVMe, AHCI, xHCI, e1000, HDA) | GRÜN |
| Startmenü „Energie sparen“ | gated (s3 inkl. Menü-Wunsch) | GRÜN |
| Deckel/Taste → Standby, Auto-Standby | r143 offen | ROT, M |
| UEFI (OVMF) | r145 offen | GELB, S |
| **Echtes Gerät** (Mehrkern, xHCI/NVMe/e1000/HDA, 20-Zyklen-Dauertest) | r304 offen — **unmeasured** | GELB, M (Gerät nötig) |
| Helligkeitstasten, S4/Hibernate | r784 offen | ROT, M |
| VMSVGA nach S3 | r957 offen | GELB, S |

### 2.7 Installer/Update — GELB, Aufwand M

| Punkt | Beleg | Ampel |
|---|---|---|
| Installer inkl. eigenes Konto | P-001 Abnahme 70/0, Kontofelder 9/0 | GRÜN |
| BIOS- und UEFI-Boot der installierten Platte | 11/0 | GRÜN |
| OTA / Feed / Rollback | OTA 161/0, feedtest 13/0 (Fassung 3282 live) | GRÜN |
| Selbst-Update mit Rückfall | Commits `selfupdate`/`osupdate gate` (Branch-Basis), Gate osupdate | GELB (QEMU) |
| **Installer-Dauer** | 7 min (Ziel < 3; KVM, Last ~8) | GELB, M |
| Installer an echter Dell-HDD | r585 offen — **unmeasured** | — |
| Boss-VM Update | Feed live, in der Boss-VM **nie ausgeführt** (r1269, r1310) | GELB, S |
| Update auf dem Stick | nicht möglich (frei 5,4 MB, nötig 20,3 MB); auf installierter Platte ja | GELB |
| Kern/Starter über Feed | r330 offen | GELB, M |
| Fern-Update Dell | 4/4 in **VM**, am echten Dell offen | GELB |
| NVMe-Größe im Installer falsch (r315) | offen | GELB, S |

### 2.8 Stabilität — GELB, Aufwand M

| Punkt | Beleg | Ampel |
|---|---|---|
| Abstürze Serien (QEMU/KVM) | execsmp 0/30 · Dell-Serie 8 Kerne 0/50 · Boot-#UD 0/60 · Bootserie 30/30 · Leichen 30/30 · FS-Schreiber 4 Kerne 11/0 | GRÜN |
| Programme gleichzeitig | 15 (Ziel ≥ 13) | GRÜN |
| **VBox-Hänger** | r1133/r1134: Leerlauf bis 99 % Host-Kern, Anmeldeschirm friert ohne Serial ein; „1 von 3 Läufen“ Burn (Ziel 0 von 5); r1308 Ursache-Hypothese `sleep_ticks`→`yield_now`-Spin | ROT, M–L |
| Echte Hardware | nur 1 Maschine (B-005); Maus am Dell (r153), AML/INTx geraten (r154) | GELB |
| Gate-Rot auf altem main | lockscene/lockseal (r1324), actionbus gui 63/8, pci 96/2, vmsvga desktop 11/1, themestore 298/14 (alt, r137) | GELB, M |
| Gates ungemergt | `gates2` (r1315), r1325, r1332, r1269, r1306 | GELB |

### 2.9 Performance vs. Mint — GELB, Aufwand M

Referenz: Mint 22.3 XFCE Live-ISO, QEMU/KVM, 3 vCPU/2 GB, Median 3 Läufe (`tools/bench/mint.sh`), **Host unter Last** (4 andere Jobs → Bootzeit grob). OrientOS: Vollabbild, QEMU/KVM 2 vCPU. **Nicht identische Konfiguration**; VBox-Vergleich fehlt (r1332).

| Metrik | OrientOS | Mint 22.3 | Debian 13 (Ref) | Ampel |
|---|---|---|---|---|
| Boot bis Login/Desktop | 24,5 s (AHCI; davon Limine-Menü 20 s, Lader 1,0 s, Kernel 3,5 s) | 53,7 s (ohne Bootmenü) | 16,4 s | GELB (Menü-Timeout = Hebel, r1218, S) |
| Idle-RAM benutzt | 190,2 MB | 1801,7 MB (655,5 MB MemAvailable) | 177,8 MB | GRÜN |
| Image | 146 MB (Genutzte Wurzel 31,9 MB) | 2893 MB ISO | 389,9 MB | GRÜN |
| Idle-CPU (QEMU) | 3,9–5,4 % eines Kerns (Boot-Idle; Ziel ≤ 3) | 0,7 % | — | GELB, M |
| Idle-Host-CPU in **VBox** 3 vCPU | Test-VM 23,8 %; Boss-VM GUI 47–62 % (51–116); Login-Schirm 28 % (Ziel < 30) | **unmeasured** | — | ROT (Boss-VM), M |
| Eingabe→Bild | 2,2–2,3 ms Median | **unmeasured** | — | GRÜN |
| App-Start bis Fenster | **unmeasured** (OrientOS) | Terminal 143 ms, Thunar 299 ms, xed 1223 ms | — | — |
| Kernelgröße | 8437 KB | — | — | — |
| exec+exit+wait | 1,5 ms | — | — | GRÜN |

Fazit: Speicher und Größe gewinnen klar; Boot ist nur wegen 20-s-Menü schlechter als nötig; **Leerlauf-CPU in VirtualBox** ist der ehrliche Schwachpunkt.

---

## 3. Linux app compatibility (Firefox path)

> **Messlage:** Die Berichte `reports/20261021-M1-unterbau.md` und `reports/20261021-M2-linuxapps.md` lagen beim Schreiben dieses Abschnitts **nicht** vor. Alles unten stammt aus vorhandenen Berichten/Metriken. Neumessungen der anderen Worker sind **nicht** eingearbeitet (siehe Ende dieses Abschnitts, falls nachgezogen).

### 3.1 Stand (belegt)

| Baustein | Messwert | Quelle | Ampel |
|---|---|---|---|
| ELF dynamisch + `dlopen` fremder `.so` | dynlader 36/0, `t_dl` 18/0 | Metriken | GRÜN |
| Unterbau gesamt (26 `t_*`-Tests) | **655 PASS / 5 FAIL / 9 GAP von 669** (main bea3ffb1; GPU/DRM ausgenommen) | Metrik | GELB |
| POSIX | posix 150/0 | Metrik | GRÜN |
| Firefox-Grenzen (`t_limits`) | fds ≥ 256, Fäden ≥ 64, anon ≥ 256 MiB, Reserve ≥ 4 GiB: alle PASS | Metrik | GRÜN |
| Dateischreiben nach /tmp | 3115 KiB/s (Ziel ≥ 10000; vorher 880) | Metrik | GELB |
| busybox / python / curl / git | busybox 56/0; python3 11/11; curl http+https ok; git init/add/commit ok | `LINUX-COMPAT.md` §5 (13.10.) | GRÜN |
| Wayland | wayd 52/0, Eingabe 66/0, `foot` 12/0, `weston-simple-shm` läuft | Metriken | GRÜN |
| Events/IPC | epoll, eventfd, timerfd, signalfd, inotify (teils), AF_UNIX+SCM_RIGHTS, socketpair | `LINUX-COMPAT.md` §1 | GRÜN |
| Offen (laut `LINUX-COMPAT-OPEN.md`, 14.10.) | `MAP_SHARED`-Datei max. 1 MiB je Mapping (#5), `/proc/self/maps` ohne Dateinamen (#6), kein DRM (#7, nur Software-Renderer) | Doku | GELB |
| Offen (Roadmap) | `/dev/shm` nur 16 paged Objekte (r947), `*at` mit echtem dirfd (r754), fehlende Aufrufe wie `statx` (r780), RT-Signale (r666), linux-dmabuf (r670) | Roadmap | GELB |
| **Echtes Firefox** | nie gestartet — **unmeasured**; Startzeit `libxul`, Netz-Sandbox, viele Fäden, `fork` großer Prozesse laut Bericht „nicht gemessen“ | `RUNDE-UNTERBAU-FIREFOX.md` §5.4 | ROT |
| GTK/Qt | GTK4-Stein begonnen (r729), nicht fertig | Roadmap | ROT |
| Vulkan/GL | kein DRM/GPU; Software-Raster, SPIR-V-Abnahme 36/0, SWR 10/0; **Mesa/Vulkan-ICD fehlt** | Metriken | ROT (für Firefox nicht nötig, wenn Software-Rendering) |

Alte Doku-Zahlen (z. B. „28 Fäden“, „30 offen“) sind **überholt** gegenüber den Metriken oben; Quelle der Wahrheit = Metriken.

### 3.2 Meilensteine und Schätzung

| # | Meilenstein | Abnahme (Vorschlag) | Status | Aufwand (Schätzung) |
|---|---|---|---|---|
| F0 | Prüfsteine busybox/python/curl/git/foot | s. 3.1 | erledigt | — |
| F1 | Restlücken Unterbau auf 0 FAIL/GAP (5 FAIL, 9 GAP) | `tools/unterbau/run.sh` alle PASS | offen | M (je Lücke S–M; `MAP_SHARED`-Größe und `/proc/maps` sind L) |
| F2 | GTK4/Qt-Stein (glib, cairo, fontconfig) mit Software-Renderer über `wl_shm` | Hello-Fenster sichtbar (r729, r676) | offen | M–L |
| F3 | **Firefox startet**: Fenster mit `about:blank`, Software-WebRender, Content-Sandbox aus (Annahme: abschaltbar, ungeprüft) | Screenshot-Gate | offen | L, **Risiko hoch**: viele unbekannte Aufrufe tauchen erst jetzt auf |
| F4 | Firefox lädt eine HTTPS-Seite (Netz, TLS, `/etc/ssl`, Schriften) | Gate gegen lokalen HTTPS-Server | offen | M nach F3 |
| F5 | Alltagstauglich: Tempo, Absturzfestigkeit, Audio | Messwerte vs Mint-Firefox | offen | L |
| F6 | GPU-Beschleunigung (DRM/KMS, Vulkan-Teilmenge) | — | offen | XL (optional) |

**Gesamtschätzung:** F1–F4 zusammen ca. **15–40 Arbeitstage** (reine Schätzung des Schreibers, nicht gemessen). Der KB-Eintrag r572 nennt für den Weg „Firefox-Unterbau“ **30–80+ Tage**, für **Certus** (eigener Browser, ins Abbild + TLS 1.2) **5–10 Tage**. TLS 1.2 ist inzwischen erledigt (58/0); Certus ist aber blockiert (r935–r938). Die Entscheidung Certus vs Firefox liegt beim Boss (r572).

Ehrliche Reihenfolge: **F1 → F3 mit Messung statt Raten**. Erst ein echter Firefox-Start liefert die echte Lückenliste.

---

## 4. Wer macht was als Nächstes (Empfehlung, nur Priorität)

1. **PRIO0** Boss-VM-Taskleiste (r1364): Boss-UART1 auf Datei, Kaltstart cf6b, `taskbar:`-Zeilen vergleichen.
2. VBox-Hänger/Idle (r1133, r1134, r1308) — gleicher Test-Weg, Laptop nötig.
3. Echte Hardware für S3, Audio, Installer-Dauer (r304, r571, r585) — Gerät nötig.
4. Boss-VM-Update ausführen (r1269/r1310) und Mint-VBox-Vergleich (r1332).
5. Entscheidung Certus vs Firefox (r572).

Pflege: diese Datei nach jeder größeren Runde nachziehen; Zahlen immer mit Gate-Namen und Datum.
