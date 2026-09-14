#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/hotplug/lauf.sh -- EIN LAUF MIT EINEM STICK, DER IM BETRIEB KOMMT.
#
#   bash tools/hotplug/lauf.sh <name> <kernel> <kommandozeile> <drehbuch> [qemu-args...]
#
# Startet QEMU im Hintergrund, faehrt das Drehbuch ueber den Monitor
# (tools/hotplug/monitor.py) und laesst danach abraeumen. Die serielle
# Ausgabe landet in $ARB/<name>.txt, die Bilder dort, wo das Drehbuch
# sie hinlegt.
#
# $ARB (Arbeitsverzeichnis) kommt von aussen; ohne es wird eines
# angelegt. Das ist Absicht: der Laeufer darueber will die Dateien
# NACH dem Lauf noch lesen, und ein `mktemp -d` mit `trap rm` haette
# sie weggeraeumt, bevor die erste Zusage gemessen ist.
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)

NAME=${1:?name fehlt}
KERN=${2:?kernel fehlt}
APP=${3:?kommandozeile fehlt}
DREH=${4:?drehbuch fehlt}
shift 4

ARB=${ARB:-$(mktemp -d)}
mkdir -p "$ARB"
SER="$ARB/$NAME.txt"
SOCK="$ARB/mon-$NAME.sock"
rm -f "$SER" "$SOCK" "$ARB/$NAME.rc"

ACC=(-accel tcg)
[ -r /dev/kvm ] && [ -w /dev/kvm ] && ACC=(-accel kvm)

(
    timeout "${HP_TIMEOUT:-180}" qemu-system-x86_64 "${ACC[@]}" \
        -kernel "$KERN" -m "${HP_MEM:-512}" -append "$APP" \
        -serial "file:$SER" -display none -no-reboot -vga std \
        -monitor "unix:$SOCK,server,nowait" \
        "$@" \
        -device isa-debug-exit,iobase=0xf4,iosize=0x04 \
        > "$ARB/$NAME.qemu" 2>&1
    echo $? > "$ARB/$NAME.rc"
) &
QP=$!

python3 tools/hotplug/monitor.py "$SOCK" "$SER" "$DREH" \
    > "$ARB/$NAME.mon" 2>&1
MRC=$?

# Dem Kern Zeit geben, sich selbst zu beenden -- `isa-debug-exit` gibt
# 21, und diese Zahl ist eine Zusage. Wer hier sofort abschiesst, misst
# stattdessen sein eigenes `kill`.
i=0
while [ $i -lt "${HP_NACHLAUF:-40}" ]; do
    kill -0 "$QP" 2>/dev/null || break
    sleep 0.5
    i=$((i + 1))
done
kill "$QP" 2>/dev/null
wait "$QP" 2>/dev/null
rm -f "$SOCK"

echo "ARB=$ARB"
echo "MON=$MRC"
echo "RC=$(cat "$ARB/$NAME.rc" 2>/dev/null || echo 99)"
