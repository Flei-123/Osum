#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -euo pipefail
cd "$(dirname "$0")/../.."
[ $# -ge 1 ] || { echo "usage: bash tools/livedesign/run.sh <program> [out.png] [--no-run] [--no-photo]"; exit 2; }
PROG=$1
OUT=${2:-${LIVEDESIGN_DIR:-/tmp/livedesign}/$PROG.png}
shift $(( $# >= 2 ? 2 : 1 ))
BUILD=${LIVEDESIGN_DIR:-/tmp/livedesign}/build
mkdir -p "$BUILD" "$(dirname "$OUT")"
. tools/lib/firnenv.sh
T0=$EPOCHREALTIME
bash tools/sync/build.sh "$BUILD" 0 "$PROG"
printf 'livedesign: build    %5.1f s\n' "$(awk -v a="$EPOCHREALTIME" -v b="$T0" 'BEGIN{print a-b}')"
python3 -I tools/livedesign/push.py "$PROG" "$BUILD/$PROG.elf" "$OUT" "$@"
printf 'livedesign: total    %5.1f s\n' "$(awk -v a="$EPOCHREALTIME" -v b="$T0" 'BEGIN{print a-b}')"
echo "$OUT"
