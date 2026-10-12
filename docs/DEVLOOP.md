# DEVLOOP — OrientOS als Alltags- und Entwicklungsgerät mit Hot-Reload-Schleife

Stand 11.10.2026 (main `08d38d8b`, Teil 5 + Updates W-DELLTEST am Ende). Konzept + Ist-Analyse; seit W-DELLTEST: OTA-Platzbedarf gesenkt, `dell_walk smoke`, Abschnitt 7.
Alle Zahlen sind gelesen oder gemessen (Beleg dabei). Was nicht gemessen ist, steht als *ungemessen*.
Alle Aufwände in Abschnitt 4 sind **SCHÄTZUNGEN**, keine Zusagen.

**Boss-Ziel:** Du arbeitest am Dell (OptiPlex 9020) mit OrientOS wie mit Windows. JARVIS hat direkten
Zugriff (Befehle, Fotos, Klicks, Tippen). Du sagst Feedback → JARVIS ändert, testet selbst → Update kommt
aufs Dell → du lädst neu und siehst es (wie Strg+F5 bei einer Webseite).

---

## 1. IST-STAND der Bausteine

Legende: **Dell** = läuft am echten Dell (gemessen), **VM** = nur in QEMU gemessen, **fehlt**.

| Baustein | Status | Beleg |
|---|---|---|
| **Bridge / jarvisd** (Befehle, Lesen, Schreiben, Auflisten) | **Dell** | Dell `osum-a4206b26eb96` ist jetzt online (`/bruecke/geraete`: verbunden=true). Heute gemessen: Befehl `/bin/ps` 3,3 s, `uname`, `grep ahci /proc/klog`, `df`, `cat /proc/hwid` kamen zurück. Code `kernel/app/jarvisd.fi`, Doku `docs/BRUECKE.md`. |
| **Rechteliste** `/etc/jarvis/permissions.conf` | **Dell** | Wird vor JEDEM Auftrag neu gelesen (`docs/BRIDGE.md`). Dell-Abbild nutzt `/root/abbilder/justin-permissions.conf`: `commands=yes`, **47** `command_allowed` (u.a. `/bin/sh`, `/bin/ota`, `/bin/reboot`, `/bin/act`, `/bin/cp`, `/bin/mv`, `/bin/rm`, `/bin/fetch`, `/bin/jarvisctl`), `screenshot=yes`, `input=yes`, `write` nur `/users/justin/`, `/var/jarvis/`, `/tmp/`, `/etc/orientbus/`, `/etc/ntp.conf`, `/etc/time.conf` (**nicht** `/etc/jarvis`). Limit: 64 Einträge pro Liste. Die Datei kann nur am Gerät/per neuem Abbild geändert werden — bewusst nicht per OTA (`docs/BRUECKE.md`, Abschnitt D1). |
| **Eingabe** (Tasten, Zeiger) Bridge-Auftrag `input` | **VM**, am Dell **ungeprüft** | `tools/bridge2/eingabe.sh` 13/0 (Config-Schlüssel, Public-Wächter, Not-Aus mit Gegenprobe). Mit `input=yes` im Dell-Abbild ausgeliefert, aber **noch nie am Dell ausgelöst** (`docs/QA-DELL-DURCHKLICK.md`: Echt-Lauf „nie gelaufen“, r526). |
| **Not-Aus** `Win+Esc`, `jarvisctl input off`, rotes Feld „JARVIS“ in der Leiste | **VM** | Im Kern (`kbd.fi`), geht auch bei hängender Oberfläche; Sperre liegt im RAM. Abnahme `tools/bridge2/eingabe.sh`. |
| **Screenshot** `jarvisctl screenshot` (Erlaubnis 60 s, **ein** Foto) + Auftrag `photo` | **Dell** | Heute gemessen: Erlaubnis + Foto **1,6 s**, PNG ~300 KB (`Bruecke.photo` in `tools/qa/dell_walk.py`). Vor JEDEM Foto neu nötig. |
| **A11y-Szenenbaum** (Fensterinhalt als Knoten statt Pixel; Lesen + Knopf drücken über den Bus) | **VM** | `tools/a11y/run.sh` 58/0, `tools/a11y/scene.sh` 25/0, `docs/A11Y.md`. Bridge darf nur `act call a11y.tree` (Probelauf zuerst, `docs/BRUECKE.md`). Am Dell nicht gemessen. |
| **Aktions-Bus (`act`)** | **VM** | `tools/actionbus/run.sh` 306/0; im Abbild 21/0; am Bildschirm 67/0 (Kennzahlen). `act reload` lädt neue Manifeste ohne Broker-Neustart (r239 erledigt, `docs/ACTION-BUS.md`). Am Dell nicht gemessen. |
| **OTA / Feed** (`/bin/ota`, signiert, Rückschrittsschutz, Kanäle, Wachhund, Rollback) | **VM** (Dell: **blockiert**) | OTA-Abnahme 150/0 (Kennzahl; beim letzten Nachlauf `tools/ota/run.sh` am 11.10. nur bis Abschnitt 4 abgewartet, Endstand ungemessen), `feedtest.sh` 13/0 (Fassung 0→5, Bestätigen, Rollback). Live-Feed `store.fleitec.com`: Fassung 5, 14 Programmpakete. Dell steht auf **Fassung 0** (`cat /system/FASSUNG` = `00000000`, heute gelesen). Doku `docs/OTA.md`, `STATUS-OTA.md`. |
| **Delta-Update + Platzbedarf** (r542) | **VM** (Platz: Code umgestellt, Lauf siehe Abschnitt 7) | `ota` holt zuerst INDEX+Signatur und lädt nur Pakete, die fehlen (main `f69ac58f`; VM: „packages already current: 1“, Server lieferte 0 Pakete). Platzbedarf seit W-DELLTEST: Summe + größtes Paket + Luft = **20,3 MB** statt 47,4 MB (Staging-Datei wird nach jedem `opk` gelöscht); der Stick hat 5,4 MB frei, hilft ihm also immer noch nicht — auf einer INSTALLIERTEN Platte (Wurzel wächst auf 256 MiB) ist es kein Thema mehr. Heute `df`: 11391 von 102400 Blöcken frei (≈5,6 MB). |
| **Kern-/Wurzel-Update ohne Stick** | **fehlt** | Kern, Starter, wlib, **Fensterserver `wm.fi` (liegt im Kern)** kommen NICHT über den Feed (r330, r104). Nur `dell-update.py` (Bridge, schreibt EFI-Partition des Sticks): Kern ~9 min, Wurzel ~30 min (Notiz r494). Rückfall nur über Bootmenü „previous version“ → braucht einen Menschen am Gerät. |
| **dell_walk** (Durchklick aller Apps, Foto je Schritt, Urteil) | **VM**; `smoke` (nur lesen, 9–10 Prüfungen + Foto) **am Dell gelaufen** (66–115 s); `echt` gebaut, bricht bei gesperrtem Schirm ab (am Dell geprüft), Durchlauf mit Eingabe **nie gelaufen**. Doku `docs/DELLWALK.md` | `tools/qa/dell_walk.sh vm`: 12 Apps; letzter Stand 4 von 12 Apps gemessen, davon 1 OK (Explorer); Terminal/Terminal2 FEHLER (r534), Settings mit `tzrule=eu` 0 Fehler (W4b, r545). Voller VM-Lauf ~25 min, real „4 Apps in 40 min“ unter Last (r535). Echt-Modus repariert (r547), `--dry` getestet, echter Lauf steht aus. |
| **Terminal / Editor** | **VM**, teils Dell | Terminal-Abnahme 6/0 + vttest 32/32, Resize am echten Dell bestätigt. Editor im eigenen Terminalfenster (r543, editwin 11/0). Am Dell offen: erster Terminalstart ohne Fenster (r555). |
| **Abbild-Bau** (`tools/usbimg/build.sh`, Dell-Profil) | **Dell** | Abbild 08d38d8 liegt bereit (`/root/abbilder/…08d38d8-personal-dell.img.xz`, 8,7 MiB gepackt / 148 MiB). Bauzeit ≈ 7 min (Dateizeiten 05de680: Log 12:31 → .xz 12:38; grobe Ableitung, nicht gestoppt). |
| **Stick-Betrieb** (Wurzel = RAM) | **Dell** | `docs/LIVE-STICK.md`: Wurzel ist ein Boot-Modul (`modfs`) im RAM, **nichts, was du schreibst, bleibt nach Neustart**. Das ist der heutige Dell-Zustand (`df`: 102400 Blöcke = RAM-Abbild). |
| **Installer** (Platte, GPT+ESP, UEFI) | **VM** | P-001 70/0. `install /dev/hda --ja` 7 min (vorher 9:42), ESP-Schreiben ~25 KB/s (r556). Am Dell **nie ausgeführt**: Dell-Platte war nicht sichtbar (RAID-Modus), Fix r558 in main, am Dell **ungemessen**. |
| **Dell-AHCI-Fix** (r558) | **VM**, Dell **ungemessen** | `grep ahci /proc/klog` heute am Dell (alter Kern): `AHCI controller in RAID mode … used as AHCI` → 0,49 s später `AHCI init failed, why=8`. Neuer Kern (05de680/08d38d8) steht noch nicht auf dem Dell. |

**Kurz:** Befehle + Fotos gehen am Dell **heute** (3,3 s / 1,6 s). Klicks/Tippen, Bus, A11y-Baum und OTA sind in der VM belegt,
am Dell **nie durchgespielt**. Das Dell-System ist noch das alte (7583dad3, ohne AHCI-/Drag-/Lock-Fix) und hat keinen Platz für OTA.

---

## 2. LÜCKEN bis „Alltag“

Schweregrad: **BLOCKIERT** = ohne das kein Alltag/keine Schleife, **STÖRT** = geht, nervt täglich, **KOMFORT**.

| # | Lücke | Schwere | Beleg |
|---|---|---|---|
| L1 | **Nichts bleibt gespeichert** (Stick-Wurzel im RAM). Dein Zeug, Einstellungen, installierte Programme sind nach Neustart weg. | **BLOCKIERT** | `docs/LIVE-STICK.md`; Dell-`df` = RAM-Abbild |
| L2 | **Installation auf Platte nie am Dell gelaufen**: Platte unsichtbar (BIOS RAID On, `ahci init failed why=8`); Fix r558 ungemessen; nur **eine** Platte sichtbar (r559); Installer nur UEFI (r203); USB-Platten nicht anbietbar (r355); NVMe-Größe falsch (r315) | **BLOCKIERT** | r558, r559, r203; Dell-klog heute |
| L3 | **Installer langsam**: 7 min in VM (Kern 8,4 MB über PIO, ~25 KB/s). Auf echter Hardware ungemessen. | STÖRT | r556, Bericht W5 |
| L4 | **OTA hat am Dell-Stick keinen Platz**: 20,3 MB nötig (vorher 47,4) / 5,4 MB frei; Wurzel liegt als `root.img` auf 96-MiB-ESP, Fernupdate passt nur knapp („Tight“, `dell-update.py`); r469 will ESP ≥ 192 MiB | **BLOCKIERT** (für OTA auf Stick) | r542, r550, r336, r351, r469; nach Installation auf Platte entfällt das teilweise (Platzbedarf der Platten-Wurzel ungeprüft) |
| L5 | **Kern/GUI-Änderungen nur per Voll-Update + Neustart**: Fenster, Titelleisten, Menüs, Rahmen leben im Kern (`wm.fi`, 14k Zeilen) bzw. in Starter/wlib — nicht im Feed. Das sind genau die Dinge, zu denen du Feedback gibst. | **BLOCKIERT** für „Strg+F5-Gefühl“ | r330, r104, r413 (wm.fi nach Ring 3 = Risiko, Planung) |
| L6 | **Eingabe-Pfad (Klick/Tippen) am Dell ungeprüft**; `dell_walk echt` nie gelaufen; USB-Tasten-Reihenfolge bei schnellem Tippen vertauscht (H-001); Maus am Dell zuletzt „bewegt sich nicht“ (r153, mit neuem Abbild nachtesten) | **BLOCKIERT** für Auto-Test am Dell | r526, r157, r153 |
| L7 | **Rollback des Kerns braucht einen Menschen** (Bootmenü). OTA-Rollback gilt nur für Programme; Gesundheitsprüfung nur 60 s nach Start (r274); Taskleiste/Starter werden bei Tod nicht neu gestartet (r331); `jarvisd`-Respawn nicht belegt (r531: `respawn.sh` 0/3) | STÖRT (Risiko: Dell hängt, keiner am Gerät) | r274, r331, r531, `dell-update.py` Kopf |
| L8 | **Feed liegt nicht auf dem Stand von main**: Veröffentlichen ist Handarbeit (r178), `stable/`/`test/`-Verzeichnisse existieren auf dem Live-Store nicht (Freigabe nötig), Abbild kennt seine Fassung nicht (r314: `FASSUNG = 0`) | STÖRT | r178, r314, `docs/OTA.md` Abschnitt Kanäle |
| L9 | **OTA-Einspielen langsam**: 14 Pakete ≈ 25 min in VM (≈1 min Download + 1,5 min `opk` je Paket); wo die Zeit bleibt: ungemessen | STÖRT | r179 |
| L10 | **Browser**: Certus nicht im Personal-Abbild (Platz, r546), Web-Konformität lückenhaft (r120–r124), TLS 1.2 fehlt (r405). Firefox-Unterbau gemessen: freie Deskriptoren 13 (Ziel ≥256), Fäden 28 (≥64), anonymer Speicher 185 MiB (≥256), Dateischreiben 26 KiB/s (≥10000); Aufgabentafel 32 Plätze (r344) | STÖRT (Alltag), Firefox = **Wochen** | Kennzahlen, r516–r519, r344 |
| L11 | **Netz Dell**: Bridge ist online, also geht Ethernet (heute belegt). Alte Roadmap-Punkte r182/r189 (DHCP) sind offen eingetragen, vermutlich überholt — prüfen. WLAN: **kein Funktreiber**, Chip unbekannt (Dell ist Desktop) | WLAN: KOMFORT (Dell hat Kabel) | r21, r296, `docs/WLAN-TREIBER.md` |
| L12 | **Tastatur AltGr / Layouts**: `code_of(…, altgr)` existiert (`docs/I18N.md`), am Dell nie geprüft (`@`, `{` im Durchklick-Plan als manuell). Nur de/us (r418) | STÖRT | `docs/QA-DELL-DURCHKLICK.md` Punkt 7, r418 |
| L13 | **Ton**: HDA-Treiber gebaut (`STATUS-HDA.md`), am Dell ungeprüft; HDMI-Ton übersprungen (r419) | KOMFORT | STATUS-HDA.md, r419 |
| L14 | **Standby S3**: in VM 55/0 (2/4 Kerne), am echten Gerät nie (r304); GPU nach S3 ohne Treiber oft schwarz | KOMFORT | r4, r143, r304 |
| L15 | **Stabilität**: Dell-Absturzserie 8 Kerne: 0 von 50 Boots kaputt (VM, vorher 20/20); Dell `kerne 1` vs. 4 Leerlaufprozesse offen (r471); seltene Panik (r210); `elf: refused`-Kollision bei zwei gleichzeitigen Starts (r174); VM-Walk 1 von 4 Apps OK | STÖRT | Kennzahlen, r210, r471, r174, r534 |
| L16 | **Bildqualität/Fenster**: AA-Popups Maßstab 2 rot (aacorner-Gate: 123 falsche Pixel, Ziel ≈0, r560); Drag-Fix nur VM (r561); Kantenzeiger/Resize 26/0 VM; Fensterschatten am Dell nie bestätigt (r399); Widgets-Streifen (r552/r557) | STÖRT | Kennzahlen, r560, r561, r399 |
| L17 | **Dateisystem-Größe**: OFS-v2-Dateigrenze 2.134.016 Oktette; `explorer` 2.137.632 → nur mit `--v3` baubar (r383); Dateischreiben 26 KiB/s; FAT-Kopieren 3,5 KB/s (r208) | STÖRT | r383, r208, Kennzahl „Dateimanager-Größe“ 480 Oktette Luft |
| L18 | **Logs ohne Rotation/Zeitstempel** (`jarvisd.log`, ota/sntp/dhcp): schlecht für automatische Fehlersuche per Bridge | KOMFORT | r539, r540 |
| L19 | **Zwei Bridge-Wege**: `/var/jarvis` fasst ~7 Dateien; Ergebnisdateien werden nach Name statt Zeit gelöscht (r352); jarvisd Leerlauf 3,5 % eines Kerns am echten Server (r490) | KOMFORT | `docs/BRUECKE.md`, r352, r490 |
| L20 | **Programm-Sandbox, Secure Boot, Datenträgerverschlüsselung** fehlen (r47, r310, r415) | KOMFORT für den Anfang | Roadmap |

---

## 3. DESIGN der Dev-Loop

### 3.1 Drei Update-Stufen (nur was im Code da ist)

| Stufe | Was ändert sich | Weg | Neustart? | Zustand |
|---|---|---|---|---|
| **A: Programm** (`/apps/*.osp`, fUi-Programme wie Settings, Explorer, Editor, Widgets) | nur dieses Programm | Paket bauen → signieren → Feed → `ota apply` (Delta lädt nur Geändertes) → `act reload` (Manifest) → Programm beenden und neu starten (`kill` + Startmenü oder `act`) | **nein** | OTA ohne Neustart: VM-belegt (`ota apply … OHNE Neustart`, `docs/OTA.md`). **Ob ein laufendes Programm ersetzt wird / sich selbst neu lädt: ungemessen** (Programm läuft vermutlich mit altem Abbild weiter, bis es neu startet — nicht geprüft). |
| **B: Dienst** (`jarvisd`, `ota`, `sntp`, `orientbus`) | Dienst | `kill <pid>` → `init` startet `respawn`-Dienste nach 200 ms neu (`kernel/user/init.fi`, `RESPAWN_MS`) | nein | `jarvisd`-Respawn **nicht belegt** (r531). Taskleiste/Starter ohne Wächter (r331). Neustart von `jarvisd` reißt die Bridge kurz ab → Auftrag nur mit Ablauf-Skript. |
| **C: Kern/Treiber/Wurzel/Fensterserver** | alles in `osum.mb`, `root.img` | `dell-update.py` über die Bridge (EFI-Partition des Sticks) bzw. Installer-ESP; dann `reboot` | **ja** | Kern ~9 min + Wurzel ~30 min Upload (r494). **kexec/Live-Kerntausch: im Repo nicht vorhanden** (`grep kexec` ohne Treffer) → Neustart ist Pflicht. Boot-Dauer am Dell: ungemessen. |

**Konsequenz, ehrlich:** Programme ohne Neustart sind erreichbar. Alles Optische am Fensterrahmen (Titelleiste,
Ziehen, Schatten, Popup-Ränder) steckt im Kern → Stufe C. Wer das ändern will, muss dem Dell einen Neustart zumuten
(Ziel: ≤ 2 min statt 40 min; dafür müsste der Kern über den Feed kommen, r330) oder wm nach Ring 3 verlagern (r413,
Compositor-Pfad S6/S7 läuft schon: wmd komponiert Schatten + Chrome mit 0 Abweichung, Bild in 4,8 ms, Kennzahlen).

### 3.2 Ablauf (Text-Diagramm)

```
 Boss: "Titelleiste zu dick" (Chat)
        |
        v
 [1] JARVIS ändert Code im eigenen Worktree ................ Minuten
        |
        v
 [2] Bauen: Programm (firnc) bzw. Abbild (usbimg/build.sh) . Abbild ~7 min (grob)
        |
        v
 [3] VM-Gates (heavy-Queue): k15 258/0, a11y 58/0, wm, look, passendes Messwerkzeug
        |    Wartezeit in der Queue oft 10+ min; Gates je 3-25 min ......... ungemessen als Summe
        v
 [4] grün? -> merge main, Paket signieren, Feed veröffentlichen (heute Handarbeit, r178)
        |
        v
 [5] Auslieferung aufs Dell
        |-- Stufe A: ota apply (Delta) + act reload + App neu starten ...... ungemessen am Dell
        |-- Stufe C: dell-update.py (Kern ~9 min, Wurzel ~30 min) + reboot
        v
 [6] Auto-Test am Dell: Befehl ps/uname/log -l warn (3,3 s je Befehl),
        |    dell_walk echt (Smoke: 3 Apps), Foto (1,6 s je Foto), A11y-Baum lesen
        v
 [7] Foto + Ergebnis an Boss; Boss lädt neu / sieht nach, sagt Feedback
        |
        v  Rollback bei Fehler: ota rollback (Stufe A) / Bootmenü "previous version" (C, Mensch nötig)
```

Latenz je Schritt (nur belegte Zahlen):

| Schritt | Dauer | Quelle |
|---|---|---|
| Befehl an Dell → Antwort | 3,3 s | heute gemessen |
| Erlaubnis + Foto | 1,6 s (300 KB) | heute gemessen |
| Abbild bauen | ≈ 7 min (grob aus Dateizeiten) | `/root/img-logs/build-dell.log` → `.img.xz` |
| Installer (VM, Last ~8) | 7 min | r548/W5 |
| `ota apply` 14 Pakete (VM) | ≈ 25 min | r179 |
| Fernupdate Kern / Wurzel (Dell) | ~9 min / ~30 min | r494 |
| `dell_walk vm` komplett / je App | ~25 min / ~3 min | `docs/QA-DELL-DURCHKLICK.md` |
| VM-Queue (`heavy`) | oft 10+ min Wartezeit | KNOWLEDGE |
| Boot Dell bis Schreibtisch, `ota apply` mit Delta, Reload eines Programms | **ungemessen** | — |

### 3.3 Auto-Test nach dem Update

1. **Vorher:** `ps`-Liste, `log -l warn`, Foto (Ausgangslage). Läuft Sperr-/Anmeldeschirm → abbrechen (Regel in `dell_walk`).
2. **Smoke (Ziel < 3 min):** Version/Commit lesen (`uname`, `/system/FASSUNG`), `grep ahci /proc/klog`, `log -l warn`, dann
   3 Apps per Startmenü (Eingabe-Job) + Foto + neue PID prüfen — das ist `dell_walk echt --apps settings,explorer,terminal`.
   `dell_walk` urteilt per Pixeldifferenz + `ps`-Diff; Fenster-Urteil bleibt grob („Pixel haben sich geändert“, nicht „richtig“).
3. **Gezielt:** je nach Feedback das passende Messwerkzeug (`tools/aacorner/aacorner.py` Pixelwerte an Rundungen,
   `tools/drag/check.py` Titelleiste in jedem Bild einer Serie, `tools/midline`, `tools/signinlook`) — heute VM-Gates, am Dell nicht gelaufen.
4. **Playwright gilt NICHT für OrientOS** (nur für Webinhalte). OrientOS-GUI = **A11y-Baum** (`act call a11y.tree`: Rolle, Name,
   Lage, Zustand der Knöpfe/Felder; Probelauf zuerst) **+ Foto-Vergleich** + **Bridge-Eingabe** (Scancodes, Zeiger).
5. **Selbsttest auf dem Dell:** ein Skript in `/var/jarvis/` (Schreiben erlaubt, `/bin/sh` ist freigegeben) gibt Zustände aus
   (`ps`, `df`, `klog`-Filter, `ota show`) — heute nutzt `dell-update.py` genau diesen Weg (`u.sh`). Grenze: `/var/jarvis` fasst ~7 Dateien.
6. **Urteil:** grün → Foto an Boss. Rot → Rollback (3.4) + Befund in die Roadmap.

### 3.4 Rollback

| Ebene | Weg | Zustand |
|---|---|---|
| Programme | Generationen + Erprobungszähler; nach 3 Fehlstarts vorige Generation; `ota rollback` von Hand; Wachhund `ota boot` (60 s) | VM-belegt (OTA Abschnitt 7 (e),(g) mit Gegenprobe), Dell nie |
| Feed-Fassung | Fassung steigt nur (0→5); Gerät lehnt gleich/alt ab (Rückschrittsschutz); Rücknahme/Sperrliste serverseitig (`veroeffentlichen.py`) | VM (feedtest 13/0) |
| Kern/Wurzel | `dell-update.py` behält „previous version“ (alter Kern + alte Wurzel) im Bootmenü; kaputter Kern → Auswahl braucht **Person am Gerät** | gebaut; nie ausgelöst; bei vollem Stick nicht möglich (TIGHT) |
| Absturz nach der ersten Minute | **fehlt** (r274) | offen |

Lücke für die Schleife: Ein kaputter Kern auf dem Dell ohne Mensch davor = Gerät bleibt tot, bis jemand F12/Bootmenü drückt.
Mildern: Kern-Update nur, wenn du am Dell sitzt; Programm-Updates (Stufe A) immer mit Rollback.

### 3.5 Sicherheit

* **Feed:** Ed25519-signiert (VERZEICHNIS, INDEX, jedes Paket), zweite Prüfung durch `opk`, Rückschrittsschutz, Schlüsselbund mit Ersatzschlüssel,
  Sperrliste, TLS 1.3 gegen `/etc/ssl/roots.pem` (Name wird geprüft). Krypto gegen RFC/libsodium geprüft (4725 Prüfungen), **nicht auditiert** (`docs/OTA.md`).
* **Bridge:** Ed25519-Schlüssel des Geräts (private Hälfte nur in `jsig`), Rechteliste vor jedem Auftrag neu gelesen, Standard = verboten,
  `..`-Pfade abgelehnt, nur Befehle der Liste mit vollem Pfad, Aufträge laufen nach 120 s ab (`ttl_s`), Fotos nur mit 60-s-Erlaubnis,
  rotes „JARVIS“-Feld bei Fernsteuerung, **Not-Aus Win+Esc**.
* **Freigaben, die der Boss gibt:** Veröffentlichen auf `store.fleitec.com` (Live-System), Schlüsselwechsel, `stable/test`-Kanäle auf dem Live-Store.
* **Offen:** `input = yes` ist die mächtigste Freigabe; sie hängt an einer Datei, die nur über Abbild/am Gerät geändert wird. Eine Update-Kette, die ihre
  eigenen Rechte ändern könnte, gibt es mit Absicht nicht.

---

## 4. MEILENSTEINE (alle Aufwände = SCHÄTZUNG in Arbeitstagen, Spanne von–bis)

Ein „Arbeitstag“ = ein Tag JARVIS-Arbeit mit Gate-Läufen; Wartezeiten auf den Boss (Stick stecken, BIOS, Freigaben) sind **nicht** eingerechnet.

| M | Ziel | Aufwand (SCHÄTZUNG) | Hängt ab von | Was der Boss dann kann |
|---|---|---|---|---|
| **M1** | Dell läuft mit dem neuen Abbild (08d38d8): AHCI-Log lesbar, Drag/Lock-Fix am Dell bestätigt, Klick/Tippen per Bridge einmal am Dell durchgespielt | 1–2 | Boss: Stick neu oder `dell-update.py` (~40 min) nach OK; Dell erreichbar | Dell vom Stick wie Windows ansehen/testen; JARVIS sieht Bildschirm, tippt, klickt. **Nichts bleibt gespeichert.** |
| **M2** | Installation auf Platte + Start ohne Stick (AHCI r558, mehrere Platten r559, UEFI-Pflicht r203, Dualboot-Test) | 3–6 | M1; BIOS-Einstellungen vom Boss (RAID On/AHCI, UEFI); Boss-Entscheid Platte/Windows | **Ab M2 ohne Stick starten**, Dateien/Programme bleiben. Erst ab hier „Windows-Ersatz“ im Wortsinn. |
| **M3** | Platz + Feed-Stand: Platten-Wurzel passend dimensioniert, ESP ≥ 192 MiB (r469/r550), Abbild kennt seine Fassung (r314), Feed-Stand im Abbild (r549), Delta am Gerät gemessen | 2–4 | M2; Boss-Freigabe für Veröffentlichung/Kanal `test` auf dem Live-Store | Programm-Updates per OTA ohne Stick; Dell holt sich Fassungen selbst. |
| **M4** | Hot-Reload-Schleife Stufe A+B: `devloop`-Skript (Bauen → Gates → Feed → OTA → Reload → Smoke → Foto), Veröffentlichen automatisch (r178), Programm-Reload messen/bauen, Wächter für Taskleiste/Starter/jarvisd (r331/r531), Gesundheit > 1 min (r274), `dell_walk echt` am Dell | 6–12 | M3; Eingabe am Dell stabil (r153/r157) | **Ab M4: sagst du Feedback, kommt die App-Änderung in Minuten bis Dutzend Minuten aufs Dell, mit Foto zurück.** (Kern-/Fensteränderungen weiter mit Neustart.) |
| **M5** | Kern-Update ohne Stick (System-Generation im Feed, r330/r104) + Rollback ohne Mensch (Boot-Zähler für den Kern) | 6–15 | M3, M4; Platz | Auch Fenster-/Kernänderungen ohne USB-Gefummel; Neustart bleibt. |
| **M6** | Alltagsbasis: AltGr/Layout am Dell, Ton (HDA), Standby S3, Netz-Stabilität, Logs mit Zeitstempel/Rotation, Dell-Stabilität (r210/r471/r174) | 8–20 | M2; Hardwaretests nur mit Boss/Dell | Schreiben, Musik, Dokumente, Mail-lose Büroarbeit ohne Ärger. |
| **M7** | Browser: Certus ins Abbild + TLS 1.2 + Konformität **oder** Firefox-Unterbau (L1/L2/M1: Adressraum, Tabellen, epoll …) | Certus: 5–10; Firefox: 30–80+ | M2 (Platz), M6 | Certus: Web mit Lücken. Firefox: echtes Web — das ist der große Brocken. |
| **M8** | Entwicklung am Gerät (Firn-Bau im Abbild prüfen, Debugger r424), Programm-Sandbox, Verschlüsselung (r415) | 15–40 | M2–M5 | Selbst auf dem Dell entwickeln; nicht nötig für die Schleife. |

Reihenfolge: **M1 → M2 → M3 → M4** ist der kürzeste Weg zur Schleife (grob **12–24 Arbeitstage**, Spanne ehrlich weit).
M5/M6 laufen danach teils parallel. M7 hängt von deiner Browser-Entscheidung ab.

---

## 5. Roadmap

Die Punkte stehen im JARVIS-Projekt OrientOS, Gruppe **Dev-Loop** (neue Punkte) bzw. verweisen auf bestehende
(r542, r550, r558, r559, r556, r203, r330, r104, r274, r331, r531, r178, r314, r469, r549, r526). Nicht doppelt angelegt.

---

## 6. EHRLICH AN DEN BOSS

* **Heute** kannst du am Dell vom Stick arbeiten; JARVIS kann Befehle ausführen und Fotos holen (3,3 s / 1,6 s gemessen). **Gespeichert wird nichts** (RAM-Wurzel).
* **Ohne Stick starten** (M2): frühestens in **~1–2 Wochen** (Schätzung) — und nur, wenn der Installer am echten Dell wirklich die Platte findet. Das ist **nie** am Dell gelaufen.
* **Programm-Änderungen per Hot-Reload** (M4): realistisch in **~3–5 Wochen** (Schätzung). Davon ist der Teil „Programm ersetzen, während es läuft“ bisher **ungemessen**.
* **Fenster-/Rahmen-Feedback** (Titelleiste, Schatten, Ziehen) steckt im Kern → braucht **Neustart**. Ohne M5 heißt das ~40 min Upload per Stick-Update — kein Strg+F5-Gefühl.
* **Klicks/Tippen durch JARVIS am Dell** sind noch nicht am Dell erprobt. Wenn Maus/Tastatur am Dell zicken (r153, r157), steht der Auto-Test.
* **Größte Risiken:** (1) Dell-Platte/RAID-Modus bleibt unsichtbar → BIOS-Umstellung nötig und Windows-Dualboot betroffen; (2) kaputter Kern ohne Mensch am Gerät = Gerät tot bis Bootmenü;
  (3) Zeitplan hängt an Gate-Läufen (Queue 10+ min, `dell_walk` 25 min); (4) Browser (Firefox) ist Monate-Arbeit, Certus hat Lücken.
* **Ich brauche von dir:** BIOS-Check (SATA-Modus) am Dell, Freigabe zum Aufspielen von 08d38d8, später Freigabe für `test`-Kanal auf dem Live-Feed.
* **Nicht versprechbar:** WLAN (Chip unbekannt), Standby am echten Gerät, Ton — erst mit Test am Dell wissbar.


---

## 7. W-DELLTEST (11.10.2026): Dell-Standardabnahme, OTA-Platz, Update-Weg

### 7.1 Was sich geändert hat

* **OTA-Platz (r542):** `kernel/user/ota.fi` löscht Staging-Datei + `.sig` sofort nach dem erfolgreichen `opk` je Paket. Bedarf =
  Summe + größtes Paket + 512 KiB + Summe/8 (vorher 3 × Summe). Live-Feed Fassung 5 (aus `/srv/store/osum/aktuell/VERZEICHNIS`, 14 Pakete):
  Summe 15 807 042, größtes 1 993 737 → **20 300 947 statt 47 421 126 Oktett**. Die Alles-erst-prüfen-Reihenfolge (Schritt 4) bleibt;
  nur die Staging-Bytes wandern früher zurück. Lauf: `tools/ota/run.sh --kurz` (Zahlen: Bericht `reports/20261011-W-DELLTEST.md`).
* **Wo liegt das Staging?** `/tmp/ota` im Wurzeldateisystem. Stick: 50 MiB RAM-Abbild, 5,4 MiB frei (`df` am Dell heute) → OTA geht dort nicht.
  Installiert: `instkern.wachsen` lässt OFS auf die Partition wachsen, **gedeckelt auf 524 288 Blöcke = 256 MiB** (`FS_KARTEN=128`,
  Blockkarte 128 × 4096 Bit × 512 B); frei ≈ 256 − 44.6 MiB ≈ 210 MiB (gerechnet, nicht am Dell gemessen). Damit liegt das Staging nach der
  Installation automatisch auf der Platte; kein eigener „Staging-Pfad“ nötig. **Offen:** der 256-MiB-Deckel (mehr Karten = Abbildlayout ändern, `FS_KARTEN=512` → 1 GiB; nicht getestet).
* **dell_walk:** `smoke` (nur lesen) + Sperrschirm-Wächter in `echt` + Ablage unter `/root/dellwalk-logs/<datum>/` + `docs/DELLWALK.md`.
* **Installer am Dell:** am 11.10. ~15:20–15:35 UTC beobachtet: der Dell steht im **Live-System vom Stick am Sperrbildschirm**, kein `install`-Prozess,
  `/dev/sda` ist in `/dev` da (AHCI-Fix im neuen Kern: `link scan done, 11605 us / ports left 0`, zwei Ports `verdict`), `FASSUNG` = 0.
  **Eine Installation lief in dieser Zeit NICHT** (kein Prozess, `df` = Stick-Abbild) → Installer-Dauer an der echten HDD: **nicht gemessen**.

### 7.2 Update-Weg: wo geht die Zeit hin? (Belege, kein Neumessen am Dell)

| Weg | Dauer (Messung) | Engpass |
|---|---|---|
| Kern-Fernupdate (`dell-update.py`, osum.mb 8,4 MB) | ~9 min (r494) ≈ 15 KB/s | **Schreiben auf die FAT-Partition des Sticks** (PIO, ESP-Schreiben ≈ 25 KB/s, r556) + Hash zurücklesen, nicht das Netz |
| Wurzel-Fernupdate (root.img, ~50 MB) | ~30 min (r494) ≈ 28 KB/s | dasselbe |
| `ota apply` 14 Pakete (VM) | ~25 min (r179): ≈ 1 min Holen + 1,5 min `opk` je Paket | Dateischreiben im OFS: `t_limits.file_4mib_write` = **26 KiB/s** (Ziel ≥ 10 000) |

Ergebnis: **fast die ganze Zeit ist Schreibdurchsatz (~25 KB/s) im Gerät**, nicht Download und nicht Signaturprüfung.
Hebel in dieser Reihenfolge (alle SCHÄTZUNG):

1. **Schreibdurchsatz OFS/FAT/USB** auf ≥ 1 MB/s heben (Blockgröße 512 B, Journal je Schreibaufruf, PIO-Pfad prüfen) — würde Kern-Update auf ~10 s, Wurzel auf ~1 min und `ota apply` auf Minuten drücken. Größter Hebel, eigener Auftrag.
2. **Kern-only-Update:** `wm.fi` steckt im Kern (8,4 MB, ~9 min), `root.img` (~30 min) ändert sich dann nicht. `dell-update.py` schickt immer beide.
   Eine Option „Wurzel behalten“ (neuer Eintrag = neuer Kern + aktuelle Wurzel) würde Kern-Änderungen von ~40 auf ~9 min bringen.
   **Nicht umgesetzt:** das Werkzeug schreibt am Dell-Stick, war in diesem Lauf verboten und ist nur mit `dell-update-fakedev.py` testbar.
3. **Block-Delta der Wurzel** (nur geänderte Blöcke senden): bräuchte ein Patch-Werkzeug im Gerät und ändert `root.img` an Ort und Stelle (kein „vorherige Version“).
   Nicht klein, nicht sicher → nicht gebaut.
4. **Programme (Stufe A) ohne Neustart** sind schon getrennt: Paket je App; Delta lädt nur geänderte Pakete (`ota: packages already current`).
   Ein einzelnes Paket ≈ 1–2 MB ≈ 1–2,5 min (nach Zeile 3 der Tabelle) — das ist der schnellste Weg heute.

### 7.3 Schnellster Weg heute: neue Fassung → Dell

1. Bauen + VM-Vorprüfung (Gates, `heavy`).
2. Feed-Stand lokal bauen + signieren (`docs/OTA-FEED.md` §1), `feedtest.sh` (§2), mit Boss-Ja veröffentlichen (§3, Live-System).
3. Dell: Bridge-Befehl `/bin/ota apply` (nur auf INSTALLIERTEM System: Platz) → `/bin/act reload` → App neu starten → `dell_walk smoke` + Foto.
4. Kern/wm.fi: `dell-update.py` (Stick, ~40 min) + Neustart. Bis M5 gibt es nichts Schnelleres.

### 7.4 Nächste Schritte (Dell-Standardabnahme, VM nur Vorprüfung)

* Nach JEDEM Update am Dell: `bash tools/qa/dell_walk.sh smoke` (~1–2 min, nur lesen). Rot = Befund in die Roadmap, Rollback prüfen.
* Am Desktop (entsperrt, Boss am Gerät oder Not-Aus bekannt): `dell_walk.sh echt --apps settings,explorer,terminal` — erster echter Lauf steht aus (r526).
* Installation auf die Platte am Dell (M2): Boss-Freigabe; danach `smoke` (df ≥ 20 MiB muss grün werden), dann `ota apply` am Dell messen (Zeit, Platz).
* VM-Läufe (`dell_walk vm`, `ota/run.sh`) bleiben Vorprüfung vor dem Dell, nicht Ersatz.

---

## 8. ACCEL phase 1 (12.10.2026): expected red, gate manifest, build cache

Source: `docs/ACCEL.md` (C-03, C-02/B-03, B-01/B-02). Everything below is measured on the server (20 cores, load ~10 from other workers, KVM).

### 8.1 Expected red (`tools/qa/expected-red.txt`, `tools/qa/redcheck.sh`)
- One line per KNOWN red case: `gate | case-regex | red|flaky | reason | since | ref`. The case regex is matched against the text of a `FAIL`/`NEIN`/`FEHL`/`ROT` line (colour codes stripped); `*` = the gate may fail as a whole (flaky gates such as `term/multi`).
- `redcheck.sh GATE LOG EXIT` prints `expected red : <line> (reason)` or `NEW red : <line>`, exits 1 only on NEW red. A baseline entry that did not fire in a green run is reported as `FIXED?` (remove it), flaky entries never.
- Rule: an entry needs a control run on the old main. Remove it when the gate is green. `bash tools/qa/redcheck-test.sh` = self-test (22/0).
- No more "was it red on old main?" control runs for the listed cases; only a NEW red needs one.
- The regexes of the 12 starting entries come from the gate sources and the 11.10. reports; they are verified by `gates.sh --run` the first time each gate runs (a wrong regex shows up as NEW red, never as silent green).

### 8.2 Gate manifest (`tools/qa/gates.tsv`, `tools/qa/gates.sh`)
- `gates.tsv`: all 157 `tools/*/run.sh` gates with `tier` (quick 22 / full 109 / nightly 26), `needs` (qemu, netlock), `paths` (globs that trigger the gate), `source` (`auto` = generated guess, `manual` = hand-edited, kept by the generator).
- `tools/qa/gen-manifest.py` generates/refreshes it (AREAS and tier sets are at its top); `gates.sh --check` fails when a `run.sh` has no row or a row has no script.
- `gates.sh --changed [--base REF] [--level quick|full|nightly]` = the minimum set for the diff against `origin/main` (+ uncommitted + untracked). Dry run by default; `--run` runs the set through `/root/jarvis/bin/heavy` (`--jobs N` gates in parallel, the heavy queue still limits), classifies every log with `redcheck.sh`, exit 1 = NEW red. Unmapped files under kernel/lib/vendor/etc/assets trigger the fallback gates `kernel` + `userland` and a warning.
- Levels are cumulative: quick = representative/cheap gates of the touched areas, full = + the rest of the touched areas (before a merge), nightly = everything (cron on main).
- The tiers are a HEURISTIC (host-only or representative = quick; known long gates = nightly). `gates.sh --run` appends the wall time per gate to `~/.cache/osum-gates/times.tsv` (`gates.sh --times`); retier from those numbers. No per-gate runtime was measured before this round.

### 8.3 Build cache for the kernel compile (`tools/kernel/buildcache.sh`, used by `tools/build-kernel.sh`)
- Finding: `firnc` compiles the kernel as TWO whole-program units (`kmain.fi` -> `k.o`, `uprog.fi` -> `uprog.o`; the `as`/`ld`/`symtab` steps are small). There is no per-module object, so a per-module hash cannot work; the key is the hash of everything the compiler can read: firnc binary, `vendor/firn/.gebaut`, the prepared kernel copy (brand/version substituted), `lib/`, `vendor/firn/lib`, stage, root file, format version.
- The kernel copy contains the git short hash, so the key changes with every commit: the cache pays off for every further build of the SAME commit (the dozens of gates per branch, retries, parallel workers sharing `~/.cache/osum-build`), not across commits.
- The two compiles now run in PARALLEL and with cwd = the kernel copy and relative root paths. Before, the random mktemp name was embedded in the image 13312 times: two uncached builds of the same tree differed in 133120 bytes (not reproducible). Now cached == uncached byte for byte.
- Measured (`bash tools/kernel/buildcache-test.sh`, 15/0, load ~10): cold 40.5 s, warm 1.7 s, uncached 46.1 s (before this change: 43.6 s with two builds at once, ~58 s single). Counter-proof: a changed source line gives 2 misses and a different image; `OSUM_BUILD_CACHE_VERIFY=1` compiles on a hit and compares.
- Switches: `OSUM_BUILD_CACHE=off|<dir>`, `OSUM_BUILD_CACHE_MAX_MB` (default 1024, oldest entries pruned), `OSUM_BUILD_CACHE_VERIFY=1`. Log lines `buildcache: hit|miss <root> key=<12 hex> (<n> ms)`.
- Not done (next): one kernel image per commit shared by all gates (artifact store) - gates that call `build-kernel.sh` with other options (`--gui off`, `--ohne-tunnel`, other `OSUM_*`) are other keys, which is correct. Gates that still link their own `ld` line or use `firnc` directly do not use the cache yet.
