#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -u
cd "$(dirname "$0")/../.."
SCALE=${1:-1}
D=$(mktemp -d)
trap '[ -n "${DECOAX_KEEP:-}" ] && cp -r "$D/out" "$DECOAX_KEEP"; rm -rf "$D"' EXIT
bash tools/design/eh6.sh "$D/out" res=1920x1080 accel=kvm mode=light uiscale="$SCALE" lang=en drehbuch=tools/decoax/script.txt moreprogs=decodemo > "$D/run.log" 2>&1
if [ ! -f "$D/out/serial.txt" ]; then
    echo "DECOAX: 0 passed, 1 failed (no serial log)"
    tail -15 "$D/run.log"
    exit 1
fi
python3 -I tools/decoax/check.py "$D/out/serial.txt"
