#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/screen/boot.sh -- EIN Start, EIN Foto, EIN Mitschnitt.
#
#   bash tools/screen/boot.sh <name> <ausgabeverzeichnis> <sekunden> \
#        <bios|uefi|kernel> <xres> <yres> [weitere qemu-worte...]
#
# Der Laeufer der Runde SCHIRM braucht immer dasselbe: eine Maschine
# starten, warten, ein Bildschirmfoto ueber den QEMU-Monitor holen, den
# seriellen Mitschnitt behalten, abschiessen. Das steht hier EINMAL,
# damit die Zahlen aus verschiedenen Abschnitten vergleichbar sind.
#
#   bios    das USB-Abbild ueber den MBR-Weg (Limine bios-install)
#   uefi    dasselbe Abbild ueber OVMF und /EFI/BOOT/BOOTX64.EFI
#   kernel  qemu -kernel mit dem Multiboot-Abbild (kein Lader, VBE-Weg)
#
# $IMG    Pfad des USB-Abbilds (bios/uefi)
# $KERN   Pfad des Multiboot-Kerns (kernel)
# $APPEND Befehlszeile (nur kernel)
# $DISK   Plattenabbild (nur kernel)
# $VGAMEM Bildspeicher der Karte in MiB (Vorgabe 64)
# $MARKE  Stichwort im Mitschnitt, auf das gewartet wird
set -uo pipefail
cd "$(dirname "$0")/../.."

NAME=$1
OUT=$2
WAIT=$3
ART=$4
XRES=$5
YRES=$6
shift 6

mkdir -p "$OUT"
SOCK=$OUT/mon-$NAME.sock
SER=$OUT/$NAME.txt
PPM=$OUT/$NAME.ppm
rm -f "$SOCK" "$SER" "$PPM"

VGAMEM=${VGAMEM:-64}
ACCEL=(-accel kvm -cpu host)
[ -w /dev/kvm ] || ACCEL=(-accel tcg)

VGA=(-device "VGA,edid=on,xres=$XRES,yres=$YRES,vgamem_mb=$VGAMEM")
COMMON=(-m "${MEM:-1024}" -serial "file:$SER" -display none -no-reboot
        -monitor "unix:$SOCK,server,nowait" "${VGA[@]}")

case "$ART" in
    bios)
        qemu-system-x86_64 "${ACCEL[@]}" "${COMMON[@]}" \
            -drive "file=$IMG,format=raw,if=ide,index=0,snapshot=on" "$@" \
            > "$OUT/$NAME.qemu" 2>&1 &
        ;;
    uefi)
        cp -f /usr/share/OVMF/OVMF_VARS_4M.fd "$OUT/vars-$NAME.fd"
        qemu-system-x86_64 "${ACCEL[@]}" "${COMMON[@]}" \
            -drive "if=pflash,format=raw,unit=0,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd" \
            -drive "if=pflash,format=raw,unit=1,file=$OUT/vars-$NAME.fd" \
            -drive "file=$IMG,format=raw,if=ide,index=0,snapshot=on" "$@" \
            > "$OUT/$NAME.qemu" 2>&1 &
        ;;
    kernel)
        DRV=()
        [ -n "${DISK:-}" ] && DRV=(-drive "file=$DISK,format=raw,if=ide,index=0")
        qemu-system-x86_64 "${ACCEL[@]}" "${COMMON[@]}" \
            -kernel "$KERN" -append "${APPEND:-}" "${DRV[@]}" "$@" \
            > "$OUT/$NAME.qemu" 2>&1 &
        ;;
    *)
        echo "boot.sh: unbekannte Art '$ART'" >&2
        exit 2
        ;;
esac
PID=$!

# Warten: entweder bis das Stichwort im Mitschnitt steht ($MARKE) oder
# die Frist ab ist. Eine feste Frist allein macht die Messung von der
# Last des Wirts abhaengig.
i=0
N=$(python3 -c "print(int($WAIT*10))")
getroffen=0
while [ $i -lt "$N" ]; do
    if [ -n "${MARKE:-}" ] && grep -qa "$MARKE" "$SER" 2>/dev/null; then
        getroffen=1; break
    fi
    kill -0 "$PID" 2>/dev/null || break
    sleep 0.1
    i=$((i + 1))
done
[ "$getroffen" = 1 ] && sleep "${NACH:-1}"

python3 tools/gfx/screenshot.py "$SOCK" "$PPM" 20 > "$OUT/$NAME.shot" 2>&1
kill "$PID" 2>/dev/null
wait "$PID" 2>/dev/null
rm -f "$SOCK"
if [ -f "$PPM" ]; then
    head -2 "$PPM" | tr '\n' ' '
    echo " <- $PPM  (marke=$getroffen)"
else
    echo "KEIN FOTO fuer $NAME"
fi
exit 0
