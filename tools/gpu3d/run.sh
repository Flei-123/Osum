#!/usr/bin/env bash
#
# ===================================================================
# WAS GEBAUT WURDE
# ===================================================================
#
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. tools/lib/qemu.sh >/dev/null 2>&1
pass=0; fail=0
ok()  { pass=$((pass+1)); echo "  ok   $1"; }
bad() { fail=$((fail+1)); echo "  FEHL $1"; }

TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT

PAKETE=${GPU3D_PAKETE:-2000}

echo "== 1. the kernel and the memory map =="
if python3 tools/kernel/memmap.py kernel > "$TMPD/map.txt" 2>&1; then
    if grep -q "0 collisions" "$TMPD/map.txt"; then
        ok "Speicherkarte: $(tail -1 "$TMPD/map.txt")"
    else
        bad "Speicherkarte meldet Kollisionen"; tail -3 "$TMPD/map.txt"
    fi
else
    bad "memmap.py lief nicht"
fi

K=${GPU3D_KERNEL:-$TMPD/k.mb}
if [ -z "${GPU3D_KERNEL:-}" ]; then
    if bash tools/build-kernel.sh "$K" >"$TMPD/build.log" 2>&1; then
        ok "der Kern baut ($(stat -c%s "$K") Oktette)"
    else
        bad "Bau fehlgeschlagen"; tail -20 "$TMPD/build.log"; exit 1
    fi
else
    ok "Kern vorgegeben: $K"
fi

echo
echo "== 2. was dieser Wirt hergibt (ERNEUT GEFAHREN) =="
GL=$(qemu-system-x86_64 -device virtio-gpu-gl-pci -display none -m 64 2>&1 | head -1)
case "$GL" in
    *"opengl is not available"*)
        ok "virtio-gpu-gl: '$GL' -- kein VIRGL auf diesem Wirt" ;;
    *)
        echo "  HINWEIS virtio-gpu-gl meldet: $GL"
        echo "          This host can do more than the one it was built on."
        ok "virtio-gpu-gl abgefragt" ;;
esac
if [ -e /dev/dri ]; then
    echo "  HINWEIS /dev/dri existiert hier"
else
    ok "/dev/dri missing -- no render node, so no VIRGL"
fi
ok "Behaelter: $(systemd-detect-virt 2>/dev/null || echo unbekannt)"

python3 tools/osum/mkfs.py build "$TMPD/disk.img" 4096 /lib/ \
    /lib/mono.ttf=assets/osum-mono.ttf /lib/sans.ttf=assets/osum-sans.ttf \
    > "$TMPD/mkfs.txt" 2>&1 \
    && ok "image with the fonts built" \
    || { bad "mkfs fehlgeschlagen"; cat "$TMPD/mkfs.txt"; }

GRUND="nokbd noproc nofs"

lauf() { # name zusatz qemu-geraete...
    local name=$1; shift
    local extra=$1; shift
    cp -f "$TMPD/disk.img" "$TMPD/live-$name.img"
    timeout 240 $QEMU_X86 -kernel "$K" -m 256 \
        -append "gfx wm wig desk wmhold wiglong vsync mauslauf=$PAKETE wighalt=14 $GRUND $extra" \
        -serial "file:$TMPD/$name.txt" -display none -no-reboot \
        -global VGA.edid=off \
        -trace "virtio_gpu_*" -D "$TMPD/trace-$name.txt" \
        "$@" \
        -drive "file=$TMPD/live-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1
}

zahl() { grep -a "^$2" "$1" 2>/dev/null | tail -1; }
feld() { echo "$1" | grep -oE "$2=[0-9]+" | tail -1 | cut -d= -f2; }
wirt() { grep -c "$2" "$TMPD/trace-$1.txt" 2>/dev/null | head -1; }

echo
echo "== 3. the measurement: $PAKETE cursor packets, 800x600 =="
lauf hw "" -vga std -device virtio-gpu-pci,id=vg
lauf sw "nohwcur" -vga std -device virtio-gpu-pci,id=vg

HWG=$(zahl "$TMPD/hw.txt" "gpu:");  HWM=$(zahl "$TMPD/hw.txt" "mauslauf:")
SWG=$(zahl "$TMPD/sw.txt" "gpu:");  SWM=$(zahl "$TMPD/sw.txt" "mauslauf:")

HW_B=$(feld "$HWG" bilder); HW_O=$(feld "$HWG" okt); HW_US=$(feld "$HWM" us)
SW_B=$(feld "$SWG" bilder); SW_O=$(feld "$SWG" okt); SW_US=$(feld "$SWM" us)
HW_P=$(feld "$HWM" pakete); SW_P=$(feld "$SWM" pakete)
HW_CE=$(feld "$HWM" curerr)
HW_HW=$(feld "$HWM" hw); SW_HW=$(feld "$SWM" hw)
HW_UC=$(wirt hw virtio_gpu_update_cursor)
SW_UC=$(wirt sw virtio_gpu_update_cursor)

echo "  with hardware cursor: $HWG"
echo "                        $HWM"
echo "  without (nohwcur)   : $SWG"
echo "                        $SWM"
echo "  beim WIRT angekommen: update_cursor  hw=$HW_UC  sw=$SW_UC"

[ "${HW_P:-0}" = "$PAKETE" ] && [ "${SW_P:-0}" = "$PAKETE" ] \
    && ok "beide Laeufe haben GENAU $PAKETE Pakete geschickt" \
    || bad "the packet count is wrong ($HW_P / $SW_P instead of $PAKETE)"

[ "${HW_HW:-0}" = "1" ] && ok "in the hardware run the device carries the cursor (hw=1)" \
    || bad "hw=1 is missing in the hardware run"
[ "${SW_HW:-1}" = "0" ] && ok "with nohwcur the kernel carries it (hw=0)" \
    || bad "nohwcur did not switch off"

[ "${SW_UC:-1}" = "0" ] \
    && ok "CONTROL: without the path NO cursor command reaches the host (0)" \
    || bad "GEGENPROBE gescheitert: nohwcur schickte $SW_UC Zeigerbefehle"
[ "${HW_UC:-0}" -gt 0 ] \
    && ok "with the path $HW_UC cursor commands reach the host" \
    || bad "the host saw NO cursor command"
[ "${HW_CE:-1}" = "0" ] && ok "no cursor command failed (curerr=0)" \
    || bad "curerr=$HW_CE"

if [ -n "${HW_B:-}" ] && [ -n "${SW_B:-}" ] && [ "${HW_B:-0}" -gt 0 ]; then
    FAKT=$(( SW_B / HW_B ))
    if [ "$SW_B" -gt "$HW_B" ]; then
        ok "Frames: $SW_B without -> $HW_B with  (${FAKT}x fewer)"
    else
        bad "the hardware cursor did NOT reduce the frames ($SW_B -> $HW_B)"
    fi
fi
if [ -n "${HW_O:-}" ] && [ -n "${SW_O:-}" ] && [ "${HW_O:-0}" -gt 0 ]; then
    if [ "$SW_O" -gt "$HW_O" ]; then
        ok "Bytes: $SW_O without -> $HW_O with"
    else
        bad "Oktette nicht gesunken ($SW_O -> $HW_O)"
    fi
fi
if [ -n "${HW_US:-}" ] && [ -n "${SW_US:-}" ] && [ "${HW_US:-0}" -gt 0 ]; then
    echo "  Time for $PAKETE packets: $SW_US us without -> $HW_US us with"
    if [ "$SW_US" -gt "$HW_US" ]; then
        ok "the hardware cursor is faster"
    else
        echo "  NOTE the time depends on load on this host;"
        echo "          frames and bytes are the hard numbers."
    fi
fi

echo
echo "== 4. der Bildbeleg =="
foto() { # name extra
    local name=$1; shift
    local extra=$1; shift
    local S="$TMPD/mon-$name.sock"
    rm -f "$S"
    cp -f "$TMPD/disk.img" "$TMPD/shot-$name.img"
    timeout 240 $QEMU_X86 -kernel "$K" -m 256 \
        -append "gfx wm wig desk wmhold wiglong vsync mauslauf=600 wighalt=18 $GRUND $extra" \
        -serial "file:$TMPD/f-$name.txt" -display none -no-reboot \
        -vga std -device virtio-gpu-pci,id=vg -global VGA.edid=off \
        -monitor "unix:$S,server,nowait" \
        -drive "file=$TMPD/shot-$name.img,format=raw,if=ide,index=0" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 >/dev/null 2>&1 &
    local pid=$!
    local i=0
    while [ $i -lt 900 ]; do
        grep -qa 'wm: hold' "$TMPD/f-$name.txt" 2>/dev/null && break
        kill -0 $pid 2>/dev/null || break
        sleep 0.15; i=$((i+1))
    done
    sleep 3
    python3 tools/vgpu/schuss.py "$S" "$TMPD/$name.ppm" 25 vg >/dev/null 2>&1
    wait $pid 2>/dev/null
}
foto bhw ""
foto bsw "nohwcur"

if [ -s "$TMPD/bhw.ppm" ] && [ -s "$TMPD/bsw.ppm" ]; then
    python3 tools/gpu3d/zeigerpruef.py "$TMPD/bhw.ppm" "$TMPD/bsw.ppm" \
        > "$TMPD/bild.txt" 2>&1
    rc=$?
    sed 's/^/     /' "$TMPD/bild.txt"
    if [ $rc -eq 0 ]; then
        ok "der Bildbeleg stimmt"
    else
        bad "the image evidence is WRONG"
    fi
    mkdir -p /tmp/gpu3d-bilder
    cp -f "$TMPD/bhw.ppm" "$TMPD/bsw.ppm" /tmp/gpu3d-bilder/ 2>/dev/null
    echo "     (the photos are in /tmp/gpu3d-bilder/)"
else
    bad "no photo was produced"
fi

echo
echo "== 5. der saubere Rueckfall =="
lauf rf1 "novgpu" -vga std -device virtio-gpu-pci,id=vg
lauf rf2 "" -vga std
for n in rf1 rf2; do
    m=$(zahl "$TMPD/$n.txt" "mauslauf:")
    p=$(feld "$m" pakete); h=$(feld "$m" hw)
    if grep -qa 'panic' "$TMPD/$n.txt"; then
        bad "$n: the kernel stopped"
    elif [ "${p:-0}" = "$PAKETE" ] && [ "${h:-1}" = "0" ]; then
        ok "$n: keeps running cleanly without the path ($m)"
    else
        bad "$n: unerwartet ($m)"
    fi
done

echo
echo "-------------------------------------------------------------"
echo "  $pass Zusagen gehalten, $fail gebrochen"
if [ $fail -eq 0 ]; then
    echo "  GPU3D-ABNAHME PASSED."
    exit 0
fi
echo "  GPU3D-ABNAHME FEHLGESCHLAGEN."
exit 1
