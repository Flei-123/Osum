#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.."
WD=${1:?workdir with Alpine root and fxrun/spec.txt}
BIN=${2:?freeviewer musl-dynamic binary}
OUT=${3:?outdir}
mkdir -p "$OUT"
SOCK="$OUT/mon.sock"
mon() { printf '%s\n' "$1" | socat - "UNIX-CONNECT:$SOCK" > /dev/null 2>&1; }
(
    i=0
    until grep -qa 'wayd: window c=' "$OUT/ser.txt" 2>/dev/null; do sleep 2; i=$((i + 2)); [ "$i" -gt "${FVGUI_MARKERCAP:-900}" ] && exit 0; done
    sleep "${FVGUI_PAINTWAIT:-60}"
    mon "screendump $OUT/window.ppm"
) &
SHOTPID=$!
env GUI=1 BLOCKS=${BLOCKS:-1200000} TMO=${TMO:-1500} MEM=${MEM:-3072} \
    "EXTRA=/opt/@755 /opt/fv/@755 /etc/fvgui.sh=$PWD/tools/xremote/guest-gui-app.sh@755 /opt/fv/freeviewer=$BIN@755 ${FVGUI_LIBS:-}" \
    "KARGS=gfx disp wm wmdauer wmshell osum vfs bus fremdtrace script=sh /etc/fx.sh;exit" \
    bash tools/linuxapps/run.sh "$WD" tools/xremote/guest-gui-boot.sh "$OUT"
rc=$?
kill "$SHOTPID" 2>/dev/null
exit $rc
