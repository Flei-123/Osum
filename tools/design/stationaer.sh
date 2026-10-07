#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/design/stationaer.sh -- docs/COMPOSITOR.md S0: the frame time AFTER the boot, by phase.
#
#   bash tools/design/stationaer.sh [<outdir>]        (start it through /root/jarvis/bin/heavy)
#
# Boots the shipping configuration (tools/design/audit.sh), drives tools/design/stationaer.txt (F12 between
# the phases) and prints every `wm: bild` line the machine wrote: the frames composed since the last F12.
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:-}
if [ -z "$OUT" ]; then OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT; fi
# every run builds in its own directory (several of these runs at once share nothing)
export DESIGNBUILD="${DESIGNBUILD:-$OUT-build}"
bash tools/design/audit.sh "$OUT" accel=kvm uitrace=yes halt=300 drehbuch="$(pwd)/tools/design/stationaer.txt" > "$OUT.log" 2>&1
n=0
for ph in "1 the rest of the boot" "2 idle (six seconds)" "3 pointer moves over the desktop" "4 start menu open / close" "5 window dragged"; do
    n=$((n + 1))
    l=$(grep -a '^wm: bild n=' "$OUT/serial.txt" | sed -n "${n}p")
    printf '  phase %-34s %s\n' "$ph" "${l#wm: bild }"
    # r460: the next line says where the time of those frames went (microseconds summed, n frames)
    l2=$(grep -a '^wm: phase n=' "$OUT/serial.txt" | sed -n "${n}p")
    printf '        %-34s %s\n' "" "${l2#wm: phase }"
done
[ -n "${1:-}" ] || rm -rf "$OUT.log" "$OUT-build"
