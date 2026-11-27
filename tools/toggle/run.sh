#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:-}
if [ -z "$OUT" ]; then OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT; fi
mkdir -p "$OUT"
export DESIGNBUILD="${DESIGNBUILD:-$OUT/build}"
PROGS="desktop taskbar settings launcher explorer netview taskmgr edit sh echo ls cat theme"
script() {
  echo "warte 12"
  echo "klick 24,780"; echo "warte 3"
  echo "klickauf start_Settings"; echo "warte 12"
  echo "klickauf srecttabv"; echo "warte 12"
  echo "foto 00-before"
  echo "klickauf srectwhq"
  for i in 1 2 3 4 5 6; do echo "foto 0$i-frame"; done
  echo "warte 30"
  echo "foto 09-after"
}
for mode in slow off; do
  D="$OUT/$mode"
  mkdir -p "$D"
  script > "$D-drehbuch.txt"
  if [ "$mode" = slow ]; then extra="motion=12000"; else extra="motion=0"; fi
  bash tools/design/eh6.sh "$D" res=1280x800 accel=kvm mode=light moreprogs=term progs="$PROGS" tafel=nein themeextra="$extra" drehbuch="$D-drehbuch.txt" > "$D.log" 2>&1
  rm -f "$D-drehbuch.txt"
done
rm -rf "$OUT/build"
python3 -I tools/toggle/check.py "$OUT/slow" "$OUT/off" | tee "$OUT/result.txt"
! grep -q '^  FAIL' "$OUT/result.txt"
