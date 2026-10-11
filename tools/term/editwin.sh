#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/term/editwin.sh -- r543: console apps (the "Editor" bundle -> /bin/edit) open in their OWN terminal window.
# Start through /root/jarvis/bin/heavy. Boots the stick's machine WITH /bin/term, starts Editor, Editor+ and Terminal from the
# start menu and reads every terminal window's cells from the serial line. `nowrap` = counter-proof (the old plain bundle start).
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
export DESIGNBUILD="$TMPD/build"
[ "${1:-}" = "nowrap" ] && export OSUM_NOCONSOLE=1
bash tools/design/eh6.sh "$TMPD/run" accel=kvm moreprogs="term termfull nedit" drehbuch=tools/term/editwin.txt > "$TMPD/run.log" 2>&1
S="$TMPD/run/serial.txt"
if [ -n "${EDITWIN_KEEP:-}" ]; then
    mkdir -p "$EDITWIN_KEEP"; cp "$S" "$TMPD/run.log" "$EDITWIN_KEEP/"
    for n in "$TMPD"/run/*.ppm; do python3 tools/design/ppm2png.py "$n" "$EDITWIN_KEEP/$(basename "$n" .ppm).png" > /dev/null 2>&1; done
fi
tail -2 "$TMPD/run.log"
grep -a "launcher: start\|term:" "$S" | head -12
python3 tools/term/editwin.py "$S"; rc=$?
echo "TERM-EDITWIN: exit $rc"
exit $rc
