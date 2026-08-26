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
