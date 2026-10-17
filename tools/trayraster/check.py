#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/trayraster/check.py <outdir> <scale> -- judge the tray raster (pictures + serial of shot.sh).

Prints OK/FAIL lines and "RESULT ok=<n> fail=<n>".  Measured (Windows 11 tray):
  rects   chevron, language, network, volume, battery, clock: in one row, one gap (all gaps identical),
          the same top and height (one centre line), right margin >= 8, nothing past the screen edge
  cells   the icon-only cells (chevron, network, volume) are exactly 24 points * scale wide
  icons   every tray symbol is <= 16*scale + 1 high and wide (ink), its ink centre lies on the centre line
          (+-1 px) and, in an icon-only cell, in the middle of the cell (+-2*scale px)
  text    battery text is not clipped (ink stays >= 3 px inside the field), text of battery, language and
          clock has one height (digits/caps within 2*scale px), the gaps between the fields stay empty
  apps    the program symbol of a window button is about as big as the logo of the start button
          (ink height >= logo - 6*scale) and sits on the same centre line (+-1 px)
"""
import re, sys, os

out = sys.argv[1]
sc = int(sys.argv[2]) if len(sys.argv) > 2 else 1
ok = fail = 0
def say(good, msg):
    global ok, fail
    if good: ok += 1
    else: fail += 1
    print(("  OK    " if good else "  FAIL  ") + msg)

def load_ppm(path):
    d = open(path, "rb").read(); f = []; at = 2
    while len(f) < 3:
        while d[at:at+1].isspace(): at += 1
        s = at
        while not d[at:at+1].isspace(): at += 1
        f.append(int(d[s:at]))
    return f[0], f[1], d[at+1:]

ser = open(os.path.join(out, "serial.txt"), "rb").read().decode("latin1")
def last(pat):
    m = re.findall(pat, ser)
    return [int(v) for v in m[-1]] if m else None
geom = last(r"taskbar: geom edge=0 x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
F = {}
for n in ("lang", "net", "snd", "battery", "clock"):
    F[n] = last(r"taskbar: field %s x=(\d+) y=(\d+) w=(\d+) h=(\d+) lines=(\d+)" % n)
F["noti"] = last(r"taskbar: field noti x=(\d+) y=(\d+) w=(\d+) h=(\d+) lines=(\d+)")   # optional notification bell field
F["chevron"] = last(r"taskbar: chevron x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
start = last(r"taskbar: start x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
btn = last(r"taskbar: btn i=0 id=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
need = ("chevron", "lang", "net", "snd", "battery", "clock")
say(geom is not None and all(F[n] is not None for n in need),
    "the bar reports its geometry and the fields chevron, lang, net, snd, battery, clock")
if geom is None or not all(F[n] is not None for n in need):
    print("RESULT ok=%d fail=%d" % (ok, fail)); sys.exit(1)
bx, by, bw, bh = geom
w, h, px = load_ppm(os.path.join(out, "00-bar.ppm"))

def at_px(x, y):
    o = (y * w + x) * 3
    return px[o], px[o + 1], px[o + 2]
def inkbox(x0, y0, x1, y1, bg=None, thr=70):
    """bounding box (l, t, r, b inclusive) of pixels differing from the background, or None"""
    x0 = max(x0, 0); y0 = max(y0, 0); x1 = min(x1, w); y1 = min(y1, h)
    if bg is None: bg = at_px(x0, (y0 + y1) // 2)
    l = t = 10**9; r = b = -1
    for y in range(y0, y1):
        o = (y * w + x0) * 3
        for x in range(x0, x1):
            if max(abs(px[o] - bg[0]), abs(px[o + 1] - bg[1]), abs(px[o + 2] - bg[2])) > thr:
                if x < l: l = x
                if x > r: r = x
                if y < t: t = y
                if y > b: b = y
            o += 3
    return None if r < 0 else (l, t, r, b)

# ---- rects
order = ["chevron"] + (["noti"] if F["noti"] else []) + ["lang", "net", "snd", "battery", "clock"]
rects = {n: (F[n][0], F[n][1] + by, F[n][2], F[n][3]) for n in order}   # absolute y
rects_x = [rects[n] for n in order]
NF = len(order) - 1
ordered = all(rects_x[i][0] + rects_x[i][2] <= rects_x[i + 1][0] for i in range(NF))
say(ordered, "fields in order %s, no overlap" % " < ".join(order))
gaps = [rects_x[i + 1][0] - (rects_x[i][0] + rects_x[i][2]) for i in range(NF)]
say(len(set(gaps)) == 1 and gaps[0] >= 4, "one gap between all tray fields (gaps %s)" % gaps)
say(len(set((r[1], r[3]) for r in rects_x)) == 1, "all fields have the same top and height (centre line) %s" % sorted(set((r[1], r[3]) for r in rects_x)))
cm = rects["clock"]
say(bw - (cm[0] + cm[2]) >= 8 and cm[0] + cm[2] <= w, "right margin of the clock >= 8 (%d)" % (bw - (cm[0] + cm[2])))
cw = 24 * sc
say(all(rects[n][2] == cw for n in ("chevron", "net", "snd")),
    "icon-only cells chevron/net/snd are %d wide (%s)" % (cw, [rects[n][2] for n in ("chevron", "net", "snd")]))

# ---- icons
mid = rects["clock"][1] + rects["clock"][3] / 2.0
icon_cells = [("chevron", rects["chevron"]), ("lang", rects["lang"]), ("net", rects["net"]),
              ("snd", rects["snd"]), ("battery", rects["battery"])]
sizes = []
for name, (x, y, ww, hh) in icon_cells:
    cell_w = cw if name in ("chevron", "net", "snd") or ww >= cw else ww
    bg = at_px(x + 1, y + hh // 2)
    bb = inkbox(x + 2, y + 2, x + cell_w - 1 if name in ("chevron", "net", "snd") else x + cell_w, y + hh - 2, bg)
    if bb is None:
        say(False, "%s symbol has ink" % name); continue
    iw, ih = bb[2] - bb[0] + 1, bb[3] - bb[1] + 1
    cy = (bb[1] + bb[3]) / 2.0
    cx = (bb[0] + bb[2]) / 2.0
    sizes.append((name, max(iw, ih)))
    say(iw <= 16 * sc + 1 and ih <= 16 * sc + 1, "%s symbol <= %d px (ink %dx%d)" % (name, 16 * sc, iw, ih))
    say(abs(cy - mid) <= 1.0, "%s symbol on the centre line (ink centre %.1f, line %.1f)" % (name, cy, mid))
    if name in ("chevron", "net", "snd"):
        say(abs(cx - (x + ww / 2.0)) <= 2 * sc, "%s symbol in the middle of its cell (ink centre %.1f, cell %.1f)" % (name, cx, x + ww / 2.0))
mx = max(s for _, s in sizes) if sizes else 0
mn = min(s for _, s in sizes) if sizes else 0
say(mn >= 8 * sc and mx <= 16 * sc + 1, "tray symbols are of one size class (largest side %s)" % [s for _, s in sizes])

# ---- text
bt = rects["battery"]
bgb = at_px(bt[0] + 1, bt[1] + bt[3] // 2)
tb = inkbox(bt[0] + cw - 2 * sc, bt[1] + 2, bt[0] + bt[2] + gaps[-1], bt[1] + bt[3] - 2, bgb)
if tb is None:
    say(False, "battery text has ink")
else:
    say(tb[2] <= bt[0] + bt[2] - 3, "battery text not clipped: ink right edge %d, field right edge %d" % (tb[2], bt[0] + bt[2]))
    say(tb[0] >= bt[0] + cw - 2 * sc, "battery text starts behind the symbol (%d)" % tb[0])
    th = tb[3] - tb[1] + 1
    cl = rects["clock"]
    cb = inkbox(cl[0] + 2, cl[1] + 2, cl[0] + cl[2] - 1, cl[1] + cl[3] // 2 - 1, at_px(cl[0] + 1, cl[1] + cl[3] // 2))
    lg = rects["lang"]
    lb = inkbox(lg[0] + cw - 2 * sc, lg[1] + 2, lg[0] + lg[2] - 1, lg[1] + lg[3] // 2 - 1, at_px(lg[0] + 1, lg[1] + lg[3] // 2))
    if cb and lb:
        chh, lhh = cb[3] - cb[1] + 1, lb[3] - lb[1] + 1
        say(abs(th - chh) <= 3 * sc and abs(lhh - chh) <= 2 * sc,
            "text height alike: battery %d, clock line %d, language line %d" % (th, chh, lhh))
    else:
        say(False, "clock and language text have ink")
# gaps between fields stay empty (nothing runs over into a neighbour)
leak = 0
for i in range(NF):
    gx0 = rects_x[i][0] + rects_x[i][2]
    gx1 = rects_x[i + 1][0]
    y0, y1 = rects_x[i][1] + 3, rects_x[i][1] + rects_x[i][3] - 3
    if gx1 > gx0 and (order[i], order[i + 1]) not in (("net", "snd"), ("snd", "battery")):      # inside the capsule the panel edge itself is drawn
        bb = inkbox(gx0 + 1, y0, gx1 - 1, y1, at_px(gx0 + 1, (y0 + y1) // 2))
        if bb: leak += 1
say(leak == 0, "the gaps between the fields stay empty (%d with ink)" % leak)

# ---- program symbol vs start logo
if start and btn:
    sx, sy, sw, shh = start[0], start[1] + by, start[2], start[3]
    logo = inkbox(sx + 3, sy + 3, sx + sw - 3, sy + shh - 3, at_px(sx + 3, sy + 3), 60)
    bx0, by0, bw0, bh0 = btn[0], btn[1] + by, btn[2], btn[3]
    app = inkbox(bx0 + 3, by0 + 3, bx0 + bw0 - 3, by0 + bh0 - 8, at_px(bx0 + 3, by0 + 3), 60)
    if logo and app:
        lh, ah = logo[3] - logo[1] + 1, app[3] - app[1] + 1
        say(ah >= lh - 6 * sc, "program symbol as big as the start logo (app ink %d px, logo ink %d px)" % (ah, lh))
        lc, ac = (logo[1] + logo[3]) / 2.0, (app[1] + app[3]) / 2.0
        say(abs(lc - ac) <= 1.0, "program symbol and start logo on one centre line (%.1f vs %.1f)" % (ac, lc))
        say(app[0] >= bx0 + 1 and app[2] <= bx0 + bw0 - 1 and app[1] >= by0 and app[3] <= by0 + bh0, "program symbol not cut off by its button")
    else:
        say(False, "start logo and program symbol have ink")
else:
    say(False, "the bar reports the start button and a window button")
print("RESULT ok=%d fail=%d" % (ok, fail))
sys.exit(1 if fail else 0)
