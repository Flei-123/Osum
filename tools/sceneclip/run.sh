#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/sceneclip/run.sh -- r379: THE CLIPBOARD OF A TEXT FIELD IN A SCENE WINDOW.
#
#   bash tools/sceneclip/run.sh [<out dir>]
#
# Until r379 a field of the scene host could be typed into and nothing else:
# Ctrl+C, Ctrl+X and Ctrl+V did nothing (the wlib fields had them, K15 section
# 7). Measured on scenedemo (a text field "Hallo", a SECRET field holding the
# canary GEHEIMNIS7), through real keys over the QEMU monitor:
#
#   copy     Ctrl+A, Ctrl+C, x (replaces the selection), Ctrl+V -> xHallo
#   cut      Ctrl+A, Ctrl+X empties the field, Ctrl+V brings it back
#   replace  Ctrl+A, Ctrl+V replaces everything by the clipboard
#   secret   Ctrl+A, Ctrl+C in the SECRET field copies NOTHING: the clipboard
#            still holds the old text, and the canary appears nowhere
#   counter  Ctrl+C without a selection copies nothing
set -uo pipefail
cd "$(dirname "$0")/../.."
ROOT=$(pwd)
export FIRNLIB="$ROOT/lib"
[ -w /dev/kvm ] && export OSUM_ACCEL=kvm
OUT=${1:-$(mktemp -d)}
[ -n "${1:-}" ] || trap 'rm -rf "$OUT"' EXIT
mkdir -p "$OUT"
pass=0; fail=0
. "${FIRN:-/root/firn}/tools/testkit/testkit.sh"
keys() { local m=""; for c in "$@"; do m="$m mon=sendkey\\ $c mon=warte\\ 1"; done; echo "$m"; }
run() { # name keys...
    local nm=$1; shift
    eval bash tools/alltag/build.sh "$OUT/$nm" kbd=yes uitrace=yes warten=10 bloecke=32768 \
        extra=\"wigapp=/bin/scenedemo wighalt=100\" progs=\"scenedemo theme sh echo ls cat\" \
        $(keys "$@") > "$OUT/$nm.log" 2>&1
}
last() { grep -a 'scenedemo: entry=' "$OUT/$1/serial.txt" | tail -1 | sed 's/.*entry=//' | tr -d '\r'; }

# the text field is the sixth stop of the Tab chain (menu bar 2, tabs 3), the
# secret field the seventh
T6="tab tab tab tab tab tab"
# copy: Ctrl+A selects all, a typed character replaces the selection, Ctrl+V
# brings the copy back next to it
run c1 $T6 ctrl-a ctrl-c x ctrl-v ret
r=$(last c1); [ "$r" = "xHallo" ] && ok "copy, replace by 'x', paste: '$r'" || bad "copy + paste: '$r', expected xHallo"
# cut and paste back
run c2 $T6 ctrl-a ctrl-x ret ctrl-v ret
n=$(grep -a 'scenedemo: entry=' "$OUT/c2/serial.txt" | sed 's/.*entry=//' | tr -d '\r' | tr '\n' '|')
[ "$n" = "|Hallo|" ] && ok "cut empties the field, paste brings it back ($n)" || bad "cut/paste: '$n', expected '|Hallo|'"
# replace the selection by the clipboard
run c3 $T6 ctrl-a ctrl-c x ctrl-a ctrl-v ret
r=$(last c3); [ "$r" = "Hallo" ] && ok "paste over a selection replaces it: '$r'" || bad "replace: '$r', expected Hallo"
# the secret field gives nothing out
run c4 $T6 ctrl-a ctrl-c tab ctrl-a ctrl-c shift-tab ctrl-a ctrl-v ret
r=$(last c4); [ "$r" = "Hallo" ] && ok "Ctrl+C in the SECRET field copied nothing (clipboard still 'Hallo'): '$r'" || bad "secret copy: '$r'"
n=$(grep -ac 'GEHEIMNIS7' "$OUT/c4/serial.txt")
[ "$n" = 0 ] && ok "the canary appears nowhere on the serial line: $n" || bad "the canary appears $n times"
# counter-proof: no selection, nothing is copied
run c5 $T6 x ctrl-c ctrl-v ret
r=$(last c5)
[ "$r" = "Hallox" ] && ok "COUNTER-PROOF: Ctrl+C without a selection copies nothing (paste adds nothing: '$r')" || bad "no-selection copy: '$r', expected Hallox"

echo; echo "SCENECLIP: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
