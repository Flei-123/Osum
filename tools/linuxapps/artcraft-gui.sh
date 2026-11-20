#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
WD=${1:?workdir with Alpine root and fxrun/spec.txt}
APP=${2:?app binary name, e.g. gridcraft}
OUT=${3:?outdir}
BINDIR=${AC_BINDIR:?directory holding the app binary}
mkdir -p "$OUT"
SOCK="$OUT/mon.sock"
mon() { printf '%s\n' "$1" | socat - "UNIX-CONNECT:$SOCK" > /dev/null 2>&1; }
(
    i=0
    until grep -qa 'wayd: window c=' "$OUT/ser.txt" 2>/dev/null; do sleep 2; i=$((i + 2)); [ "$i" -gt "${AC_MARKERCAP:-900}" ] && exit 0; done
    sleep "${AC_PAINTWAIT:-90}"
    mon "screendump $OUT/window.ppm"
    sleep 5
    for key in h e l l o ret; do mon "sendkey $key"; sleep 1; done
    sleep "${AC_TYPEWAIT:-40}"
    mon "screendump $OUT/typed.ppm"
) &
SHOTPID=$!
PIN=()
for f in /usr/lib/x86_64-linux-gnu/dri/swrast_dri.so /usr/share/glvnd/egl_vendor.d/50_mesa.json \
    /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf /usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf /usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf; do PIN+=("pin:$f"); done
LIBS=(libEGL.so.1 libEGL_mesa.so.0 libGLdispatch.so.0 libGLESv2.so.2 libGL.so.1 libgbm.so.1 libwayland-client.so.0 libwayland-egl.so.1 libwayland-cursor.so.0 libxkbcommon.so.0 libasound.so.2)
{ echo "AC_APP=$APP"; cat tools/linuxapps/guest-artcraft-gui-app.sh; } > "$OUT/acgui.sh"
GLIBC_ENTRIES=$(python3 -I tools/linuxapps/glibcspec.py "bin:$AC_BINDIR/$APP" "${LIBS[@]}" "${PIN[@]}")
env GUI=1 GUI_EXTRA="settingsd apprights orientbus act" BLOCKS=${BLOCKS:-2400000} INODES=${INODES:-8000} TMO=${TMO:-1500} MEM=${MEM:-3072} AC_APP="$APP" \
    "EXTRA=$GLIBC_ENTRIES /opt/ac/ /opt/ac/$APP=$AC_BINDIR/$APP@755 /etc/acgui.sh=$(realpath "$OUT")/acgui.sh@755 /etc/settings.schema=etc/settings.schema@644 /etc/actions.d/@755 /etc/actions.d/settings.actions=etc/actions.d/settings.actions@644" \
    "KARGS=gfx disp wm wmdauer wmshell osum vfs bus fremdtrace script=sh /etc/fx.sh;exit" \
    bash tools/linuxapps/run.sh "$WD" tools/linuxapps/guest-artcraft-gui-boot.sh "$OUT"
rc=$?
kill "$SHOTPID" 2>/dev/null
[ -f "$OUT/window.ppm" ] || { echo "ARTCRAFT-GUI: no screenshot"; exit 1; }
echo "ARTCRAFT-GUI: screenshot $OUT/window.ppm"
exit $rc
