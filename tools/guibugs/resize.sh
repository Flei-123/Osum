#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:?usage: resize.sh <outdir> <WxH> <uiscale> [extra kernel words]}
RES=${2:-1280x800}
SCALE=${3:-1}
EXTRA=${4:-}
XRES=${RES%x*}
YRES=${RES#*x}
STEPS=${STEPS:-"r,-300,0 r,-300,0 u,0,-200 l,200,0 o,0,150 ru,-100,-100 ru,700,500 lu,-300,200 lo,-200,-100 r,500,0 u,0,300 ro,-400,200 lo,300,300 ru,900,200 l,600,0 o,0,500 ru,-900,-800"}
mkdir -p "$OUT"
DREH="$OUT-drehbuch.txt"
{
  echo "warte 12"
  echo "klick $((24 * SCALE)),$((YRES - 20 * SCALE))"
  echo "warte 3"
  echo "klickauf start_Settings"
  echo "warte 12"
  echo "taste f12"
  echo "warte 3"
  echo "foto 00-start"
  n=0
  for s in $STEPS; do
    n=$((n + 1))
    IFS=, read -r e dx dy <<< "$s"
    case "$e" in
      max) echo "taste f12"; echo "warte 2"; echo "klickauf cap_max" ;;
      page) echo "klickauf ${PAGETAB:-srecttabd}" ;;
      *) echo "ziehkante ${WINID:-19} $e $((dx * SCALE)),$((dy * SCALE))" ;;
    esac
    echo "warte 4"
    echo "taste f12"
    echo "warte 2"
    printf 'foto %02d-%s\n' "$n" "$e"
  done
} > "$DREH"
export DESIGNBUILD="${DESIGNBUILD:-$OUT-build}"
export AUDIT_TIMEOUT="${AUDIT_TIMEOUT:-1800}"
bash tools/design/audit.sh "$OUT" accel=kvm uitrace=yes halt="${HALT:-1500}" res="$RES" uiscale="$SCALE" extra="$EXTRA" drehbuch="$DREH" > "$OUT.log" 2>&1
python3 -I tools/guibugs/resize_check.py "$OUT/serial.txt" "$OUT" "$n" "${GUARDMODE:-guard}"
