#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/trayfit/check.py <outdir> <scale> <lang> <flags> -- judge the tray corner (picture 00-bar + serial of shot.sh).

Windows 11 corner, measured:
  fields   language is ONE line (the code only), the clock is two lines (time over date), no keyboard symbol
  fit      every text of a field starts inside the cell and ends inside it (measured text width from the report,
           `tw=`), the ink in the picture too; the clock cell ends >= 8 px before the bar's right edge
  raster   icon cells are 24*scale wide, all gaps between the tray fields are identical (+-1), one top/height
  nochip   NO plate behind the symbols or texts: the pixels inset in each cell (corners, edge middles) are the bar
           background (the gap pixels), +-4 per channel
  text     language text is DEU/ENG, the clock reads HH:MM (or h:MM AM|PM with flag 12h), date dd.mm.yyyy
flags: 12h (clock_12h=1), wday (clock_weekday=1)
"""
import re, sys, os

out = sys.argv[1]
sc = int(sys.argv[2]); lang = sys.argv[3]; flags = sys.argv[4].split(",") if len(sys.argv) > 4 else []
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
ser_bar = ser[:ser.find("taskbar: click")] if "taskbar: click" in ser else ser
def last(pat):
    m = re.findall(pat, ser_bar)
    return m[-1] if m else None
def ints(t): return [int(v) for v in t] if t else None
geom = ints(last(r"taskbar: geom edge=0 x=(\d+) y=(\d+) w=(\d+) h=(\d+)"))
F = {}
for n in ("lang", "net", "snd", "battery", "clock"):
    F[n] = ints(last(r"taskbar: field %s x=(\d+) y=(\d+) w=(\d+) h=(\d+) lines=(\d+)" % n))
tw = {}
for n in ("lang", "battery", "clock"):
    t = last(r"taskbar: field %s x=\d+ y=\d+ w=\d+ h=\d+ lines=\d+ tw=(\d+)" % n)
    tw[n] = int(t) if t else None
F["chevron"] = ints(last(r"taskbar: chevron x=(\d+) y=(\d+) w=(\d+) h=(\d+)"))
need = ("chevron", "lang", "net", "snd", "battery", "clock")
say(geom is not None and all(F[n] is not None for n in need), "the bar reports its geometry and the fields %s" % ", ".join(need))
if geom is None or not all(F[n] is not None for n in need):
    print("RESULT ok=%d fail=%d" % (ok, fail)); sys.exit(1)
bx, by, bw, bh = geom
w, h, px = load_ppm(os.path.join(out, "00-bar.ppm"))
def at_px(x, y):
    o = (y * w + x) * 3
    return px[o], px[o + 1], px[o + 2]
def near(a, b, t=4): return max(abs(a[i] - b[i]) for i in range(3)) <= t

# ---- text reports of the fields
def texts(mark):
    return re.findall(r"taskbar: text %s x=(\d+) base=(\d+) fg=\d+ bg=\d+ tw=(\d+) t=(.*)" % mark, ser_bar)
lt = texts("lang"); ct = texts("clock")
say(F["lang"][4] == 1, "language field is ONE line (lines=%d)" % F["lang"][4])
code = "DEU" if lang == "de" else "ENG"
say(len(lt) >= 1 and lt[-1][3].strip() == code, "language text is the code only: %s" % ([t[3] for t in lt[-2:]],))
say(F["clock"][4] == 2, "clock field is two lines (lines=%d)" % F["clock"][4])
ctx = [t[3].strip() for t in ct[-2:]]
if "12h" in flags:
    say(len(ctx) == 2 and re.fullmatch(r"(1[0-2]|[1-9]):[0-5][0-9] (AM|PM)", ctx[0]) is not None, "12-hour time over date: %s" % ctx)
else:
    say(len(ctx) == 2 and re.fullmatch(r"[0-2][0-9]:[0-5][0-9]( \?)?", ctx[0]) is not None, "24-hour time over date: %s" % ctx)
dre = r"(..., )?[0-3][0-9]\.[01][0-9]\.20[0-9][0-9]" if "wday" in flags else r"[0-3][0-9]\.[01][0-9]\.20[0-9][0-9]"
say(len(ctx) == 2 and re.fullmatch(dre, ctx[1]) is not None, "date line %s%s" % (ctx[1:] , " (with weekday)" if "wday" in flags else ""))
say("kbd" not in "".join(re.findall(r"taskbar: icon field=(\w+)", ser_bar)), "no keyboard symbol in front of the language")

# ---- text inside its cell (reported widths)
for name, tl in (("lang", lt), ("clock", ct)):
    f = F[name]
    ok_all = bool(tl)
    for tx, base, wd, t in tl[-2:]:
        tx = int(tx); wd = int(wd)
        if not (tx >= f[0] + 2 and tx + wd <= f[0] + f[2] - 2): ok_all = False
    say(ok_all, "%s text lies inside its cell with >= 2 px air (cell x %d..%d, texts %s)" %
        (name, f[0], f[0] + f[2], [(int(t[0]), int(t[0]) + int(t[2])) for t in tl[-2:]]))
cl = F["clock"]
say(bw - (cl[0] + cl[2]) >= 8, "the clock cell ends >= 8 px before the bar edge (%d)" % (bw - (cl[0] + cl[2])))
say(bx + cl[0] + cl[2] <= w, "nothing past the screen edge")

# ---- rects / raster
order = ["chevron", "lang", "net", "snd", "battery", "clock"]
R = {n: (F[n][0], F[n][1] + by, F[n][2], F[n][3]) for n in order}
rs = [R[n] for n in order]
say(all(rs[i][0] + rs[i][2] <= rs[i + 1][0] for i in range(5)), "fields in order %s, no overlap" % " < ".join(order))
gaps = [rs[i + 1][0] - (rs[i][0] + rs[i][2]) for i in range(5)]
say(max(gaps) - min(gaps) <= 1 and min(gaps) >= 4, "gaps between all tray fields identical +-1 (%s)" % gaps)
say(len(set((r[1], r[3]) for r in rs)) == 1, "one top and height for all fields")
say(all(R[n][2] == 24 * sc for n in ("chevron", "net", "snd")), "icon cells are %d wide (%s)" % (24 * sc, [R[n][2] for n in ("chevron", "net", "snd")]))

# ---- text ink inside the cell (picture)
def ink_cols(x0, y0, x1, y1, bg, thr=60):
    l = r = None
    for y in range(y0, y1):
        for x in range(x0, x1):
            p = at_px(x, y)
            if max(abs(p[0] - bg[0]), abs(p[1] - bg[1]), abs(p[2] - bg[2])) > thr:
                if l is None or x < l: l = x
                if r is None or x > r: r = x
    return l, r
bgc = at_px(rs[0][0] + rs[0][2] + gaps[0] // 2, rs[0][1] + rs[0][3] // 2)   # the gap between chevron and language = bar ground
for name in ("lang", "clock"):
    x, y, ww, hh = R[name]
    l, r = ink_cols(x - 1, y + 2, x + ww + 1, y + hh - 2, bgc)
    say(l is not None and l >= x + 1 and r <= x + ww - 2, "%s ink (x %s..%s) is inside its cell (%d..%d), not cut" % (name, l, r, x, x + ww))

# ---- no chip: just around the ink of every symbol / text the pixels are the ground next to the cell (a plate would be 32 steps off)
def inkbox(x0, y0, x1, y1, bg, thr=60):
    l = t = 10**9; r = bb = -1
    for y in range(y0, y1):
        for x in range(x0, x1):
            p = at_px(x, y)
            if max(abs(p[0] - bg[0]), abs(p[1] - bg[1]), abs(p[2] - bg[2])) > thr:
                l = min(l, x); r = max(r, x); t = min(t, y); bb = max(bb, y)
    return None if r < 0 else (l, t, r, bb)
bad = []
for k, name in enumerate(order):
    x, y, ww, hh = R[name]
    ref = at_px(x - max(gaps[max(k - 1, 0)] // 2, 2), y + hh // 2)       # the gap left of the cell, same row
    bb = inkbox(x + 1, y + 2, x + ww - 1, y + hh - 2, at_px(x + 1, y + hh // 2))
    if bb is None:
        bad.append((name, "no ink")); continue
    l, t, r, b = bb
    m = 2 * sc
    pts = [(l - m, (t + b) // 2), (r + m, (t + b) // 2), ((l + r) // 2, t - m), ((l + r) // 2, b + m)]
    for (qx, qy) in pts:
        if qx < x or qx >= x + ww or qy < y or qy >= y + hh: continue
        if not near(at_px(qx, qy), ref, 10): bad.append((name, qx, qy, at_px(qx, qy), ref))
say(not bad, "no plate/chip around any symbol or text: the pixels next to the ink are the bar ground (bad: %s)" % (bad[:3],))
print("RESULT ok=%d fail=%d" % (ok, fail)); sys.exit(1)
bx, by, bw, bh = geom
w, h, px = load_ppm(os.path.join(out, "00-bar.ppm"))
def at_px(x, y):
    o = (y * w + x) * 3
    return px[o], px[o + 1], px[o + 2]
def near(a, b, t=4): return max(abs(a[i] - b[i]) for i in range(3)) <= t

# ---- text reports of the fields
def texts(mark):
    return re.findall(r"taskbar: text %s x=(\d+) base=(\d+) fg=\d+ bg=\d+ tw=(\d+) t=(.*)" % mark, ser_bar)
lt = texts("lang"); ct = texts("clock")
say(F["lang"][4] == 1, "language field is ONE line (lines=%d)" % F["lang"][4])
code = "DEU" if lang == "de" else "ENG"
say(len(lt) >= 1 and lt[-1][3].strip() == code, "language text is the code only: %s" % ([t[3] for t in lt[-2:]],))
say(F["clock"][4] == 2, "clock field is two lines (lines=%d)" % F["clock"][4])
ctx = [t[3].strip() for t in ct[-2:]]
if "12h" in flags:
    say(len(ctx) == 2 and re.fullmatch(r"(1[0-2]|[1-9]):[0-5][0-9] (AM|PM)", ctx[0]) is not None, "12-hour time over date: %s" % ctx)
else:
    say(len(ctx) == 2 and re.fullmatch(r"[0-2][0-9]:[0-5][0-9]( \?)?", ctx[0]) is not None, "24-hour time over date: %s" % ctx)
dre = r"(..., )?[0-3][0-9]\.[01][0-9]\.20[0-9][0-9]" if "wday" in flags else r"[0-3][0-9]\.[01][0-9]\.20[0-9][0-9]"
say(len(ctx) == 2 and re.fullmatch(dre, ctx[1]) is not None, "date line %s%s" % (ctx[1:] , " (with weekday)" if "wday" in flags else ""))
say("kbd" not in "".join(re.findall(r"taskbar: icon field=(\w+)", ser_bar)), "no keyboard symbol in front of the language")

# ---- text inside its cell (reported widths)
for name, tl in (("lang", lt), ("clock", ct)):
    f = F[name]
    ok_all = bool(tl)
    for tx, base, wd, t in tl[-2:]:
        tx = int(tx); wd = int(wd)
        if not (tx >= f[0] + 2 and tx + wd <= f[0] + f[2] - 2): ok_all = False
    say(ok_all, "%s text lies inside its cell with >= 2 px air (cell x %d..%d, texts %s)" %
        (name, f[0], f[0] + f[2], [(int(t[0]), int(t[0]) + int(t[2])) for t in tl[-2:]]))
cl = F["clock"]
say(bw - (cl[0] + cl[2]) >= 8, "the clock cell ends >= 8 px before the bar edge (%d)" % (bw - (cl[0] + cl[2])))
say(bx + cl[0] + cl[2] <= w, "nothing past the screen edge")

# ---- rects / raster
order = ["chevron", "lang", "net", "snd", "battery", "clock"]
R = {n: (F[n][0], F[n][1] + by, F[n][2], F[n][3]) for n in order}
rs = [R[n] for n in order]
say(all(rs[i][0] + rs[i][2] <= rs[i + 1][0] for i in range(5)), "fields in order %s, no overlap" % " < ".join(order))
gaps = [rs[i + 1][0] - (rs[i][0] + rs[i][2]) for i in range(5)]
say(max(gaps) - min(gaps) <= 1 and min(gaps) >= 4, "gaps between all tray fields identical +-1 (%s)" % gaps)
say(len(set((r[1], r[3]) for r in rs)) == 1, "one top and height for all fields")
say(all(R[n][2] == 24 * sc for n in ("chevron", "net", "snd")), "icon cells are %d wide (%s)" % (24 * sc, [R[n][2] for n in ("chevron", "net", "snd")]))

# ---- text ink inside the cell (picture)
def ink_cols(x0, y0, x1, y1, bg, thr=60):
    l = r = None
    for y in range(y0, y1):
        for x in range(x0, x1):
            p = at_px(x, y)
            if max(abs(p[0] - bg[0]), abs(p[1] - bg[1]), abs(p[2] - bg[2])) > thr:
                if l is None or x < l: l = x
                if r is None or x > r: r = x
    return l, r
bgc = at_px(rs[0][0] + rs[0][2] + gaps[0] // 2, rs[0][1] + rs[0][3] // 2)   # the gap between chevron and language = bar ground
for name in ("lang", "clock"):
    x, y, ww, hh = R[name]
    l, r = ink_cols(x - 1, y + 2, x + ww + 1, y + hh - 2, bgc)
    say(l is not None and l >= x + 1 and r <= x + ww - 2, "%s ink (x %s..%s) is inside its cell (%d..%d), not cut" % (name, l, r, x, x + ww))

# ---- no chip: inset pixels of every cell are the bar ground
bad = []
for name in order:
    x, y, ww, hh = R[name]
    ins = 2 * sc
    pts = [(x + ins, y + ins), (x + ww - 1 - ins, y + ins), (x + ins, y + hh - 1 - ins), (x + ww - 1 - ins, y + hh - 1 - ins),
           (x + ins, y + hh // 2), (x + ww - 1 - ins, y + hh // 2)]
    for (qx, qy) in pts:
        if not near(at_px(qx, qy), bgc): bad.append((name, qx, qy, at_px(qx, qy)))
say(not bad, "no plate/chip behind any tray cell: corner/edge pixels == bar ground %s (bad: %s)" % (bgc, bad[:3]))
# the group capsule: the pixel between network and sound (inside the gap) is ground too
gx = rs[2][0] + rs[2][2] + gaps[2] // 2
say(near(at_px(gx, rs[2][1] + rs[2][3] // 2), bgc), "the gap inside the network/sound/battery group is bar ground")
print("RESULT ok=%d fail=%d" % (ok, fail))
sys.exit(1 if fail else 0)
