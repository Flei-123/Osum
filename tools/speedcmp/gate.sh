#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
RATCHET=0; METRICS=0; WRITE=1
for arg in "$@"; do
    case "$arg" in
        --ratchet) RATCHET=1 ;;
        --metrics) METRICS=1 ;;
        --no-write) WRITE=0 ;;
        *) echo "usage: gate.sh [--ratchet] [--metrics] [--no-write]" >&2; exit 2 ;;
    esac
done
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
OUTROOT=${SPEED_KEEP_OUT:-$W}
TSV=$W/matrix.tsv; RAW=$W/raw.tsv; MD=$W/matrix.md
KEEP_CACHE=${SPEEDCMP_CACHE:-/root/abbilder/speedcmp-cache}; mkdir -p "$KEEP_CACHE"
export SPEEDCMP_CACHE=$KEEP_CACHE

SPEED_MATRIX_ONLY_OUT=1 SPEED_OUT=$OUTROOT/a bash tools/speedcmp/measure.sh || { echo "gate: matrix run failed" >&2; exit 2; }
DIRS=("$OUTROOT/a")
python3 tools/speedcmp/matrix.py build "${DIRS[@]}" --tsv "$TSV" --raw "$RAW" --md "$MD" --notes "$(cat "$OUTROOT/a/notes.txt")"
RED=$(python3 tools/speedcmp/matrix.py red "$TSV" | tr '\n' ' ')
if [ -n "$RED" ] && [ "${SPEED_RERUN:-1}" = 1 ]; then
    echo "gate: rerun for outliers: $RED"
    SPEED_ONLY="$RED" SPEED_MATRIX_ONLY_OUT=1 SPEED_OUT=$OUTROOT/b bash tools/speedcmp/measure.sh && DIRS+=("$OUTROOT/b")
    python3 tools/speedcmp/matrix.py build "${DIRS[@]}" --tsv "$TSV" --raw "$RAW" --md "$MD" --notes "$(cat "$OUTROOT/a/notes.txt") Outlier rerun: ${RED}"
fi
[ "$RATCHET" = 1 ] && python3 tools/speedcmp/matrix.py ratchet "$TSV"
if [ "$WRITE" = 1 ]; then
    cp "$TSV" docs/speed-osum-vs-linux.tsv; cp "$RAW" docs/speed-osum-vs-linux-raw.tsv; cp "$MD" docs/speed-osum-vs-linux.md
fi
[ "$METRICS" = 1 ] && python3 tools/speedcmp/matrix.py metrics "$TSV" > "${SPEED_METRICS_OUT:-docs/speed-metrics.jsonl}"
cp "$OUTROOT/a/load.log" "${SPEED_LOAD_OUT:-/dev/null}" 2>/dev/null
python3 tools/speedcmp/matrix.py gate "$TSV"
