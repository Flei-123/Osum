#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:-}
if [ -z "$OUT" ]; then OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT; fi
shift || true
CFGS=${*:-wide}
mkdir -p "$OUT"
total_fail=0
for cfg in $CFGS; do
  D="$OUT/$cfg"
  mkdir -p "$D"
  DREH="$D-drehbuch.txt"
  {
    echo "warte 12"
    echo "klick 24,780"; echo "warte 3"
    echo "klickauf start_Settings"; echo "warte 12"
    echo "foto 00-start"
    echo "klickauf srecttabb"; echo "warte 3"; echo "foto 01-display"
    echo "klickauf srecttab32"; echo "warte 3"; echo "foto 02-monitors"
    echo "klickauf srecttabp"; echo "warte 3"; echo "foto 03-input"
    echo "klickauf srecttabm"; echo "warte 3"; echo "foto 04-privacy"
  } > "$DREH"
  export DESIGNBUILD="${DESIGNBUILD:-$D-build}"
  bash tools/design/audit.sh "$D" accel=kvm uitrace=yes halt=420 res=1280x800 mode=light drehbuch="$DREH" > "$D.log" 2>&1
  echo "== $cfg"
  python3 -I tools/settingsnavcol/check.py "$cfg" "$D/serial.txt" "$D" || total_fail=$((total_fail+1))
  rm -rf "$D-build" "$DREH"
  unset DESIGNBUILD
done
echo "SETTINGSNAVCOL: $total_fail config(s) failed"
[ "$total_fail" = 0 ]
