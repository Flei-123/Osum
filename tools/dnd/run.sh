#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/dnd/run.sh -- W-DND: drag and drop in the window server. Start through /root/jarvis/bin/heavy.
#
# Boots the stick's machine, starts an Explorer, and drives REAL mouse events (QEMU monitor): a drag without payload (control),
# a file drag + Esc, a file drag held over the taskbar's Terminal button, a file drag held over a background Terminal window and
# released there. The kernel reports `wm: dndcancel`, `taskbar: dndraise`, `wm: dndraise`, `wm: dndterm`; tools/dnd/dnd.py judges.
# Counter-proof: origin/main before W-DND has none of those lines. DND_KEEP=<dir> keeps serial + screenshots (png).
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
export DESIGNBUILD="$TMPD/build"
bash tools/design/eh6.sh "$TMPD/run" accel=kvm drehbuch=${DND_SCRIPT:-tools/dnd/dnd.txt} > "$TMPD/run.log" 2>&1
S="$TMPD/run/serial.txt"
if [ -n "${DND_KEEP:-}" ]; then
    mkdir -p "$DND_KEEP"; cp "$S" "$TMPD/run.log" "$DND_KEEP/"
    for n in "$TMPD"/run/*.ppm; do [ -s "$n" ] && python3 tools/design/ppm2png.py "$n" "$DND_KEEP/$(basename "$n" .ppm).png" > /dev/null 2>&1; done
fi
tail -2 "$TMPD/run.log"
python3 tools/dnd/dnd.py "$S"; rc=$?
echo "DND-GATE: exit $rc"
exit $rc
