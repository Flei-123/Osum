#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/dnd/nedit.sh -- W-FIN-DND: a file dragged from the Explorer and released over a background nedit window opens in the
# editor (hover-raise `wm: dndraise`, then `nedit: drop`). Counter-proof: a drag released over the empty desktop prints no `nedit: drop`.
# Start through /root/jarvis/bin/heavy. DND_KEEP=<dir> keeps serial + screenshots.
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
export DESIGNBUILD="$TMPD/build"
bash tools/design/eh6.sh "$TMPD/run" accel=kvm moreprogs=nedit drehbuch=tools/dnd/nedit.txt > "$TMPD/run.log" 2>&1
S="$TMPD/run/serial.txt"
if [ -n "${DND_KEEP:-}" ]; then
    mkdir -p "$DND_KEEP"; cp "$S" "$TMPD/run.log" "$DND_KEEP/"
    for n in "$TMPD"/run/*.ppm; do [ -s "$n" ] && python3 tools/design/ppm2png.py "$n" "$DND_KEEP/$(basename "$n" .ppm).png" > /dev/null 2>&1; done
fi
tail -2 "$TMPD/run.log"
pass=0; fail=0
chk() { if [ "$2" = "1" ]; then pass=$((pass+1)); echo "  OK    $1"; else fail=$((fail+1)); echo "  FAIL  $1"; fi; }
has() { grep -aq "$1" "$S" && echo 1 || echo 0; }
chk "editor started" "$(has 'nedit: ready')"
chk "hover over the background editor raised it (wm: dndraise)" "$(has 'wm: dndraise')"
chk "the drop reached the editor (nedit: drop)" "$(has 'nedit: drop')"
echo "NEDIT-DND: $pass ok, $fail fail"
[ "$fail" = 0 ]
