#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/term/scroll.sh -- r838: the terminal window keeps the lines that scroll off the top (256 per window) and the mouse
# wheel moves the view through them. Start through /root/jarvis/bin/heavy.
#
# Boots the stick's machine, prints 40 marker lines (`sbmark-NN`), wheels up/far up/down/up and presses Esc; the kernel
# window reports `wm: termsb lines=N view=V` and the rows of a scrolled view (`wm: termview R [text]`) on the serial line.
# Counter-proof: on origin/main of 15.10.2026 (no scrollback) there is no `termsb` line and the wheel does nothing.
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
export DESIGNBUILD="$TMPD/build"
bash tools/design/eh6.sh "$TMPD/run" accel=kvm drehbuch=tools/term/scroll.txt > "$TMPD/run.log" 2>&1
S="$TMPD/run/serial.txt"
if [ -n "${SCROLL_KEEP:-}" ]; then
    mkdir -p "$SCROLL_KEEP"; cp "$S" "$TMPD/run.log" "$SCROLL_KEEP/"
    for n in "$TMPD"/run/*.ppm; do [ -s "$n" ] && python3 tools/design/ppm2png.py "$n" "$SCROLL_KEEP/$(basename "$n" .ppm).png" > /dev/null 2>&1; done
fi
tail -2 "$TMPD/run.log"
python3 tools/term/scroll.py "$S"; rc=$?
echo "TERM-SCROLL: exit $rc"
exit $rc
