#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }
MIN_PITCH=32
BAR_TOP=${BAR_TOP:-760}
OUT=${MENULOOK_OUT:-$TMPD/out}
[ -n "${MENULOOK_REUSE:-}" ] || bash tools/menulook/shoot.sh "$OUT" > /dev/null 2>&1
S="$OUT/serial.txt"
line=$(grep -a -m1 'taskbar: jumplist n=' "$S")
if [ -z "$line" ]; then
    bad "no jump list line in the serial log"
    echo "MENULOOK: $pass passed, $fail failed"; exit 1
fi
n=$(echo "$line" | sed -E 's/.*n=([0-9]+) .*/\1/'); x=$(echo "$line" | sed -E 's/.* x=([0-9]+) .*/\1/')
y=$(echo "$line" | sed -E 's/.* y=([0-9]+) .*/\1/'); w=$(echo "$line" | sed -E 's/.* w=([0-9]+) .*/\1/')
h=$(echo "$line" | sed -E 's/.* h=([0-9]+).*/\1/')
[ "$h" -ge $((n * MIN_PITCH)) ] && ok "row pitch: $n rows in $h px (>= $MIN_PITCH per row)" || bad "menu too low: $n rows in $h px"
[ $((y + h)) -le "$BAR_TOP" ] && ok "menu bottom ${y}+${h} stays above the bar ($BAR_TOP)" || bad "menu overlaps the bar: bottom $((y + h))"
[ "$w" -ge 200 ] && ok "menu width $w px" || bad "menu too narrow: $w px"
ink=$(python3 -I - "$OUT/02b-icon-menu.ppm" "$x" "$y" "$w" "$h" <<'PY'
import sys
def load(p):
    d = open(p, "rb").read(); f = []; at = 2
    while len(f) < 3:
        while d[at:at+1].isspace(): at += 1
        s = at
        while not d[at:at+1].isspace(): at += 1
        f.append(int(d[s:at]))
    return f[0], d[at+1:]
W, d = load(sys.argv[1]); x, y, w, h = (int(v) for v in sys.argv[2:6])
def px(a, b):
    o = (b * W + a) * 3
    return d[o], d[o+1], d[o+2]
bg = px(x + w - 8, y + h - 8)
n = 0
for b in range(y + 60, y + h - 8):
    for a in range(x + 14, x + 34):
        p = px(a, b)
        if sum(abs(p[i] - bg[i]) for i in range(3)) > 120:
            n += 1
print(n)
PY
)
[ "$ink" -ge 40 ] && ok "icon column carries glyph ink ($ink pixels)" || bad "icon column empty ($ink pixels)"
bl=$(grep -a -m1 'taskbar: context empty x=' "$S")
bx=$(echo "$bl" | sed -E 's/.* x=([0-9]+) .*/\1/'); by=$(echo "$bl" | sed -E 's/.* y=([0-9]+) .*/\1/')
bw=$(echo "$bl" | sed -E 's/.* w=([0-9]+) .*/\1/'); bh=$(echo "$bl" | sed -E 's/.* h=([0-9]+) .*/\1/')
cmp_rect() {
    python3 -I - "$1" "$2" "$3" "$4" "$5" "$6" <<'PY'
import sys
def load(p):
    d = open(p, "rb").read(); f = []; at = 2
    while len(f) < 3:
        while d[at:at+1].isspace(): at += 1
        s = at
        while not d[at:at+1].isspace(): at += 1
        f.append(int(d[s:at]))
    return f[0], d[at+1:]
W, a = load(sys.argv[1]); _, b = load(sys.argv[2])
x0, y0, w, h = (int(v) for v in sys.argv[3:7])
n = 0
for y in range(y0, y0 + h):
    for x in range(x0, x0 + w):
        o = (y * W + x) * 3
        if a[o:o+3] != b[o:o+3]:
            n += 1
print(n)
PY
}
dk=$(cmp_rect "$OUT/02-bar-menu.ppm" "$OUT/02a-bar-keys.ppm" "$bx" "$by" "$bw" "$bh")
[ "$dk" -ge $((bw * 20)) ] && ok "Down key highlights the first row ($dk pixels changed in the card)" || bad "Down key changed only $dk pixels"
dw=$(cmp_rect "$OUT/02a-bar-keys.ppm" "$OUT/02a2-bar-keys-wrap.ppm" "$bx" "$by" "$bw" "$bh")
[ "$dw" -ge $((bw * 20)) ] && ok "Up key moves the highlight to the last row ($dw pixels changed)" || bad "Up key changed only $dw pixels"
OLD_H=$((n * 28 + 8))
[ "$OLD_H" -ge $((n * MIN_PITCH)) ] && bad "counter-proof: the old 28 px pitch would pass" || ok "counter-proof: the old 28 px pitch ($OLD_H px) fails the pitch check"
echo; echo "MENULOOK: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
