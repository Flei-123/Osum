#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/install/hg.sh -- einen Lauf im Hintergrund anstossen, damit die
# Werkzeugsitzung nicht auf ihn warten muss.
#   bash tools/install/hg.sh <name> <wie> "<skript>" [zeitlimit] [neuePlatte?]
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${OUT:-/tmp/ins}
NAME=${1:-w}
WIE=${2:-iso}
SKRIPT=${3:-}
LIMIT=${4:-900}
NEU=${5:-0}
if [ "$NEU" = 1 ]; then
    rm -f "$OUT/ziel.img"
    head -c $((${ZIEL_MIB:-256} * 1024 * 1024)) /dev/zero > "$OUT/ziel.img"
fi
OUT="$OUT" bash tools/install/oneshot.sh "$NAME" "$WIE" "$SKRIPT" "$LIMIT"
echo "ENDE $NAME"
