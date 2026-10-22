#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/settingssound/run.sh -- Settings Sound page + ranked search result list (SND-1, SET-12).
#
#   /root/jarvis/bin/heavy bash tools/settingssound/run.sh [<outdir>]
#
# One QEMU boot with a sound card (tools/design/audit.sh ton=ja): open Settings, open the Sound page (tab 29), click the volume
# slider, the speaker mute toggle and the microphone mute toggle, then search "sound" (Ctrl+F) and look at the result list.
# Settings prints `settings: sound <what> v=<value> rc=<syscall result>` after every change and `settings: results n=<k> top=<page> r0=<page>..`
# after every build. tools/settingssound/check.py judges and proves itself red on doctored copies of the log.
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
  echo "klickauf srecttab29"; echo "warte 3"; echo "foto 01-sound"
  echo "klickauf srectsvol"; echo "warte 2"
  echo "klickauf srectsmute"; echo "warte 2"
  echo "klickauf srectsmic"; echo "warte 2"; echo "foto 02-sound-changed"
  echo "taste ctrl-f"; echo "tippe sound"; echo "warte 3"; echo "foto 03-search"
  echo "taste ret"; echo "warte 3"; echo "foto 04-opened"
} > "$DREH"
export AUDIT_TIMEOUT="${AUDIT_TIMEOUT:-1700}"
export DESIGNBUILD="${DESIGNBUILD:-$OUT/build}"
bash tools/design/audit.sh "$D" accel=kvm uitrace=yes ton=ja halt=420 drehbuch="$DREH" > "$OUT/audit.log" 2>&1
python3 -I tools/settingssound/check.py "$D/serial.txt" "$D"
rc=$?
rm -rf "$OUT/build" "$DREH"
exit $rc
