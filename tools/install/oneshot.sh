#!/usr/bin/env bash
. "$(dirname "${BASH_SOURCE[0]}")/../lib/marke-env.sh"
#
#   bash tools/install/oneshot.sh <name> <wie> "<skript>" [zeitlimit]
#
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

#     OTA_NETZ="nic nip=10.0.2.15/24 ngw=10.0.2.2 nsvc=0 nwait=0"
#
CPU=${OSUM_CPU:-max}
NETZ=${OTA_NETZ:-}
# $OSUM_RTC = QEMU's -rtc argument (e.g. "base=2026-10-11T11:00:00,clock=vm"):
# the hardware clock the guest finds at boot (r544 clock tests)
RTCARGS=()
[ -n "${OSUM_RTC:-}" ] && RTCARGS=(-rtc "$OSUM_RTC")
NETARGS=()
if [ -n "$NETZ" ]; then
    NETARGS=(-netdev "user,id=otan0"
             -device "${OTA_NIC:-e1000},netdev=otan0,mac=52:54:00:0a:0b:0c")
fi

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
    ROHDISK=(-drive "file=$OUT/ziel.img,format=raw,if=ide,index=0")
    if [ "${OTA_DRIVE:-ide}" = ahci ]; then
        ROHDISK=(-device ich9-ahci,id=ahci0 -drive "if=none,id=hd0,file=$OUT/ziel.img,format=raw"
                 -device ide-hd,drive=hd0,bus=ahci0.0)
    fi
    ZEILE="$BASIS"
    [ -n "${OSUM_EXTRA:-}" ] && ZEILE="$ZEILE $OSUM_EXTRA"
    [ -n "$NETZ" ] && ZEILE="$ZEILE $NETZ"
    [ -n "$SKRIPT" ] && ZEILE="$ZEILE script=$SKRIPT"
    timeout "$LIMIT" $QEMU_X86 -machine pc -cpu "$CPU" -m "$MEM" -smp "${OSUM_SMP:-1}" \
        -kernel "$OUT/k.mb" -append "$ZEILE" \
        -serial "file:$OUT/$NAME.txt" -display none -no-reboot "${RTCARGS[@]}" \
        "${ROHDISK[@]}" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
    rc=$?
elif [ "$WIE" = iso ]; then
    ZEILE="$BASIS modfs modcrc=$CRC"
    [ -n "${OSUM_EXTRA:-}" ] && ZEILE="$ZEILE $OSUM_EXTRA"
    [ -n "$NETZ" ] && ZEILE="$ZEILE $NETZ"
    [ -n "$SKRIPT" ] && ZEILE="$ZEILE script=$SKRIPT"
    timeout "$LIMIT" $QEMU_X86 -machine pc -cpu "$CPU" -m "$MEM" -smp "${OSUM_SMP:-1}" \
        -kernel "$OUT/k.mb" -initrd "$OUT/quelle.img" -append "$ZEILE" \
        -serial "file:$OUT/$NAME.txt" -display none -no-reboot "${RTCARGS[@]}" \
        -drive "file=$OUT/ziel.img,format=raw,if=ide,index=0" \
        "${ZWEITE[@]}" "${NETARGS[@]}" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 > /dev/null 2>&1
    rc=$?
else
    {
        :
    }
    # ESP_KEEP=1: the caller already wrote /limine.conf on the ESP (tools/abkern)
    if [ -z "${ESP_KEEP:-}" ]; then
        {
            echo "timeout: 0"
            echo "verbose: yes"
            echo
            echo "/${MARKE_PRODUKT}"
            echo "    protocol: multiboot1"
            echo "    path: boot():/osum.mb"
            ZL="osum vfs nokbd nosched noproc nofs noring3"
            [ -n "$NETZ" ] && ZL="$ZL $NETZ"
            # `initsh` is what runs the script on an image whose inittab has
            # no console target (every fUi image): without it init goes to
            # the graphical target and `script=` is never read.
            [ -n "$SKRIPT" ] && ZL="$ZL initsh"
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
    if [ "${OTA_DRIVE:-ide}" = ahci ]; then
        DISKARGS=(-device ich9-ahci,id=ahci0 -drive "if=none,id=hd0,file=$OUT/ziel.img,format=raw"
                  -device ide-hd,drive=hd0,bus=ahci0.0)
    else
        DISKARGS=(-drive "file=$OUT/ziel.img,format=raw,if=ide,index=0")
    fi
    ARGS=(-machine pc -cpu "$CPU" -m "$MEM" -display none -no-reboot "${RTCARGS[@]}"
          -drive "if=pflash,format=raw,unit=0,readonly=on,file=$OVMF"
          -serial "file:$OUT/$NAME.txt"
          "${DISKARGS[@]}"
          "${ZWEITE[@]}" "${NETARGS[@]}"
          -device isa-debug-exit,iobase=0xf4,iosize=0x04)
    [ -f "$VARS" ] && ARGS+=(-drive "if=pflash,format=raw,unit=1,file=$VARS")
    timeout "$LIMIT" $QEMU_X86 "${ARGS[@]}" > /dev/null 2>&1
    rc=$?
fi
echo "$rc" > "$OUT/$NAME.rc"
echo "rc=$rc  $(wc -c < "$OUT/$NAME.txt") Oktette seriell"
exit 0
