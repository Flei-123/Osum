#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/settingsmode/run.sh -- Settings Network page: address fields only in manual mode (SET-10/11).
#
#   /root/jarvis/bin/heavy bash tools/settingsmode/run.sh [<outdir>] [res=WxH]
#
# One QEMU boot (tools/design/audit.sh): open Settings, open Network (the machine has no carrier: starts on the fixed address),
# pick Automatic in the mode dropdown, pick the fixed address again.
# Settings prints `settings: controls page=3 n=<count>` after every page build and the rect of every control.
# tools/settingsmode/check.py judges: manual = N+3 controls (IP, mask, gateway entries), automatic = N, manual again = N+3,
# the entry rects appear in manual mode, and it proves itself red on doctored copies of the log (counter-proof).
# The default window is 800x480 (low): the sidebar cannot show every tab there; picture 05 (last tab opened by its rect) is the look
# at the sidebar reveal (a search filters the sidebar, so it cannot test scrolling).
# Load-proof (r1611): every step waits for the state it needs (`settings: menu open`, the next `settings: controls`, the
# rebuilt tab rects) instead of a fixed delay; the script ends the machine itself (`monitor quit`), halt= is only the ceiling (SM_HALT).
# Pictures: 01..06 in the run folder; pass res=1280x800 for the roomy window.
set -uo pipefail
cd "$(dirname "$0")/../.."
OUT=""
RES=800x480
for a in "$@"; do case "$a" in res=*) RES=${a#res=} ;; *) OUT=$a ;; esac; done
if [ -z "$OUT" ]; then OUT=$(mktemp -d); trap 'rm -rf "$OUT"' EXIT; fi
mkdir -p "$OUT"
D="$OUT/run"
mkdir -p "$D"
DREH="$OUT/drehbuch.txt"
YRES=${RES#*x}
{
  echo "warteauf taskbar: start x= || 420"
  echo "warte 8"
  echo "klick 24,$((YRES-20))"; echo "warte 3"
  echo "klickauf start_Settings"; echo "warte 12"
  echo "warteauf settings: nav route=settings://personalization page=0 || 150"
  echo "marke settings: controls page=3"
  echo "klickauf srecttabd"; echo "warteneu settings: controls page=3 || 90"
  echo "warte 2"; echo "foto 01-auto"
  echo "marke settings: menu open"
  echo "klickauf srectwco"; echo "warteneu settings: menu open || 60"
  echo "warte 1"; echo "foto 02-popup"
  echo "taste up"; echo "warte 1"
  echo "marke settings: controls page=3"
  echo "taste ret"; echo "warteneu settings: controls page=3 || 90"
  echo "warte 2"; echo "foto 03-auto"
  echo "marke settings: menu open"
  echo "klickauf srectwco"; echo "warteneu settings: menu open || 60"
  echo "warte 1"
  echo "taste down"; echo "warte 1"
  echo "marke settings: controls page=3"
  echo "taste ret"; echo "warteneu settings: controls page=3 || 90"
  echo "warte 2"; echo "foto 04-manual-again"
  echo "marke settings: stand reiter=28"
  echo "klickauf srecttab28"; echo "warteneu settings: stand reiter=28 || 90"
  echo "warte 2"; echo "foto 05-last-tab"
  echo "monitor quit"
} > "$DREH"
export AUDIT_TIMEOUT="${AUDIT_TIMEOUT:-1700}"
export DESIGNBUILD="${DESIGNBUILD:-$OUT/build}"
bash tools/design/audit.sh "$D" accel=kvm uitrace=yes halt=${SM_HALT:-1500} res=$RES drehbuch="$DREH" > "$OUT/audit.log" 2>&1
python3 -I tools/settingsmode/check.py "$D/serial.txt" "$D"
rc=$?
rm -rf "$OUT/build" "$DREH"
exit $rc
