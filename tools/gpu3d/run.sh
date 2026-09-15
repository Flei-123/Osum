#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/gpu3d/run.sh -- DIE ABNAHME DER RUNDE GPU (G-012).
#
# ===================================================================
# ZUERST: WAS DIESER WIRT HERGIBT -- UND WARUM DIE RUNDE 2D GEWORDEN IST
# ===================================================================
#
# Der Auftrag verlangte, VOR dem Bauen zu messen, ob VIRGL auf diesem
# Rechner ueberhaupt laeuft, und das Ergebnis aufzuschreiben. Es wurde
# gemessen, und es war ein klares NEIN -- aus mehreren voneinander
# unabhaengigen Gruenden:
#
#   qemu-system-x86_64 -device virtio-gpu-gl-pci
#       -> "opengl is not available"
#          (dieses QEMU 7.2.22 ist OHNE OpenGL gebaut; `-display help`
#           meldet zusaetzlich "module ui-ui-none not found")
#   qemu-system-x86_64 -display egl-headless
#       -> "egl: no drm render node available"
#   ls /dev/dri            -> existiert NICHT
#   systemd-detect-virt    -> lxc
#   ls /lib/modules/$(uname -r)/kernel/drivers/gpu/drm -> existiert NICHT
#   modprobe vgem          -> "Module vgem not found"
#
# libvirglrenderer.so.1 (0.10.4) IST installiert -- sie nuetzt nur
# nichts, solange QEMU kein OpenGL hat und es keinen Renderknoten gibt.
# In einem LXC-Behaelter ohne durchgereichte GPU laesst sich beides von
# innen nicht herstellen.
#
# Damit waere ein VIRGL-Pfad auf diesem Wirt NICHT EINMAL ZU STARTEN,
# also auch nicht zu messen -- und unueberpruefbare Arbeit ist nach der
# Regel dieses Baums nichts wert. Deshalb Punkt 4 des Auftrags: der
# 2D-Weg von virtio-gpu wird ausgebaut, und zwar an der Stelle, an der
# heute wirklich jeder Bildpunkt durch die CPU geht -- DEM ZEIGER.
#
# ===================================================================
# WAS GEBAUT WURDE
# ===================================================================
#
# Die ZWEITE WARTESCHLANGE von virtio-gpu (`cursorq`) und der Zeiger
# als EIGENE FLAECHE des Geraets:
#
#   kernel/vgpu.fi   cursor_queue_setup (Warteschlange 1, eigener Ring),
#                    CMD_UPDATE_CURSOR/CMD_MOVE_CURSOR, eine 64x64-
#                    Ressource in B8G8R8A8, das Bild aus cursor.deck()
#   kernel/wm.fi     compose malt den Zeiger NICHT mehr ins Bild, und
#                    on_mouse macht bei einer Bewegung KEIN Rechteck
#                    mehr schmutzig
#   kernel/kgui.fi   `mauslauf=<n>` -- ein GEZAEHLTER Zeigerlauf
#
# WARUM `mauslauf` UND NICHT DAS VORHANDENE `mausflut`: `mausflut`
# rechnet aus der UHR (`marken * hz / 100`). Auf diesem Wirt laufen
# acht Runden gleichzeitig (Lastmittel ueber 10 bei 20 Kernen), und
# derselbe Kern mit derselben Zeile lieferte nacheinander packets=0,
# 0, 1 -- und in einem frueheren Lauf 21. Eine Waage, die bei gleicher
# Last verschiedene Zahlen zeigt, wiegt nichts. `mauslauf=<n>` schickt
# GENAU n Pakete, ohne die Uhr zu fragen.
#
# ===================================================================
# WAS DIESE ABNAHME PRUEFT
# ===================================================================
#
#   1. Der Kern baut, die Speicherkarte hat 0 Kollisionen.
#   2. Der Wirtsbefund oben wird ERNEUT GEFAHREN, nicht behauptet.
#   3. Die Messung: n Zeigerpakete, einmal mit Zeiger in der Hardware,
#      einmal mit `nohwcur`. Verglichen werden Bilder, Oktette und
#      Zeit -- und WIRTSSEITIG (QEMU `-trace`), wie viele
#      `virtio_gpu_update_cursor` wirklich ankamen.
#   4. DER BILDBELEG: zwei Fotos, maschinell verglichen. Der Zeiger
#      muss im Softwarebild DRIN sein und im Hardwarebild FEHLEN --
#      an derselben Stelle, in Zeigergroesse.
#   5. DIE GEGENPROBEN, ohne die hier nichts zaehlt:
#        - `nohwcur` erzeugt NULL Zeigerbefehle beim Wirt.
#        - `novgpu` (kein Treiber) laeuft sauber weiter, hw=0.
#        - GAR KEIN virtio-gpu-Geraet: laeuft sauber weiter, hw=0.
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

echo "== 1. der Kern und die Speicherkarte =="
if python3 tools/kernel/memmap.py kernel > "$TMPD/map.txt" 2>&1; then
    if grep -q "0 Kollisionen" "$TMPD/map.txt"; then
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
        echo "          Dieser Wirt kann mehr als der, auf dem gebaut wurde."
        ok "virtio-gpu-gl abgefragt" ;;
esac
if [ -e /dev/dri ]; then
    echo "  HINWEIS /dev/dri existiert hier"
else
    ok "/dev/dri fehlt -- kein Renderknoten, also kein VIRGL"
fi
ok "Behaelter: $(systemd-detect-virt 2>/dev/null || echo unbekannt)"

python3 tools/osum/mkfs.py build "$TMPD/disk.img" 4096 /lib/ \
    /lib/mono.ttf=assets/osum-mono.ttf /lib/sans.ttf=assets/osum-sans.ttf \
    > "$TMPD/mkfs.txt" 2>&1 \
    && ok "Abbild mit den Schriften gebaut" \
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
# `grep -c` schreibt bei null Treffern schon "0" und gibt TROTZDEM 1
# zurueck. Mit `|| echo 0` stand danach "0\n0" in der Variablen, und der
# Vergleich mit "0" schlug fehl -- die Gegenprobe meldete einen Fehler,
# wo keiner war. Richtig ist, den Rueckgabecode zu schlucken und die
# Zahl zu nehmen, die grep ohnehin schreibt.
wirt() { grep -c "$2" "$TMPD/trace-$1.txt" 2>/dev/null | head -1; }

echo
echo "== 3. die Messung: $PAKETE Zeigerpakete, 800x600 =="
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

echo "  mit Hardware-Zeiger : $HWG"
echo "                        $HWM"
echo "  ohne (nohwcur)      : $SWG"
echo "                        $SWM"
echo "  beim WIRT angekommen: update_cursor  hw=$HW_UC  sw=$SW_UC"

[ "${HW_P:-0}" = "$PAKETE" ] && [ "${SW_P:-0}" = "$PAKETE" ] \
    && ok "beide Laeufe haben GENAU $PAKETE Pakete geschickt" \
    || bad "die Paketzahl stimmt nicht ($HW_P / $SW_P statt $PAKETE)"

[ "${HW_HW:-0}" = "1" ] && ok "im Hardwarelauf traegt das Geraet den Zeiger (hw=1)" \
    || bad "hw=1 fehlt im Hardwarelauf"
[ "${SW_HW:-1}" = "0" ] && ok "mit nohwcur traegt ihn der Kern (hw=0)" \
    || bad "nohwcur hat nicht abgeschaltet"

[ "${SW_UC:-1}" = "0" ] \
    && ok "GEGENPROBE: ohne den Weg kommt beim Wirt KEIN Zeigerbefehl an (0)" \
    || bad "GEGENPROBE gescheitert: nohwcur schickte $SW_UC Zeigerbefehle"
[ "${HW_UC:-0}" -gt 0 ] \
    && ok "mit dem Weg kommen $HW_UC Zeigerbefehle beim Wirt an" \
    || bad "der Wirt hat KEINEN Zeigerbefehl gesehen"
[ "${HW_CE:-1}" = "0" ] && ok "kein Zeigerbefehl ist fehlgeschlagen (curerr=0)" \
    || bad "curerr=$HW_CE"

if [ -n "${HW_B:-}" ] && [ -n "${SW_B:-}" ] && [ "${HW_B:-0}" -gt 0 ]; then
    FAKT=$(( SW_B / HW_B ))
    if [ "$SW_B" -gt "$HW_B" ]; then
        ok "Bilder: $SW_B ohne -> $HW_B mit  (${FAKT}x weniger)"
    else
        bad "der Hardwarezeiger hat die Bilder NICHT verringert ($SW_B -> $HW_B)"
    fi
fi
if [ -n "${HW_O:-}" ] && [ -n "${SW_O:-}" ] && [ "${HW_O:-0}" -gt 0 ]; then
    if [ "$SW_O" -gt "$HW_O" ]; then
        ok "Oktette: $SW_O ohne -> $HW_O mit"
    else
        bad "Oktette nicht gesunken ($SW_O -> $HW_O)"
    fi
fi
if [ -n "${HW_US:-}" ] && [ -n "${SW_US:-}" ] && [ "${HW_US:-0}" -gt 0 ]; then
    echo "  Zeit fuer $PAKETE Pakete: $SW_US us ohne -> $HW_US us mit"
    if [ "$SW_US" -gt "$HW_US" ]; then
        ok "der Hardwarezeiger ist schneller"
    else
        echo "  HINWEIS die Zeit ist auf diesem Wirt lastabhaengig;"
        echo "          Bilder und Oktette sind die harten Zahlen."
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
        bad "der Bildbeleg stimmt NICHT"
    fi
    # Die Fotos aufheben, damit man sie ansehen kann -- klein genug.
    mkdir -p /tmp/gpu3d-bilder
    cp -f "$TMPD/bhw.ppm" "$TMPD/bsw.ppm" /tmp/gpu3d-bilder/ 2>/dev/null
    echo "     (die Fotos liegen unter /tmp/gpu3d-bilder/)"
else
    bad "es kam kein Foto zustande"
fi

echo
echo "== 5. der saubere Rueckfall =="
lauf rf1 "novgpu" -vga std -device virtio-gpu-pci,id=vg
lauf rf2 "" -vga std
for n in rf1 rf2; do
    m=$(zahl "$TMPD/$n.txt" "mauslauf:")
    p=$(feld "$m" pakete); h=$(feld "$m" hw)
    if grep -qa 'panic' "$TMPD/$n.txt"; then
        bad "$n: der Kern ist stehengeblieben"
    elif [ "${p:-0}" = "$PAKETE" ] && [ "${h:-1}" = "0" ]; then
        ok "$n: laeuft ohne den Weg sauber weiter ($m)"
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
