#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/winopts/run.sh -- W-WINOPTS stage 1 (docs/APP-WINDOW-OPTS.md): WINDOW OPTIONS WORD AND THE WINDOW'S OWN OPACITY (WS_OPAC).
#
#   bash tools/winopts/run.sh        (start it through /root/jarvis/bin/heavy)
#
# /bin/winopts (kernel/user/winopts.fi) runs in the desktop image and prints one serial line `winopts: <name> <a> <b>` per probe:
#   1. wlib.window_opts makes a window frameless + keys + opacity 128 in ONE call; the opacity reads back, the client area starts at
#      the window corner; the default wlib.window keeps 255 and its frame (counter-proof: nothing changed for old callers)
#   2. WS_OPAC sets 0 / 255 / 77 and reads back; 256, 2^32 and -1 are refused with E_INVALID (4) and change nothing
#   3. an options word with an unknown bit (0x10, 1<<16) is refused with E_INVALID and makes no window
#   4. every handle number the program does not own is refused by WS_OPAC (a foreign window cannot be named), our windows keep theirs
#   5. as uid 1000: L_TOP is still refused with E_RIGHTS (2) (as root it is allowed), L_NORMAL is allowed, window_opts and WS_OPAC work
set -uo pipefail
cd "$(dirname "$0")/../.."
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
pass=0; fail=0
export CAPTURE_TIME=${CAPTURE_TIME:-1760000000}
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

val() { # val <serial> <name> <field 3|4>   the last line "winopts: name a b"
    grep -a "^winopts: $2 " "$1" | tail -1 | awk -v f="$3" '{print $f}'
}
eq() { # eq <serial> <name> <field> <expected> <text>
    local v; v=$(val "$1" "$2" "$3")
    if [ "$v" = "$4" ]; then ok "$5"; else bad "$5 (got '$v', want '$4')"; fi
}

echo "== build + run /bin/winopts in the desktop =="
bash tools/alltag/build.sh "$D/w1" kbd=no accel=kvm shot=no uitrace=no \
    "extra=wigapp=/bin/winopts wighalt=25" progs="winopts sh echo" > "$D/w1.log" 2>&1
S="$D/w1/serial.txt"
if [ ! -s "$S" ]; then
    grep -a "FEHLGESCHLAGEN\|error" "$D/w1.log" | head -5
    bad "no serial output"
fi
grep -a '^winopts:' "$S" | sed 's/^/        /'

echo "== 1. window_opts: one call, three options =="
eq "$S" begin 3 1 "the window library started"
eq "$S" o-make 3 1 "window_opts made a window"
eq "$S" o-opac 3 128 "its opacity reads back as 128"
eq "$S" o-frame 3 0 "frameless: client area at the window corner (x)"
eq "$S" o-frame 4 0 "frameless: client area at the window corner (y)"
eq "$S" d-opac 3 255 "COUNTER-PROOF: the default window is still opaque (255)"
DX=$(val "$S" d-frame 3); DY=$(val "$S" d-frame 4)
{ [ "${DX:-0}" -gt 0 ] || [ "${DY:-0}" -gt 0 ]; } && ok "COUNTER-PROOF: the default window keeps its frame ($DX,$DY)" || bad "the default window lost its frame ($DX,$DY)"

echo "== 2. WS_OPAC: set, read back, range =="
eq "$S" set-0 3 0 "WS_OPAC 0 accepted"
eq "$S" set-0 4 0 "  reads back 0"
eq "$S" set-255 3 0 "WS_OPAC 255 accepted"
eq "$S" set-255 4 255 "  reads back 255"
eq "$S" set-77 3 0 "WS_OPAC 77 accepted"
eq "$S" set-77 4 77 "  reads back 77"
eq "$S" set-256 3 4 "WS_OPAC 256 refused with E_INVALID"
eq "$S" set-256 4 77 "  and the opacity stays 77"
eq "$S" set-big 3 4 "WS_OPAC 2^32 refused with E_INVALID"
eq "$S" set-big 4 77 "  and the opacity stays 77"
eq "$S" set-256k 3 4 "WS_OPAC -1 refused with E_INVALID"
eq "$S" set-256k 4 77 "  and the opacity stays 77"

echo "== 3. unknown option bits =="
eq "$S" bad-bit 3 4 "options word 0x10 refused with E_INVALID"
eq "$S" bad-bit 4 0 "  no window made"
eq "$S" bad-bit0 3 4 "options word 1<<16 refused with E_INVALID"
eq "$S" bad-bit0 4 0 "  no window made"

echo "== 4. foreign windows =="
R=$(val "$S" foreign 3); T=$(val "$S" foreign 4)
[ -n "$R" ] && [ "$R" = "$T" ] && [ "$T" -ge 240 ] && ok "all $R handle numbers that are not ours are refused" || bad "foreign handles refused: '$R' of '$T'"
eq "$S" foreign-keep 3 77 "our window 1 kept its opacity"
eq "$S" foreign-keep 4 255 "our window 2 kept its opacity"

echo "== 5. ordinary user =="
eq "$S" uid0-top 3 0 "as root L_TOP is allowed (the rule is about uid, not about the call)"
eq "$S" setuid 3 1 "setuid(1000) done"
eq "$S" user-top 3 2 "as uid 1000 L_TOP is refused with E_RIGHTS"
eq "$S" user-norm 3 0 "as uid 1000 L_NORMAL is allowed"
eq "$S" user-make 3 1 "as uid 1000 window_opts makes a window"
eq "$S" user-make 4 200 "  with opacity 200"
eq "$S" user-opac 3 0 "as uid 1000 WS_OPAC on the own window works"
eq "$S" user-opac 4 33 "  reads back 33"
eq "$S" done 3 1 "winopts ran to the end"

echo
echo "winopts: OK=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
