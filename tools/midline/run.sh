#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/midline/run.sh -- D-009: icon, text and row on ONE centre line, measured on the file manager.
#   bash tools/midline/run.sh [<outdir>]        (start it through /root/jarvis/bin/heavy)
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:-}
if [ -z "$OUT" ]; then OUT=$(mktemp -d); trap 'rm -rf "$OUT" "$OUT-build"' EXIT; fi
export DESIGNBUILD="${DESIGNBUILD:-$OUT-build}"
bash tools/design/audit.sh "$OUT" accel=kvm uitrace=yes halt=420 drehbuch="$(pwd)/tools/design/explorer.txt" > "$OUT.log" 2>&1
python3 tools/midline/check.py "$OUT"
