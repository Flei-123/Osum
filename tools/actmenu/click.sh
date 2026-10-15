#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/actmenu/click.sh -- D1 UI click gate: Explorer context menu row 14 "Actions" opens the sub menu
# from the action bus, a click on its first row becomes a broker `call` (`explorer: action <name> rc=<n>`).
#
#   /root/jarvis/bin/heavy bash tools/actmenu/click.sh
#
# A  with broker + notes provider: right click on a row -> menu (menurect) -> row 14 -> a second menu
#    (menurect again) -> row 0 -> `explorer: action notes.addfile rc=0`, the broker audit has the call.
# B  (negative control) image WITHOUT broker/notes: the sub menu has only the "(no actions)" row, a click
#    on it does NOTHING (no `explorer: action` line).
# DOES NOT MEASURE: the pixels of the sub menu (screenshots 11-submenu.png are written for a human look).
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
KEEP=${ACTMENU_KEEP:-}

run() { # name moreprogs extra-mkfs
    local O="$TMPD/$1"
    mkdir -p "$O"
    local more=()
    [ -n "$2" ] && more=("moreprogs=$2")
    DESIGNBUILD="$TMPD/build" EH_MKFS_EXTRA="$3" \
        bash tools/design/eh6.sh "$O" accel=kvm "${more[@]}" drehbuch=tools/actmenu/click.txt \
        > "$O.log" 2>&1
    if [ -n "$KEEP" ]; then
        mkdir -p "$KEEP/$1"; cp "$O/serial.txt" "$O.log" "$KEEP/$1/" 2>/dev/null
        for n in "$O"/*.ppm; do [ -s "$n" ] && python3 tools/design/ppm2png.py "$n" "$KEEP/$1/$(basename "$n" .ppm).png" >/dev/null 2>&1; done
    fi
}

NOTES_X="/var/ /var/log/ /apps/ /apps/notes.prog/ /apps/notes.prog/ACTIONS=pakete/notes/ACTIONS@0644"
run A "orientbus notes act" "$NOTES_X"
SA="$TMPD/A/serial.txt"
if [ ! -s "$SA" ]; then bad "A: no serial output"; tail -5 "$TMPD/A.log"; echo "ACTMENU-CLICK: $pass passed, $fail failed"; exit 1; fi
grep -qa 'explorer: ready' "$SA" && ok "A: the explorer started" || bad "A: explorer did not start"
n=$(grep -ac 'explorer: menurect' "$SA")
[ "$n" -ge 2 ] && ok "A: two menus were opened (context + sub menu, $n menurect lines)" || bad "A: only $n menurect line(s) -- row 14 opened no sub menu"
grep -aq 'explorer: action notes.addfile rc=0' "$SA" && ok "A: the pick became a broker call (notes.addfile rc=0)" \
    || bad "A: no 'explorer: action notes.addfile rc=0' ($(grep -a 'explorer: action' "$SA" | tail -1))"

run B "" ""
SB="$TMPD/B/serial.txt"
if [ ! -s "$SB" ]; then bad "B: no serial output"; else
    grep -qa 'explorer: ready' "$SB" && ok "B: the explorer started" || bad "B: explorer did not start"
    nb=$(grep -ac 'explorer: menurect' "$SB")
    [ "$nb" -ge 2 ] && ok "B (control): the sub menu opens even without actions ($nb menurect lines)" || bad "B: only $nb menurect line(s)"
    grep -aq 'explorer: action ' "$SB" && bad "B (control): a click on the empty sub menu ran an action" \
        || ok "B (control): no action without a provider"
fi
echo "ACTMENU-CLICK: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
