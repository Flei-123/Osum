#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# tools/comp/termshare.sh -- docs/COMPOSITOR.md r486 (terminal): THE TERMINAL WINDOW PAINTS INTO A SHARED BUFFER THE KERNEL MADE.
#
#   bash tools/comp/termshare.sh        (start it through /root/jarvis/bin/heavy)
#
# The kernel terminal (kind 1: the server paints the cell grid) used to own a private run of frames, so the compositor in ring 3 could
# not look at it. Now the buffer is a shared object the kernel makes itself (wm.kern_shared); the window table names it (shm column) and
# says "plain", wmd maps it read-only (WM_BUFFD), composes the client area and compares it with /dev/fb.
#
# Gates: the terminal has a shared object (`wm: termgeo ... shared=N`, N > 0); wmd judged terminal pixels (termpx) and NOT ONE differs
# (termdiff = 0); the cells of the kernel's own state show up in the screenshot (an INDEPENDENT witness: the screenshot comes from the
# screen device, the cells from the terminal state, neither goes through wmd or the judge).
# Counter-proof 1: `noshare` -> the terminal has no shared object (shared=0), wmd judges no terminal pixel, and the text still stands in the
# picture (the old path works). Counter-proof 2: the independent check run on a screenshot where the terminal is wiped fails.
set -uo pipefail
cd "$(dirname "$0")/../.."
D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  OK    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s\n' "$1"; }

cat > "$D/dreh.txt" <<'DREH'
warteauf 'launcher: ready' || 90
warte 25
klick 300,200
warte 2
tippe ls /bin
taste ret
warte 3
tippe echo second line of text
taste ret
warte 2
tippe echo tsmarker4711
taste ret
warte 30
foto s
taste f12
warte 3
DREH
run() { # run <name> <extra words>   (the machine of the stick: tools/design/eh6.sh, a shell stands in the terminal window)
    bash tools/design/eh6.sh "$D/$1" res=1280x800 accel=kvm drehbuch="$D/dreh.txt" schatten=an window_alpha=100 tafel=nein \
        "extra=wigapp=/bin/wmd wighalt=150 termdump $2" "progs=desktop taskbar settings launcher explorer netview taskmgr edit sh echo ls cat theme wmd" \
        > "$D/$1.log" 2>&1
    grep -a "FEHLGESCHLAGEN" "$D/$1.log" | head -3
}
# witness <serial> <ppm> -> "cells_with_ink cells_checked agree" ; exit 0 when >= 95 % of the checked cells agree
witness() {
    python3 - "$1" "$2" <<'PY'
import re, sys
from PIL import Image
ser = open(sys.argv[1], 'rb').read().decode('latin-1').splitlines()
geo = None; rows = {}; last_geo = -1
for n, l in enumerate(ser):
    m = re.match(r'wm: termgeo cx=(\d+) cy=(\d+) cw=(\d+) ch=(\d+) cols=(\d+) rows=(\d+) bg=(\d+) fg=(\d+) shared=(\d+)', l)
    if m:
        geo = tuple(int(v) for v in m.groups()); rows = {}
        continue
    m = re.match(r'wm: termzeile (\d+) \[(.*)\]$', l)
    if m and geo:
        rows[int(m.group(1))] = m.group(2)
if not geo or not rows:
    print("0 0 0"); sys.exit(1)
cx, cy, cw, ch, cols, nrows, bg, fg, shared = geo
im = Image.open(sys.argv[2]).convert("RGB")
def dist(a, b): return abs(a[0]-b[0]) + abs(a[1]-b[1]) + abs(a[2]-b[2])
bgc = ((bg >> 16) & 255, (bg >> 8) & 255, bg & 255)
ink = 0; checked = 0; agree = 0
for r in range(nrows):
    text = rows.get(r, "")
    for c in range(cols):
        ch_ = text[c] if c < len(text) else ' '
        if r == max(rows) and ch_ == ' ':
            continue            # the cursor line: the cursor box is ink on a blank
        x0, y0 = cx + c * cw, cy + r * ch
        n = 0
        for yy in range(y0, y0 + ch, 1):
            for xx in range(x0, x0 + cw, 1):
                if dist(im.getpixel((xx, yy)), bgc) > 150:
                    n += 1
        has = n >= 3
        want = ch_ != ' '
        checked += 1
        if want: ink += 1
        if has == want: agree += 1
print(ink, checked, agree)
sys.exit(0 if ink >= 20 and checked and agree * 100 >= checked * 95 else 1)
PY
}

echo "== 1. the desktop with the shadow compositor, terminal in a shared buffer =="
run ts ""
S="$D/ts/serial.txt"
grep -a '^wm: termgeo' "$S" | tail -n 1 | sed 's/^/        /'
grep -a '^wmd: cycle ' "$S" | tail -n 2 | sed 's/^/        /'
SHR=$(grep -a '^wm: termgeo' "$S" | tail -n 1 | sed -n 's/.* shared=\([0-9]*\).*/\1/p')
[ "${SHR:-0}" -gt 0 ] && ok "the terminal window has a kernel-made shared object (shared=$SHR)" || bad "the terminal has no shared object (shared=${SHR:-none})"
TP=$(grep -a '^wmd: cycle ' "$S" | tr ' ' '\n' | awk -F= '$1 == "termpx" { s += $2 } END { print s + 0 }')
TM=$(grep -a '^wmd: cycle ' "$S" | tr ' ' '\n' | awk -F= '$1 == "termpx" && $2 > m { m = $2 } END { print m + 0 }')
TD=$(grep -a '^wmd: cycle ' "$S" | tr ' ' '\n' | awk -F= '$1 == "termdiff" { s += $2 } END { print s + 0 }')
echo "        terminal pixels judged: sum=$TP max per cycle=$TM, differing=$TD"
[ "$TM" -ge 40000 ] && ok "wmd judged $TM terminal pixels in one cycle" || bad "wmd judged only $TM terminal pixels"
[ "$TP" -gt 0 ] && [ "$TD" = 0 ] && ok "0 of $TP judged terminal pixels differ" || bad "terminal pixels differing: $TD of $TP"
if [ -s "$D/ts/s.ppm" ]; then
    W=$(witness "$S" "$D/ts/s.ppm"); echo "        witness (cells with ink, cells checked, cells agreeing): $W"
    witness "$S" "$D/ts/s.ppm" >/dev/null && ok "independent witness: the terminal's cells stand in the screenshot" || bad "independent witness: the screenshot does not show the cells"
    grep -aq 'tsmarker4711' "$S" && ok "the marker typed into the terminal is in the cells" || bad "the marker is not in the cells"
else
    bad "no screenshot"
fi

echo "== 2. counter-proof: noshare -- the terminal falls back to its private frames =="
run nts "noshare"
S2="$D/nts/serial.txt"
SHR2=$(grep -a '^wm: termgeo' "$S2" | tail -n 1 | sed -n 's/.* shared=\([0-9]*\).*/\1/p')
TP2=$(grep -a '^wmd: cycle ' "$S2" | tr ' ' '\n' | awk -F= '$1 == "termpx" { s += $2 } END { print s + 0 }')
echo "        shared=${SHR2:-none} terminal pixels judged=$TP2"
[ "${SHR2:-1}" = 0 ] && ok "noshare: the terminal has no shared object" || bad "noshare: shared=${SHR2:-none}"
[ "$TP2" = 0 ] && ok "noshare: wmd judged no terminal pixel" || bad "noshare: wmd judged $TP2 terminal pixels"
if [ -s "$D/nts/s.ppm" ]; then
    W=$(witness "$S2" "$D/nts/s.ppm"); echo "        witness: $W"
    witness "$S2" "$D/nts/s.ppm" >/dev/null && ok "noshare: the terminal still shows its text (old path works)" || bad "noshare: the terminal shows no text"
else
    bad "noshare: no screenshot"
fi

echo "== 3. counter-proof: the witness fails on a screenshot with the terminal wiped =="
if [ -s "$D/ts/s.ppm" ]; then
    python3 - "$S" "$D/ts/s.ppm" "$D/wiped.ppm" <<'PY'
import re, sys
from PIL import Image, ImageDraw
geo = None
for l in open(sys.argv[1], 'rb').read().decode('latin-1').splitlines():
    m = re.match(r'wm: termgeo cx=(\d+) cy=(\d+) cw=(\d+) ch=(\d+) cols=(\d+) rows=(\d+) bg=(\d+)', l)
    if m: geo = tuple(int(v) for v in m.groups())
cx, cy, cw, ch, cols, rows, bg = geo
im = Image.open(sys.argv[2]).convert("RGB")
ImageDraw.Draw(im).rectangle([cx, cy, cx + cols * cw, cy + rows * ch], fill=((bg >> 16) & 255, (bg >> 8) & 255, bg & 255))
im.save(sys.argv[3])
PY
    witness "$S" "$D/wiped.ppm" >/dev/null && bad "the witness passes on a wiped terminal (it would see nothing)" || ok "the witness fails on a wiped terminal"
fi

echo
echo "TERMSHARE: $pass passed, $fail failed"
[ "$fail" = 0 ]
