#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/settingsaudit/run.sh -- settings audit: one screenshot per page for ALL 33 pages + serial trace for runtime.py.
#
#   /root/jarvis/bin/heavy bash tools/settingsaudit/run.sh [<outdir>] [mode=light|dark] [scale=1|2]
#   AUDIT_PAGES=1,32,19 limits the run to those page numbers (shorter run, needs less halt=)
#
# It boots the design-audit machine (tools/design/audit.sh), opens Settings, clicks every sidebar page
# (rect names srecttab* = pages; `klicksuche` scrolls the sidebar until the tab has a rectangle; child pages are opened through their parent page first), types a search that matches nothing, takes a picture each time and
# prints the per-page control count of the scene tree (tools/settingsaudit/runtime.py).
# Pass `halt=900` (20 pages need more than the default 420 s). The outdir keeps serial.txt and the *.ppm pictures;
# convert them for docs with `python3 -I tools/settingsaudit/ppm2png.py <outdir> docs/img/settings 60`.
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:-}
if [ -z "$OUT" ]; then OUT=$(mktemp -d); trap 'rm -rf "$OUT" "$OUT-build"' EXIT; fi
shift || true
export AUDIT_TIMEOUT="${AUDIT_TIMEOUT:-1700}"
export DESIGNBUILD="${DESIGNBUILD:-$OUT-build}"
DREH="$OUT-drehbuch.txt"
# the start button sits 20 px above the bottom edge of the screen (default 1280x800)
YRES=800
for a in "$@"; do case "$a" in res=*) r=${a#res=}; YRES=${r#*x} ;; esac; done
python3 -I tools/settingsaudit/script.py kernel/user/settings.d/settings.pagemap "$YRES" "${AUDIT_PAGES:-}" > "$DREH"
bash tools/design/audit.sh "$OUT" accel=kvm uitrace=yes halt=420 drehbuch="$DREH" "$@" > "$OUT.log" 2>&1
echo "serial: $OUT/serial.txt"; python3 -I tools/settingsaudit/runtime.py "$OUT/serial.txt"
python3 -I tools/settingsaudit/declared.py "$OUT/serial.txt" kernel/user/settings.d/settings.routes kernel/user/settings.d/settings.pagemap --check
exit 0
