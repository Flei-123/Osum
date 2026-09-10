# Osum

Eigener Betriebssystem-Kernel für x86-64, geschrieben in **Firn** (eigene
Programmiersprache, siehe `../firn`). Bootet per Multiboot (BIOS + UEFI),
eigene Speicherverwaltung, Prozesse, Dateisystem, Treiber, Fensterserver.
Darüber liegt **OrientOS** — die Oberfläche und Anwendungen.

**BEGONNEN AM:** 19.08.2026 (erster Commit in diesem Baum: "Etappe A,
Schritt 1: alle Bezeichner englisch"). Der Kernel selbst ist **älter** —
er stammt aus dem Firn-Repository (`demos/kernel/`), wo er seit Runde 52
gewachsen war, und wurde am 19.08. als eigenes Repo mit vollständiger
Historie herausgelöst. Das echte Startdatum des Kernels liegt vor dem
19.08., ist aber nicht als Datum dokumentiert.

## Stand heute (10.09.2026)

- 1153 Commits, 362 eigene `.fi`-Dateien, **291.169 Zeilen** (ohne vendor/).
- Bootet BIOS und UEFI, eigene Speicherverwaltung/Prozesse/Scheduler (SMP,
  Speedup 3,54× auf 4 Kernen gemessen), OFS-Dateisystem + FAT32 + MBR/GPT,
  VFS mit `/proc` und `/dev`.
- POSIX-Schicht mit Linux-x86-64-Syscall-Nummern, eigene Handles/Capabilities
  parallel dazu (`kernel/cap.fi`).
- Netzwerk: virtio-net, TCP/IP-Stack, Sockets — gegen echten Linux-Kernel
  gemessen (75 Prüfungen, u. a. 0 % Paketverlust bei `ping`, TCP-Retransmit
  funktioniert).
- SSH-2-Server, echter OpenSSH-Client kann sich einloggen.
- GUI: Fensterserver, Maus, TrueType mit Antialiasing, Tiling-Fenstermodell,
  Dunkel-/Hellmodus, Theme-System. **Läuft noch im Kernel (Ring 0), nicht
  isoliert.**
- Userland: eigene Shell (`if`/`for`/`while`/Funktionen), ~25 Tools
  (`find`, `sed`, `diff`, `tar`, `gzip`, …), Dateimanager (`explorer.fi`,
  1920 Zeilen), Texteditor, Einstellungen, Taskleiste, Taschenrechner,
  Snipping-Tool, ZIP/TAR/GZIP nativ, Backup mit Deduplizierung/Crypto-Erase.
- **Certus (eigener Browser) läuft als normales Ring-3-Programm auf Osum.**
- Linux-Binaries (musl-statisch) laufen unverändert; Lua 5.4.7 komplett;
  busybox mit 15 gemessenen Applets.
- USB-Stick-Abbild bootet auf echter Hardware (BIOS + UEFI), AHCI/SATA-,
  Realtek-Netzwerk- und Intel-HDA-Audiotreiber gemessen auf echtem Blech.

Laufende Statusdateien mit allen Belegen: `/root/osum-roadmap/` (`ROADMAP.md`,
`ERLEDIGT.md`, `OFFEN.md`, `INVENTAR.md`, `PROGRAMM-AUDIT.md`, `KERNEL.md`).

## Was noch fehlt

- Grafischer Login/Sperrbildschirm — Schreibtisch läuft als `root`.
- Installation auf Platte über die Oberfläche (Stick läuft nur aus dem RAM).
- Ausschalten/Neustart als Knopf in der GUI (nur Befehlszeile).
- Zwischenablage Ende-zu-Ende (Unterbau da, kein Programmpaar nutzt es).
- Drag-and-Drop-Ziel (Quelle da, Ablegen wird nirgends angenommen).
- WLAN (kein Funktreiber), DNS-Resolver, NTP.
- AVX-512/XSAVE für Ring 3 — moderne CPUs stürzen mit `#UD` ab.
- Explorer: Einfügen/Ausschneiden, Mehrfachauswahl, Eigenschaften-Dialog.
- Fensterserver läuft im Kernel statt isoliert; kein Standby (S3).
- Nur x86-64, keine Architekturgrenze für aarch64-Port.

Die vollständige, laufend gepflegte Liste mit stabilen IDs: `OFFEN.md`.

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

Einzelne Abschnitte: `bash tools/<name>/run.sh` (siehe `docs/` für die Liste).

## Aufbau

| Pfad | Inhalt |
|---|---|
| `kernel/*.fi` | der Kernel |
| `kernel/user/*.fi` | Shell, Tools, Userland-Bibliothek |
| `lib/libc/*.fi` | die Libc |
| `tools/` | Testläufer je Abschnitt |
| `vendor/firn/` | festgenagelter Firn-Compiler (nur Hash + Holen-Skript im Repo) |
| `docs/` | Rundenberichte (Archiv, kein Handbuch) |

Firn kommt nicht als Quelltext mit — `vendor/firn/COMMIT` nagelt einen
Firn-Commit fest, `vendor/firn/fetch-firnc.sh` holt und baut ihn.

## Lizenz

Zwei Lizenzen, Trennlinie ist Ring 0 gegen Ring 3:

- **MIT** für die Ring-3-Bibliotheken (`lib/libc/`, `kernel/user/crt.s`,
  `ulib.fi`, `wlib.fi` u. a.) — Programme für Osum dürfen unter jeder
  Lizenz erscheinen, auch closed source. Volltext: `LICENSE.MIT`.
- **GPL-2.0-only** für den Kernel und die Ring-3-Programme/Tools/Tests.
  Volltext: `LICENSE`.

Details und Dateiliste: `LICENSING.md`, `THIRD_PARTY.md`.
