#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/term/run.sh -- THE TERMINAL WINDOW MUST EXECUTE THE CONTROL SEQUENCES OF A FULL-SCREEN PROGRAM, NOT PRINT THEM
# (Justin, Dell photo 07.10.2026 19:05: the editor showed `~[19;1H[K`, `[7m`, `[24;1H[K^O Write`, `[?25h[?25l`, `[2;4H`, `[m`).
#
#   bash tools/term/run.sh          (start it through /root/jarvis/bin/heavy)
#
# Boots the desktop (the machine of the stick: tools/design/eh6.sh), clicks into the terminal window, starts `edit /etc/passwd`
# (the editor of this system: cursor addressing `ESC[r;cH`, erase `ESC[K`, reverse video `ESC[7m` ... `ESC[m`, cursor `ESC[?25h/l`)
# and reads what stands in the CELLS of the window (`wm: termzeile N [text]`, one line per row every five seconds), then the
# pictures. The check: no octet of any control sequence is a visible character in any row.
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
export DESIGNBUILD="$TMPD/build"

echo "== 1. boot, open the editor in the terminal window =="
bash tools/design/eh6.sh "$TMPD/run" accel=kvm drehbuch=tools/term/dreh.txt > "$TMPD/run.log" 2>&1
S="$TMPD/run/serial.txt"
for n in 01-edit-open 02-edit-typed 03-edit-write 04-edit-closed; do
    [ -s "$TMPD/run/$n.ppm" ] && ok "picture $n taken" || bad "picture $n missing: $(tail -2 "$TMPD/run.log" | tr '\n' ' ')"
done

echo "== 2. what stands in the cells =="
python3 tools/term/check.py "$S" | sed 's/^/        /'
python3 tools/term/check.py "$S" > "$TMPD/check.txt" 2>&1 && ok "no control sequence shows up as text in any row of the window" \
    || bad "control sequences are printed as text: $(grep -a 'RAW' "$TMPD/check.txt" | head -3 | tr '\n' ' ')"
grep -aq 'EDITOR-SCREEN' "$TMPD/check.txt" && ok "the editor's screen was drawn (its help line and status are in the cells)" \
    || bad "the editor's screen is not in the cells"

mkdir -p docs/shots/term
for n in 01-edit-open 02-edit-typed 03-edit-write; do
    [ -s "$TMPD/run/$n.ppm" ] && python3 tools/design/ppm2png.py "$TMPD/run/$n.ppm" "docs/shots/term/$n.png" > /dev/null 2>&1
done

echo
echo "TERM: $pass passed, $fail failed"
[ "$fail" = 0 ]
