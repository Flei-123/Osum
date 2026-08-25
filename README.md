# Osum

Ein Betriebssystemkern fuer x86-64, geschrieben in **Firn**. Er bootet
ueber Multiboot, verwaltet Speicher und Adressraeume, plant Prozesse,
liest seine eigene Hardware ueber PCI, spricht NVMe ueber DMA, laeuft auf
mehreren Prozessoren, bietet eine POSIX-Schicht mit den Systemaufruf-
nummern von Linux x86-64 und startet ein Userland aus eigenstaendigen
ELF-Dateien von der Platte — eine Shell und dreiundzwanzig Werkzeuge.

    osum$ cat /d/nums.txt | grep 1 | wc -l
    4
    osum$ sort /d/three.txt | head -n 1 > /first.txt
    osum$ cd /d ; ls ; wc -l < nums.txt
    ./ ../ three.txt dup.txt nums.txt empty.txt
    12

Der Umfang, gezaehlt:

| Teil | Zeilen |
|---|---:|
| `kernel/*.fi` — der Kern | 14 519 |
| `kernel/user/*.fi` — Shell, Werkzeuge, ulib | 3 592 |
| `kernel/*.s`, `kernel/user/crt.s` — Assembler | 1 181 |
| `lib/libc/*.fi` — die libc aus Runde K4 | 1 234 |
| `tools/` — die Testlaeufer | 4 421 |

Osum ist **kein Spielzeug-Bootloader und kein fertiges System.** Was er
kann, steht unten; was er nicht kann, steht ebenfalls unten, und das ist
die laengere Liste.

---

## Was er kann

**Start und Kern.** Multiboot ueber `boot.s`, eigene GDT/IDT, alle
Ausnahmen mit Fehlercode und Registersatz gemeldet (`#DE`, `#PF`, `#GP`,
`#DF`), PIC und PIT mit hochlaufendem Tickzaehler, serielle Konsole,
Tastatur ueber IRQ1.

**Speicher.** Speicherkarte aus dem Multiboot-Header, Rahmenallokator,
Halde, Seitentabellen. Jeder Prozess bekommt einen **eigenen Adressraum**;
ein Prozess, der Kernelspeicher anfasst, stirbt, und der Kernel lebt
weiter.

**Prozesse.** Ablaufplaner mit Praeemption ueber den Zeitgeber,
Kontextwechsel in `switch.s`, Ring 3 ueber `syscall`/`sysret`,
`fork`, `execve`, `wait4`, Roehren, `dup2`.

**Dateisystem.** OFS — ein eigenes Dateisystem mit Inodes, direkten und
indirekten Bloecken, Verzeichnissen, `getdents64`. Es liegt auf einer
RAM-Platte, auf einer ATA-Platte oder auf NVMe. `tools/osum/mkfs.py`
baut Abbilder davon ausserhalb des Kernels.

**ELF-Lader.** `/bin/sh` ist eine Datei. Der Kernel liest sie von der
Platte, legt ihre Segmente mit den Rechten, die sie verlangt, in einen
frischen Adressraum und startet sie. Alle Werkzeuge sind eigenstaendige
ELF64-Dateien ohne libc-Anbindung an den Kernel.

**Hardware.** PCI-Durchmusterung ueber den Konfigurationsraum, lokaler
APIC und I/O-APIC, NVMe ueber DMA mit eigener Warteschlange.

**NVMe-Durchsatz, gemessen.** In QEMU/TCG bei 2,19 GHz, 128 KiB am
Stueck (`tools/pci/run.sh` reproduziert es):

| Weg | KiB/s | Worte durch die CPU |
|---|---:|---:|
| ATA PIO, 1 Block je Befehl | 4 541 | 65 536 |
| NVMe DMA, 1 Block je Befehl | 6 485 | **0** |
| NVMe DMA, 16 Bloecke je Befehl | 97 663 | **0** |

Das sind die Zahlen aus `docs/OSUM-K2.md`. Der Wert des schnellen Weges
haengt am Wirt: derselbe Test lieferte auf diesem Server unter Last
109 208 KiB/s, auf einer freien Maschine wurden 140 799 KiB/s gemessen.
Strukturell ist nur die letzte Spalte: der DMA-Weg schiebt **kein**
Datenwort durch die CPU, und das aendert sich mit keinem Wirt.

**Mehrere Prozessoren.** Die Anwendungsprozessoren werden aus der
ACPI-MADT gelesen und mit INIT/SIPI gestartet; jeder bekommt Stapel,
Deskriptortabelle und lokalen APIC. Laufliste, Rahmenallokator und
Dateisystem stehen unter einer Sperre. Gemessen: dieselbe Arbeit auf
einem Kern gegen vier Kerne, **Beschleunigung 3,54**, mit den Gegenproben
`nosmp`, `nolock` und `thread=single`.

**POSIX-Schicht.** Sechsundzwanzig Systemaufrufe mit den **Nummern von
Linux x86-64** — `read`, `write`, `open`, `close`, `stat`, `fstat`,
`lseek`, `mmap`, `brk`, `pipe`, `dup2`, `fork`, `execve`, `wait4`,
`getdents64` und die uebrigen — und darauf eine libc in Firn
(`lib/libc/`). Die Fehlerfaelle sind mitgemessen: vierzehn Arten, falsch
zu liegen, vierzehn negative Rueckgaben, ein lebender Kernel danach.

**Userland.** `/bin/sh` mit Roehren, Umlenkung (`>`, `<`), `;`,
Zeileneditor, `cd`, `exit` — und dreiundzwanzig Werkzeuge: `cat`, `cp`,
`date`, `df`, `echo`, `false`, `grep`, `head`, `kill`, `ls`, `mkdir`,
`mv`, `ps`, `rm`, `rmdir`, `sleep`, `sort`, `tail`, `touch`, `true`,
`uname`, `uniq`, `wc`.

---

## Was ihm fehlt

* **Keine Grafik.** Kein Framebuffer, kein VGA-Textmodus als Konsole, kein
  Fenstersystem. Die Konsole ist die serielle Schnittstelle.
* **Kein Netz.** Kein Treiber fuer eine Netzkarte. Ein TCP/IP-Stack in
  Firn existiert (Runde K3, `docs/OSUM-K3.md`), er liegt aber im
  Firn-Repository unter `lib/net/` und ist nie an diesen Kernel
  angeschlossen worden — er wurde gegen den Linux-Kernel ueber ein
  `veth`-Paar gemessen, nicht gegen eine Karte.
* **Kein UEFI.** Der Start laeuft ueber Multiboot; eine UEFI-Umgebung
  wird nicht unterstuetzt.
* **Kein USB.** Weder Host-Controller noch Tastatur ueber USB. Die
  Tastatur ist der PS/2-Controller.
* **Kein SATA/AHCI**, kein Partitionstabellen-Leser, kein Journal im
  Dateisystem, keine Rechte/Benutzer, keine Signale ausser dem
  Noetigsten, keine dynamische Bindung, keine gemeinsam genutzten
  Bibliotheken.
* **Nur x86-64.** Firn kann auch aarch64, der Kernel nicht.
* **Getestet wird in QEMU**, nicht auf echter Hardware.

---

## Bauen und starten

Vorausgesetzt: `bash`, `git`, `rustc`/`cargo` (fuer den festgenagelten
Uebersetzer), `binutils` (`as`, `ld`, `objcopy`, `nm`, `objdump`),
`python3`, `qemu-system-x86_64`.

```sh
git clone <dieses repo> osum
cd osum

# einmalig: den festgenagelten Firn-Uebersetzer bauen
FIRN_REPO=/pfad/zu/firn ./vendor/firn/hole-firnc.sh

# die ganze Abnahme (neun Abschnitte, QEMU pro Fall)
./test.sh
```

`./test.sh` ruft `hole-firnc.sh` selbst auf, wenn der Uebersetzer fehlt.
Liegt das Firn-Repository als Geschwisterverzeichnis (`../firn`), findet
das Skript es ohne `FIRN_REPO`.

Einzelne Abschnitte laufen auch fuer sich:

```sh
bash tools/kernel/run.sh      # der Kern (Runden 59/62)
bash tools/osum/run.sh        # ELF-Lader, /bin/sh von der Platte (K1)
bash tools/pci/run.sh         # PCI, APIC, NVMe (K2)
bash tools/posix/run.sh       # POSIX-Schicht und libc (K4)
bash tools/smp/run.sh         # vier Prozessoren (K5)
bash tools/userland/run.sh    # Shell und Werkzeuge (K6)
```

Ein Abbild von Hand bauen und starten (was `tools/userland/run.sh`
ausfuehrlicher tut):

```sh
export FIRNLIB=$PWD/lib
FC=vendor/firn/bin/firnc
for f in boot isr switch smp; do as --64 -o /tmp/$f.o kernel/$f.s; done
$FC kernel/kmain.fi -o /tmp/k.o
$FC kernel/uprog.fi -o /tmp/u.o
ld -T kernel/kernel.ld --defsym=KERNEL_MAIN=_F0.kernel_main \
   -o /tmp/k.elf /tmp/boot.o /tmp/isr.o /tmp/switch.o /tmp/smp.o /tmp/k.o /tmp/u.o
objcopy -O elf32-i386 /tmp/k.elf /tmp/k.mb
qemu-system-x86_64 -kernel /tmp/k.mb -m 128 -append "osum" \
   -serial stdio -display none -no-reboot
```

---

## Der Uebersetzer ist eine Abhaengigkeit, kein Inhalt

Osum wird in Firn geschrieben, aber der Firn-Uebersetzer gehoert **nicht**
in dieses Repository. Er wird **festgenagelt**:

* `vendor/firn/COMMIT` enthaelt genau **einen** Firn-Commit.
* `vendor/firn/hole-firnc.sh` holt diesen Stand (`git archive`, ohne im
  Firn-Repository irgendetwas anzulegen) und baut daraus
  `vendor/firn/bin/firnc` (firnc0, in Rust), `vendor/firn/bin/firnc1`
  (der Uebersetzer in Firn, von firnc0 uebersetzt) und
  `vendor/firn/lib/` (die Firn-Bibliothek desselben Commits).
* Eingecheckt ist nur der Hash und das Skript, nie die Binaerdatei.

**Warum.** Firn wird gerade aktiv weiterentwickelt. Wuerde Osum immer
gegen den neuesten Stand gebaut, waere bei jedem Fehler unklar, ob er aus
dem Kernel oder aus dem Uebersetzer kommt. Nachgezogen wird der Hash
deshalb **erst, wenn `./test.sh` gruen ist** — nicht vorher.

**Was aus der Firn-Bibliothek hereinkommt.** Nur `std`, und nur an einer
Stelle: `kernel/kcore.fi` schreibt `import std.core` — die Haelfte der
Bibliothek, die weder Allokator noch Systemaufruf braucht (Runde 73,
`docs/ROUND73.md`). Alles andere im Kernel steht in diesem Repository.
Der Weg dorthin ist der Suchpfad, den beide Uebersetzer zuletzt gehen,
`<Verzeichnis der Uebersetzerdatei>/../lib` — deshalb liegen
`vendor/firn/bin/` und `vendor/firn/lib/` nebeneinander. `$FIRNLIB` zeigt
auf `lib/` dieses Repositoriums und ist damit fuer die eigene libc frei
(`import libc.io`).

Beide Uebersetzerstufen werden gemessen: jeder Testlaeufer baut den
Kernel mit firnc0 **und** mit firnc1 und vergleicht die Ausgaben.

---

## Verhaeltnis zu Firn und zu OrientOS

**Firn** ist die Sprache und ihr Uebersetzer
(`../firn`). Osum ist aus dem Firn-Repository herausgeloest worden — die
Commit-Geschichte in diesem Repository ist die echte, sie beginnt lange
vor der Ausgliederung. Der Kernel lag dort als `demos/kernel/`, die libc
als `lib/osum/`. Was im Firn-Repository geblieben ist: der Uebersetzer,
die Standardbibliothek, die Browser-Bausteine (`lib/html`, `lib/css`,
`lib/js`, `lib/dom`) und der TCP/IP-Stack aus Runde K3.

**OrientOS** ist das Betriebssystem *um* einen Kernel herum — eigenes
Repository, eigene Abnahme. Es hat einen Kern gleichen Namens, der aber
zu ueber 17 000 Zeilen aus Rust besteht und gerade erst nach Firn
migriert wird. **Der Kernel in diesem Repository ist der weiter
entwickelte.** Die Aufteilung, die Justin festgelegt hat:

* **Osum** = der Kernel. Dieses Repository.
* **OrientOS** = das System drumherum.

Dass beide bisher „osum" hiessen, ist historisch und wird dort
aufgeloest, nicht hier.

---

## Doku

Die Rundenberichte in `docs/` sind unveraendert aus dem Firn-Repository
uebernommen und nennen deshalb noch die alten Pfade (`demos/kernel/`,
`lib/osum/`). Sie sind Protokoll, kein Handbuch, und werden nicht
nachtraeglich umgeschrieben.

| Datei | Runde |
|---|---|
| `docs/ROUND52.md` | `profile kernel` — freistehend uebersetzen |
| `docs/ROUND59.md` | der Kern: IDT, Ausnahmen, Zeitgeber, Speicher, Ring 3 |
| `docs/ROUND62.md` | Aufgaben, Adressraeume, Systemaufrufe, Dateisystem |
| `docs/ROUND73.md` | `std.core` — die Bibliothek ohne Allokator |
| `docs/OSUM-K1.md` | der ELF-Lader, `exec`, `/bin/sh` von der Platte |
| `docs/OSUM-K2.md` | PCI, APIC, NVMe ueber DMA |
| `docs/OSUM-K3.md` | der TCP/IP-Stack (Code im Firn-Repository) |
| `docs/ROUNDK4.md` | die POSIX-Schicht und die libc |
| `docs/ROUNDK5.md` | vier Prozessoren und die Sperre |
| `docs/ROUNDK6.md` | das Userland: Shell und Werkzeuge |

`ENTFERNEN-AUS-FIRN.md` beschreibt, was im Firn-Repository geloescht
werden muss, damit dort nichts doppelt liegt. **Ausgefuehrt ist das
nicht.**

## Lizenz

MIT, siehe `LICENSE`.
