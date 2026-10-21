#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/settingsaudit/run.sh -- settings audit: one screenshot per page for ALL 20 pages (a..t) + serial trace for runtime.py.
#
#   /root/jarvis/bin/heavy bash tools/settingsaudit/run.sh [<outdir>] [mode=light|dark] [scale=1|2]
#
# It boots the design-audit machine (tools/design/audit.sh), opens Settings, clicks every sidebar page
# (rect names taba..tat = pages 0..19), types a search that matches nothing, takes a picture each time and
# prints the per-page control count of the scene tree (tools/settingsaudit/runtime.py).
# Pass `halt=900` (20 pages need more than the default 420 s). The outdir keeps serial.txt and the *.ppm pictures;
# convert them for docs with `python3 -I tools/settingsaudit/ppm2png.py <outdir> docs/img/settings 60`.
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:-}
if [ -z "$OUT" ]; then OUT=$(mktemp -d); trap 'rm -rf "$OUT" "$OUT-build"' EXIT; fi
shift || true
export DESIGNBUILD="${DESIGNBUILD:-$OUT-build}"
DREH="$OUT-drehbuch.txt"
# the start button sits 20 px above the bottom edge of the screen (default 1280x800)
YRES=800
for a in "$@"; do case "$a" in res=*) r=${a#res=}; YRES=${r#*x} ;; esac; done
{
  echo "warte 12"
  echo "klick 24,$((YRES-20))"; echo "warte 3"
  echo "klickauf start_Settings"; echo "warte 12"
  echo "foto 00-start"
  for p in a b c d e f g h i j k l m n o p q r s t u v w x; do
    echo "klickauf srecttab$p"; echo "warte 2"; echo "foto page-$p"
  done
  echo "taste ctrl-f"; echo "tippe zzzz"; echo "warte 2"; echo "foto search-empty"
} > "$DREH"
bash tools/design/audit.sh "$OUT" accel=kvm uitrace=yes halt=420 drehbuch="$DREH" "$@" > "$OUT.log" 2>&1
echo "serial: $OUT/serial.txt"; python3 -I tools/settingsaudit/runtime.py "$OUT/serial.txt"
exit 0
