#!/usr/bin/env bash
# ./test.sh -- die Abnahme von Osum.
#
# Elf Abschnitte, in der Reihenfolge, in der der Kernel entstanden ist.
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
    n=$(grep -aoE '^[A-Z]+: [0-9]+ (passed|proofs)' "$log" | tail -1 | grep -oE '[0-9]+' | head -1)
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
# Gegenprobe: im Repo selbst liegt kein Uebersetzer. Faende sich hier einer,
# waere nicht mehr gesagt, welcher Stand gemessen wurde.
{ [ -e compiler ] || [ -e bin/firnc1.fi ]; } && \
    S1="$S1 im Repo liegt ein Uebersetzer -- er gehoert nach vendor/;"
ZUSAGEN=$((ZUSAGEN + 5))
if [ -z "$S1" ]; then
    echo "   Firn ${COMMIT:0:8}, firnc0 + firnc1 gebaut, lib/std daneben (5 Zusagen)"
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

lauf "9. ein Userland: eine Shell, 23 Werkzeuge, Roehren und Umlenkung (tools/userland/run.sh, Runde K6)" \
     tools/userland/run.sh userland '^USERLAND:|the whole userland in octets|the biggest program|programs loaded off the disk'

lauf "10. Handles statt Umgebungsautoritaet: die Capability-Schicht aus OrientOS (tools/caps/run.sh)" \
     tools/caps/run.sh caps '^CAPS: |^        \(\.utext'

lauf "11. der Multiboot-Kopf verlangt einen Bildschirm -- der UEFI-Pfad (tools/boot/run.sh)" \
     tools/boot/run.sh boot '^BOOT: '

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
