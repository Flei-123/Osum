#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/traylayout/check.py <outdir> -- judge the pictures + serial of tools/traylayout/shot.sh.

Prints OK/FAIL lines and a last line "RESULT ok=<n> fail=<n>".  The numbers it measures (r1015/r1016):
  tray    fields of the right end of the bar in one order (chevron, language, network, clock), no overlap,
          one gap, right margin >= 8, the chevron button not wider than 32 points
  clock   two lines, both RIGHT-aligned (right ink edges of the two lines differ <= 4 px)
  flyout  the overflow card lies completely above the bar and inside the screen; its text does not touch
          the right card edge (no hard clip)
  icons   the window button's program icon is a glyph, not a filled tile: share of strongly different
          pixels in its 24x24 box <= 55 % (a tile is ~ 80 %)
"""
import re, sys, os

def load_ppm(path):
    d = open(path, "rb").read(); f = []; at = 2
    while len(f) < 3:
        while d[at:at+1].isspace(): at += 1
        s = at
        while not d[at:at+1].isspace(): at += 1
        f.append(int(d[s:at]))
    return f[0], f[1], d[at+1:]

out = sys.argv[1]
ok = fail = 0
def say(good, msg):
    global ok, fail
    if good: ok += 1
    else: fail += 1
    print(("  OK    " if good else "  FAIL  ") + msg)

ser = open(os.path.join(out, "serial.txt"), "rb").read().decode("latin1")
def last(pat):
    m = re.findall(pat, ser)
    return [int(v) for v in m[-1]] if m else None
geom = last(r"taskbar: geom edge=0 x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
chev = last(r"taskbar: chevron x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
lang = last(r"taskbar: field lang x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
net = last(r"taskbar: field net x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
clk = last(r"taskbar: field clock x=(\d+) y=(\d+) w=(\d+) h=(\d+) lines=(\d+)")
say(all(v is not None for v in (geom, chev, lang, net, clk)), "the bar reports geometry, chevron, language, network and clock")
if not all(v is not None for v in (geom, chev, lang, net, clk)):
    print("RESULT ok=%d fail=%d" % (ok, fail)); sys.exit(1)
bx, by, bw, bh = geom
# 1. tray fields
seq = [("chevron", chev), ("language", lang), ("network", net), ("clock", clk)]
ordered = all(seq[i][1][0] + seq[i][1][2] <= seq[i + 1][1][0] for i in range(3))
say(ordered, "fields in order chevron < language < network < clock, no overlap")
gaps = [seq[i + 1][1][0] - (seq[i][1][0] + seq[i][1][2]) for i in range(3)]
say(max(gaps) - min(gaps) <= 4 and min(gaps) >= 4, "one gap between the tray fields (gaps %s)" % gaps)
say(bw - (clk[0] + clk[2]) >= 8, "right margin of the clock >= 8 (%d)" % (bw - (clk[0] + clk[2])))
say(chev[2] <= 32, "chevron button <= 32 points wide (%d)" % chev[2])
say(clk[4] == 2, "clock has two lines (time over date)")
# 2. clock right alignment
w, h, px = load_ppm(os.path.join(out, "00-bar.ppm"))
def ink_right(x0, y0, x1, y1):
    bgp = px[(y0 * w + x0) * 3:(y0 * w + x0) * 3 + 3]
    best = -1
    for y in range(y0, y1):
        for x in range(x0, x1):
            o = (y * w + x) * 3
            if max(abs(px[o + c] - bgp[c]) for c in range(3)) > 90:
                best = max(best, x)
    return best
cx, cy, cw, ch = clk[0], clk[1] + by, clk[2], clk[3]
r1 = ink_right(cx, cy, cx + cw, cy + ch // 2 - 1)
r2 = ink_right(cx, cy + ch // 2 + 1, cx + cw, cy + ch)
say(r1 > 0 and r2 > 0 and abs(r1 - r2) <= 4, "clock lines right-aligned (right ink edges %d and %d)" % (r1, r2))
# 3. flyout
m = re.search(r"traypop: open n=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)", ser)
if not m:
    say(False, "the chevron opened the flyout")
else:
    fx, fy, fw, fh = (int(v) for v in m.groups())
    say(fy + fh <= by and fy >= 0, "flyout lies above the bar (y %d..%d, bar at %d)" % (fy, fy + fh, by))
    say(fx >= 0 and fx + fw <= 1280, "flyout inside the screen (x %d..%d)" % (fx, fx + fw))
    w2, h2, p2 = load_ppm(os.path.join(out, "01-open.ppm"))
    bgp = p2[((fy + fh - 4) * w2 + fx + fw - 8) * 3:((fy + fh - 4) * w2 + fx + fw - 8) * 3 + 3]
    touch = 0
    for y in range(max(fy, 0) + 12, min(fy + fh, h2) - 4):
        for x in range(fx + fw - 12, min(fx + fw - 2, w2)):
            o = (y * w2 + x) * 3
            if max(abs(p2[o + c] - bgp[c]) for c in range(3)) > 60:
                touch += 1
    say(touch <= 20, "no text runs into the right card edge (%d inked px in the last 10 columns)" % touch)
# 4. icon is not a tile
b = re.findall(r"taskbar: btn i=0 id=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)", ser)
sym = re.findall(r"taskbar: sym btn=0 app=(\w+) w=(\d+) gemalt=(\d+)", ser)
if not b or not sym:
    say(False, "the bar reports a window button with a program symbol")
else:
    x, y, bw2, bh2 = (int(v) for v in b[-1]); n = int(sym[-1][2])
    ix, iy = x + (bw2 - n) // 2, y + by + (bh2 - n) // 2
    bgo = ((y + by + 5) * w + x + 5) * 3
    bgp = px[bgo:bgo + 3]
    strong = tot = 0
    for yy in range(iy, iy + n):
        for xx in range(ix, ix + n):
            o = (yy * w + xx) * 3
            tot += 1
            if max(abs(px[o + c] - bgp[c]) for c in range(3)) > 70:
                strong += 1
    say(strong * 100 <= tot * 55, "program icon '%s' in the bar is a glyph, not a filled tile (%d %% strongly different)" % (sym[-1][0], strong * 100 // tot))
print("RESULT ok=%d fail=%d" % (ok, fail))
sys.exit(1 if fail else 0)
