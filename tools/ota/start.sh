#!/usr/bin/env bash
set -u
cd "$(dirname "$0")/../.."
ZIEL=${1:?ausgabeverzeichnis}
MODUS=${2:-}
mkdir -p "$ZIEL"
setsid bash -c "cd '$(pwd)'; OUT='$ZIEL' bash tools/ota/run.sh $MODUS \
    > '$ZIEL/lauf.log' 2>&1; echo \"EXIT=\$?\" >> '$ZIEL/lauf.log'" \
    < /dev/null > /dev/null 2>&1 &
sleep 1
echo "started, the log grows in $ZIEL/lauf.log"
