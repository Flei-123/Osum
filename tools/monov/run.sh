#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/monov/run.sh -- MON-3 gate: the developer overlay (Ctrl+Shift+F), kernel/user/fpsov.fi.
#
#   /root/jarvis/bin/heavy bash tools/monov/run.sh
#
# Run A (key pressed): off picture, on, off again, on again with a terminal typing.
#   - `wm: monov on` / `wm: monov off` on the serial line, `fpsov: shown x= y= w= h=` / `fpsov: hidden`
#   - the rectangle differs from the picture without it and carries text ink
#   - switched off again, the rectangle is as before (off = identical frame)
#   - while a terminal types the sparkline and the numbers carry more ink than the idle overlay
#   - `fpsov: stat peak= cpu= used= tot= n=`: cpu 0..100, used > 0, used <= tot
#   - the bar had room for the window (no `no fpsov host`), nothing else refused
# Run B (counter-proof, same script without the key): no monov line, no overlay line, rectangle unchanged.
# eh6 boots without the `vfs` word and without a /proc mount point: both are added here (EH_MKFS_EXTRA, extra=), else the bar cannot open /proc/frames (fd=-2).
set -uo pipefail
cd "$(dirname "$0")/../.."
TMPD=$(mktemp -d)
trap 'rm -rf "$TMPD"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

cat > "$TMPD/a.txt" <<'EOF'
warteauf 'taskbar: steht|taskbar: geom' || 120
warte 8
foto 00-off
taste ctrl-shift-f
warte 5
foto 01-on
taste ctrl-shift-f
warte 4
foto 02-off
taste ctrl-shift-f
warte 2
taste ctrl-shift-t
warte 6
tippe aaaaaaaaaa
warte 1
tippe bbbbbbbbbb
warte 1
tippe cccccccccc
warte 1
tippe dddddddddd
warte 1
tippe eeeeeeeeee
warte 1
tippe ffffffffff
warte 1
tippe gggggggggg
warte 1
tippe hhhhhhhhhh
warte 2
foto 03-active
EOF
grep -v 'ctrl-shift-f' "$TMPD/a.txt" > "$TMPD/b.txt"

run_one() { # name, drehbuch
    mkdir -p "$TMPD/$1"
    EH_MKFS_EXTRA="/proc/" DESIGNBUILD="$TMPD/$1/build" bash tools/design/eh6.sh "$TMPD/$1/o" res=1280x800 accel=kvm tafel=nein moreprogs=term "extra=vfs lang=en" \
        drehbuch="$2" > "$TMPD/$1/o.log" 2>&1
    rm -rf "$TMPD/$1/build"
}

bash vendor/firn/fetch-firnc.sh >/dev/null 2>&1
run_one a "$TMPD/a.txt"
run_one b "$TMPD/b.txt"
SA="$TMPD/a/o/serial.txt"; SB="$TMPD/b/o/serial.txt"
if [ -n "${MONOV_OUT:-}" ]; then
    mkdir -p "$MONOV_OUT"
    cp "$TMPD"/a/o/*.ppm "$MONOV_OUT/" 2>/dev/null; cp "$SA" "$MONOV_OUT/serial-a.txt" 2>/dev/null; cp "$SB" "$MONOV_OUT/serial-b.txt" 2>/dev/null
fi
if [ ! -s "$TMPD/a/o/03-active.ppm" ] || [ ! -s "$TMPD/b/o/03-active.ppm" ]; then
    bad "no pictures: $(tail -n 3 "$TMPD/a/o.log" | tr '\n' ' ') / $(tail -n 3 "$TMPD/b/o.log" | tr '\n' ' ')"
    echo "MONOV: $pass passed, $fail failed"; exit 1
fi

# the desktop clock tile under the overlay changes its minute digit between pictures (about 70-140 pixels), so "unchanged" means <= 150 of 16800
diffpix() { # <a.ppm> <b.ppm> <x> <y> <w> <h>  -> number of different pixels
    python3 -I - "$@" <<'PY'
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
ink() { # <ppm> <x> <y> <w> <h>  -> pixels that differ from the plate colour
    python3 -I - "$@" <<'PY'
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
num() { echo "$1" | sed -E "s/.* $2=([0-9]+).*/\1/"; }

grep -aq 'wm: monov on' "$SA" && ok "Ctrl+Shift+F reached the window server (\`wm: monov on\`)" || bad "no 'wm: monov on'"
grep -aq 'wm: monov off' "$SA" && ok "the second press switched it off (\`wm: monov off\`)" || bad "no 'wm: monov off'"
sl=$(grep -a 'fpsov: shown x=' "$SA" | head -1 | sed 's/.*fpsov: shown/fpsov: shown/')
if [ -z "$sl" ]; then
    bad "no 'fpsov: shown' line"
else
    x=$(num "$sl" x); y=$(num "$sl" y); w=$(num "$sl" w); h=$(num "$sl" h)
    ok "the overlay stood at $x,$y ${w}x$h"
    d=$(diffpix "$TMPD/a/o/00-off.ppm" "$TMPD/a/o/01-on.ppm" "$x" "$y" "$w" "$h")
    if [ "$d" -gt $((w * h / 3)) ]; then ok "the rectangle differs from the picture without it ($d of $((w * h)) pixels)"
    else bad "only $d of $((w * h)) pixels differ -- no overlay in the picture"; fi
    i1=$(ink "$TMPD/a/o/01-on.ppm" "$x" "$y" "$w" "$h")
    [ "$i1" -ge 60 ] && ok "text is in it ($i1 inked pixels)" || bad "no text in the overlay ($i1 inked pixels)"
    d2=$(diffpix "$TMPD/a/o/00-off.ppm" "$TMPD/a/o/02-off.ppm" "$x" "$y" "$w" "$h")
    [ "$d2" -le 150 ] && ok "switched off the rectangle is as before ($d2 pixels differ)" || bad "after switching off $d2 pixels still differ from the picture without it"
    i3=$(ink "$TMPD/a/o/03-active.ppm" "$x" "$y" "$w" "$h")
    [ "$i3" -gt $((i1 + 20)) ] && ok "typing in a terminal adds ink: $i1 -> $i3 (sparkline and numbers)" || bad "no more ink while a terminal types: $i1 -> $i3"
    d3=$(diffpix "$TMPD/b/o/00-off.ppm" "$TMPD/b/o/01-on.ppm" "$x" "$y" "$w" "$h")
    [ "$d3" -le 150 ] && ok "COUNTER-PROOF without the key the rectangle stays as it was ($d3 pixels differ)" || bad "without the key $d3 pixels changed"
fi
if [ -n "$sl" ]; then
    ovl=$(python3 -I - "$SA" "$x" "$y" "$w" "$h" <<'PY'
import re, sys
ox, oy, ow, oh = (int(v) for v in sys.argv[2:6])
hits = []
for line in open(sys.argv[1], "rb").read().decode("latin-1").splitlines():
    m = re.search(r"desktop: modul (\d+) name=(\S*) an=(\d+).* x=(\d+) y=(\d+) w=(\d+) h=(\d+)", line)
    if not m or m.group(3) != "1":
        continue
    x, y, w, h = (int(m.group(i)) for i in (4, 5, 6, 7))
    if w and h and x < ox + ow and ox < x + w and y < oy + oh and oy < y + h:
        hits.append(m.group(2))
print(",".join(hits) if hits else "none")
PY
)
    nm=$(grep -ac 'desktop: modul ' "$SA")
    [ "$nm" -ge 1 ] && ok "desktop modules reported ($nm lines)" || bad "no desktop module lines to compare against"
    [ "$ovl" = "none" ] && ok "the overlay overlaps no desktop module tile" || bad "the overlay overlaps desktop module tiles: $ovl"
fi
grep -aq 'fpsov: hidden' "$SA" && ok "the overlay was hidden again (\`fpsov: hidden\`)" || bad "no 'fpsov: hidden'"
st=$(grep -a 'fpsov: stat peak=' "$SA" | tail -1 | sed 's/.*fpsov: stat/fpsov: stat/')
if [ -z "$st" ]; then
    bad "no 'fpsov: stat' line (the overlay never took 8 samples)"
else
    pk=$(num "$st" peak); cpu=$(num "$st" cpu); us=$(num "$st" used); tt=$(num "$st" tot)
    ok "numbers: peak=$pk cpu=$cpu used=$us tot=$tt"
    cap=$(num "$st" cap)
    [ "$cap" -gt 0 ] && ok "frame cost reported (phases sum $cap x0.1 ms)" || bad "no frame cost in the stat line"
    [ "$cpu" -le 100 ] && ok "cpu within 0..100" || bad "cpu out of range: $cpu"
    [ "$us" -gt 0 ] && [ "$us" -le "$tt" ] && ok "used memory plausible ($us of $tt MB)" || bad "memory implausible: used=$us tot=$tt"
fi
if grep -aq 'no fpsov host' "$SA"; then bad "the bar had no room for the overlay window"; else ok "the bar had room for the window"; fi
if grep -aq 'kein Platz\|no tooltip/toast host\|no notifc host\|no task view card' "$SA"; then
    bad "a pop-up window was refused: $(grep -a 'kein Platz\|no tooltip/toast host\|no notifc host\|no task view card' "$SA" | head -1)"
else ok "no other pop-up window was refused (nine fit)"; fi
if grep -aq 'wm: monov\|fpsov: ' "$SB"; then bad "COUNTER-PROOF: monov/fpsov lines without the key: $(grep -a 'wm: monov\|fpsov: ' "$SB" | head -1)"
else ok "COUNTER-PROOF: without the key there is no monov and no fpsov line"; fi
if grep -aqi 'panic' "$SA"; then bad "panic on the serial line"; else ok "no panic"; fi
echo; echo "MONOV: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
