#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
. tools/speedcmp/common.sh
KERNEL_A=${1:?kernel A (absolute path)}; WORDS_A=${2-}; KERNEL_B=${3:?kernel B (absolute path)}; WORDS_B=${4-}
OUT=${5:?outdir}; FILTER=${6:?test filter}; RUNS=${7:-5}
mkdir -p "$OUT/a" "$OUT/b"
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
build_bench "$(pwd)" "$W/speedbench" || exit 1
export SPEED_SMP=${SPEED_SMP:-1} SPEED_RUNS=$RUNS SPEED_ONLY="$FILTER" SPEED_MIN_MS=${SPEED_MIN_MS:-0}
export SPEED_SCRIPT='/bin/speedbench;cat /proc/bench;exit'
SPEED_KERNEL="$KERNEL_A" SPEED_OSUM_WORDS="nosched noproc nofs $WORDS_A" bash tools/speedcmp/osum.sh "$OUT/a" "$W/speedbench" & PA=$!
SPEED_KERNEL="$KERNEL_B" SPEED_OSUM_WORDS="nosched noproc nofs $WORDS_B" bash tools/speedcmp/osum.sh "$OUT/b" "$W/speedbench" & PB=$!
wait "$PA"; wait "$PB"
python3 tools/speedcmp/abreport.py "$OUT/a" "$OUT/b"
