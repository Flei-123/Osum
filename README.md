# Osum

Ein Betriebssystemkern fuer x86-64, geschrieben in **Firn**. Er bootet
ueber Multiboot, verwaltet Speicher und Adressraeume, plant Prozesse,
liest seine eigene Hardware ueber PCI, spricht NVMe ueber DMA, laeuft auf
mehreren Prozessoren, bietet eine POSIX-Schicht mit den Systemaufruf-
nummern von Linux x86-64, startet ein Userland aus eigenstaendigen
ELF-Dateien von der Platte — eine Shell und dreiundzwanzig Werkzeuge —
und **zeigt das alles in Fenstern**: mit Maus, Fensterserver und
TrueType-Schriften mit Kantenglaettung.

mehreren Prozessoren, **spricht TCP/IP ueber eine virtio-net-Karte**,
bietet eine POSIX-Schicht mit den Systemaufrufnummern von Linux x86-64
und startet ein Userland aus eigenstaendigen ELF-Dateien von der Platte —
eine Shell und fuenfundzwanzig Werkzeuge. Seit Runde K11 kann man darauf
**arbeiten**: es gibt einen bildschirmorientierten Editor, zwanzig
weitere Werkzeuge (`find`, `sed`, `diff`, `patch`, `tar`, `gzip`, …) und
eine Shell mit `if`, `for`, `while`, `case` und Funktionen.

    osum$ edit /notizen.txt          # ^O sichert, ^X geht, ^W sucht
    osum$ find / -name *.txt -type f
    /d/three.txt
    /notizen.txt
    osum$ tar -cf /w/alles.tar /d ; gzip /w/alles.tar
    osum$ for f in a b c ; do echo $f > /w/$f ; done
    osum$ if [ -s /w/a ] ; then echo da ; fi
    da

    osum$ cat /d/nums.txt | grep 1 | wc -l
    4
    osum$ sort /d/three.txt | head -n 1 > /first.txt
    osum$ cd /d ; ls ; wc -l < nums.txt
    ./ ../ three.txt dup.txt nums.txt empty.txt
    12
    osum$ ping -c 3 10.9.0.1
    PING 10.9.0.1 56 octets of data.
    64 octets from 10.9.0.1: icmp_seq=1 time=20 ms
    64 octets from 10.9.0.1: icmp_seq=2 time=10 ms
    64 octets from 10.9.0.1: icmp_seq=3 time=10 ms
    --- ping statistics
    3 transmitted, 3 received, 0% packet loss
    osum$ wget http://10.9.0.1:8000/x
    wget: connected to 10.9.0.1:8000
    a page from the linux kernel side, 46 octets.
    wget: status 200

Der Umfang, gezaehlt:

| Teil | Zeilen |
|---|---:|
| `kernel/*.fi` — der Kern | 30 383 |
| `kernel/user/*.fi` — Shell, Werkzeuge, ulib | 5 114 |
| `kernel/*.s`, `kernel/user/crt.s` — Assembler | 1 336 |
| `lib/libc/*.fi` — die libc aus Runde K4 | 1 598 |
| `tools/` — die Testlaeufer | 9 650 |

Zuletzt dazugekommen: Runde K10 hat ZWEI Teile, die parallel liefen.
Die Oberflaeche -- `kernel/wm.fi` (der Fensterserver), `kernel/ttf.fi`
(TrueType-Leser und Rasterer) und `kernel/ps2m.fi` (das Zeigegeraet),
dazu auf dem Wirt `tools/ttf/schnitt.py`, `tools/ttf/raster.py` (die
ZWEITE Fassung des Rasterers, gegen die die erste gemessen wird) und
`tools/wm/` (`docs/ROUNDK10W.md`). Und die Schutzbits --
`kernel/guard.fi` (SMEP und SMAP in CR4 samt dem `stac`-Fenster) und
`kernel/bootmod.fi` (ein Boot-Modul als Wurzelplatte, mit CRC32 davor);
beides aus OrientOS' Rust-Kernel portiert und dort die letzten zwei
offenen Punkte des Kernelwechsels (`docs/ROUNDK10.md`). Runde K11 hat
den Editor und die zwanzig Werkzeuge dazugelegt (`docs/ROUNDK11.md`).

Dazu aus der Capability-Runde: `kernel/cap.fi` (die Handle-Tabelle) und
die Testlaeufer `tools/caps/` und `tools/boot/`. Aus der Netzrunde K8:
`kernel/virtio.fi`, `kernel/inet.fi`, `kernel/netsvc.fi`,
`lib/libc/net.fi` und `tools/net/`.

Der **TCP/IP-Stack** (2 646 Zeilen) steht in dieser Rechnung nicht — er
wird nicht hier geschrieben. Er kommt als Abhaengigkeit aus dem
Firn-Commit, den `vendor/firn/COMMIT` ohnehin schon fuer den Uebersetzer
festnagelt; `vendor/net/HERKUNFT.md` sagt, wie, und Abschnitt 1 von
`./test.sh` prueft die drei Blob-Hashes.

Osum ist **kein Spielzeug-Bootloader und kein fertiges System.** Was er
kann, steht unten; was er nicht kann, steht ebenfalls unten, und das ist
die laengere Liste.

---

## Was er kann

**Start und Kern, BIOS und UEFI.** Multiboot ueber `boot.s`. Der Kopf
verlangt seit der Capability-Runde einen **linearen Rahmenpuffer**
(Flag-Bit 2): ohne dieses Bit besteht ein Multiboot-Lader auf einem
Textmodus, den es unter UEFI nicht gibt, und bricht ab — mit ihm bootet
dasselbe Abbild ueber SeaBIOS **und** ueber OVMF. Das ISO dazu baut
OrientOS. Weiter: eigene GDT/IDT, alle
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

**Bildschirm.** Ein linearer Rahmenpuffer, entgegengenommen vom Lader
(Multiboot, Flag-Bit 12) oder von der Karte selbst eingestellt
(Bochs-VBE ueber PCI — QEMUs `-kernel` hat keinen Videoteil). Darauf eine
Textkonsole von 100 x 37 Zeichen mit eigenem 8x16-Zeichensatz, Rollen,
Farben und Textmarke, dazu Bildpunkt, Linie, Rechteck, Bildbereich und
ein Zweitpuffer mit bereichsweiser Uebertragung. **Die serielle Konsole
bleibt parallel bestehen** — `serial.put` spiegelt jedes Oktett, also
zeigen beide dasselbe, von den Bootmeldungen bis zur Shell. Und
**/dev/fb**: ein Programm in Ring 3 oeffnet es, schreibt hinein, liest
zurueck und bildet es sich mit `mmap` als 2-MiB-Kachel in den eigenen
Adressraum ab — mit den ueblichen Rechtepruefungen. Alles davon haengt an
dem Wort `gfx` auf der Kommandozeile; ohne es aendert sich am Kernel
nichts. Gemessen an Bildschirmfotos (`docs/ROUNDK7.md`).

**Oberflaeche (Runde K10).** Ein **Zeigegeraet** am zweiten Anschluss
des Tastaturbausteins (IRQ 12, `kernel/ps2m.fi`): Drei- und
Vier-Oktett-Pakete, Rad, Anschlag an den Bildraendern, ein gezeichneter
Zeiger. Ein **Fensterserver** (`kernel/wm.fi`): Fenster anlegen,
verschieben, Groesse aendern, schliessen; Stapelreihenfolge;
Eingabefokus; Ereignisse an das richtige Fenster; und
**Bereichsverfolgung**, damit nur das Neue gemalt wird — gemessen 6801 us
fuer den ganzen Schirm gegen 198 us fuer eine Zeigerbewegung, also
Faktor 34. Anwendungen reden ueber **Handles** aus `kernel/cap.fi` mit
ihm (neun Aufrufe ab 2100), nicht ueber einen zweiten Weg.

Und **echte Schriften** (`kernel/ttf.fi`): ein TrueType-Leser (`head`,
`hhea`, `maxp`, `hmtx`, `cmap` Format 4, `loca`, `glyf`, `kern`) und ein
Rasterer mit **Kantenglaettung**, ganz in Firn und ganz in Festkomma —
kein FreeType, keine Gleitkommazahl. Die Schriften liegen als
zusammengeschnittene TrueType-Dateien auf der Platte (`assets/`,
`tools/ttf/schnitt.py`). Darauf ein **Terminalfenster**, in dem
`/bin/sh` von der Platte laeuft, und ein zweites Fenster, das ein
Programm in **Ring 3** anlegt, bemalt und auf Klicks und Tasten
antwortet.

Gemessen an Bildschirmfotos, in die ueber den QEMU-Monitor **echte
Mausbewegungen, Klicks und Tastendruecke** eingespeist wurden — und der
Text darin nicht gegen eine Flaeche, sondern **je Zeichen** gegen eine
zweite, unabhaengige Rasterung desselben Umrisses
(`tools/ttf/raster.py`). `docs/ROUNDK10.md`.

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

**Handles statt Umgebungsautoritaet.** Neben der POSIX-Schicht steht eine
zweite ABI, portiert aus OrientOS (`libs/osum-abi-native/`, Rust →
`kernel/cap.fi`, Firn): eine **Handle-Tabelle je Prozess**, in der ein
Handle aus Platz, Generation und einem prozesseigenen Wuerfelwert besteht,
mit zehn Rechtebits und acht Objektarten. Drei Saetze, und jeder ist aus
Ring 3 gemessen (`tools/caps/run.sh`, achtzehn Zusagen):

* **Eine frische Tabelle ist leer.** Es wird nichts geerbt — auch nicht
  von einem Vorgaenger auf demselben Platz der Aufgabentabelle.
* **Ein geschlossenes Handle trifft nie wieder etwas**, auch nicht nach
  Wiederverwendung des Platzes (Generation).
* **Rechte koennen nur kleiner werden.** Eine Kopie mit weniger Rechten
  kann sich das Verlorene nicht zurueckholen.

Der Unterschied zu POSIX in einer Zeile: ein gueltiges Handle ohne das
noetige Recht ist `RightsDenied`, ein gefaelschtes ist `BadHandle` —
POSIX hat fuer beides nur `-EBADF`. Die Aufrufnummern liegen ab 2000; was
es noch **nicht** gibt (Kanaele, Ports, Namensraeume, Spawn mit
Handle-Liste, Speicherobjekte), antwortet `NotSupported` und steht in
OrientOS' `KERNELWECHSEL.md` als offener Punkt.

**Netz.** Ein **virtio-net-Treiber** in Firn (`kernel/virtio.fi`), modern
nach virtio 1.0: die vier Bereiche aus der Faehigkeitsliste des Geraets,
Merkmalsaushandlung mit `FEATURES_OK`, zwei virtqueues zu 64
Deskriptoren, MSI-X oder der Unterbrechungsstift. Darauf der
**TCP/IP-Stack aus Runde K3** — als Abhaengigkeit, nicht als Kopie — und
darueber **Steckdosen fuer Ring 3** mit den Nummern von Linux x86-64
(`socket` 41, `connect` 42, `accept` 43, `sendto` 44, `recvfrom` 45,
`shutdown` 48, `bind` 49, `listen` 50, `getsockname` 51, `getpeername`
52). Eine Steckdose ist ein Eintrag der offenen Dateien aus Runde K4, also
funktionieren `read`, `write`, `close`, `dup2` und `fork` darauf, ohne
dass eines davon weiss, was eine Steckdose ist.

**Gemessen gegen den echten Linux-Kernel** (`tools/net/run.sh`, 75
Zusagen, `veth` + `AF_PACKET` in einem eigenen Netz-Namensraum, QEMU ohne
KVM):

| was | Ergebnis |
|---|---|
| `ping -c 10` vom Linux-Kern | **10 von 10**, 3,3 ms im Mittel |
| `nc` schiebt 1 MiB hinein | **1 048 576 Oktette**, 732 Rahmen, **6 027 KiB/s**, 0 Neusendungen |
| `nc` durch das Echo | **262 144 Oktette hin und zurueck, md5 gleich** |
| `curl http://10.9.0.2:8080/` | Statuszeile, Kopf und Rumpf von curl selbst akzeptiert |
| Osum verbindet sich **aktiv** | 262 144 hin, 262 144 zurueck, **0 falsche Oktette** |
| `tc netem loss 20 %` hinein | alles in Reihenfolge, 132 Segmente neu zusammengesetzt |
| `tc netem loss 10 %` hinaus | 0 falsch, **4 Verluste erholt: 1 ueber den Zeitgeber, 3 ueber drei doppelte Quittungen** |

Gegenprobe: dasselbe Kernelabbild ohne das Wort `nic` verliert jedes
Paket, `nicnobm` (kein Busmaster) ebenso, und mit `nicnoirq` kommen alle
262 144 Oktette an waehrend der Unterbrechungszaehler auf 0 stehen bleibt.
Die Zahlen und die offenen Punkte stehen in `docs/ROUNDK8.md`.

**Der Kernel schuetzt sich vor dem Userland (Runde K10).** SMEP und SMAP
stehen in CR4, sobald CPUID sie meldet — auf JEDEM Kern, denn CR4 ist pro
Prozessor. Ring 0 fuehrt damit keinen Nutzercode mehr aus, und
Nutzerdaten fasst er nur noch im `stac`-Fenster an, das an genau vier
Stellen steht (`sys.peek`, `sys.poke`, `sys.copy_in`, `sys.copy_out`)
plus am Signalrahmen. Gemessen wird nicht die Behauptung, sondern das
Register: `guard: cr4=0x300020  smep=1  smap=1`. Gegenproben: `smapraw`
und `smepraw` muessen mit den Bits einen #PF geben (Fehlercode 0x1 und
0x11) und ohne sie durchlaufen.

**Ein Boot-Modul kann die Wurzelplatte sein (Runde K10).** Was ein Lader
neben den Kern legt (Multiboot, Flag-Bit 3), wird mit CRC32 geprueft und
dann als Blockgeraet gemountet — `fs.fi` merkt davon nichts, es sind
dieselben 512 Oktette je Block. Damit traegt ein ISO nicht nur einen
Kern, sondern ein Userland. Ein falsches `modcrc=` laesst das Modul
liegen, und `mem.scan` nimmt seinen Bereich aus dem Rahmenverwalter --
nachgewiesen dadurch, dass die Summe am ENDE des Laufs dieselbe ist.

**Benutzer, Rechte und ein erster Prozess (Runde K13).** Jeder Prozess
traegt eine echte, eine wirksame und eine gesicherte Benutzer- und
Gruppenkennung; sie werden ueber `fork` und `execve` vererbt und ueber
`setuid`/`setgid`/`setresuid` mit den Regeln von POSIX gewechselt --
Aufrufnummern wie bei Linux. Dateien tragen Rechtebits und einen
Eigentuemer IM INODE; das Format hat dafuer eine Fassungsnummer im
Superblock bekommen und alte Abbilder bleiben lesbar. Die Pruefung steht
an EINER Stelle (`kernel/perm.fi`) und wird aus fuenf Toren gerufen:
`open`, `mkdir`, `unlink`, `chdir`, `execve`. Dazu `chmod`, `chown`,
`id`, `whoami`, `su`, `passwd` und `login` -- Passwoerter als
PBKDF2-HMAC-SHA256 mit Salz, gegen Pythons `hashlib` gemessen. Und
`/sbin/init` als **Prozess 1**: eine Dienstetafel (`/etc/inittab`),
Neustart abgestuerzter Dienste, Einsammeln von Waisen, `svc` zum
Starten/Stoppen/Abfragen und ein Herunterfahren ueber echtes ACPI -- an
QEMUs Beendigungscode zu erkennen (0 statt 21). Ein Notweg ueber die
Kommandozeile (`initsh`) startet die Shell wie vorher.

**Userland.** `/bin/sh` mit Roehren, Umlenkung (`>`, `<`), `;`,
Zeileneditor, `cd`, `exit` — und fuenfundzwanzig Werkzeuge: `cat`, `cp`,
`date`, `df`, `echo`, `false`, `grep`, `head`, `kill`, `ls`, `mkdir`,
`mv`, `ping`, `ps`, `rm`, `rmdir`, `sleep`, `sort`, `tail`, `touch`,
`true`, `uname`, `uniq`, `wc`, `wget`.

---

## Was ihm fehlt

* **Kein Fenstersystem.** Es gibt einen Rahmenpuffer, eine Textkonsole
  und `/dev/fb` (Runde K7) — aber nur EINE Flaeche. Konsole und Programm
  uebermalen sich, wenn sie dieselben Bildzeilen nehmen. Es gibt auch
  kein `ioctl`: ein Programm erfaehrt die Groesse des Bildes ueber
  `lseek(SEEK_END)` und die Breite gar nicht.
* **Der Fensterserver laeuft IM KERN.** Runde K10 hat Fenster, Maus,
  Stapelreihenfolge, Eingabefokus und echte Schriften — aber der Server
  sitzt in Ring 0, weil dieser Kernel keinen Speicher zwischen zwei
  Prozessen teilen kann (`mmap` kennt anonyme Seiten und den
  Rahmenpuffer, sonst nichts). Der Schutz zwischen den ANWENDUNGEN
  steht; der zwischen Server und Anwendung nicht.
* **Kein `ioctl` fuer die Flaeche.** Ein Programm erfaehrt die Groesse
  seines Fensters ueber `wm_info`, die des Bildschirms ueber
  `lseek(SEEK_END)` auf `/dev/fb` — aendern kann es die Aufloesung
  nicht.
* **Kein Hinting, keine Unterpixel-Positionierung, keine Drehung.** Der
  Rasterer setzt Glyphen auf ganze Bildpunkte und setzt zusammengesetzte
  Glyphen mit ihrer Verschiebung ein, nicht mit ihrer Matrix.
* **Kein Netz.** Kein Treiber fuer eine Netzkarte. Ein TCP/IP-Stack in
  Firn existiert (Runde K3, `docs/OSUM-K3.md`), er liegt aber im
  Firn-Repository unter `lib/net/` und ist nie an diesen Kernel
  angeschlossen worden — er wurde gegen den Linux-Kernel ueber ein
  `veth`-Paar gemessen, nicht gegen eine Karte.

* **Keine Grafik.** Kein Framebuffer, kein VGA-Textmodus als Konsole, kein
  Fenstersystem. Die Konsole ist die serielle Schnittstelle.
* **Keine Namensaufloesung.** Kein Resolver, kein `/etc/hosts`: eine
  Adresse sind vier Zahlen. `/bin/wget` weist eine URL mit einem Namen
  darin ab, statt etwas Falsches zu antworten.
* **Nur eine Warteschlangenpaarung im Netz**, keine Auslagerung von
  Pruefsummen an die Karte, kein IPv6, keine Neuzusammensetzung von
  IP-Fragmenten, kein Fensterskalieren, kein SACK.
* **Kein USB.** Weder Host-Controller noch Tastatur ueber USB. Die
  Tastatur ist der PS/2-Controller.
* **Kein SATA/AHCI**, kein Partitionstabellen-Leser, kein Journal im
  Dateisystem, keine dynamische Bindung, keine gemeinsam genutzten
  Bibliotheken.
* **Rechte, aber keine vollstaendigen.** Seit Runde K13 gibt es
  Benutzer, Rechtebits und Eigentuemer -- aber das Betretungsrecht wird
  nur am LETZTEN Verzeichnis eines Pfades geprueft, nicht an jedem
  Glied; es gibt keine Nebengruppen und kein `/etc/group`; das
  Sticky-Bit wird gespeichert und nicht beachtet; und die 2048 Runden
  PBKDF2 sind fuer heutige Verhaeltnisse zu wenig (die Rundenzahl steht
  im Eintrag und laesst sich erhoehen). `docs/ROUNDK13.md`, Abschnitt 7,
  zaehlt die Luecken einzeln auf.
* **Nur x86-64, und ohne Architekturgrenze.** Firn kann auch aarch64, der
  Kernel nicht — und es gibt in diesem Baum keine Schicht, hinter der die
  x86-Einzelheiten steckten. OrientOS hatte dafuer `kcore/arch_iface.rs`
  (Traits plus ein Testschritt, der x86-Begriffe ausserhalb von `arch/`
  verbietet); das ist NICHT portiert, weil es eine Umbauarbeit an jedem
  Modul waere und keine Portierung. Die Vorlage steht in OrientOS unter
  `vorlage/arch_iface.rs`.
* **Kanaele, Ports, Namensraeume.** Die nativen Aufrufe dafuer gibt es in
  `sys.fi`, und sie antworten `NotSupported` (−9): der Aufruf EXISTIERT in
  dieser ABI, dieser Kernel bietet ihn nur nicht an. Portiert ist das
  Handle-Modell darunter (`cap.fi`), nicht die Objekte, die daran haengen.
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

# die ganze Abnahme (fuenfzehn Abschnitte, 1181 Zusagen, QEMU pro Fall)
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
bash tools/gfx/run.sh         # der Bildschirm (K7)
bash tools/unix/run.sh        # Signale, Terminal, Uhr, Zufall (K9)
bash tools/net/run.sh         # virtio-net und der TCP/IP-Stack (K8)
bash tools/guard/run.sh       # SMEP/SMAP und das Boot-Modul (K10)
bash tools/wm/run.sh          # Maus, Fenster, TrueType (K10)
bash tools/hv/run.sh          # der Hypervisor: AMD-V, NPT, Gaeste (K12)
```

Den Kernel mit Bildschirm starten und selbst hinsehen — `-vga std` ist
die Karte, die `kernel/fb.fi` bedient:

```sh
qemu-system-x86_64 -kernel /tmp/k.mb -m 256 -append "osum gfx" \
   -serial stdio -vga std
```

Und mit **Fenstern**, Maus und echten Schriften (Runde K10). Die
Schriften liegen auf der Platte, also braucht es ein Abbild mit
`/lib/mono.ttf` und `/lib/sans.ttf` darauf:

```sh
python3 tools/osum/mkfs.py build /tmp/d.img 4096 /lib/ \
   /lib/mono.ttf=assets/osum-mono.ttf /lib/sans.ttf=assets/osum-sans.ttf
qemu-system-x86_64 -kernel /tmp/k.mb -m 256 -append "gfx wm wmhold" \
   -serial stdio -vga std -drive file=/tmp/d.img,format=raw,if=ide,index=0
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
| `docs/ROUNDK7.md` | der Bildschirm: Rahmenpuffer, Textkonsole, /dev/fb |
| `docs/ROUNDK7B.md` | warum nach dem Verschmelzen die Buchstaben vom Schirm verschwanden — und die Karte von `kdata` |
| `docs/ROUNDK8.md` | das Netz: virtio-net, der Stack aus K3, Steckdosen |
| `docs/ROUNDK9.md` | Signale, Terminals, Uhr und Zufall |
| `docs/ROUNDK10.md` | SMEP/SMAP und das Boot-Modul — die letzten zwei Punkte des Kernelwechsels |
| `docs/ROUNDK11.md` | **man kann darauf arbeiten**: der Editor, zwanzig Werkzeuge, die Shell als Sprache |
| `docs/ROUNDK10W.md` | die Oberflaeche: Maus, Fensterserver, TrueType mit Kantenglaettung |
| `docs/ROUNDK12.md` | ein Wirt fuer fremde Prozessoren: AMD-V, verschachtelte Seitentabellen, Gaeste, Gastmaschinen aus Ring 3 |
| `docs/ROUNDK13.md` | **Benutzer, Rechte und `init`**: uid/gid, chmod/chown, /etc/passwd und /etc/shadow, Anmeldung, der erste Prozess |

`ENTFERNEN-AUS-FIRN.md` beschreibt, was im Firn-Repository geloescht
werden muss, damit dort nichts doppelt liegt. **Ausgefuehrt ist das
nicht.**

## Lizenz

MIT, siehe `LICENSE`.
