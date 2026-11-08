#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -u
cd "$(dirname "$0")/../.."
MODE=${1:-light}
SCALE=${2:-1}
D=$(mktemp -d)
trap '[ -n "${DIALOGD_KEEP:-}" ] && cp -r "$D/out" "$DIALOGD_KEEP"; rm -rf "$D"' EXIT
ALLTAGREBUILD=1 bash tools/design/eh6.sh "$D/out" res=1920x1080 accel=kvm mode="$MODE" uiscale="$SCALE" lang=en drehbuch=tools/dialogd/script.txt moreprogs="dialogd dialogdemo" > "$D/run.log" 2>&1
if [ ! -f "$D/out/msg.ppm" ]; then
    echo "FAIL: no screenshots"
    tail -15 "$D/run.log"
    exit 1
fi
python3 -I tools/dialogd/check.py "$D/out" "$D/out/serial.txt"
