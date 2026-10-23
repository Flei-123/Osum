#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/settingstp/run.sh -- Settings Touchpad page (W-TPSET4, page 30, keys K_TP_*).
#
#   /root/jarvis/bin/heavy bash tools/settingstp/run.sh [<outdir>]
#
# One boot (tools/design/audit.sh): open Settings, open the Touchpad page (tab 30), click tap, natural scrolling, the speed
# slider and the 3-finger swipe toggle. Settings prints `settings: touchpad v0,..,v10 i=<n> ok=<0|1>` after every change
# (table order: tap tap2 drag corner natural scroll momentum pinch speed swipe3 swipe4). check.py judges and proves itself
# red on doctored copies of the log.
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:-}
if [ -z "$OUT" ]; then OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT; fi
mkdir -p "$OUT"
D="$OUT/run"
mkdir -p "$D"
DREH="$OUT/drehbuch.txt"
YRES=800
{
  echo "warte 12"
  echo "klick 24,$((YRES-20))"; echo "warte 3"
  echo "klickauf start_Settings"; echo "warte 12"
  echo "warteauf settings: nav route=settings://personalization page=0 || 90"
  echo "klickauf srecttab30"; echo "warte 3"; echo "foto 01-touchpad"
  echo "klickauf srecttptap"; echo "warte 2"
  echo "klickauf srecttpnat"; echo "warte 2"
  echo "klickauf srecttpspd"; echo "warte 2"
  echo "klickauf srecttpsw3"; echo "warte 2"; echo "foto 02-touchpad-changed"
} > "$DREH"
export AUDIT_TIMEOUT="${AUDIT_TIMEOUT:-1700}"
export DESIGNBUILD="${DESIGNBUILD:-$OUT/build}"
bash tools/design/audit.sh "$D" accel=kvm uitrace=yes halt=420 drehbuch="$DREH" > "$OUT/audit.log" 2>&1
python3 -I tools/settingstp/check.py "$D/serial.txt" "$D"
rc=$?
rm -rf "$OUT/build" "$DREH"
exit $rc
