# STATUS-ALLTAG — ehrliche Polish-Liste (Stand 21.10.2026, main 280e1fa6)

Ziel des Boss: OrientOS **täglich benutzen**. Diese Liste ist eine Bestandsaufnahme, keine Werbung.
Quellen: Projekt-Kennzahlen + Roadmap (project_get), `reports/*` (KB), `docs/DAILY-DRIVER.md`, `docs/LINUX-COMPAT*.md`, `docs/RUNDE-UNTERBAU-FIREFOX.md`.
Abschnitte 1–2 sind aus vorhandenen Messungen zusammengetragen (**nichts neu gemessen**); Abschnitt 3 stützt sich auf die frischen Läufe M1/M2 vom 21.10. Jede Zahl trägt ihr Datum/ihren Gate-Namen; was nirgends gemessen ist, steht als **unmeasured**.

**Ampel:** GRÜN = Gate belegt und nichts Offenes im Alltag · GELB = Gate grün, aber Alltag-Lücke oder nur in QEMU belegt · ROT = fehlt oder bekannt kaputt.
**Aufwand:** S = Stunden · M = ca. 1 Tag · L = mehrere Tage / Umbau. (Schätzung des Schreibers, außer wo eine Quelle genannt ist.)
**Plan-IDs:** Arbeitspakete stehen in `docs/PLAN-DESKTOP-2026Q4.md` (ID-Karte Abschnitt 15), GPU in `docs/GPU-PLAN.md` (GPU-1..6 = r1374–r1379), Einstellungen in `docs/SETTINGS-REDESIGN.md` (SET-1..13 = r1434–r1446; ersetzt SET-1..4 = r1395–r1398 des Masterplans). Diese Datei dupliziert keine Roadmap-Punkte, sie bewertet nur den Ist-Zustand.
**Wichtig:** fast alle Gates laufen in **QEMU/KVM**. Echte Hardware: nur ein Dell 9020 (B-005 „nur eine Maschine gemessen“), der Laptop ist offline.

---

## 1. Übersicht nach Bereich

| Bereich | Ampel | Aufwand bis grün | Kurzbegründung | Plan-IDs |
|---|---|---|---|---|
| Desktop/Shell | GELB | M–L | Gates grün, aber **PRIO0: Taskleiste in der Boss-VM leer** (Ursache offen) | STAB-1..5, SHELL-1..4 |
| Apps | GELB | L | Kern-Apps gated; **kein Video, kein Office**; Explorer-Popups offen | TM T1-S0..S6, TK-1..2 |
| Netz (Kabel) | GELB | M | TLS 1.2 + DHCP-Erneuerung grün; kein IPv6, Boss-VM-DNS ungeklärt | — |
| WLAN | ROT | L | kein Funktreiber; nur Vorarbeit ohne Hardware | — |
| Audio | GELB | M | HDA Ausgabe+Mikrofon gated; HDMI-Ton, USB-Audio, Ton-Einstellungen fehlen | — |
| Suspend (S3) | GELB | M | in QEMU grün; am echten Gerät **unmeasured**; Deckel/Taste fehlt | — |
| Installer/Update | GELB | M | Installer + OTA gated; Installer 7 min (Ziel < 3), Boss-VM-Update nie ausgeführt | UPD-1..5 |
| Stabilität | GELB | M | QEMU: 0 Abstürze in Serien; VBox: Hänger/99-%-Burn, Gate-Rot auf altem main | STAB-1..5, ENG-1..8 |
| Performance vs. Mint | GELB | M | RAM/Image/Latenz deutlich besser; Boot und VBox-Idle-CPU nicht | BENCH-1..2, MON-1..5 |
| Linux-Apps (Firefox) | ROT | L | Unterbau 710/717 PASS, foot 12/0, GTK4 16/3; **Firefox baut nicht ins Abbild** (libxul 148 MiB (155 673 104 B) > OFS-Grenze 130 MiB) | LA-1..9, GPU-1..6 |

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

Messlage: gemessen am 21.10. auf main 280e1fa6 (QEMU/KVM) von den Workern M1 (`reports/20261021-M1-unterbau.md`) und M2 (`reports/20261021-M2-linuxapps.md`). Nichts davon auf echter Hardware.

### 3.1 Stand (gemessen)

| Baustein | Messwert | Quelle | Ampel |
|---|---|---|---|
| Unterbau (27 `t_*`-Programme + libub) | **710 PASS / 3 FAIL / 4 GAP von 717** (vorher 655/5/9 von 669) | M1 | GRÜN |
| busybox-Prüfstein | 55 ok / 1 offen (`top`: `/proc/stat` nicht im Linux-Format) | M1 | GELB |
| python3 / curl / git inkl. TLS | 31 ok / 0 offen; statische Fremdprogramme 4/4 | M1 | GRÜN |
| dynlader | 35 bestanden / 1 gescheitert (**Gate-Regel veraltet**, alle 35 funktionalen Checks grün) | M1 | GRÜN |
| Wayland | wayd 52/0, Eingabe 73/0, `foot` 12/0 (kein Compose-Table, kein primary selection, kein xdg-activation / fractional-scale / cursor-shape) | M1, M2 | GRÜN |
| GTK4-Hello | Fenster 448x249 sichtbar, 555 Farben; Gate **16 ok / 3 FAIL** (glib-Hauptschleife: Ticks 2 statt 6, SIGUSR1-Quelle, **Sprung auf Nicht-Code-Seite** nach `g_spawn`/inotify-Faden, r796) | M2 | GELB |
| Qt | nicht versucht — **unmeasured** | M2 | — |
| **Firefox 151 in OrientOS** | **0 Läufe**: `libxul.so` 155 673 104 B > OFS-v3-Dateigrenze 136 351 744 B → Abbild lässt sich nicht bauen | M2 | ROT |
| Firefox unter Linux (Referenz, strace) | `--headless --screenshot about:blank`: 77 verschiedene Syscalls, ~6000 Aufrufe, 17 `clone` (15 Fäden), 6 `execve` (contentproc, glxtest), 18 memfd + `F_ADD_SEALS`, AF_UNIX + `socketpair` + `sendmsg`, `mremap` 80×, `madvise` 88× | M2 | Referenz |
| Syscall-Nummern | fast vollständig; ohne Treffer nur `readahead`, `fadvise64`, `rseq` (harmlos) | M2 (Heuristik) | GRÜN |
| GPU/DRM | kein `/dev/dri`, kein `/sys/class/drm`, kein dmabuf; Firefox fällt auf Software-WebRender zurück (kein Blocker). GTK4-GL/Qt Quick/Vulkan nur mit Software-Renderer (`GSK_RENDERER=cairo`) | M1 | GELB |
| Dateischreiben nach /tmp | 3115 KiB/s (Ziel ≥ 10000) | Metrik | GELB |

**Widerspruch, offen:** M2 nennt `MAX_TASKS=32` (28 Fäden) und „fd-Tabelle je Faden kopiert“ als Blocker (aus älteren Docs). M1 misst `t_limits` und `t_threads` **ohne FAIL**, die Kennzahl sagt Fäden ≥ 64. Widerspruch M1/M2 ist als LA-7 (r1416) im Masterplan erfasst. Vor Arbeit an LA-2 (r1367) per `t_limits` neu nachmessen.

### 3.2 Blocker für Firefox, nach Reihenfolge (M2) mit Roadmap

| # | Blocker | Aufwand | Roadmap |
|---|---|---|---|
| 1 | OFS-v3 max. Dateigröße 130 MiB < `libxul` 148 MiB (4. Indirektionsstufe oder Extents; fs.fi + mkfs.py + fsck + Gate) | L | r1366 |
| 2 | Aufgabentafel 32 (Firefox: 15 Fäden + contentproc + glxtest) — Messwert widerspricht, siehe oben | L (falls bestätigt) | r1367 |
| 2b | `CLONE_FILES`: fd-Tabelle je Faden kopiert statt geteilt (Firefox/glib öffnen in einem Faden, benutzen im anderen); M2 stuft L ein, laut M1 `t_threads` ohne FAIL → nachmessen | M–L (falls bestätigt) | LINUX-COMPAT-OPEN #1, LA-7 (r1416) |
| 3 | glib-Hauptschleife (inotify EBADF nach `g_spawn`, SIGUSR1, Sprung auf Nicht-Code-Seite) — GTK3 ist Firefox-UI | M | r796 |
| 4 | Speicher: `libxul` privat kopiert (155 MB), kein Demand-Paging für Dateimappings, `MAP_NORESERVE`/`PROT_NONE`-Reserven — **ungemessen** | M | — |
| 5 | procfs: `/proc/self/mountinfo`, `cgroup`, `maps` mit Namen, `/proc/stat` im Linux-Format | S–M | r1370, r1372, r934 |
| 6 | IPC im Verbund: memfd-Seals, SCM_RIGHTS über stream, `mremap`-Last — einzeln ok, im Verbund ungetestet | M | r1368 |
| 7 | Stubs `readahead`/`fadvise64`, `fallocate(PUNCH_HOLE)`; wayd-Protokolle (primary selection, xdg-activation, fractional-scale, cursor-shape) | S je | r1370 |
| 8 | Trace-Lücke: `fremdtrace` meldet nur ENOSYS + 6 Speicheraufrufe, nicht alle fehlschlagenden Aufrufe | S | r1369 |
| 9 | `system()`/`popen()` im Test-Abbild (Artefakt; im Persönlich-Abbild gelöst, Gate `bbsh` 7/0; BBSH-Gegenlauf im unterbau-Gate bootet nicht) | S | r1373 |

### 3.3 Meilensteine und Schätzung

| # | Meilenstein | Abnahme | Status | Aufwand (Schätzung) |
|---|---|---|---|---|
| F0 | Prüfsteine busybox/python/curl/git/foot | s. 3.1 | erledigt (busybox 55/56) | — |
| F1 | Unterbau 0 FAIL/GAP (heute 3 FAIL, 4 GAP, großteils Test-Artefakte) | `tools/unterbau/run.sh` | fast | S–M |
| F2 | OFS-Dateigröße ≥ 256 MiB, Firefox-Abbild baut | `prep-firefox.sh` ohne mkfs-Fehler | offen | L |
| F3 | `firefox --version` im Gast | `guest-fx1-version.sh` | offen | M nach F2 |
| F4 | `--headless --screenshot about:blank` | Screenshot-Datei im Gast | offen | L (Fäden, glib, Speicher) |
| F5 | Firefox-Fenster über Wayland (Software-WebRender), HTTPS-Seite | Screenshot-Gate | offen | L |
| F6 | GTK4/Qt-Hello grün (glib-Schleife, Qt-Stein) | gtk/run.sh 19/0 | GTK 16/3 | M |
| F7 | Alltag: Tempo, Absturzfestigkeit, Audio | Messung vs Mint | offen | L |
| F8 | GPU-Beschleunigung (DRM/KMS minimal → Vulkan-Teilmenge) | — | offen | XL, optional |

**Gesamtschätzung (Schreiber, nicht gemessen):** F2–F5 zusammen **ca. 20–45 Arbeitstage**, Risiko hoch, weil erst ein echter Lauf die nächste Lücke zeigt (Methode: Runde je Lauf, erster fehlschlagender Syscall, r1368). Zum Vergleich r572 (KB): „Firefox-Unterbau 30–80+ Tage“, Certus (eigener Browser) 5–10 Tage — Certus ist aber blockiert (r935–r938). Entscheidung Certus vs Firefox: Boss (r572). TLS 1.2 ist inzwischen da (58/0).

---

## 4. Wer macht was als Nächstes (Empfehlung, nur Priorität)

1. **PRIO0** Boss-VM-Taskleiste (r1364): Boss-UART1 auf Datei, Kaltstart cf6b, `taskbar:`-Zeilen vergleichen.
2. VBox-Hänger/Idle (r1133, r1134, r1308) — gleicher Test-Weg, Laptop nötig.
3. Echte Hardware für S3, Audio, Installer-Dauer (r304, r571, r585) — Gerät nötig.
4. Boss-VM-Update ausführen (r1269/r1310) und Mint-VBox-Vergleich (r1332).
5. Entscheidung Certus vs Firefox (r572); danach OFS-Dateigröße (r1366) als erster Firefox-Schritt.

Pflege: diese Datei nach jeder größeren Runde nachziehen; Zahlen immer mit Gate-Namen und Datum.
