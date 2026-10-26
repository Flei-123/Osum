#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/settingswin11/run.sh -- Settings Windows-11 layout: search bar on top, category accordion in the sidebar.
#
#   /root/jarvis/bin/heavy bash tools/settingswin11/run.sh [<outdir>] [cfg ...]   cfg = light | dark | hd | narrow | flat
#
#   light/dark  1280x800, accordion sidebar (only the open category shows its sub-pages)
#   hd          1920x1080 (HP EliteBook panel), light, with hover pictures of the sidebar entries
#   narrow      640x480, navigation mode, accordion list
#   flat        counter-proof: /etc/setflat puts every page in the sidebar again; the accordion checks must FAIL there
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:-}
if [ -z "$OUT" ]; then OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT; fi
shift || true
CFGS=${*:-light dark narrow flat}
mkdir -p "$OUT"
total_fail=0
for cfg in $CFGS; do
  EXTRA=""
  RES=1280x800
  MODE=light
  SIDE=tree
  case "$cfg" in
    light) ;;
    dark) MODE=dark ;;
    hd) RES=1920x1080 ;;
    narrow) RES=640x480 ;;
    flat) SIDE=flat ;;
    *) echo "unknown cfg $cfg"; exit 2 ;;
  esac
  D="$OUT/$cfg"
  mkdir -p "$D"
  YRES=${RES#*x}
  DREH="$D-drehbuch.txt"
  {
    echo "warte 12"
    echo "klick 24,$((YRES-20))"; echo "warte 3"
    echo "klickauf start_Settings"; echo "warte 12"
    echo "foto 00-start"
    if [ "$cfg" = narrow ]; then
      echo "klickauf srecttabl"; echo "warte 3"; echo "foto 01-system"
    else
      echo "klickauf srecttabl"; echo "warte 3"; echo "foto 01-system"
      echo "klickauf srecttabq"; echo "warte 3"; echo "foto 02-power"
      if [ "$cfg" = hd ]; then
        echo "fahreauf srecttabl"; echo "warte 1"; echo "fahre 146,359"; echo "warte 3"; echo "foto 04-hover-other"
        echo "fahreauf srecttabq"; echo "warte 2"; echo "foto 05-hover-selected"
        echo "fahre 900,700"; echo "warte 2"; echo "foto 06-hover-none"
        echo "halteauf srecttabl"; echo "warte 1"; echo "foto 07-down-other"
        echo "fahre 900,700"; echo "loslassen"; echo "warte 2"
      fi
      echo "taste ctrl-f"; echo "tippe sound"; echo "warte 3"; echo "foto 03-search"
    fi
  } > "$DREH"
  export DESIGNBUILD="${DESIGNBUILD:-$D-build}"
  bash tools/design/audit.sh "$D" accel=kvm uitrace=yes halt=420 res=$RES mode=$MODE sidebar=$SIDE drehbuch="$DREH" > "$D.log" 2>&1
  echo "== $cfg ($RES $MODE $SIDE)"
  python3 -I tools/settingswin11/check.py "$cfg" "$D/serial.txt" "$D" || total_fail=$((total_fail+1))
  rm -rf "$D-build" "$DREH"
  unset DESIGNBUILD
done
echo "SETTINGSWIN11: $total_fail config(s) failed"
[ "$total_fail" = 0 ]
