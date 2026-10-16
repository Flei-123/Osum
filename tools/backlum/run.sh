#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/backlum/run.sh -- W-WINOPTS S4 (docs/APP-WINDOW-OPTS.md): THE BRIGHTNESS BEHIND A WINDOW (WI_BACKLUM) AND THE TEXT COLOUR DECIDER.
#
#   bash tools/backlum/run.sh        (start it through /root/jarvis/bin/heavy)
#
# /bin/backlum (kernel/user/backlum.fi, generated from tools/backlum/backlum.tpl) runs in the desktop image: a background window B, a RED probe
# window P over it, a white window T over P, a far window U. One serial line `backlum: <name> <a> <b>` per probe; the expected numbers are
# computed HERE with floating point from the sRGB formula (an independent second implementation of what the server does with a Q16 table).
#   1. WI_BACKLUM / _HI / _LO behind P for black, white, grey, red, green, blue, left black + right white, a gradient: within +-8/255 of full
#      scale (2056 of 65536). P is red the whole time: a measurement that included the window itself would be 13933 off on black
#   2. the contrast of the chosen text colour on the worst sample is >= 4.5:1 (450); the gradient has no single colour, the tint repairs it
#   3. a window ABOVE the probe does not count, a window BELOW does
#   4. the cache: repeat = hit, own repaint = hit, far window = hit, repaint of B = one run
#   5. the decider on the live measurement: noisy constant grey -> 0 flips (plain threshold: many), one real change -> 1 flip, a ramp -> 1 flip
set -uo pipefail
cd "$(dirname "$0")/../.."
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
pass=0; fail=0
export CAPTURE_TIME=${CAPTURE_TIME:-1760000000}
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

val() { # val <serial> <name> <field 3|4>   the last line "backlum: name a b"
    grep -a "backlum: $2 " "$1" | tail -1 | sed 's/.*backlum: /backlum: /' | awk -v f="$3" '{print $f}'
}
eq() { # eq <serial> <name> <field> <expected> <text>
    local v; v=$(val "$1" "$2" "$3")
    if [ "$v" = "$4" ]; then ok "$5"; else bad "$5 (got '$v', want '$4')"; fi
}
near() { # near <serial> <name> <field> <expected> <tolerance> <text>
    local v; v=$(val "$1" "$2" "$3")
    if [ -n "$v" ] && python3 -c "import sys; sys.exit(0 if abs(int('$v') - int('$4')) <= int('$5') else 1)"; then ok "$6 ($v, want $4 +-$5)"; else bad "$6 (got '$v', want $4 +-$5)"; fi
}
ge() { # ge <serial> <name> <field> <minimum> <text>
    local v; v=$(val "$1" "$2" "$3")
    if [ -n "$v" ] && [ "$v" -ge "$4" ]; then ok "$5 ($v >= $4)"; else bad "$5 (got '$v', want >= $4)"; fi
}

# the expected values, computed with floating point (the sRGB formula of the standard, not the server's table)
cat > "$D/exp.py" <<'PYEOF'
import sys
def lin(c):
    s = c / 255.0
    return s / 12.92 if s <= 0.04045 else ((s + 0.055) / 1.055) ** 2.4
def lum(rgb):
    return 0.2126 * lin((rgb >> 16) & 255) + 0.7152 * lin((rgb >> 8) & 255) + 0.0722 * lin(rgb & 255)
Q = 65536
def q(x): return int(round(x * Q))
out = {}
for name, c in (("black", 0x000000), ("white", 0xFFFFFF), ("grey", 0x808080), ("red", 0xFF0000), ("green", 0x00FF00), ("blue", 0x0000FF)):
    out["k-" + name] = q(lum(c))
# P covers 160 x 80 at B-local x 120..280; the sampler takes the centres of an 8 x 4 grid of the OUTER rectangle
def grid(x0, y0, w, h):
    return [(x0 + (2 * ix + 1) * w // 16, y0 + (2 * iy + 1) * h // 8) for iy in range(4) for ix in range(8)]
def grey(v): return (v << 16) | (v << 8) | v
# gradient: the exact mean over P's columns, and the sampler's second brightest / second darkest
cols = [lum(grey(x * 255 // 399)) for x in range(120, 280)]
out["grad-mean"] = q(sum(cols) / len(cols))
samples = sorted(lum(grey((x - 100) * 255 // 399)) for (x, y) in grid(220, 160, 160, 80))
out["grad-hi"] = q(samples[-2]); out["grad-lo"] = q(samples[1])
# left black / right white (B-local x >= 200 is white)
s2 = [0.0 if (x - 100) < 200 else 1.0 for (x, y) in grid(220, 160, 160, 80)]
out["two-mean"] = q(sum(s2) / 32); out["two-hi"] = q(sorted(s2)[-2]); out["two-lo"] = q(sorted(s2)[1])
# T (300,200,100x60) over P (220,160,160x80, red) over B (black): what lies behind T
def behind_t(x, y):
    if 220 <= x < 380 and 160 <= y < 240: return 0xFF0000
    return 0x000000
s3 = [lum(behind_t(x, y)) for (x, y) in grid(300, 200, 100, 60)]
out["t-mean"] = q(sum(s3) / 32); out["t-hi"] = q(sorted(s3)[-2])
out["switch"] = q(0.179)
for k, v in out.items():
    print(k, v)
PYEOF
python3 "$D/exp.py" > "$D/exp.txt"
exp() { grep "^$1 " "$D/exp.txt" | awk '{print $2}'; }
TOL=2056

echo "== build + run /bin/backlum in the desktop =="
bash tools/alltag/build.sh "$D/w1" kbd=no accel=kvm shot=no uitrace=no \
    "extra=wigapp=/bin/backlum wighalt=100" progs="backlum sh echo" > "$D/w1.log" 2>&1
S="$D/w1/serial.txt"
if [ ! -s "$S" ]; then
    grep -a "FEHLGESCHLAGEN\|error" "$D/w1.log" | head -5
    bad "no serial output"
fi
[ -n "${BL_KEEP:-}" ] && cp "$S" "$BL_KEEP"
grep -a '^backlum:' "$S" | sed 's/^/        /'

eq "$S" begin 3 1 "the window library started"
eq "$S" make 3 1 "B and P exist"
eq "$S" make 4 1 "  with buffers"

echo "== 1. WI_BACKLUM behind P (P is red all the time) =="
for c in black white grey red green blue; do
    E=$(exp "k-$c")
    near "$S" "k-$c" 3 "$E" $TOL "$c: mean luminance"
    near "$S" "k-$c" 4 "$E" $TOL "$c: second brightest sample"
    near "$S" "k-$c-lo" 3 "$E" $TOL "$c: second darkest sample"
done
near "$S" k-two 3 "$(exp two-mean)" $TOL "left black / right white: mean is the middle"
near "$S" k-two 4 "$(exp two-hi)" $TOL "  second brightest = white"
near "$S" k-two-lo 3 "$(exp two-lo)" $TOL "  second darkest = black"
near "$S" k-grad 3 "$(exp grad-mean)" $TOL "gradient: mean"
near "$S" k-grad 4 "$(exp grad-hi)" $TOL "  second brightest sample"
near "$S" k-grad-lo 3 "$(exp grad-lo)" $TOL "  second darkest sample"

echo "== 2. contrast of the chosen text colour on the worst sample >= 4.5:1 =="
for c in black white grey red green blue; do
    ge "$S" "k-$c-lo" 4 450 "$c: text colour contrast on the worst sample"
done
V=$(val "$S" k-grad-lo 4)
[ -n "$V" ] && [ "$V" -lt 450 ] && ok "COUNTER-PROOF: on the gradient NO single text colour reaches 4.5:1 ($V)" || bad "the gradient was supposed to be too wide for one colour (got '$V')"
ge "$S" k-grad-scrim 4 450 "gradient: with the tint the worst sample reaches 4.5:1"
V=$(val "$S" k-grad-scrim 3); [ -n "$V" ] && [ "$V" -gt 0 ] && ok "  and the tint is really asked for ($V/255)" || bad "no tint was asked for on the gradient ($V)"
V=$(val "$S" k-black-lo 4); [ -n "$V" ] && [ "$V" -ge 1900 ] && ok "black: white text, 21:1 ($V)" || bad "black: contrast $V"

echo "== 3. above does not count, below does =="
near "$S" pre-above 3 0 $TOL "B black: the probe reads black"
near "$S" above 3 0 $TOL "a WHITE window T over the probe does not count (still black)"
near "$S" t-behind 3 "$(exp t-mean)" $TOL "behind T lie B and the red probe P: the window below DOES count"

echo "== 4. the cache =="
eq "$S" c-repeat 3 0 "asking twice again: no new run"
eq "$S" c-repeat 4 2 "  both answers from the cache"
eq "$S" c-own 3 0 "the probe repaints ITSELF: no new run"
eq "$S" c-own 4 1 "  the answer comes from the cache"
eq "$S" c-far 3 0 "a window far away repaints: no new run"
eq "$S" c-far 4 1 "  the answer comes from the cache"
eq "$S" c-below 3 1 "B (below) repaints: exactly one new run"
eq "$S" c-below 4 0 "  and no hit"
near "$S" c-below-mean 3 65536 $TOL "  with the new value (white)"
eq "$S" c-after 3 1 "afterwards the cache holds again (still 1 run since the repaint)"
eq "$S" c-after 4 1 "  and the next answer is a hit"

echo "== 5. the text colour decider on the live measurement =="
L=$(exp switch)
near "$S" noise-range 3 "$L" 2500 "noisy grey: lowest mean sits at the switch point"
near "$S" noise-range 4 "$L" 2500 "noisy grey: highest mean sits at the switch point"
eq "$S" noise-flips 3 0 "NOISY CONSTANT BACKGROUND: 0 flips in 60 frames"
eq "$S" noise-flips 4 1 "  and the colour stays white text"
ge "$S" noise-flips-plain 3 10 "COUNTER-PROOF: the plain threshold (no band, no hold) flips on the same frames"
eq "$S" step-flips 3 1 "ONE REAL CHANGE (black -> white): exactly 1 flip"
eq "$S" step-flips 4 0 "  and the text is black on white"
eq "$S" ramp-flips 3 1 "a slow ramp black -> white: exactly 1 flip"
eq "$S" ramp-flips 4 0 "  and the text ends black"
eq "$S" final 3 1 "the run reached its end"

echo
echo "backlum: OK=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
