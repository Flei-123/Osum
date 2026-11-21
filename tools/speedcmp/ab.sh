#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/speedcmp/common.sh
BASE=${1:?base kernel}; NEW=${2:?new kernel}; OUT=${3:?outdir}; FILTER=${4:?test filter}
mkdir -p "$OUT/a" "$OUT/b"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
build_bench "$(pwd)" "$W/speedbench" || exit 1
export SPEED_ONLY="$FILTER" SPEED_MIN_MS=${SPEED_MIN_MS:-0}
SPEED_KERNEL="$BASE" bash tools/speedcmp/osum.sh "$OUT/a" "$W/speedbench" & PA=$!
SPEED_KERNEL="$NEW" bash tools/speedcmp/osum.sh "$OUT/b" "$W/speedbench" & PB=$!
wait "$PA"; wait "$PB"
python3 tools/speedcmp/abreport.py "$OUT/a" "$OUT/b"
