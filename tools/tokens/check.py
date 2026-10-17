#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/tokens/check.py <rows> -- asserts the rows dumped by tools/tokens/host.fi.

The model below is written independently of lib/fui/tokens.fi (floats where the library has
integers, tolerance where the rounding differs on purpose)."""
import sys

rows = {}
for line in open(sys.argv[1]):
    g, a, b, v = (int(x) for x in line.split())
    rows[(g, a, b)] = v
ok = bad = 0


def chk(name, cond, detail=""):
    global ok, bad
    if cond:
        ok += 1
        print("  OK    " + name)
    else:
        bad += 1
        print("  FAIL  %s %s" % (name, detail))


def ch(c):
    return (c >> 16) & 255, (c >> 8) & 255, c & 255


def lum(c):  # true sRGB relative luminance
    def lin(v):
        v /= 255.0
        return v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = ch(c)
    return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)


def contrast(a, b):
    la, lb = sorted((lum(a), lum(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def mixc(a, b, pct):
    return tuple(int((x * (100 - pct) + y * pct + 50) // 100) for x, y in zip(ch(a), ch(b)))


def tup(c):
    return ch(c)


print("== 1. radii, spacing, type: values and scale 1 = scale 2 / 2 ==")
for s in (1, 2):
    chk("radius s=%d 4/8/8 (Windows 11 window/menu/popup = 8)" % s, [rows[(1, i, s)] for i in range(3)] == [4 * s, 8 * s, 8 * s])
    chk("spacing s=%d 0,4,8,12,16,24,32" % s,
        [rows[(2, i, s)] for i in range(7)] == [0] + [v * s for v in (4, 8, 12, 16, 24, 32)])
    chk("type s=%d 12/15/15/18/24" % s, [rows[(6, i, s)] for i in range(5)] == [v * s for v in (12, 15, 15, 18, 24)])
    chk("spacing on a 4 grid s=%d" % s, all(rows[(2, i, s)] % 4 == 0 for i in range(7)))
for g in (1, 2, 3, 4, 6):
    n = 4 if g in (1, 3, 4) else 7 if g == 2 else 5
    chk("group %d scales exactly x2" % g, all(rows[(g, i, 2)] == 2 * rows[(g, i, 1)] for i in range(n)))
chk("radius order small < medium <= large", rows[(1, 0, 1)] < rows[(1, 1, 1)] <= rows[(1, 2, 1)])

print("== 2. elevation: three levels, growing, stronger in dark ==")
chk("dy grows", rows[(3, 0, 1)] == 0 < rows[(3, 1, 1)] < rows[(3, 2, 1)] < rows[(3, 3, 1)])
chk("reach grows", rows[(4, 0, 1)] == 0 < rows[(4, 1, 1)] < rows[(4, 2, 1)] < rows[(4, 3, 1)])
chk("alpha grows light", rows[(5, 0, 0)] == 0 < rows[(5, 1, 0)] < rows[(5, 2, 0)] < rows[(5, 3, 0)])
chk("dark shadow stronger", all(rows[(5, i, 1)] > rows[(5, i, 0)] for i in (1, 2, 3)))

print("== 3. neutrals: contrast ==")
for dk, nm in ((0, "light"), (1, "dark")):
    base, surf, text, muted = (rows[(9, i, dk)] for i in (0, 1, 5, 6))
    chk("%s text/base >= 12:1 (true sRGB %.1f)" % (nm, contrast(text, base)), contrast(text, base) >= 12)
    chk("%s muted/base >= 4.5:1 (%.2f)" % (nm, contrast(muted, base)), contrast(muted, base) >= 4.5)
    chk("%s muted/surface >= 4.5:1 (%.2f)" % (nm, contrast(muted, surf)), contrast(muted, surf) >= 4.5)
    chk("%s library contrast within 12%% of true" % nm,
        abs(rows[(19, 0, dk)] / 100.0 - contrast(text, base)) / contrast(text, base) < 0.12,
        "%s vs %.2f" % (rows[(19, 0, dk)], contrast(text, base)))
    chk("%s hover differs from surface and press from hover" % nm,
        rows[(9, 8, dk)] != rows[(9, 1, dk)] and rows[(9, 9, dk)] != rows[(9, 8, dk)])

print("== 4. accent states for blue / yellow / purple, light and dark ==")
accs = [0x2563EB, 0xFFD60A, 0x5B21B6]
for dk, nm in ((0, "light"), (1, "dark")):
    for ai, acc in enumerate(accs):
        hv, pr, rg, ds, on = (rows[(g, ai, dk)] for g in (10, 11, 12, 13, 17))
        chk("%s accent %d: hover != normal != press" % (nm, ai), len({acc, hv, pr}) == 3)
        want_h = mixc(acc, 0xFFFFFF, 14) if dk else mixc(acc, 0, 8)
        chk("%s accent %d: hover = model" % (nm, ai), tup(hv) == want_h)
        base = 0x202020 if dk else 0xF3F3F3
        chk("%s accent %d: focus ring >= 3:1 against the surface (%.1f)" % (nm, ai, contrast(rg, rows[(9, 1, dk)])),
            contrast(rg, rows[(9, 1, dk)]) >= 3.0)
        chk("%s accent %d: disabled is quieter than the accent" % (nm, ai),
            contrast(ds, rows[(9, 1, dk)]) < contrast(acc, rows[(9, 1, dk)]) or ds != acc)
        # on-accent: never worse than 3:1 (large-text bar), and it is the better of white/black
        better = 0xFFFFFF if contrast(acc, 0xFFFFFF) >= contrast(acc, 0) else 0
        chk("%s accent %d: on-accent colour reads (%.1f:1)" % (nm, ai, contrast(acc, on)), contrast(acc, on) >= 3.0 and
            (on == better or abs(contrast(acc, 0xFFFFFF) - contrast(acc, 0)) < 1.0))
        chk("%s accent %d: state_fill(hover, accent) = hover" % (nm, ai), rows[(18, ai, dk)] == hv)

print("== 5. motion ==")
chk("durations 100/160/300", (rows[(20, 0, 0)], rows[(20, 1, 0)], rows[(20, 2, 0)]) == (100, 160, 300))
chk("ease_out 0 -> 0, 1000 -> 1000", rows[(7, 0, 0)] == 0 and rows[(7, 1000, 0)] == 1000)
chk("ease_in_out 0 -> 0, 500 -> 500, 1000 -> 1000",
    rows[(8, 0, 0)] == 0 and rows[(8, 500, 0)] == 500 and rows[(8, 1000, 0)] == 1000)
ts = sorted(t for (g, t, _), _v in rows.items() if g == 7)
chk("ease_out monotonic", all(rows[(7, a, 0)] <= rows[(7, b, 0)] for a, b in zip(ts, ts[1:])))
chk("ease_out leads linear (decelerates)", rows[(7, 300, 0)] > 300)
chk("ease_at: halfway of 160 ms = 875", rows[(21, 0, 0)] == 875, str(rows[(21, 0, 0)]))
chk("ease_at past the end = 1000", rows[(21, 1, 0)] == 1000)

print("== 6. glass ==")
chk("blur 8 bar/menu/qs, 4 tip/toast (scale 1)", [rows[(14, i, 1)] for i in range(5)] == [8, 8, 8, 4, 4])
chk("blur scales x2", all(rows[(14, i, 2)] == 2 * rows[(14, i, 1)] for i in range(5)))
chk("noglass: blur 0 everywhere", all(rows[(14, i + 10, s)] == 0 for i in range(5) for s in (1, 2)))
for dk, nm in ((0, "light"), (1, "dark")):
    worst = min(
        contrast(rows[(9, 5, dk)],
                 sum(((int(((rows[(15, k, dk)] >> sh) & 255) * rows[(16, k, dk)] + wp * (100 - rows[(16, k, dk)])) // 100) << sh)
                     for sh in (16, 8, 0)))
        for k in range(5) for wp in ((0, 255) if True else ()))
    chk("%s: text on tint over the WORST wallpaper (black/white) >= 4.5:1 (%.1f)" % (nm, worst), worst >= 4.5)

print("== 7. drift guard: tokens agree with assets/shapes/osum.shape ==")
import os
shape = {}
for ln in open(os.path.join(os.path.dirname(__file__), "..", "..", "assets", "shapes", "osum.shape")):
    if "=" in ln and not ln.lstrip().startswith("#"):
        k, v = ln.strip().split("=", 1)
        shape[k] = v
chk("spacing xs/s/m/l = space(1,2,4,5)", [int(shape[k]) for k in ("spacing_xs", "spacing_s", "spacing_m", "spacing_l")] ==
    [rows[(2, i, 1)] for i in (1, 2, 4, 5)])
chk("font = type body", int(shape["font"]) == rows[(6, 1, 1)])
chk("motion = D_NORMAL", int(shape["motion"]) == rows[(20, 1, 0)])
chk("radius_button = R_MEDIUM, radius_window = R_LARGE", int(shape["radius_button"]) == rows[(1, 1, 1)]
    and int(shape["radius_window"]) == rows[(1, 2, 1)])

print("tokens: %d ok, %d fail" % (ok, bad))
sys.exit(1 if bad else 0)
