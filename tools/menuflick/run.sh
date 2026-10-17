#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/menuflick/run.sh -- flicker on fast pointer moves over the start menu and the Settings window (boss, 16.10.2026).
#
#   /root/jarvis/bin/heavy bash tools/menuflick/run.sh [outdir] [extra kernel words]
#
# One boot of the shipping configuration (tools/design/audit.sh, word `phases`), the workload tools/menuflick/menuhover.txt, and per
# phase the `wm: bild` line (frames composed, mean/max ms, frames over 16 ms) plus the large dirty rectangles (> 16384 px) the
# compositor printed in that phase. Verdict: hover phases need <= 1 large dirty rectangle per 20 frames (hover must not repaint the
# whole window or the blurred backdrop again and again) and no frame over 16 ms at the mean.
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:-}
if [ -z "$OUT" ]; then OUT=$(mktemp -d); trap 'rm -rf "$OUT" "$OUT-build" "$OUT.log"' EXIT; fi
EXTRA="phases ${2:-}"
export DESIGNBUILD="${DESIGNBUILD:-$OUT-build}"
bash tools/design/audit.sh "$OUT" accel=kvm uitrace=yes extra="$EXTRA" halt="${HALT:-900}" drehbuch="$(pwd)/tools/menuflick/menuhover.txt" > "$OUT.log" 2>&1
S="$OUT/serial.txt"
python3 -I tools/menuflick/judge.py "$S"
