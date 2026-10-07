#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/design/shots.sh <outdir> <script> -- ONE machine, one capture script (tools/design/*.txt), pictures into <outdir>.
#   /root/jarvis/bin/heavy bash tools/design/shots.sh /tmp/x tools/design/taskmgr2.txt
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:?usage: shots.sh <outdir> <script>}
SCRIPT=${2:?usage: shots.sh <outdir> <script>}
export DESIGNBUILD="${DESIGNBUILD:-$OUT-build}"
bash tools/design/audit.sh "$OUT" accel=kvm uitrace=yes halt=420 drehbuch="$(pwd)/$SCRIPT" > "$OUT.log" 2>&1
for f in "$OUT"/*.ppm; do [ -f "$f" ] && python3 tools/design/ppm2png.py "$f" "${f%.ppm}.png" > /dev/null 2>&1; done
tail -3 "$OUT.log"
