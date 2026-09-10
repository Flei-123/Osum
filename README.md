# Osum

Eigener Betriebssystem-Kernel für x86-64, geschrieben in **Firn** (eigene
Programmiersprache, siehe `../firn`). Bootet per Multiboot (BIOS + UEFI),
eigene Speicherverwaltung, Prozesse, Dateisystem, Treiber, Fensterserver.
Darüber liegt **OrientOS** — die Oberfläche und Anwendungen.

**BEGONNEN AM:** 19.08.2026 (erster Commit dieses Repos; der Kernel selbst
ist älter und kam aus dem Firn-Repository).

## Stand heute (10.09.2026)

**Umfang:** 1157 Commits, 362 eigene `.fi`-Dateien, **292.030 Zeilen**
(ohne `vendor/`).

**Kernel**
- Bootet BIOS und UEFI über Multiboot.
- Eigene Speicherverwaltung, Adressräume je Prozess, Scheduler mit
  Preemption. SMP: Speedup 3,54× auf 4 Kernen.
- OFS (eigenes Dateisystem), FAT32, MBR/GPT, VFS mit `/proc` und `/dev`.
- POSIX-Schicht mit Linux-x86-64-Syscall-Nummern; daneben ein eigenes
  Handle-/Capability-Modell (`kernel/cap.fi`).
- SMEP/SMAP aktiv, Panik-Berichte mit aufgelösten Symbolen in `/var/crash`.

**Netz**
- virtio-net, e1000, Realtek RTL8168/8169. TCP/IP-Stack und Sockets.
- Gegen echten Linux-Kernel gemessen: 75 Prüfungen, `ping` 10/10,
  1 MiB über TCP ohne Retransmit-Verlust, Recovery bei 10 % Paketverlust.
- SSH-2-Server; echter OpenSSH-Client loggt sich ein.

**Oberfläche**
- Fensterserver, Maus, TrueType mit Antialiasing, Tiling-Fenstermodell,
  Hell-/Dunkelmodus, Theme-System mit Farb- und Formtoken.
- **Taskleiste:** angeheftete Programme links (sichtbar auch wenn das
  Programm nicht läuft), per Ziehen umsortierbar, Reihenfolge in
  `/etc/taskbar.conf` — übersteht den Neustart. Certus ist ab Werk
  angeheftet.
- **Statusbereich rechts:** WLAN, Ton, Akku mit Prozentzahl, zweizeilige
  Uhr mit Datum; Symbolabstände gleichmäßig (29/29/29 Punkte gemessen).
- **Fensterebenen wie Windows:** die Taskleiste liegt immer obenauf,
  Fenster dürfen darunter geschoben werden. Maximieren endet an der
  Arbeitsfläche (3440×1360 auf einem 3440×1440-Schirm).
- **Vollbild mit F11:** ganzer Schirm ohne Dekoration, Rückkehr auf exakt
  die vorherige Geometrie.
- Fensterserver läuft in Ring 0, nicht als eigener Prozess.

**Userland**
- Eigene Shell (`if`/`for`/`while`/`case`/Funktionen), ~25 Standardtools
  (`find`, `sed`, `diff`, `patch`, `tar`, `gzip`, …).
- Dateimanager (`explorer.fi`, 1920 Zeilen), Texteditor, Einstellungen
  (4154 Zeilen), Taskleiste (4283 Zeilen), Taschenrechner, Snipping-Tool,
  Bildbetrachter, Medienwiedergabe (WAV, MP3), Papierkorb.
- ZIP/TAR/GZIP nativ (echtes deflate/inflate, CRC-32).
- Backup mit Inhaltsadressierung und Deduplizierung, Crypto-Erase in 20 ms.
- **Certus (eigener Browser) läuft als normales Ring-3-Programm.**

**Fremdsoftware**
- Statisch gegen musl gelinkte Linux-Binaries laufen unverändert.
- Lua 5.4.7 vollständig, busybox mit 15 gemessenen Applets, SQLite legt
  Datenbanken an.

**Echte Hardware**
- USB-Stick-Abbild bootet per BIOS und UEFI auf Justins Rechner.
- AHCI/SATA, Realtek-Netzwerk und Intel HDA Audio auf echtem Blech gemessen.
- Bis 2560×1080 Auflösung, EDID-gestützte Skalierung.

Statusdateien mit allen Belegen: `/root/osum-roadmap/` (`ROADMAP.md`,
`ERLEDIGT.md`, `OFFEN.md`, `INVENTAR.md`, `PROGRAMM-AUDIT.md`, `KERNEL.md`).

## Was noch fehlt

- Grafischer Login und Sperrbildschirm — der Schreibtisch läuft als `root`.
- Installation auf Platte über die Oberfläche; der Stick läuft aus dem RAM.
- Ausschalten und Neustart als Knopf in der Oberfläche.
- Zwischenablage Ende-zu-Ende: der Unterbau steht, kein Programmpaar nutzt ihn.
- Drag-and-Drop-Ziel: die Quelle gibt ab, niemand nimmt an.
- WLAN — kein Funktreiber. DNS-Resolver und NTP fehlen ebenfalls.
- AVX-512/XSAVE für Ring 3: auf modernen CPUs stirbt jedes Firn-Programm
  mit `#UD`.
- Explorer: Einfügen, Ausschneiden, Mehrfachauswahl, Eigenschaften-Dialog.
- USB-Stick zur Laufzeit einbinden und auswerfen; kein Hotplug-Manager.
- Kein Standby (S3), kein Bluetooth, kein Drucker, kein PDF-Betrachter.
- Nur x86-64 — es gibt keine Architekturgrenze für einen aarch64-Port.

Die vollständige Liste mit stabilen IDs: `/root/osum-roadmap/OFFEN.md`.

## Bauen und starten

Braucht: `bash`, `git`, `rustc`/`cargo`, `binutils`, `python3`,
`qemu-system-x86_64`.

```sh
git clone <dieses Repo> osum
cd osum
FIRN_REPO=/pfad/zu/firn ./vendor/firn/fetch-firnc.sh   # einmalig: Firn-Compiler holen
./test.sh                                              # ganze Abnahme, QEMU je Fall
```

Kernel mit Bildschirm starten:

```sh
qemu-system-x86_64 -kernel /tmp/k.mb -m 256 -append "osum gfx" \
   -serial stdio -vga std
```

Mit Fenstern, Maus und Schriften (Bild braucht `/lib/mono.ttf` + `/lib/sans.ttf`):

```sh
python3 tools/osum/mkfs.py build /tmp/d.img 4096 /lib/ \
   /lib/mono.ttf=assets/osum-mono.ttf /lib/sans.ttf=assets/osum-sans.ttf
qemu-system-x86_64 -kernel /tmp/k.mb -m 256 -append "gfx wm wmhold" \
   -serial stdio -vga std -drive file=/tmp/d.img,format=raw,if=ide,index=0
```

Einzelne Abschnitte: `bash tools/<name>/run.sh`.

## Aufbau

| Pfad | Inhalt |
|---|---|
| `kernel/*.fi` | der Kernel |
| `kernel/user/*.fi` | Shell, Tools, Userland-Bibliothek |
| `lib/libc/*.fi` | die Libc |
| `tools/` | Testläufer je Abschnitt |
| `assets/` | Schriften, Symbole, Programmbündel (`*.osp`) |
| `vendor/firn/` | festgenagelter Firn-Compiler (nur Hash + Holen-Skript im Repo) |
| `docs/` | Rundenberichte, Archiv |

Firn liegt nicht als Quelltext bei: `vendor/firn/COMMIT` nagelt einen
Firn-Commit fest, `vendor/firn/fetch-firnc.sh` holt und baut ihn.

## Lizenz

Zwei Lizenzen, Trennlinie ist Ring 0 gegen Ring 3:

- **MIT** für die Ring-3-Bibliotheken (`lib/libc/`, `kernel/user/crt.s`,
  `ulib.fi`, `wlib.fi` u. a.). Programme für Osum dürfen unter jeder
  Lizenz erscheinen, auch closed source. Volltext: `LICENSE.MIT`.
- **GPL-2.0-only** für den Kernel und die Ring-3-Programme, Tools und Tests.
  Volltext: `LICENSE`.

Details und Dateiliste: `LICENSING.md`, `THIRD_PARTY.md`.
