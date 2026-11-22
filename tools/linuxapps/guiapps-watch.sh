#!/usr/bin/env bash
set -uo pipefail
RUN=${1:?run directory with ser.txt and mon.sock}
SHOTS=${2:?screenshot directory}
shift 2
SOCK="$RUN/mon.sock"
CAP=${GUIAPPS_MARKERCAP:-240}
BOOT_CAP=${GUIAPPS_BOOTCAP:-3000}
mon() { printf '%s\n' "$1" | socat - "UNIX-CONNECT:$SOCK" > /dev/null 2>&1; }
wait_for() {
    local cap=$1 i=0
    shift
    until "$@"; do
        sleep 1
        i=$((i + 1))
        [ "$i" -gt "$cap" ] && return 1
    done
    return 0
}
marker() { grep -qaF -- "$1" "$RUN/ser.txt" 2>/dev/null; }
wait_marker() { wait_for "$CAP" marker "$1"; }
wait_for "$BOOT_CAP" test -S "$SOCK" || exit 1
wait_for "$BOOT_CAP" marker "${GUIAPPS_BASEMARK:-GUIAPP basedone}" || exit 1
for name in "$@"; do
    wait_marker "GUIAPP shot $name" || exit 1
    mon "screendump $SHOTS/$name.ppm"
    wait_marker "GUIAPP keys $name" || exit 1
    sleep 1
    mon "screendump $SHOTS/$name-pre.ppm"
    for key in h i; do mon "sendkey $key"; sleep 1; done
    sleep 3
    mon "screendump $SHOTS/$name-typed.ppm"
    wait_marker "GUIAPP shot2 $name" || exit 1
done
