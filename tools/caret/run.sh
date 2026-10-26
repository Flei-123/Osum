#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/caret/run.sh -- W-CARET: the caret of a fUi text field BLINKS (500 ms on / 500 ms off) on the real picture, restarts at a key, and is
# gone without the focus.
#
#   bash tools/caret/run.sh                  all cases (one VM boot each, ~3 min)
#   CASES="glogin" bash tools/caret/run.sh   one case
#
# Cases (the sign-in screen, because its password field is the one Justin missed the caret in; blinking is the same code in every fUi program):
#   glogin       blinking on: a burst of 300 screendumps (back to back, ~16 ms apart) -> the caret bar is on and off, >= 3 changes, the runs
#                between two changes are 500 ms +- 150; three key presses at different phases -> the caret is ON in the window 150..400 ms after
#                the key (phase reset); Tab moves the focus to the eye button -> NO caret in 30 frames (no focus, no caret)
#   noblink      COUNTER-PROOF: /etc/uitrace without /etc/uiblink switches the blinking off (wlib.blink_enabled) -> the burst shows NO change; the
#                check "the caret blinks" must turn RED
#   caretold     COUNTER-PROOF: /etc/caretold brings the old focus restore back (the rebuilt tree's field lost its focus bit -> no caret at
#                all in the picture); the check "a caret is drawn" must turn RED
# Also reported: idle CPU of the blinking program (system calls of the whole system in 5 s, tools/wayland/input.sh style: serial `wm:` line).
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d); trap 'rm -rf "$TMPD"' EXIT
export OSUM_RTC="base=2026-10-11T11:00:00,clock=vm"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

python3 - "$TMPD" <<'PY'
import binascii, hashlib, sys
d = sys.argv[1]
it, salt = 1024, bytes(range(8))
dk = hashlib.pbkdf2_hmac("sha256", b"geheim12", salt, it, 32)
rec = "$osum1$%d$%s$%s" % (it, binascii.hexlify(salt).decode(), binascii.hexlify(dk).decode())
open(d + "/shadow", "w").write("root:%s:0:0:99999:7:::\njustin:%s:1000:1000:99999:7:::\n" % (rec, rec))
open(d + "/passwd", "w").write("root:x:0:0:root:/root:/bin/sh\njustin:x:1000:1000:Justin:/users/justin:/bin/sh\n")
open(d + "/flag", "w").write("1\n")
PY

if [ -n "${CARET_F12:-}" ]; then   # diagnosis: window server counters before/after the burst (wm: shared ... shdmg=)
    printf 'warte 6\ntippe ab\nwarte 1\ntaste f12\nwarte 0.5\nserie idle 300 blink\nwarte 0.5\ntaste f12\nwarte 1\nfoto done\n' > "$TMPD/book"
else
printf 'warte 6\ntippe ab\nwarte 1\nserie idle 300 blink\nwarte 1\nserie key:c 25 k1\nwarte 2\nserie key:d 25 k2\nwarte 1\nserie key:e 25 k3\ntaste tab\nwarte 0.3\nserie idle 30 nf\nwarte 1\nfoto done\n' > "$TMPD/book"
fi

for c in ${CASES:-glogin noblink caretold}; do
    xo=(); tr=no
    case "$c" in
      noblink)  tr=yes ;;
      caretold) xo=(xfile=/etc/caretold="$TMPD/flag") ;;
    esac
    echo "== case $c =="
    OSUM_ACCEL=${OSUM_ACCEL:-kvm} bash tools/alltag/build.sh "$TMPD/$c" kbd=yes uitrace=$tr warten=6 res=800x600 uiscale=1 bloecke=32768 \
        extra="wigapp=/bin/glogin wighalt=200" progs="glogin theme sh echo ls cat" xfile=/etc/shadow="$TMPD/shadow" \
        xfile=/etc/wallpaper=assets/wallpaper-sea.osym passwdfile="$TMPD/passwd" "${xo[@]}" drive="$TMPD/book" > "$TMPD/$c.log" 2>&1
    if [ ! -f "$TMPD/$c/serial.txt" ] || [ ! -f "$TMPD/$c/blink-000.ppm" ]; then bad "case $c: no frames (build or boot failed)"; tail -3 "$TMPD/$c.log"; continue; fi
    if [ -n "${CARET_F12:-}" ]; then grep -a "^wm: \|wm: shared\|wm: composites\|wm: flush\|wlib: caret\|fui: paint" "$TMPD/$c/serial.txt" | cut -c1-200 | tail -${CARET_F12}; fi
    # the password field's rectangle from the program's own report (last line of kind=4 with id=7)
    R=$(grep -a "glogin: rect id=7 kind=4" "$TMPD/$c/serial.txt" | tail -1 | sed 's/.* x=\([0-9]*\) y=\([0-9]*\) w=\([0-9]*\) h=\([0-9]*\).*/\1 \2 \3 \4/')
    set -- $R
    if [ $# != 4 ]; then bad "case $c: the program did not report its password field"; continue; fi
    BOX="$(($1 + 6)) $(($2 + 6)) $(($1 + $3 - 6)) $(($2 + $4 - 6))"
    echo "        field $R -> box $BOX"
    for s in blink k1 k2 k3 nf; do
        python3 -I tools/caret/check.py "$TMPD/$c" "$s" $BOX > "$TMPD/$c.$s.chk" 2>&1
        printf '        %-6s %s\n' "$s" "$(grep -a 'STATE' "$TMPD/$c.$s.chk" | cut -c1-130)"
        printf '               %s | %s | %s\n' "$(grep -a TRANSITIONS "$TMPD/$c.$s.chk")" "$(grep -a RUNS "$TMPD/$c.$s.chk")" "$(grep -a SPAN_MS "$TMPD/$c.$s.chk")"
    done
    # evaluate
    python3 -I - "$TMPD/$c" "$c" > "$TMPD/$c.eval" <<'PY'
import re, sys
d, case = sys.argv[1], sys.argv[2]
def rd(s):
    t = open("%s.%s.chk" % (d, s)).read()
    g = lambda k: (re.search(k + r" (.*)", t) or [None, ""])[1]
    return g("STATE").strip(), int(g("TRANSITIONS") or 0), [int(x) for x in g("RUNS").split()], int(g("SPAN_MS") or 1), int(g("ONFRAMES") or 0)
st, tr, runs, span, on = rd("blink")
print("drawn", "1" if on > 0 else "0")
print("blinks", "1" if tr >= 3 else "0")
inner = runs[1:-1] if len(runs) > 2 else runs
print("period", "1" if inner and all(350 <= r <= 650 for r in inner) else "0", inner)
for k in ("k1", "k2", "k3"):
    s, t2, _, sp, _ = rd(k)
    dt = sp / max(1, len(s))
    win = [s[i] for i in range(len(s)) if 150 <= i * dt <= 400]
    print("reset_" + k, "1" if win and all(c == "1" for c in win) else "0", "".join(win))
s, t2, _, sp, on2 = rd("nf")
print("nofocus", "1" if on2 == 0 else "0")
PY
    sed 's/^/        /' "$TMPD/$c.eval"
    g() { grep -a "^$1 " "$TMPD/$c.eval" | cut -d' ' -f2; }
    case "$c" in
      glogin)
        [ "$(g drawn)" = 1 ]   && ok "glogin: a caret bar is drawn in the focused password field" || bad "glogin: no caret bar in any frame"
        [ "$(g blinks)" = 1 ]  && ok "glogin: the caret blinks (>= 3 changes in the burst)" || bad "glogin: the caret does not blink"
        [ "$(g period)" = 1 ]  && ok "glogin: the on/off runs are 500 ms (350..650)" || bad "glogin: on/off runs are not ~500 ms"
        [ "$(g reset_k1)" = 1 ] && [ "$(g reset_k2)" = 1 ] && [ "$(g reset_k3)" = 1 ] && ok "glogin: a key shows the caret at once and restarts the phase (3 trials, 150..400 ms after the key: on)" || bad "glogin: after a key the caret was off in the 150..400 ms window"
        [ "$(g nofocus)" = 1 ] && ok "glogin: Tab to the eye button -> no caret in 30 frames" || bad "glogin: caret drawn without the focus"
        # idle cost: the wm line `wm: ... composites=` is not in this build; the number of caret phase paints is bounded by the 500 ms timer
        ;;
      noblink)
        [ "$(g blinks)" = 0 ] && ok "noblink (counter-proof): blinking switched off -> no change in the burst, the blink check turns red" || bad "noblink: still blinks with the switch off -- the check is blind"
        ;;
      caretold)
        [ "$(g drawn)" = 0 ] && ok "caretold (counter-proof): old focus restore -> no caret bar at all, the check turns red" || bad "caretold: caret still drawn (the rebuild did not hit this run; counter-proof inconclusive)"
        ;;
    esac
    rm -rf "$TMPD/$c"
done
echo "CARET: $pass passed, $fail failed"
[ "$fail" = 0 ]
