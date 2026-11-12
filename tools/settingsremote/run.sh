#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/settingsremote/run.sh -- Settings "Remote desktop" page (R_XREMOTE 35, route settings://privacy/remote-desktop).
#
#   /root/jarvis/bin/heavy bash tools/settingsremote/run.sh [<outdir>] [scale=1|2]
#
# One boot of the design-audit machine (no bus): open Settings, find the page with the search field, click the switch.
# check.py judges the serial log and the screenshot (pixels of the switch and of the label rows) and proves itself red
# on doctored logs and on a blank picture.
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:-}
if [ -z "$OUT" ]; then OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT; fi
shift || true
SCALE=1
for a in "$@"; do case "$a" in scale=*) SCALE=${a#scale=} ;; esac; done
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
  echo "taste ctrl-f"; echo "tippe remote desktop"; echo "warte 3"
  echo "taste ret"; echo "warte 4"
  echo "taste ctrl-f"; echo "warte 3"
  echo "foto 01-remote"
  echo "klickauf srectxrsw"; echo "warte 3"
  echo "foto 02-remote-clicked"
} > "$DREH"
export AUDIT_TIMEOUT="${AUDIT_TIMEOUT:-1700}"
export DESIGNBUILD="${DESIGNBUILD:-$OUT/build}"
bash tools/design/audit.sh "$D" accel=kvm uitrace=yes uiscale="$SCALE" halt=300 drehbuch="$DREH" > "$OUT/audit.log" 2>&1
python3 -I tools/settingsremote/check.py "$D/serial.txt" "$D" "$SCALE"
rc=$?
rm -rf "$OUT/build" "$DREH"
exit $rc
