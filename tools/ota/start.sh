#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/ota/start.sh -- den Laeufer im Hintergrund starten, abgeloest von
# der Sitzung, die ihn gestartet hat.
#
#   bash tools/ota/start.sh <ausgabeverzeichnis> [--kurz|--probe]
#
# WARUM ES DIESE DATEI GIBT. Der Lauf dauert Stunden (ueber hundert
# QEMU-Starts), und wer ihn aus einer Sitzung heraus startet, die
# zwischendurch weggeht, verliert ihn -- `nohup` schuetzt nur vor SIGHUP,
# nicht vor einem beendeten Prozessverband. `setsid` macht daraus eine
# eigene Sitzung mit eigener Prozessgruppe; danach ist der Lauf von der
# Sitzung unabhaengig.
set -u
cd "$(dirname "$0")/../.."
ZIEL=${1:?ausgabeverzeichnis}
MODUS=${2:-}
mkdir -p "$ZIEL"
setsid bash -c "cd '$(pwd)'; OUT='$ZIEL' bash tools/ota/run.sh $MODUS \
    > '$ZIEL/lauf.log' 2>&1; echo \"EXIT=\$?\" >> '$ZIEL/lauf.log'" \
    < /dev/null > /dev/null 2>&1 &
sleep 1
echo "gestartet, das Protokoll waechst in $ZIEL/lauf.log"
