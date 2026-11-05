#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/simpleui/shots.sh <outdir> [scale ...] -- start menu, Settings landing page, Wi-Fi, network pages and the serial icon counters at UI scale 1 and 2
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:?usage: shots.sh <outdir> [scale ...]}
shift || true
SCALES=${*:-1 2}
mkdir -p "$OUT"
for sc in $SCALES; do
  D="$OUT/s$sc"
  mkdir -p "$D"
  DREH=$(mktemp)
  RES=1280x800
  if [ "$sc" = 2 ]; then RES=2560x1600; fi
  CLICKY=$(( ${RES#*x} - 20 ))
  cat > "$DREH" <<SCRIPT
warte 12
foto 00-desktop
klick 24,$CLICKY
warte 4
foto 01-start
klickauf start_Settings
warte 12
foto 02-settings
klickauf srecttabw
warte 3
foto 03-wifi
klickauf srecttabd
warte 3
foto 04-network
klick $((520 * sc)),$((60 * sc))
tippe connections
warte 2
foto 05a-search
klickauf srecttabf
warte 3
foto 05-netview
klicksuche srecttabl $((140 * sc)),$((300 * sc))
warte 3
foto 06-system
SCRIPT
  export DESIGNBUILD="$D-build"
  bash tools/design/audit.sh "$D" pins=explorer,terminal,settings accel=kvm uitrace=yes halt=300 res=$RES uiscale="$sc" drehbuch="$DREH" > "$D.log" 2>&1
  rm -rf "$D-build" "$DREH"
  unset DESIGNBUILD
  ls "$D" | head -20
done
