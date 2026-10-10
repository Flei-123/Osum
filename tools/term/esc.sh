#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/term/esc.sh -- r537: the first command after a stray ESC (or arrow keys) used to fail with `sh: cannot run ... -> -2`
# ("no such file": the name was `/bin/<ESC>ls`). Start through /root/jarvis/bin/heavy. Boots the stick's machine, sends Esc,
# Up Up and Esc Esc in front of three `echo` commands and `ls /etc`, and reads the serial line.
# Counter-proof: run it on a tree without the sh.fi change (origin/main of 10.10.2026) -- the three echo checks fail.
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
export DESIGNBUILD="$TMPD/build"
bash tools/design/eh6.sh "$TMPD/run" accel=kvm drehbuch=tools/term/esc.txt > "$TMPD/run.log" 2>&1
S="$TMPD/run/serial.txt"
if [ -n "${ESC_KEEP:-}" ]; then mkdir -p "$ESC_KEEP"; cp "$S" "$ESC_KEEP/"; fi
tail -2 "$TMPD/run.log"
grep -a "cannot run\|elf: refused" "$S" | head -5
python3 tools/term/esc.py "$S"; rc=$?
echo "TERM-ESC: exit $rc"
exit $rc
