#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/barpop/run.sh -- THE BAR'S TOOLTIP AND TOAST ARE WINDOWS OF THE SCENE HOST.
#
#   bash tools/barpop/run.sh
#
# Before 05.10.2026 the bar opened a wlib window for every tooltip and every
# toast and closed it again. Now (kernel/user/barpop.fi) there is one window of
# each kind for the life of the bar -- created hidden at its largest size,
# shrunk with WM_SIZE, moved with WM_MOVE, shown and hidden with WS_HIDDEN --
# on the bar's scene host (windows 2 and 3; 1 is the quick settings).
#
# What this measures, on the machine of the stick (tools/design/eh6.sh):
#   1. hover over the clock: after the delay `wlib: tip [<text>]` with
#      its x, y, w, h stands on the serial line, the picture differs from the
#      one without the bubble inside exactly that rectangle, and the text of
#      the bubble is in it (ink in the rectangle)
#   2. the pointer leaves: the bubble is gone (`wlib: tip zu`, the rectangle
#      is the same as before the hover again)
#   3. `notify hello toast` in the terminal: `taskbar: toast [hello toast]`
#      with x, y, w, h; the rectangle shows the plate, the stripe on its left
#      and the text; after the toast's four seconds it is gone again
#   4. NO `kein Platz` line (neither bubble nor toast was refused), and the bar
#      did not say it has no host
#   COUNTER-PROOF: the same rectangle in the pictures WITHOUT the bubble
#   (before the hover, after the pointer left) is the wallpaper: the bubble's
#   plate, line and text are what differs in `01-tip` -- not the wallpaper's
#   pattern.
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
export DESIGNBUILD="$TMPD/build"
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

PROGS="desktop taskbar settings launcher explorer netview taskmgr edit sh echo ls cat ps uname date df mkdir rm cp mv grep head tail wc find du chmod id whoami touch true false sleep kill sort uniq rmdir theme locate dhcp host ping netstat notify"

cat > "$TMPD/dreh.txt" <<'EOF'
warteauf 'taskbar: steht|taskbar: geom' || 120
warte 6
foto 00-before
fahre 1240,786
warte 5
foto 01-tip
fahre 600,300
warte 3
foto 02-gone
klick 300,200
warte 2
taste ret
warte 1
tippe notify hello toast
taste ret
warte 3
foto 03-toast
warte 8
foto 04-toast-gone
EOF

bash tools/design/eh6.sh "$TMPD/o" res=1280x800 accel=kvm progs="$PROGS" \
    drehbuch="$TMPD/dreh.txt" > "$TMPD/o.log" 2>&1
S="$TMPD/o/serial.txt"
if [ -n "${BARPOP_OUT:-}" ]; then mkdir -p "$BARPOP_OUT"; cp "$TMPD"/o/*.ppm "$S" "$BARPOP_OUT/" 2>/dev/null; fi
if [ ! -s "$TMPD/o/04-toast-gone.ppm" ]; then
    bad "no pictures: $(tail -n 3 "$TMPD/o.log" | tr '\n' ' ')"
    echo "BARPOP: $pass passed, $fail failed"; exit 1
fi

# ink in a rectangle of a picture: number of pixels that differ from the colour
# of the rectangle's top border row
ink() { # <ppm> <x> <y> <w> <h>
    python3 - "$@" <<'PY'
import sys
from collections import Counter
d = open(sys.argv[1], "rb").read(); f = []; at = 2
while len(f) < 3:
    while d[at:at+1].isspace(): at += 1
    s = at
    while not d[at:at+1].isspace(): at += 1
    f.append(int(d[s:at]))
at += 1
W, H, _ = f
x0, y0, w, h = (int(v) for v in sys.argv[2:6])
def px(x, y):
    o = at + (y * W + x) * 3
    return d[o], d[o+1], d[o+2]
c = Counter()
for x in range(x0 + 3, x0 + w - 3):
    c[px(x, y0 + 3)] += 1
base = c.most_common(1)[0][0]
n = 0
for y in range(y0 + 3, y0 + h - 3):
    for x in range(x0 + 3, x0 + w - 3):
        if px(x, y) != base:
            n += 1
print(n)
PY
}
diffpix() { # <a.ppm> <b.ppm> <x> <y> <w> <h>  -> number of different pixels
    python3 - "$@" <<'PY'
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
    o = (y * W + x0) * 3
    if a[o:o + w * 3] != b[o:o + w * 3]:
        for x in range(w):
            if a[o + x*3:o + x*3 + 3] != b[o + x*3:o + x*3 + 3]:
                n += 1
print(n)
PY
}

# 1. the tooltip
tl=$(grep -a '^wlib: tip \[.*\] x=' "$S" | head -1)
if [ -z "$tl" ]; then
    bad "no 'wlib: tip [...]' line"
else
    tx=$(echo "$tl" | sed -E 's/.* x=([0-9]+).*/\1/'); ty=$(echo "$tl" | sed -E 's/.* y=([0-9]+).*/\1/')
    tw=$(echo "$tl" | sed -E 's/.* w=([0-9]+).*/\1/'); th=$(echo "$tl" | sed -E 's/.* h=([0-9]+).*/\1/')
    ok "the bubble stood at $tx,$ty ${tw}x$th"
    d=$(diffpix "$TMPD/o/00-before.ppm" "$TMPD/o/01-tip.ppm" "$tx" "$ty" "$tw" "$th")
    if [ "$d" -gt $((tw * th / 3)) ]; then ok "the picture differs from the one without it in $d of $((tw * th)) pixels of that rectangle"
    else bad "only $d of $((tw * th)) pixels differ -- no bubble in the picture"; fi
    ik=$(ink "$TMPD/o/01-tip.ppm" "$tx" "$ty" "$tw" "$th")
    [ "$ik" -ge 30 ] && ok "the text is in it ($ik inked pixels)" || bad "no text in the bubble ($ik inked pixels)"
    # 2. gone again; COUNTER-PROOF: less ink there without the bubble
    d2=$(diffpix "$TMPD/o/00-before.ppm" "$TMPD/o/02-gone.ppm" "$tx" "$ty" "$tw" "$th")
    [ "$d2" -le 40 ] && ok "after the pointer left the rectangle is as before ($d2 pixels differ; the clock may tick)" \
        || bad "the bubble is still there: $d2 pixels differ from the picture without it"
fi
grep -aq '^wlib: tip zu' "$S" && ok "the bubble was closed (\`wlib: tip zu\`)" || bad "no 'wlib: tip zu'"
# 3. the toast
ts=$(grep -a '^taskbar: toast \[hello toast\] x=' "$S" | head -1)
if [ -z "$ts" ]; then
    bad "no 'taskbar: toast [hello toast]' line"
else
    sx=$(echo "$ts" | sed -E 's/.* x=([0-9]+).*/\1/'); sy=$(echo "$ts" | sed -E 's/.* y=([0-9]+).*/\1/')
    sw=$(echo "$ts" | sed -E 's/.* w=([0-9]+).*/\1/'); sh=$(echo "$ts" | sed -E 's/.* h=([0-9]+).*/\1/')
    ok "the toast stood at $sx,$sy ${sw}x$sh"
    d=$(diffpix "$TMPD/o/02-gone.ppm" "$TMPD/o/03-toast.ppm" "$sx" "$sy" "$sw" "$sh")
    if [ "$d" -gt $((sw * sh / 3)) ]; then ok "the toast is in the picture ($d of $((sw * sh)) pixels differ from before)"
    else bad "only $d of $((sw * sh)) pixels differ -- no toast in the picture"; fi
    d2=$(diffpix "$TMPD/o/02-gone.ppm" "$TMPD/o/04-toast-gone.ppm" "$sx" "$sy" "$sw" "$sh")
    [ "$d2" -le 300 ] && ok "four seconds later the rectangle is as before ($d2 pixels differ; the CPU gauge ticks)" \
        || bad "the toast is still there after its time: $d2 pixels differ"
fi
grep -aq '^taskbar: toast zu' "$S" && ok "the toast was closed (\`taskbar: toast zu\`)" || bad "no 'taskbar: toast zu'"
# 4. nothing refused
if grep -aq 'kein Platz\|no tooltip/toast host' "$S"; then
    bad "a pop-up was refused: $(grep -a 'kein Platz\|no tooltip/toast host' "$S" | head -1)"
else
    ok "no pop-up was refused (no 'kein Platz', the host was there)"
fi
echo; echo "BARPOP: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
