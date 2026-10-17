#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/settingsflick/run.sh -- X2: Settings paints into a private picture (fuiapp.set_atomic); hover and resize cost no whole-window compose.
#
#   /root/jarvis/bin/heavy bash tools/settingsflick/run.sh [outdir] [extra kernel words]
#
# One boot of the shipping configuration (tools/design/audit.sh, word `phases`), the workload tools/settingsflick/hover.txt, judge.py.
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:-}
if [ -z "$OUT" ]; then OUT=$(mktemp -d); trap 'rm -rf "$OUT" "$OUT-build" "$OUT.log"' EXIT; fi
EXTRA="phases ${2:-}"
export DESIGNBUILD="${DESIGNBUILD:-$OUT-build}"
bash tools/design/audit.sh "$OUT" accel=kvm uitrace=yes extra="$EXTRA" halt="${HALT:-900}" drehbuch="$(pwd)/tools/settingsflick/hover.txt" > "$OUT.log" 2>&1
S="$OUT/serial.txt"
python3 -I tools/settingsflick/judge.py "$S" "$OUT/20-maximised.ppm"
