#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/navshell/run.sh -- Settings shell on the route table (r1455/r1456): sidebar, back/forward/up, breadcrumbs, search by route.
#
#   /root/jarvis/bin/heavy bash tools/navshell/run.sh [<outdir>]
#
# One QEMU boot (tools/design/audit.sh, 1280x800): open Settings, click Themes in the sidebar, Up, Back, Back, Forward, a breadcrumb,
# then type a search word and press Enter. Settings prints `settings: nav route=... page= crumbs= back= fwd= up= depth= side= hits= rawkeys=`
# and the rects navback / navfwd / navup / navcrumb<a..> / tab<a..>. tools/navshell/check.py judges the serial log and the pictures,
# and proves itself red on doctored copies of the log (counter-proof).
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=${1:-}
if [ -z "$OUT" ]; then OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT; fi
mkdir -p "$OUT"
D="$OUT/run"
mkdir -p "$D"
DREH="$OUT/drehbuch.txt"
{
  echo "warte 12"
  echo "klick 24,780"; echo "warte 3"
  echo "klickauf start_Settings"; echo "warte 12"
  echo "warteauf settings: nav route=settings://personalization page=0 || 90"
  echo "foto 00-start"
  echo "marke settings: nav route="
  echo "klickauf srecttabh"; echo "warteneu settings: nav route=settings://personalization/themes page=7 || 30"
  echo "warte 2"; echo "foto 01-themes"
  echo "marke settings: nav route="
  echo "klickauf srectnavup"; echo "warteneu settings: nav route=settings://personalization page=0 || 30"
  echo "warte 2"; echo "foto 02-up"
  echo "marke settings: nav route="
  echo "klickauf srectnavback"; echo "warteneu settings: nav route=settings://personalization/themes page=7 || 30"
  echo "warte 2"; echo "foto 03-back"
  echo "marke settings: nav route="
  echo "klickauf srectnavback"; echo "warteneu settings: nav route=settings://personalization page=0 || 30"
  echo "warte 2"
  echo "marke settings: nav route="
  echo "klickauf srectnavfwd"; echo "warteneu settings: nav route=settings://personalization/themes page=7 || 30"
  echo "warte 2"; echo "foto 04-forward"
  echo "marke settings: nav route="
  echo "klickauf srectnavcrumbb"; echo "warteneu settings: nav route=settings://personalization page=0 || 30"
  echo "warte 2"; echo "foto 05-crumb"
  echo "klickauf srectwdu"; echo "warte 1"
  echo "tippe power"; echo "warte 3"; echo "foto 06-search"
  echo "marke settings: nav route="
  echo "taste ret"; echo "warteneu settings: nav route=settings://system/power page=16 || 30"
  echo "warte 2"; echo "foto 07-result"
  echo "marke settings: nav route="
  echo "klickauf srecttabb"; echo "warteneu settings: nav route=settings://display page=1 || 30"
  echo "warte 2"; echo "foto 08-display"
  echo "marke settings: nav route="
  echo "klickauf srecttabt"; echo "warteneu settings: nav route=settings://display/advanced page=19 || 30"
  echo "warte 2"; echo "foto 09-advanced"
} > "$DREH"
export DESIGNBUILD="${DESIGNBUILD:-$OUT/build}"
bash tools/design/audit.sh "$D" accel=kvm uitrace=yes halt=420 res=1280x800 drehbuch="$DREH" > "$OUT/audit.log" 2>&1
python3 -I tools/navshell/check.py "$D/serial.txt" "$D"
rc=$?
rm -rf "$OUT/build" "$DREH"
exit $rc
