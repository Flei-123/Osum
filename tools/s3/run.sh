#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/s3/run.sh -- K-004: THE REAL STANDBY (ACPI S3), MEASURED.
#
# The machine goes to sleep with RAM powered, the QEMU monitor reports
# "paused (suspended)", `system_wakeup` wakes it, the firmware jumps to
# the wake-up blob (end of kernel/arch/x86_64/smp.s) and the kernel
# continues from `s3_save` in kernel/pwr/s3.fi.
#
# WHY THE KERNEL BOOTS FROM A DISK HERE AND NOT WITH `-kernel`: QEMU keeps
# an ELF given with `-kernel` as a ROM blob and copies it back into RAM on
# EVERY system reset -- and an S3 wake-up IS a system reset. The first
# measurement (24.09.2026) found the page tables in .bss zeroed after the
# wake-up and the blob faulting at 0x8078 right after CR0.PG. No real
# firmware does that; Limine on a small disk does not either. So the
# runner builds a 48 MiB disk with Limine (BIOS) and the kernel on it.
#
# SECTIONS:
#   1. build: the kernel, and no LOAD segment below 1 MiB (the second trap:
#      a segment at 0xFF000 overwrites the BIOS shadow and the firmware's
#      own resume path jumps into zeros).
#   2. one cycle: suspended, woke, every restore at 0 differences, RAM
#      pattern equal, the kernel reaches its end.
#   3. two cycles in a row.
#   4. with the scheduler: the timer delivers again after the wake-up.
#   5. counter-check `s3kaputt`: the blob's first byte is `hlt`. The
#      machine sleeps the same way and must NOT come back.
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh

LIMINE=${LIMINE_DIR:-/root/jarvis/projects/u_DiS4in7esMF1/orientos/vendor/limine}
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

pass=0
fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
num() { local name=$1 value=$2 op=$3 want=$4
    if [ -z "$value" ]; then bad "$name: keine Zahl gefunden (erwartet $op $want)"; return; fi
    if [ "$value" -"$op" "$want" ] 2>/dev/null; then ok "$name: $value"
    else bad "$name: $value, erwartet $op $want"; fi
}
has() { grep -qaF "$2" "$1" && ok "$3" || bad "$3 -- '$2' fehlt"; }
hasnot() { grep -qaF "$2" "$1" && bad "$3 -- '$2' sollte nicht dastehen" || ok "$3"; }
# val log linepattern key [nth]
val() { tr -d '\r' < "$1" | grep -a "$2" | sed -n "${4:-1}p" | grep -oE " $3=[0-9a-fx]+" | head -1 | sed 's/.*=//'; }

for w in qemu-system-x86_64 sgdisk mkfs.vfat mcopy socat readelf; do
    command -v "$w" >/dev/null 2>&1 || { echo "S3: uebersprungen, $w fehlt"; exit 0; }
done
[ -x "$LIMINE/limine" ] && [ -f "$LIMINE/limine-bios.sys" ] \
    || { echo "S3: uebersprungen, Limine fehlt ($LIMINE)"; exit 0; }

# ------------------------------------------------------------ helpers
mkimg() { # kernel img cmdline
    local t="$TMPD/esp.img"
    printf 'timeout: 0\ndefault_entry: 1\n/s3\n    protocol: multiboot1\n    path: boot():/osum.mb\n    cmdline: %s\n' "$3" > "$TMPD/limine.conf"
    rm -f "$2" "$t"
    dd if=/dev/zero of="$2" bs=1M count=0 seek=48 status=none
    sgdisk --clear --new=1:2048:+40M --typecode=1:EF00 "$2" >/dev/null 2>&1 || return 1
    dd if=/dev/zero of="$t" bs=1M count=40 status=none
    mkfs.vfat -F 32 "$t" >/dev/null 2>&1 || return 1
    mcopy -i "$t" "$LIMINE/limine-bios.sys" ::/limine-bios.sys || return 1
    mcopy -i "$t" "$TMPD/limine.conf" ::/limine.conf || return 1
    mcopy -i "$t" "$1" ::/osum.mb || return 1
    dd if="$t" of="$2" bs=512 seek=2048 conv=notrunc status=none
    rm -f "$t"
    "$LIMINE/limine" bios-install "$2" >/dev/null 2>&1
}

# lauf img log cycles wake(1|0) -- sets RC, STATUS1, STATUS2, AFTER
lauf() {
    local img=$1 log=$2 cycles=$3 wake=$4 sock="$TMPD/mon.$RANDOM"
    STATUS1=""; STATUS2=""; AFTER=""
    rm -f "$log"
    timeout 120 $QEMU_X86 -m 256 -drive "file=$img,format=raw,if=ide" \
        -serial "file:$log" -display none -no-reboot -vga std \
        -monitor "unix:$sock,server,nowait" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    local pid=$! c i st n
    for c in $(seq 1 "$cycles"); do
        # wait for the marker the machine printed itself, not the host's clock
        for i in $(seq 1 450); do
            n=$(grep -ac 's3: schlafe' "$log" 2>/dev/null)
            [ "${n:-0}" -ge "$c" ] && break
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.2
        done
        sleep 1
        st=$(echo 'info status' | socat - "UNIX-CONNECT:$sock" 2>/dev/null \
             | tr -d '\r' | grep -ao 'VM status: .*' | head -1)
        if [ "$c" = 1 ]; then STATUS1=$st; else STATUS2=$st; fi
        case $st in *suspended*) ;; *) break ;; esac
        echo system_wakeup | socat - "UNIX-CONNECT:$sock" >/dev/null 2>&1
        if [ "$wake" = 0 ]; then
            sleep 8
            AFTER=$(echo 'info status' | socat - "UNIX-CONNECT:$sock" 2>/dev/null \
                    | tr -d '\r' | grep -ao 'VM status: .*' | head -1)
            echo quit | socat - "UNIX-CONNECT:$sock" >/dev/null 2>&1
            break
        fi
    done
    wait "$pid"; RC=$?
    rm -f "$sock"
}

# ------------------------------------------------------------ 1. build
echo "== 1. der Kern, und kein Ladesegment unter 1 MiB =="
bash tools/build-kernel.sh "$TMPD/k" > "$TMPD/b.txt" 2>&1 \
    && ok "Kern gebaut ($(stat -c%s "$TMPD/k") Oktette)" \
    || { bad "Kernbau"; tail -8 "$TMPD/b.txt" | sed 's/^/        /'; }
LOW=0
for a in $(readelf -lW "$TMPD/k.elf" 2>/dev/null | awk '$1=="LOAD" {print $3}'); do
    [ $((a)) -lt $((0x100000)) ] && LOW=$((LOW+1))
done
num "Ladesegmente unter 1 MiB (die ueberschrieben den BIOS-Schatten)" "$LOW" eq 0
n=0
for m in eins:s3 zwei:s3zwei kaputt:s3kaputt; do
    mkimg "$TMPD/k" "$TMPD/${m%%:*}.img" "${m#*:} nokbd nosched noproc nofs noring3" \
        && n=$((n+1))
done
mkimg "$TMPD/k" "$TMPD/sched.img" "s3 nokbd noproc nofs noring3" && n=$((n+1))
num "Platten mit Limine (BIOS) und dem Kern" "$n" eq 4

# ------------------------------------------------------------ 2. one cycle
echo "== 2. ein Zyklus: schlafen, geweckt werden, alles wieder da =="
L="$TMPD/l-eins.txt"
lauf "$TMPD/eins.img" "$L" 1 1
has "$L" "s3: fadt=" "die Werte stehen da (_S3 aus dem AML, FACS, PM1a)"
case $STATUS1 in *suspended*) ok "QEMU meldet die Maschine als SCHLAFEND ($STATUS1)";;
    *) bad "QEMU-Zustand beim Schlafen: '$STATUS1'";; esac
has "$L" "s3: wach zyklus=1 woke=1 stufe=4" "zurueck: der Aufwachcode lief bis zum Ende (Stufe 4), genau einmal"
num "Rueckgabe" "$RC" eq 21
has "$L" "kernel: done" "der Kern laeuft nach dem Aufwachen bis zu seinem Ende weiter"
num "APIC: gesicherte Leitungen" "$(val "$L" 's3: apic' leitungen)" ge 1
num "APIC: danach abweichend" "$(val "$L" 's3: apic' danach-falsch)" eq 0
num "PCI: gesicherte Geraete" "$(val "$L" 's3: pci' geraete)" ge 1
num "PCI: Register, die der Schlaf geloescht hatte" "$(val "$L" 's3: pci' verloren)" ge 1
num "PCI: danach abweichend" "$(val "$L" 's3: pci' danach-falsch)" eq 0
SV=$(val "$L" 's3: sci' vor); SN=$(val "$L" 's3: sci' nach)
if [ -n "$SV" ] && [ "$SV" = "$SN" ]; then ok "ACPI-Modus (SCI_EN) wie vorher: $SN"
else bad "SCI_EN vor=$SV nach=$SN"; fi
num "Arbeitsspeicher: Muster gleich" "$(val "$L" 's3: speicher' gleich)" eq 1
S1=$(val "$L" 's3: speicher' sum); V1=$(val "$L" 's3: speicher' vor)
if [ -n "$S1" ] && [ "$S1" = "$V1" ] && [ "$S1" != "0x0" ]; then
    ok "Pruefsumme vorher = nachher und nicht null ($S1)"
else bad "Pruefsumme $V1 -> $S1"; fi

# ------------------------------------------------------------ 3. two cycles
echo "== 3. zwei Zyklen hintereinander ($OSUM_QEMU_ACCEL) =="
L="$TMPD/l-zwei.txt"
lauf "$TMPD/zwei.img" "$L" 2 1
case $STATUS2 in *suspended*) ok "auch der zweite Schlaf ist echt ($STATUS2)";;
    *) bad "zweiter Schlaf: '$STATUS2'";; esac
has "$L" "s3: wach zyklus=2 woke=1 stufe=4" "zweimal zurueck"
num "Rueckgabe" "$RC" eq 21
A=$(val "$L" 's3: speicher' sum 1); B=$(val "$L" 's3: speicher' sum 2)
if [ -n "$A" ] && [ -n "$B" ] && [ "$A" != "$B" ]; then
    ok "zwei verschiedene Muster, beide gehalten ($A / $B)"
else bad "Muster $A / $B"; fi
num "Zyklus 2: PCI danach abweichend" "$(val "$L" 's3: pci' danach-falsch 2)" eq 0

# ------------------------------------------------------------ 4. scheduler
echo "== 4. mit Zeitgeber und Scheduler: die Unterbrechungen kommen wieder =="
L="$TMPD/l-sched.txt"
lauf "$TMPD/sched.img" "$L" 1 1
has "$L" "s3: wach zyklus=1 woke=1 stufe=4" "zurueck, mit laufendem Scheduler davor"
num "Zeitgeber-Takte in 200 ms nach dem Aufwachen (100 Hz)" "$(val "$L" 's3: ticks' ms)" ge 10
num "Rueckgabe" "$RC" eq 21

# ------------------------------------------------------------ 5. counter-check
echo "== 5. Gegenprobe: vergifteter Aufwachcode -- die Maschine darf NICHT zurueckkommen =="
L="$TMPD/l-kaputt.txt"
lauf "$TMPD/kaputt.img" "$L" 1 0
case $STATUS1 in *suspended*) ok "sie schlaeft genauso ($STATUS1)";;
    *) bad "Gegenprobe schlief nicht: '$STATUS1'";; esac
hasnot "$L" "s3: wach" "und kommt NICHT zurueck -- der Rueckweg ist dieser Code und kein anderer"
case $AFTER in *running*) ok "die Firmware hat geweckt, der Kern steht ($AFTER)";;
    *) bad "nach dem Wecken: '$AFTER'";; esac
hasnot "$L" "kernel: done" "kein Ende des Kerns"

echo
echo "S3: $pass bestanden, $fail gefallen"
[ "$fail" -eq 0 ]
