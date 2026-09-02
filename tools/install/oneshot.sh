#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/install/oneshot.sh -- EINEN Lauf machen, zum Iterieren.
#
#   bash tools/install/oneshot.sh <name> <wie> "<skript>" [zeitlimit]
#
# <wie> ist eines von
#
#   iso     wie das Produkt-ISO: der Kern bekommt das Wurzeldateisystem
#           als MULTIBOOT-MODUL (`-initrd`, genau der Weg, den Limine
#           benutzt), die Zielplatte haengt als /dev/hda daran. Das ist
#           die Lage, in der `/bin/install` laeuft.
#   platte  OHNE Modul und OHNE ISO: nur die Platte, gestartet ueber
#           OVMF, also ueber die EFI-Partition, die der Installer
#           beschrieben hat. Das ist der Nachweis dieser Runde.
#
# Legt unter $OUT ab: <name>.txt (die serielle Leitung) und den
# Beendigungscode in <name>.rc.
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/lib/qemu.sh          # $QEMU_X86, $OSUM_QEMU_ACCEL
OUT=${OUT:-/tmp/install}
NAME=${1:-w}
WIE=${2:-iso}
SKRIPT=${3:-}
LIMIT=${4:-240}
MEM=${MEM:-512}

CRC=$(cat "$OUT/quelle.crc")
BASIS="osum vfs nokbd nosched noproc nofs noring3"

# RUNDE OTA: DAS NETZ, WENN EIN LAUF EINES BRAUCHT.
#
# $OTA_NETZ traegt die Woerter, die der Kern fuer die Karte braucht --
# ueblich ist
#
#     OTA_NETZ="nic nip=10.0.2.15/24 ngw=10.0.2.2 nsvc=0 nwait=0"
#
# und dann haengt hier eine e1000 an QEMUs BENUTZERNETZ (`-netdev user`).
# Das ist absichtlich NICHT die Verdrahtung aus Runde HWNET (veth-Paar,
# Netzwerknamensraum, `tools/net/bridge.c`): die braucht Wurzelrechte und
# vertraegt keine zwei Laeufe nebeneinander. Das Benutzernetz braucht
# nichts davon, und die eine Adresse, auf die es ankommt, gibt es dort
# umsonst -- 10.0.2.2 ist der Wirt. Ein HTTPS-Dienst auf 127.0.0.1 des
# Wirts ist damit vom Gast aus unter 10.0.2.2 zu erreichen, und genau so
# wird in dieser Runde gegen die Gegenstelle gemessen.
#
# WAS DAMIT NICHT GEMESSEN IST: Runde HWNET hat den Stapel gegen den
# LINUX-KERN gemessen, ueber eine Leitung mit echten Rahmen. Das
# Benutzernetz ist ein Nachbau in QEMU. Was hier gemessen wird, ist der
# Update-Weg -- nicht der Treiber; der ist dort gemessen.
# RUNDE OTA: WELCHER PROZESSOR. Vorgabe bleibt `max`, damit sich fuer
# jeden bestehenden Laeufer nichts aendert. $OSUM_CPU stellt ihn um, und
# der Update-Weg braucht das -- der Grund steht in `docs/OTA.md` unter
# "AVX2" und ist gemessen: Firns Bibliothek nimmt ihren AVX2-Weg, sobald
# CPUID ihn anbietet, und Osum schaltet fuer Ring 3 kein XSAVE/XCR0 frei.
# Unter `-cpu max` stirbt `/bin/fetch` deshalb mit #UD, unter
# `-cpu SandyBridge` (SSE4.2, AES-NI, AVX -- aber kein AVX2) laeuft es.
CPU=${OSUM_CPU:-max}
NETZ=${OTA_NETZ:-}
NETARGS=()
if [ -n "$NETZ" ]; then
    NETARGS=(-netdev "user,id=otan0"
             -device "${OTA_NIC:-e1000},netdev=otan0,mac=52:54:00:0a:0b:0c")
fi

# NUR EIN QEMU AUF DIESER PLATTE. Zwei Maschinen auf derselben
# Abbilddatei schreiben sich gegenseitig die Sektoren um -- und der
# Fehler sieht danach aus wie ein Fehler im Treiber. Genau das ist
# waehrend dieser Runde einmal passiert und hat eine Stunde gekostet.
while pgrep -f "file=$OUT/ziel.img" > /dev/null; do sleep 1; done

# A SECOND MEDIUM, if the caller asked for one. `ZWEITE_PLATTE` is the
# path of a raw image; it becomes the ATA slave, which the kernel calls
# /dev/hdb. This is how a run can back up onto something that is not the
# disk it is running from -- a backup on the same disk is not a backup.
ZWEITE=()
if [ -n "${ZWEITE_PLATTE:-}" ]; then
    ZWEITE=(-drive "file=$ZWEITE_PLATTE,format=raw,if=ide,index=1")
fi

rm -f "$OUT/$NAME.txt"
: > "$OUT/$NAME.txt"

if [ "$WIE" = roh ]; then
    # OHNE MODUL UND OHNE FIRMWARE. Der Kern kommt ueber `-kernel`, die
    # Wurzel MUSS er auf der Platte suchen -- und niemand ausser ihm
    # sieht die Partitionstafel an. Das ist der Weg fuer die Gegenprobe
    # zur GPT-Pruefsumme: OVMF REPARIERT einen kaputten primaeren
    # GPT-Kopf aus der Sicherung, bevor irgendein Betriebssystem ihn zu
    # Gesicht bekommt (gemessen in dieser Runde), und dann prueft man
    # nicht mehr den Kern, sondern die Firmware.
    ZEILE="$BASIS"
    [ -n "$NETZ" ] && ZEILE="$ZEILE $NETZ"
    [ -n "$SKRIPT" ] && ZEILE="$ZEILE script=$SKRIPT"
    timeout "$LIMIT" $QEMU_X86 -machine pc -cpu "$CPU" -m "$MEM" \
        -kernel "$OUT/k.mb" -append "$ZEILE" \
        -serial "file:$OUT/$NAME.txt" -display none -no-reboot \
        -drive "file=$OUT/ziel.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
    rc=$?
elif [ "$WIE" = iso ]; then
    ZEILE="$BASIS modfs modcrc=$CRC"
    [ -n "$NETZ" ] && ZEILE="$ZEILE $NETZ"
    [ -n "$SKRIPT" ] && ZEILE="$ZEILE script=$SKRIPT"
    timeout "$LIMIT" $QEMU_X86 -machine pc -cpu "$CPU" -m "$MEM" \
        -kernel "$OUT/k.mb" -initrd "$OUT/quelle.img" -append "$ZEILE" \
        -serial "file:$OUT/$NAME.txt" -display none -no-reboot \
        -drive "file=$OUT/ziel.img,format=raw,if=ide,index=0" \
        "${ZWEITE[@]}" "${NETARGS[@]}" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
    rc=$?
else
    # DIE KOMMANDOZEILE STEHT AUF DER PLATTE, und wenn dieser Lauf eine
    # andere braucht, wird sie DORT geaendert -- mit `mcopy` vom Wirt in
    # die EFI-Partition, so wie ein Mensch es mit einem Editor taete.
    # Ein `-append` waere geschummelt: dann haette der Wirt dem Kern
    # gesagt, was er tun soll, und nicht die Platte.
    {
        # IMMER neu schreiben, auch ohne Skript. Sonst stuende beim
        # naechsten Lauf noch das Skript des vorigen auf der Platte --
        # und ein Testlauf, der das Skript des Vorgaengers ausfuehrt,
        # misst etwas anderes, als er behauptet.
        :
    }
    if true; then
        {
            echo "timeout: 0"
            echo "verbose: yes"
            echo
            echo "/OrientOS"
            echo "    protocol: multiboot1"
            echo "    path: boot():/osum.mb"
            ZL="osum vfs nokbd nosched noproc nofs noring3"
            [ -n "$NETZ" ] && ZL="$ZL $NETZ"
            if [ -n "$SKRIPT" ]; then
                echo "    cmdline: $ZL script=$SKRIPT"
            else
                echo "    cmdline: $ZL"
            fi
        } > "$OUT/$NAME.conf"
        mcopy -o -i "$OUT/ziel.img@@1048576" "$OUT/$NAME.conf" ::/limine.conf \
            || { echo "mcopy auf die EFI-Partition fehlgeschlagen" >&2; exit 2; }
    fi
    OVMF=$(ls /usr/share/OVMF/OVMF_CODE.fd /usr/share/ovmf/OVMF.fd 2>/dev/null | head -1)
    VARS="$OUT/$NAME.vars.fd"
    cp -f /usr/share/OVMF/OVMF_VARS.fd "$VARS" 2>/dev/null || true
    # Die Kommandozeile kommt hier NICHT von aussen: sie steht in der
    # limine.conf AUF DER PLATTE, die der Installer dorthin geschrieben
    # hat. Ein `-append` waere geschummelt -- dann haette der Wirt dem
    # Kern gesagt, was er tun soll, und nicht die Platte.
    ARGS=(-machine pc -cpu "$CPU" -m "$MEM" -display none -no-reboot
          -drive "if=pflash,format=raw,unit=0,readonly=on,file=$OVMF"
          -serial "file:$OUT/$NAME.txt"
          -drive "file=$OUT/ziel.img,format=raw,if=ide,index=0"
          "${ZWEITE[@]}" "${NETARGS[@]}"
          -device isa-debug-exit,iobase=0xf4,iosize=0x04)
    [ -f "$VARS" ] && ARGS+=(-drive "if=pflash,format=raw,unit=1,file=$VARS")
    timeout "$LIMIT" $QEMU_X86 "${ARGS[@]}" > /dev/null 2>&1
    rc=$?
fi
echo "$rc" > "$OUT/$NAME.rc"
echo "rc=$rc  $(wc -c < "$OUT/$NAME.txt") Oktette seriell"
exit 0
