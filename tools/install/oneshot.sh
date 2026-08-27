#!/usr/bin/env bash
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
OUT=${OUT:-/tmp/install}
NAME=${1:-w}
WIE=${2:-iso}
SKRIPT=${3:-}
LIMIT=${4:-240}
MEM=${MEM:-512}

CRC=$(cat "$OUT/quelle.crc")
BASIS="osum vfs nokbd nosched noproc nofs noring3"

# NUR EIN QEMU AUF DIESER PLATTE. Zwei Maschinen auf derselben
# Abbilddatei schreiben sich gegenseitig die Sektoren um -- und der
# Fehler sieht danach aus wie ein Fehler im Treiber. Genau das ist
# waehrend dieser Runde einmal passiert und hat eine Stunde gekostet.
while pgrep -f "file=$OUT/ziel.img" > /dev/null; do sleep 1; done

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
    [ -n "$SKRIPT" ] && ZEILE="$ZEILE script=$SKRIPT"
    timeout "$LIMIT" qemu-system-x86_64 -machine pc -cpu max -m "$MEM" \
        -kernel "$OUT/k.mb" -append "$ZEILE" \
        -serial "file:$OUT/$NAME.txt" -display none -no-reboot \
        -drive "file=$OUT/ziel.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
    rc=$?
elif [ "$WIE" = iso ]; then
    ZEILE="$BASIS modfs modcrc=$CRC"
    [ -n "$SKRIPT" ] && ZEILE="$ZEILE script=$SKRIPT"
    timeout "$LIMIT" qemu-system-x86_64 -machine pc -cpu max -m "$MEM" \
        -kernel "$OUT/k.mb" -initrd "$OUT/quelle.img" -append "$ZEILE" \
        -serial "file:$OUT/$NAME.txt" -display none -no-reboot \
        -drive "file=$OUT/ziel.img,format=raw,if=ide,index=0" \
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
            if [ -n "$SKRIPT" ]; then
                echo "    cmdline: osum vfs nokbd nosched noproc nofs noring3 script=$SKRIPT"
            else
                echo "    cmdline: osum vfs nokbd nosched noproc nofs noring3"
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
    ARGS=(-machine pc -cpu max -m "$MEM" -display none -no-reboot
          -drive "if=pflash,format=raw,unit=0,readonly=on,file=$OVMF"
          -serial "file:$OUT/$NAME.txt"
          -drive "file=$OUT/ziel.img,format=raw,if=ide,index=0"
          -device isa-debug-exit,iobase=0xf4,iosize=0x04)
    [ -f "$VARS" ] && ARGS+=(-drive "if=pflash,format=raw,unit=1,file=$VARS")
    timeout "$LIMIT" qemu-system-x86_64 "${ARGS[@]}" > /dev/null 2>&1
    rc=$?
fi
echo "$rc" > "$OUT/$NAME.rc"
echo "rc=$rc  $(wc -c < "$OUT/$NAME.txt") Oktette seriell"
exit 0
