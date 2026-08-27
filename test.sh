#!/usr/bin/env bash
# ./test.sh -- die Abnahme von Osum.
#
# Fuenfzehn Abschnitte, in der Reihenfolge, in der der Kernel entstanden ist.
# Jeder ruft einen eigenen Testlaeufer unter tools/ auf, jeder Laeufer
# startet QEMU pro Fall mit Zeitlimit, prueft die serielle Ausgabe und den
# Beendigungscode (21 = der Kernel hat sich selbst beendet, 63 = er ist an
# einer Ausnahme stehengeblieben), und zu jeder Zusage gehoert eine
# Gegenprobe -- eine Eigenschaft ohne Gegenprobe ist eine Behauptung.
#
#   1. Der festgenagelte Uebersetzer (vendor/firn/COMMIT). firnc0 und
#      firnc1 kommen aus EINEM Firn-Commit. Solange Firn sich bewegt, ist
#      bei jedem Fehler sonst unklar, ob er aus dem Kernel oder aus dem
#      Uebersetzer kommt.
#   2. Freistehend uebersetzen (tools/freestanding/run.sh, Runde 52):
#      `profile kernel`, Inline-Assembler, MMIO, `#[interrupt]` --
#      kernel/core.fi wird in BEIDEN Uebersetzern zu einer ELF-Objektdatei
#      OHNE undefinierte Symbole und laesst sich gegen ein Linkerskript
#      binden.
#   3. std.core im Kernel (tools/core/run.sh, Runde 73): die Haelfte der
#      Firn-Bibliothek, die weder Allokator noch Systemaufruf braucht;
#      kernel/kcore.fi bindet sie ein und bootet damit. Gegenproben: was
#      allokiert, bleibt verboten, und ein Modul, das das Kernel-Profil nur
#      BEHAUPTET, wird erwischt.
#   4. Der Kern laeuft (tools/kernel/run.sh, Runden 59 und 62): IDT und
#      Ausnahmemeldungen (#DE, #PF, #GP, #DF), PIC/PIT mit hochlaufendem
#      Tickzaehler, Speicherkarte, Rahmenallokator und Halde, Tastatur ueber
#      IRQ1, Ring 3 mit `syscall`/`sysret`, drei Aufgaben verschraenkt auf
#      einem Prozessor, zwei Prozesse mit eigenem Adressraum, Dateisystem
#      auf RAM-Platte und auf echter ATA-Platte.
#   5. Ein Programm von der Platte (tools/osum/run.sh, Runde K1): der
#      ELF-Lader, `exec`, /bin/sh aus dem OFS-Dateisystem.
#   6. Der Kernel liest seine eigene Maschine (tools/pci/run.sh, Runde K2):
#      PCI-Durchmusterung, lokaler APIC, NVMe ueber DMA -- mit gemessenem
#      Durchsatz.
#   7. Die POSIX-Schicht und die libc (tools/posix/run.sh, Runde K4):
#      sechsundzwanzig Systemaufrufe mit den NUMMERN VON LINUX x86-64 und
#      eine libc in Firn darauf (lib/libc/). Vierzehn Arten, falsch zu
#      liegen, vierzehn negative Rueckgaben, ein lebender Kernel.
#   8. Vier Prozessoren (tools/smp/run.sh, Runde K5): ACPI-MADT,
#      INIT/SIPI, je Kern Stapel, Deskriptortabelle und lokaler APIC,
#      Sperren um Laufliste, Rahmenallokator und Dateisystem. Gegenproben:
#      `nosmp`, `nolock`, `thread=single`.
#   9. Ein Userland (tools/userland/run.sh, Runde K6): eine Shell,
#      dreiundzwanzig Werkzeuge, Roehren und Umlenkung -- alles eigene
#      ELF-Dateien von der Platte.
#  10. Handles statt Umgebungsautoritaet (tools/caps/run.sh): die
#      Capability-Schicht, portiert aus OrientOS' nativer ABI
#      (`libs/osum-abi-native/`, Rust). Eine Handle-Tabelle je Prozess mit
#      Platz, Generation und Wuerfelwert (`kernel/cap.fi`), eine zweite
#      Aufrufnummerierung ab 2000 (`kernel/sys.fi`) und ein Programm in
#      Ring 3, das achtzehn Zusagen darueber meldet, was es darf und was
#      nicht. Gegenprobe: ohne das Wort `caps` gibt es nichts davon, und
#      der uebrige Kernel verhaelt sich Zeile fuer Zeile wie vorher.
#  11. Der Multiboot-Kopf und der UEFI-Pfad (tools/boot/run.sh): Bit 2
#      der Flags verlangt einen linearen Rahmenpuffer. Ohne das bricht
#      jeder Multiboot-Lader unter UEFI mit "Cannot use text mode with
#      UEFI" ab; mit ihm bootet dasselbe Abbild ueber BIOS UND ueber
#      UEFI. Der Start ueber eine echte UEFI-Firmware wird in OrientOS
#      gemessen -- dort liegen Lader und ISO.
#  12. Der Bildschirm (tools/gfx/run.sh, Runde K7, nachgezogen in K7B):
#      der lineare Rahmenpuffer, eine Textkonsole mit eigenem
#      8x16-Zeichensatz, Zeichengrundlagen mit Zweitpuffer und /dev/fb
#      fuer Ring 3. Gemessen an echten BILDSCHIRMFOTOS ueber den
#      QEMU-Monitor, bildpunktgenau gegen den Zeichensatz gerechnet --
#      und dazu die Speicherkarte von `kdata`, 38 Bereiche aus vier
#      Dateien paarweise gegeneinander (`tools/kernel/karte.py`).
#      Gegenproben: ohne das Wort `gfx` bricht jede Messung zusammen, und
#      mit der alten Adresse 0x2F000 MUSS der Kartenpruefer anschlagen.
#  13. Was jedes Unix-Programm voraussetzt (tools/unix/run.sh, Runde
#      K9): Signale (kill, sigaction, sigprocmask, sigreturn, die
#      Standardverhalten, SIGCHLD, und SIGSEGV/SIGFPE/SIGILL aus den
#      echten Prozessorausnahmen statt eines Kernel-Panics), eine
#      Terminalschicht mit Zeilenpuffer, rohem Modus, Steuerzeichen,
#      Fenstergroesse, Prozessgruppen und Pseudoterminals, eine Uhr
#      (Echtzeit aus dem CMOS, monoton aus dem Zyklenzaehler,
#      clock_gettime, nanosleep) und Zufall (Sammler aus
#      Zeitgeberflattern und Ereigniszeitpunkten, ChaCha20 darauf,
#      getrandom). STRG-C beendet den Vordergrundprozess wirklich, und
#      zwar gemessen: 128 + SIGINT. Gegenproben: `nosig` (nichts wird
#      zugestellt, der Zaehler bleibt bei null), `fixedrand` (fester
#      Strom, die statistische Pruefung faellt durch), und drei Neustarts
#      mit drei verschiedenen Saaten.
#
#  14. Das Netz (tools/net/run.sh, Runde K8): ein virtio-net-Treiber in
#      Firn (`kernel/virtio.fi`), der TCP/IP-Stack aus Runde K3 als
#      ABHAENGIGKEIT ueber vendor/firn/COMMIT (`vendor/net/HERKUNFT.md`),
#      die Naht dazwischen (`kernel/inet.fi`) und Steckdosen-Aufrufe fuer
#      Ring 3 mit den Nummern von Linux. Gemessen gegen den ECHTEN
#      Linux-Kernel ueber veth + AF_PACKET: ping, nc, curl, ein
#      Python-Server und `tc netem`. Gegenproben: ohne das Wort `nic`
#      bricht jede Messung zusammen, `nicnobm` nimmt das Busmaster-Bit,
#      `nicnoirq` maskiert den Vektor, `nicintx` nimmt den Stift statt
#      MSI-X.
#  21. WIDGETS UND EIN DATEIMANAGER (tools/k15/run.sh, Runde K15):
#      zwischen dem Rechteck, das Runde K10 einer Anwendung gab, und
#      einer Anwendung fehlte alles. Diese Runde baut es -- als
#      BIBLIOTHEK IN RING 3 (`kernel/user/wlib.fi`, `wlibc.fi`), nicht im
#      Kernel: Knoepfe, Beschriftungen, Textfelder mit Einfuegemarke,
#      Auswahl und Zwischenablage, Listen und Tabellen mit
#      Bildlaufleisten, Menues und Kontextmenues, Kontrollkaestchen,
#      Auswahlfelder, Reiter, Dialoge, eine Ereignisschleife, drei
#      Anordnungen und die Tastaturweiterschaltung. Im Kernel stehen
#      sieben Aufrufe (1800..1899, `kernel/wig.fi`), die kein Widget
#      kennen. Darauf sitzt `/bin/explorer`, die grafische Fassung von
#      `ls` -- fuer den Nutzer "Datei-Explorer", und wer `files` tippt,
#      landet am selben Ort: `/bin/files` ist ein ZWEITER NAME auf
#      dieselbe Inode, kein zweites Exemplar. Dazu ein
#      ANWENDUNGSVERZEICHNIS: ein Programm ist ein VERZEICHNIS
#      (`/apps/<name>.prog/` mit INFO, start, symbol und daten/ --
#      installieren heisst kopieren), und darueber ein STARTER mit
#      Suchfeld: man tippt "folder" und findet den Dateimanager, obwohl
#      das Wort weder im Namen noch in der Beschreibung steht.
#      DAZU EIN NAMENSINDEX UEBER DAS GANZE DATEISYSTEM, nach dem
#      Vorbild von "Everything": der Kernel gibt die Inode-Tabelle am
#      Stueck heraus (1807) und fuehrt ein Aenderungsjournal (1808), und
#      Ring 3 haelt daraus eine Liste NUR AUS NAMEN im Speicher. An 4021
#      Namen gemessen, immer PAARWEISE gegen einen rekursiven
#      Baumdurchlauf: dieselben Treffer, Name fuer Name, und der Index um
#      ein Vielfaches schneller.
#      Gemessen an echten Bildschirmfotos, in die ueber den
#      QEMU-Monitor echte Klicks und Tastendruecke gespeist wurden --
#      und der Text darin JE ZEICHEN gegen `tools/ttf/raster.py`, das
#      Symbol BILDPUNKT FUER BILDPUNKT gegen `tools/k15/symbol.py`.
#      Gegenproben: `wignohit` (keine Trefferpruefung -- kein Widget
#      erfaehrt vom Klick), `wignoclip` (keine Zwischenablage),
#      `wignokeys` (dieselbe Suche ohne die Schluesselwoerter -- dann
#      findet "folder" NICHTS), `wignoidx` (dieselbe Suche ohne den
#      Namensindex -- dann findet "blau" NICHTS), `suchen -n` (dieselben
#      drei Dateiaenderungen, aber das Journal wird nicht abgeholt --
#      dann weiss der Index von keiner), `nodirty`, `nofocus`, `nomouse`
#      und der Lauf ganz ohne `wig`.
#
#  23. USB (tools/k17/run.sh, Runde K17): ein xHCI-Regler
#      (`kernel/xhci.fi`) -- ueber PCI an seiner Klasse 0c:03:30
#      gefunden, Register aus dem Geraet gelesen, Kommandoring,
#      Ereignisring und je Endpunkt ein Uebertragungsring, Steckplaetze,
#      Adressvergabe, MSI-X auf Vektor 43. Darauf ein USB-Kern
#      (`kernel/usb.fi`): Aufzaehlung beim Anstecken, Deskriptoren,
#      Konfiguration, Treiberzuordnung an der KLASSE, Anstecken und
#      Abziehen im Betrieb. Und drei Klassen: Tastatur und Maus im
#      Boot-Protokoll, die BEIDE in den Eingabeweg von Runde 59 und K10
#      muenden (der HID-Gebrauchscode wird zu einem PS/2-Abtastcode und
#      geht durch `kbd.on_code`), und Massenspeicher ueber
#      Bulk-Only-Transport und SCSI als viertes Geraet von `blk.fi`.
#      DIE MESSUNG: derselbe Testlauf zweimal, einmal mit `-device
#      usb-kbd` und einmal mit PS/2, und die `key:`-Zeilen und die
#      Shell-Sitzung werden OKTETT FUER OKTETT verglichen -- plus die
#      Zahl `usb: keys=`, ohne die der Vergleich wertlos waere. Der
#      Stick wird von `mkfs.vfat` und `sfdisk` gebaut, von Osum
#      beschrieben und danach von `mtools` auf dem WIRT wieder gelesen.
#      Abziehen im Betrieb: der Deskriptor bleibt offen, das Geraet
#      verschwindet, jeder Zugriff gibt -ENODEV, und derselbe Prozess
#      schreibt danach auf der Wurzel weiter. Gegenproben: `nousb`,
#      `nohid`, `nomsc`, `usbnoirq` (Vektor maskiert -- keine Taste
#      kommt an), `usbpoll` (derselbe maskierte Vektor, aber der Kern
#      sieht selbst nach), ein Lauf ohne Regler und einer ohne Geraete.
#
#  15. EIN WIRT FUER FREMDE PROZESSOREN (tools/hv/run.sh, Runde K12):
#      AMD-V, verschachtelte Seitentabellen, sechs Gaeste. Der Kernel
#      legt eine Gastmaschine an, tritt ein, wertet den Austrittsgrund
#      aus und tritt wieder ein -- CPUID, Anschluesse, MSR, HLT,
#      Steuerregister, Seitenfehler des Gasts, Dreifachfehler,
#      Unterbrechungen. Ein Gast geht SELBST in den geschuetzten Modus
#      und baut sich seine EIGENE Seitentabelle; dass er durch sie
#      hindurchliest, beweist ZWEI Uebersetzungen hintereinander. Ring 3
#      fuehrt eine Gastmaschine ueber ein Handle mit Rechten.
#      Nicht Intel VT-x, sondern AMD-V, und das ist gemessen: QEMUs
#      Softwareemulation meldet vmx als nicht unterstuetzt, und einen
#      /dev/kvm gibt es auf dem Messrechner nicht. Gegenproben: ohne
#      `hv` genau eine Zeile, `nonpt` laesst den Gast in den Speicher
#      des Wirts laufen, `gastfrei` gibt dem Gast die Maschine,
#      `nosvm` schaltet alles ab, `-cpu qemu64` bietet keine NPT an.
#
#
#  15. Die zwei Schutzbits und das Boot-Modul (tools/guard/run.sh, Runde
#      K10): die letzten zwei Faehigkeiten aus OrientOS' Rust-Kernel, die
#      dieser hier noch nicht hatte. SMEP und SMAP in CR4
#      (`kernel/guard.fi`, aus `arch/x86_64/user.rs`) -- Ring 0 fuehrt
#      keinen Nutzercode mehr aus und fasst Nutzerdaten nur noch im
#      `stac`-Fenster an, das an genau vier Stellen steht (`sys.peek`,
#      `sys.poke`, `sys.copy_in`, `sys.copy_out`) und beim Signalrahmen.
#      Und ein BOOT-MODUL als Wurzelplatte (`kernel/bootmod.fi`, aus
#      `kcore/initramfs.rs`) mit CRC32 davor -- damit traegt ein ISO
#      nicht nur einen Kern, sondern ein Userland. Gegenproben: `smapraw`
#      und `smepraw` muessen mit den Bits einen #PF geben (0x1 und 0x11)
#      und ohne sie durchlaufen, ein falsches `modcrc=` laesst das Modul
#      liegen, und die Summe wird am Ende des Laufs NOCH EINMAL gerechnet
#      -- haette `mem.scan` den Bereich nicht reserviert, waere sie eine
#      andere.
#
#  16. Man kann auf diesem System ARBEITEN (tools/k11/run.sh, Runde
#      K11): ein bildschirmorientierter Editor in Ring 3 ueber den rohen
#      Terminalmodus aus Runde K9, zwanzig Werkzeuge (find, sed, diff,
#      patch, tar, gzip/gunzip, xargs, du, top, mount/umount, basename,
#      dirname, tee, cut, tr, seq, env, which) und eine Shell, die eine
#      Sprache ist (if/elif/else, while, until, for, case, Funktionen,
#      return/break/continue/shift, test und `[`). Der Editor wird
#      WIRKLICH BEDIENT: die Tasten kommen ueber den QEMU-Monitor am Tor
#      0x60 an, und danach liest der WIRT die gesicherte Datei aus dem
#      Plattenabbild und haelt sie Oktett fuer Oktett gegen die
#      Erwartung. Jedes Werkzeug steht gegen sein GNU-Gegenstueck;
#      `tar` und `gzip` arbeiten in BEIDE Richtungen mit dem echten
#      `tar` und `gzip` des Wirts zusammen. Gegenproben: ohne Sichern
#      aendert sich die Platte nicht, ohne Umschalttaste gibt es keine
#      Grossbuchstaben, ohne `gfx` kein Bild, und nach `umount` startet
#      kein Programm mehr von der Platte.
#
#
#  19. BENUTZER, RECHTE UND DER ERSTE PROZESS (tools/k13/run.sh, Runde
#      K13): uid/gid je Prozess mit den Nummern von Linux, vererbt ueber
#      fork und execve, mit echter/wirksamer/gesicherter Kennung nach
#      POSIX. Rechtebits und Eigentuemer IM INODE -- das Format wurde
#      dafuer erweitert (drei direkte Blockzeiger weniger, dafuer mode,
#      uid, gid) und traegt jetzt eine Fassungsnummer im Superblock;
#      alte Abbilder bleiben lesbar. Die Pruefung steht an EINER Stelle
#      (kernel/perm.fi) und wird aus fuenf Toren gerufen. Passwoerter
#      mit PBKDF2-HMAC-SHA256 und Salz, gegen Pythons hashlib gemessen.
#      Und /sbin/init als PROZESS 1: Dienstetafel, respawn, Waisen
#      einsammeln, `svc`, Herunterfahren ueber echtes ACPI. Gegenproben:
#      `noperm` (die Pruefung sagt immer ja -- die Messung bricht
#      zusammen), `nosuid`, `ofsv2raw` (altes Abbild, neue Regeln),
#      `noacpi` (Beendigungscode 21 statt 0), `initsh` (der Notweg),
#      und ein Lauf ohne init, in dem die Waise als Leiche stehenbleibt.
#  20. DIE VFS-SCHICHT UND DIE FREMDEN DATEISYSTEME (tools/k14/run.sh,
#      Runde K14): bis dahin kannte dieser Kernel genau EIN
#      Dateisystem, und `mount` hatte kein Ziel -- es hiess "die eine
#      Platte ist da". Jetzt melden sich Dateisysteme mit einer TAFEL
#      VON NEUN VERRICHTUNGEN an (`kernel/vfsops.fi`), die Pfade werden
#      ueber Einhaengegrenzen hinweg aufgeloest (`kernel/vfs.fi`,
#      `kernel/mnt.fi`), und OFS ist der erste NUTZER dieser Schicht
#      (`kernel/ofs.fi`) und kein Sonderfall daneben. Darauf: /proc als
#      Dateisystem, das seine Dateien beim Lesen ERZEUGT
#      (`kernel/procfs.fi`), /dev mit null, zero, random, tty, fb und
#      den Blockgeraeten (`kernel/devfs.fi`), ein Leser fuer MBR und
#      GPT samt BEIDEN CRC32-Pruefsummen (`kernel/part.fi`) und FAT32
#      lesend UND schreibend, mit langen Namen (`kernel/fat.fi`).
#      Gemessen gegen die ECHTEN Werkzeuge: das Abbild kommt von
#      `mkfs.vfat`, die Dateien von `mcopy`, die Tafeln von `sfdisk`
#      und `sgdisk`, und `fsck.fat` faellt das Urteil ueber das, was
#      Osum geschrieben hat. Gegenproben: `novfs` (nur die Wurzel),
#      `noprocfs`, `nodevfs`, `nofat`, `nopart` (das Dateisystem wird
#      bei Block 0 gesucht, wo die TAFEL steht), `fatro`, ein
#      umgedrehtes Bit im GPT-Kopf, und ein Lauf ganz ohne zweite
#      Platte. Dazu `vfsall`: dieselbe Arbeit auf OFS, einmal auf dem
#      geraden Weg von Runde 62 und einmal durch die Ops-Tafel,
#      Oktett fuer Oktett verglichen.
#
#  17. Die Oberflaeche (tools/wm/run.sh, Runde K10): ein Zeigegeraet am
#      zweiten Anschluss des Tastaturbausteins (`kernel/ps2m.fi`), ein
#      Fensterserver mit Stapelreihenfolge, Eingabefokus und
#      Bereichsverfolgung (`kernel/wm.fi`) und ein TrueType-Leser samt
#      Rasterer mit Kantenglaettung, ganz in Firn (`kernel/ttf.fi`).
#      Gemessen an echten Bildschirmfotos, in die ueber den QEMU-Monitor
#      echte Mausbewegungen, Klicks und Tastendruecke eingespeist wurden
#      -- und der Text darin nicht gegen eine Flaeche, sondern JE
#      ZEICHEN gegen eine zweite, unabhaengige Rasterung desselben
#      Umrisses (`tools/ttf/raster.py`). Gegenproben: `nodirty`
#      (Bereichsverfolgung aus -- die Messung MUSS einbrechen),
#      `nofocus` (die Taste kommt beim falschen Fenster an), `nomouse`,
#      `nompoll` und der Lauf ganz ohne das Wort `wm`.
#
#  25. DER BILDSCHIRM, ZUM ZWEITEN MAL (tools/display/run.sh, Runde
#      DISPLAY): Runde K7 hatte ZWEI Aufloesungen als vier Konstanten im
#      Quelltext, umschaltbar nur beim Start. Diese Runde fragt die Karte
#      -- Modusliste ueber Zuruecklesen der VBE-Register und
#      VBE_VIDEO_MEMORY_64K, EDID aus dem Speicherbereich der Karte,
#      Moduswechsel IM BETRIEB mit Rueckfall und einer Frist von 15
#      Sekunden, dazu Gammarampe, Drehung und Skalierung beim
#      Uebertragen. Gemessen wird mit Bildschirmfotos vorher und
#      nachher; die Gegenprobe nimmt das Wort `disp` weg und erwartet
#      nichts davon.
#  24. ENERGIE UND LEISTUNG (tools/k18/run.sh, Runde K18): bis dahin
#      konnte dieser Kernel ueber ACPI genau eine Sache -- abschalten.
#      Zwischen "laeuft" und "aus" gab es nichts. Diese Runde baut die
#      drei Profile Energiesparen/Ausgeglichen/Hoechstleistung auf
#      IA32_PERF_CTL beziehungsweise HWP, den Ruhezustand ueber
#      monitor/mwait statt einer Warteschleife, die Turbosperre ueber
#      IA32_MISC_ENABLE Bit 38, Temperatur samt Drosselung, Akku und
#      Netzteil aus den ACPI-Tabellen und /bin/power auf der Konsole.
#      WAS DIESER WIRT NICHT HERGIBT, steht ausdruecklich im Laeufer:
#      unter TCG faellt kein Takt, weil nichts taktet. Gemessen wird,
#      dass die richtigen Register die richtigen Werte bekommen -- und
#      fuer IA32_MISC_ENABLE, dem einzigen mit vollem Rundlauf auf
#      diesem Wirt, wird der Wert WIRKLICH aus dem Prozessor
#      zurueckgelesen: dieselbe Stelle, dreimal, drei verschiedene Werte.
#
#  22. DER UEBERSETZER LAEUFT AUF DEM SYSTEM SELBST (tools/k16/run.sh,
#      Runde K16). `firnc` -- der in Firn geschriebene Uebersetzer --
#      liest auf OSUM eine `.fi` von der Platte, uebersetzt sie und
#      schreibt eine `.s` dorthin zurueck; `fas`, ein Assembler und
#      Binder in Firn (kernel/user/fas.fi), macht daraus unmittelbar ein
#      ELF -- ohne `as`, ohne `ld`, die es auf diesem System nicht gibt.
#      Das Programm LAEUFT dann auf Osum. Und die Steigerung davon: was
#      Osum erzeugt, ist ZEICHENGLEICH mit dem, was derselbe Uebersetzer
#      auf Linux aus derselben Quelle macht -- der Fixpunktgedanke von
#      Firns Runde 31, eine Ebene hoeher. Dazu die Schicht unter dem
#      Doppelklick: eine Tabelle "Dateiart -> womit oeffnen" im KERN
#      (kernel/ftype.fi, Erkennung am Inhalt UND an der Endung, Inhalt
#      geht vor) und `#!` in `execve`. Gegenproben: `nostackgrow` (der
#      Stapel waechst nicht -- der Uebersetzer MUSS an einem
#      Seitenfehler sterben), `nobigmem` (die grosse Arena ist aus), eine
#      ANDERE Quelle (darf NICHT zeichengleich herauskommen), ein
#      unbekannter Befehl im Assembler, eine `.s` ohne `_start`, ein
#      Sprung ins Nichts, ein `#!` im Kreis und eine `.fi`, die nicht
#      uebersetzt -- die darf NICHT als Erfolg gemeldet werden.
#
#  25. DER FENSTERBAUM (tools/tiling/run.sh, Runde TILING): bis dahin
#      schwebten die Fenster frei -- WOHIN eines gelegt wurde, entschied
#      der, der es anlegte. Diese Runde macht daraus einen Baum, wie i3,
#      sway und bspwm ihn fuehren: Blaetter sind Fenster, innere Knoten
#      sind Aufteilungen mit einem VERHAELTNIS (nicht mit Bildpunkten),
#      Container koennen `split`, `tabbed` oder `stacked` sein, und
#      Drehen, Spiegeln und Ausbalancieren gibt es dazu. Die
#      Windows-artige Schnellablage (halb links, ein Viertel) ist ein
#      SONDERFALL des Baumes und kein zweites System.
#      WAS HIER GEMESSEN WIRD, und es ist nur eine Sache: die Fenster
#      muessen die Flaeche EXAKT ausfuellen, nach JEDER Operation.
#      Zehntausend zufaellige Operationen, nach jeder rechnet der Kern
#      die Invariante auf zwei unabhaengigen Wegen nach -- null
#      Verletzungen. Die Pruefung selbst hat eine Gegenprobe (ein
#      Rechteck um einen Bildpunkt verstellt MUSS auffallen), die
#      Bereichsverfolgung hat eine (`notiledirty`), und die
#      Tastenbelegung hat eine: sie steht in
#      /users/<name>/config/tiling.conf, und ohne die Datei gibt es
#      KEINE Belegung. Dazu drei Bildschirmfotos (Teilung, Reiter,
#      Drehung), bildpunktgenau nachgerechnet, und /bin/tiling in Ring 3.
#
# Kein '|| true', kein Verschlucken von Beendigungscodes.
set -uo pipefail

cd "$(dirname "$0")"
ROOT=$(pwd)
WORK="$ROOT/.test-work"
mkdir -p "$WORK"

# Modulsuchpfad: `import libc.*` findet ueber $FIRNLIB nach <repo>/lib.
# `import std.core` findet der Uebersetzer selbst -- er liegt in
# vendor/firn/bin/, und beide Stufen suchen zuletzt in <exe>/../lib.
export FIRNLIB="$ROOT/lib"

PASS=0
FAIL=0
FAILED=""
ZUSAGEN=0

ok()  { PASS=$((PASS + 1)); }
bad() { FAIL=$((FAIL + 1)); FAILED="$FAILED\n  $1"; echo "  FEHLER  $1"; }

# Zaehlt die Zusagen aus der Schlusszeile eines Laeufers
# ("NAME: 174 passed, 0 failed") auf die Gesamtsumme.
zusagen() {
    local log=$1
    local n
    # `[A-Z][A-Z0-9]*` und nicht `[A-Z]+`: der Laeufer von Runde K11
    # meldet sich als "K11:", und mit dem alten Muster waeren seine
    # Zusagen still unter den Tisch gefallen.
    n=$(grep -aoE '^[A-Z][A-Z0-9]*: [0-9]+ (passed|proofs)' "$log" | tail -1 | grep -oE '[0-9]+' | tail -1)
    [ -n "${n:-}" ] && ZUSAGEN=$((ZUSAGEN + n))
}

# Ein Abschnitt: Nummer+Titel, Skript, Logname, Muster fuer die Zeilen,
# die auch bei Erfolg zu sehen sein sollen.
lauf() { # titel skript logname muster
    local titel=$1 skript=$2 name=$3 muster=$4
    echo "== $titel =="
    local rc=0
    bash "$skript" > "$WORK/$name.log" 2>&1 || rc=$?
    grep -aE "$muster" "$WORK/$name.log" | sed 's/^ */   /'
    zusagen "$WORK/$name.log"
    if [ "$rc" -eq 0 ]; then
        ok
    else
        bad "$skript ist fehlgeschlagen (siehe .test-work/$name.log)"
        grep -aE '^  FAIL' "$WORK/$name.log" | head -12 | sed 's/^/     /'
    fi
}

echo "== 1. der festgenagelte Uebersetzer (vendor/firn/COMMIT) =="
COMMIT=$(cat vendor/firn/COMMIT)
S1=""
bash vendor/firn/hole-firnc.sh > "$WORK/vendor.log" 2>&1 || \
    S1="$S1 hole-firnc.sh fehlgeschlagen (siehe .test-work/vendor.log);"
[ -x vendor/firn/bin/firnc ]  || S1="$S1 vendor/firn/bin/firnc fehlt;"
[ -x vendor/firn/bin/firnc1 ] || S1="$S1 vendor/firn/bin/firnc1 fehlt;"
[ -d vendor/firn/lib/std ]    || S1="$S1 vendor/firn/lib/std fehlt;"
[ -f vendor/firn/.gebaut ] && [ "$(cat vendor/firn/.gebaut)" = "$COMMIT" ] || \
    S1="$S1 vendor/firn/.gebaut passt nicht zu COMMIT;"
# RUNDE K8: der TCP/IP-Stack kommt MIT dem festgenagelten Uebersetzer
# herein und nicht als Kopie. Die drei Blob-Hashes in vendor/net/BLOBS
# sind die, die Firn im Baum dieses Commits stehen hat -- zieht jemand
# COMMIT nach und der Stack hat sich dabei geaendert, faellt es hier auf
# und nicht erst in einer Messung. Siehe vendor/net/HERKUNFT.md.
while read -r want name; do
    case "$want" in \#*|"") continue;; esac
    got=$(git hash-object "vendor/firn/lib/$name" 2>/dev/null)
    [ "$got" = "$want" ] || S1="$S1 vendor/firn/lib/$name: $got statt $want;"
done < vendor/net/BLOBS
# Gegenprobe zur Gegenprobe: eine Kopie des Stacks im Repo waere genau
# das Auseinanderdriften, das diese Runde vermeidet.
[ -d lib/net ] && S1="$S1 im Repo liegt eine Kopie des Stacks unter lib/net;"
# Gegenprobe: im Repo selbst liegt kein Uebersetzer. Faende sich hier einer,
# waere nicht mehr gesagt, welcher Stand gemessen wurde.
{ [ -e compiler ] || [ -e bin/firnc1.fi ]; } && \
    S1="$S1 im Repo liegt ein Uebersetzer -- er gehoert nach vendor/;"
ZUSAGEN=$((ZUSAGEN + 9))
if [ -z "$S1" ]; then
    echo "   Firn ${COMMIT:0:8}, firnc0 + firnc1 gebaut, lib/std daneben,"
    echo "   lib/net/ mit den drei Blob-Hashes aus vendor/net/BLOBS (9 Zusagen)"
    ok
else
    bad "der festgenagelte Uebersetzer:$S1"
    tail -5 "$WORK/vendor.log" | sed 's/^/     /'
fi

lauf "2. freistehend uebersetzen: profile kernel, Inline-Assembler, MMIO, iretq (tools/freestanding/run.sh)" \
     tools/freestanding/run.sh freestanding '^FREESTANDING: '

lauf "3. std.core im Kernel: die Bibliothek ohne Allokator (tools/core/run.sh, Runde 73)" \
     tools/core/run.sh core '^CORE: '

lauf "4. der Kern laeuft: Aufgaben, Adressraeume, Systemaufrufe, Dateien (tools/kernel/run.sh, Runden 59/62)" \
     tools/kernel/run.sh kernel '^KERNEL: '

lauf "5. ein Programm von der Platte: ELF-Lader, exec, /bin/sh (tools/osum/run.sh, Runde K1)" \
     tools/osum/run.sh osum '^OSUM:|deepest|biggest program|refusals in one run'

lauf "6. der Kernel liest seine Maschine: PCI, APIC, NVMe ueber DMA (tools/pci/run.sh, Runde K2)" \
     tools/pci/run.sh pci '^PCI: |^        bench: '

lauf "7. die POSIX-Schicht und die libc (tools/posix/run.sh, Runde K4)" \
     tools/posix/run.sh posix '^POSIX:|^   -- '

lauf "8. vier Prozessoren, und die Sperre, die einen Kernel daraus macht (tools/smp/run.sh, Runde K5)" \
     tools/smp/run.sh smp '^SMP: |^        (one core|four cores|speed-up|one host thread|with the lock)'

lauf "9. ein Userland: eine Shell, 25 Werkzeuge, Roehren und Umlenkung (tools/userland/run.sh, Runde K6)" \
     tools/userland/run.sh userland '^USERLAND:|the whole userland in octets|the biggest program|programs loaded off the disk'

lauf "10. Handles statt Umgebungsautoritaet: die Capability-Schicht aus OrientOS (tools/caps/run.sh)" \
     tools/caps/run.sh caps '^CAPS: |^        \(\.utext'

lauf "11. der Multiboot-Kopf verlangt einen Bildschirm -- der UEFI-Pfad (tools/boot/run.sh)" \
     tools/boot/run.sh boot '^BOOT: '

lauf "12. der Bildschirm: Rahmenpuffer, Textkonsole, /dev/fb (tools/gfx/run.sh, Runde K7)" \
     tools/gfx/run.sh gfx '^GFX: |^   fbbench: '

lauf "13. was jedes Unix-Programm voraussetzt: Signale, Terminal, Uhr, Zufall (tools/unix/run.sh, Runde K9)" \
     tools/unix/run.sh unix '^UNIX: |^   -- '

lauf "14. das Netz: virtio-net, der Stack aus K3, Steckdosen -- gegen den Linux-Kern (tools/net/run.sh)" \
     tools/net/run.sh net '^NET:|^  OK    (throughput|round trip|what came back|and on three)'

lauf "15. die Schutzbits und das Boot-Modul: SMEP, SMAP, CRC32 (tools/guard/run.sh, Runde K10)" \
     tools/guard/run.sh guard '^GUARD: |^  OK    (das SMAP-Fenster|und alle drei weiteren|nach einem Lauf)'

lauf "16. man kann darauf arbeiten: ein Editor, zwanzig Werkzeuge, eine Shell mit Sprache (tools/k11/run.sh, Runde K11)" \
     tools/k11/run.sh k11 '^K11: |^  OK    (DIE GESICHERTE|EINE DATEI|AUF DEM BILDSCHIRM|GNU )'

lauf "17. die Oberflaeche: Maus, Fensterserver, TrueType (tools/wm/run.sh, Runde K10)" \
     tools/wm/run.sh wm '^WM: |^   wmbench: |^        im Regellauf|^        ohne Bereichsverfolgung'

lauf "18. ein Wirt fuer fremde Prozessoren: AMD-V, verschachtelte Seitentabellen, Gaeste (tools/hv/run.sh, Runde K12)" \
     tools/hv/run.sh hv '^HV:|^        (bench|exits|cpu):'

lauf "19. Benutzer, Rechte und der erste Prozess: uid/gid, chmod/chown, login, init (tools/k13/run.sh, Runde K13)" \
     tools/k13/run.sh k13 '^K13: |^  OK    (DIE (KENNUNG|WAISE)|GEGENPROBE|PYTHON|das Passwort steht NICHT|die Maschine (schaltet|faehrt)|DER NOTWEG)'
lauf "20. die VFS-Schicht und die fremden Dateisysteme: /proc, /dev, FAT32, MBR und GPT (tools/k14/run.sh, Runde K14)" \
     tools/k14/run.sh k14 '^K14: |^  OK    (vier Dateisysteme|blob.bin|kopie.bin|fsck.fat|dieselbe Arbeit|GEGENPROBE novfs: nur|GEGENPROBE nopart)'

# ABSCHNITT 21 STEHT AM ENDE DER ABSCHNITTSLISTE UND VOR DER SCHLUSSBILANZ.
# Zweimal an einem Tag hat ein Skript, das bis zum Dateiende reichte, die
# Bilanz mitgerissen -- danach lief der Test durch und sagte nicht mehr,
# ob er bestanden hat.
lauf "21. der Uebersetzer laeuft auf dem System selbst, und eine Datei weiss, womit man sie oeffnet (tools/k16/run.sh, Runde K16)" \
     tools/k16/run.sh k16 '^K16: |^  OK    (ZEICHENGLEICH|DAS AUF OSUM|DER DOPPELKLICK|DER AUSLEGER|DER INHALT GEHT VOR|fas uebersetzt|16 von 16)'
lauf "22. Widgets und der Dateimanager: eine Bibliothek in Ring 3 (tools/k15/run.sh, Runde K15)" \
     tools/k15/run.sh k15 '^K15: |^        -> |^  OK    (die Anordnung|ein Klick auf das Kaestchen|mit Bereichsverfolgung|und /daten/neu|der Verweis spart|getippt |OHNE (die Schluesselwoerter|das Journal|den Namensindex)|[0-9]\. (DER AUFBAU|DIE SUCHE|DIE GEGENPROBE|der Index)|und DIESELBEN NAMEN|nach dem (Anlegen|Umbenennen)|das Symbol des Dateimanagers)'
lauf "25. der Fensterbaum: Kacheln, Reiter, Drehen -- und die Invariante nach jeder Operation (tools/tiling/run.sh, Runde TILING)" \
     tools/tiling/run.sh tiling '^TILING: |^  OK    (die Zusagen des Fensterbaums|und KEINE davon|Verletzungen der Invariante|und nach JEDER Operation|GEGENPROBE|Fenster [0-9] |und im Bild|vier Reiter|nach der Drehung|der Aufwand waechst|und das spart|Kern und Ring 3)'
lauf "24. Energie und Leistung: drei Profile, Ruhezustand, Waerme, Akku (tools/k18/run.sh, Runde K18)" \
     tools/k18/run.sh k18 '^K18: |^  OK    (dieselbe Stelle|IA32_PERF_CTL bekommt|Turbo ist bei|SpeedStep ist bei|jeder Durchlauf ging|schlafend |aber es wird kein|zwei Tabellen|GEGENPROBE|GEDROSSELT|im BILD|dasselbe Pruefbild|und einen Bildpunkt DANEBEN|keine AUFRUFNUMMER)'
# ABSCHNITT 25 -- DIE ZWEITE MASCHINE (Runde ARM). Er baut KEIN Osum: der
# festgenagelte Uebersetzer kann `profile kernel` fuer AArch64 nicht
# (docs/ARCH.md, Abschnitt 6). Was er baut und misst, ist der Boden
# darunter -- Start bei EL1, MMU mit TTBR0 UND TTBR1, Ausnahmevektoren,
# GICv2, der generische Zeitgeber, PL011 und ein Kontextwechsel, auf
# `qemu-system-aarch64 -M virt`. Sechs der Zusagen sind Gegenproben, und
# die interessanteste davon ist `noaf`: ein einziges geloeschtes Bit im
# Seitendeskriptor, und die Maschine sagt kein Wort mehr.
lauf "25. die zweite Maschine: AArch64 auf qemu -M virt (tools/arm/run.sh, Runde ARM)" \
     tools/arm/run.sh arm '^ARM: |^  OK    (der erste|the first|100 virtual|arch_switch|nomm:|noaf:|notimer:|noeoi:|32 virtio|with a disk|a page mapped|the same octet|SCTLR|CNTFRQ)|^   (first octet|to the last line)'


lauf "23. USB: xHCI, Aufzaehlung, Tastatur, Maus und ein Stick (tools/k17/run.sh, Runde K17)" \
     tools/k17/run.sh k17 '^K17: |^  OK    (DIESELBEN ZEICHEN|DIESELBE SHELL|WAS OSUM SCHRIEB|die Tastatur, an Klasse|die Maus, an Klasse|der Stick, an Klasse|der Zeiger steht|GEGENPROBE usbnoirq|lesen auf dem OFFENEN)'

lauf "26. Der Bildschirm, zum zweiten Mal: Modusliste, Wechsel im Betrieb, EDID, Gamma (tools/display/run.sh, Runde DISPLAY)" \
     tools/display/run.sh display '^DISPLAY: |^  OK    (gefragt |die native |der rohe Block|er hat [0-9]+ Mikro|gemessen: |je Bildpunkt|NACHHER|VORHER|ZURUECK|Feld 1 ist rot|das Foto ist 800x600 -- der Bildmodus|und der Kernel hat von SELBST|die Aufrufnummern dieser Runde|ein Programm in Ring 3 hat)'

echo
echo "=================================================================="
if [ "$FAIL" -eq 0 ]; then
    echo "ALLE $PASS ABSCHNITTE BESTANDEN, $ZUSAGEN Zusagen, 0 Fehler"
    exit 0
else
    echo "$PASS Abschnitte bestanden, $FAIL FEHLGESCHLAGEN ($ZUSAGEN Zusagen)"
    printf '%b\n' "$FAILED"
    exit 1
fi
