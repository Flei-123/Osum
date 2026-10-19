#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/settingsnarrow/run.sh -- Z1: Settings in a narrow / low window (list -> page navigation, scrolling pages).
#
#   /root/jarvis/bin/heavy bash tools/settingsnarrow/run.sh [<outdir>] [cfg ...]     cfg = nav1 | nav2 | low (default: all)
#
#   nav1  640x480, scale 1 -> window 600 wide: navigation mode (list, page with Back)
#   nav2  1280x800, scale 2 -> 640x400 points: navigation mode, low
#   low   800x480, scale 1 -> two-column squeeze + scrolling page area (no navigation mode)
#
# `rad -N` = N notches DOWN (the guest sees wheel up for a positive QEMU dz).
# Per boot (tools/design/audit.sh): open Settings, wheel over the list (to the end, then 3 notches back), open "Darstellung", wheel over the page, Back.
# The window reports `settings: layout nav= detail= scroll= content= view= off=` (content/view/off of the page or list area,
# pixels) after every change; tools/settingsnarrow/check.py reads them and the pictures.
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:-}
if [ -z "$OUT" ]; then OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT; fi
shift || true
CFGS=${*:-nav1 nav2 low}
mkdir -p "$OUT"
total_fail=0
for cfg in $CFGS; do
  case "$cfg" in
    nav1) RES=640x480;  EXTRA="" ;;
    nav2) RES=1280x800; EXTRA="uiscale=2" ;;
    low)  RES=800x480;  EXTRA="" ;;
    *) echo "unknown cfg $cfg"; exit 2 ;;
  esac
  D="$OUT/$cfg"
  mkdir -p "$D"
  YRES=${RES#*x}
  XRES=${RES%x*}
  DREH="$D-drehbuch.txt"
  {
    echo "warte 12"
    echo "klick 24,$((YRES-20))"; echo "warte 3"
    echo "klickauf start_Settings"; echo "warte 12"
    echo "foto 00-start"
    echo "fahre $((XRES/2)),$((YRES/2))"; echo "warte 1"
    echo "rad -6"; echo "warte 2"; echo "foto 01-wheel1"
    echo "rad -10"; echo "warte 2"; echo "foto 02-wheel2"
    echo "rad 3"; echo "warte 2"
    echo "klickauf srecttaba"; echo "warte 3"; echo "foto 03-page"
    # the page wheel goes over the page margin: a list box under the pointer (Colour scheme) would take the notches itself
    case "$cfg" in nav*) PGX=$((XRES/45)) ;; *) PGX=$((XRES/2)) ;; esac
    echo "fahre $PGX,$((YRES/2))"; echo "warte 1"
    echo "rad -8"; echo "warte 2"; echo "foto 04-page-wheel1"
    echo "rad -8"; echo "warte 2"; echo "foto 05-page-wheel2"
    echo "rad 40"; echo "warte 6"
    for _k in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do echo "taste tab"; echo "warte 0.6"; done
    echo "warte 2"; echo "foto 07-focus"
    case "$cfg" in nav*) echo "klickauf srectwhp" ;; esac
    echo "warte 3"; echo "foto 06-back"
  } > "$DREH"
  export DESIGNBUILD="${DESIGNBUILD:-$D-build}"
  # shellcheck disable=SC2086
  bash tools/design/audit.sh "$D" accel=kvm uitrace=yes halt=420 res=$RES $EXTRA drehbuch="$DREH" > "$D.log" 2>&1
  echo "== $cfg ($RES $EXTRA)"
  python3 -I tools/settingsnarrow/check.py "$cfg" "$D/serial.txt" "$D" || total_fail=$((total_fail+1))
  rm -rf "$D-build" "$DREH"
  unset DESIGNBUILD
done
echo "SETTINGSNARROW: $total_fail config(s) failed"
[ "$total_fail" = 0 ]
