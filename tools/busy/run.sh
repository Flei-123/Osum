#!/usr/bin/env bash
set -u
cd "$(dirname "$0")/../.."
MODE=${1:-light}
SCALE=${2:-1}
D=$(mktemp -d)
trap '[ -n "${BUSY_KEEP:-}" ] && cp -r "$D/out" "$BUSY_KEEP"; rm -rf "$D"' EXIT
bash tools/design/eh6.sh "$D/out" res=1920x1080 accel=kvm mode="$MODE" uiscale="$SCALE" lang=en drehbuch=tools/busy/dreh.txt moreprogs=busydemo > "$D/run.log" 2>&1
if [ ! -f "$D/out/pct-100.ppm" ]; then
    echo "FAIL: no screenshots"
    tail -15 "$D/run.log"
    exit 1
fi
python3 -I tools/busy/check.py "$D/out" "$D/out/serial.txt"
