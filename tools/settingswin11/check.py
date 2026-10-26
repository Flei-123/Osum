#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/settingswin11/check.py <cfg> <serial.txt> <outdir> -- checks of tools/settingswin11/run.sh.
# cfg flat is the counter-proof: the accordion checks must be RED there (exit 0 only when they are).
import re, sys, os

cfg, serial, outdir = sys.argv[1:4]
txt = open(serial, "rb").read().decode("latin1")
txt = re.sub(r"(?<=[^\n])wm: schlieren grow=\d+ alpha=\d+ blur=\d+ aus=\d+ unterpx=\d+\n", "", txt)
rect_re = re.compile(r"settings: rect name=(\w+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
reports = []
cur = None
for ln in txt.splitlines():
    m = rect_re.search(ln)
    if not m:
        continue
    n = m.group(1)
    if n == "waa":
        cur = {}
        reports.append(cur)
    if cur is None:
        continue
    cur[n] = tuple(int(m.group(i)) for i in range(2, 6))

fails = []
passes = []


def check(c, msg):
    (passes if c else fails).append(msg)
    print(("  OK    " if c else "  FAIL  ") + msg)


def tabs(r):
    return {n for n in r if n.startswith("tab")}


def ppm(n):
    p = os.path.join(outdir, n + ".ppm")
    return open(p, "rb").read() if os.path.exists(p) else None


check(len(reports) > 0, "rect reports present (%d)" % len(reports))
check(not re.search(r"ABSTURZ|EXCEPTION|^panic", txt, re.M), "no crash lines")
check(os.path.exists(os.path.join(outdir, "00-start.ppm")), "start picture taken")
first = reports[0] if reports else {}
check("wdu" in first, "search field reported")
if "wdu" in first and tabs(first):
    top = min(first[t][1] for t in tabs(first))
    check(first["wdu"][1] < top, "search field sits above the sidebar (y %d < %d)" % (first["wdu"][1], top))
after = None
for r in reports[1:]:
    if "tabq" in r:
        after = r
        break
acc = []
n0 = len(tabs(first))
acc.append(("sidebar shows few pages at start (%d <= 17)" % n0, n0 <= 17 and n0 >= 5))
acc.append(("sub-pages of other categories are hidden at start (no tabq)", "tabq" not in first))
acc.append(("opening System shows its sub-pages (tabq appears)", after is not None))
if after is not None:
    acc.append(("opening System collapses Personalization (tab24 gone)", "tab24" not in after))
else:
    acc.append(("opening System collapses Personalization (tab24 gone)", False))
if cfg == "flat":
    bad = [m for m, c in acc if not c]
    check(len(bad) >= 2, "counter-proof: accordion checks are red in flat mode (%d red)" % len(bad))
    print("SETTINGSWIN11 flat: %s" % ("OK" if not fails else "FAIL"))
    sys.exit(1 if fails else 0)
for m, c in (acc[:1] if cfg == "narrow" else acc):
    check(c, m)
if cfg in ("light", "dark", "hd"):
    for n in ("01-system", "02-power", "03-search"):
        check(ppm(n) is not None, "picture %s taken" % n)
    if ppm("00-start") and ppm("01-system"):
        check(ppm("00-start") != ppm("01-system"), "System page looks different from the start page")
    if ppm("02-power") and ppm("03-search"):
        check(ppm("02-power") != ppm("03-search"), "search changes the sidebar")
if cfg == "hd":
    def px(name):
        d = ppm(name)
        if d is None:
            return None
        m = re.match(rb"P6\s+(\d+)\s+(\d+)\s+(\d+)\s", d)
        w, h = int(m.group(1)), int(m.group(2))
        return w, d[m.end():]

    def at(img, x, y):
        w, data = img
        o = (y * w + x) * 3
        return data[o:o + 3]

    def crop(img, x, y, w, h):
        return b"".join(img[1][((y + j) * img[0] + x) * 3:((y + j) * img[0] + x + w) * 3] for j in range(h))

    rect = None
    for r in reports:
        if "tabq" in r and "tabl" in r:
            rect = r
            break

    def mean(img, x, y, w, h):
        n = 0
        acc = [0, 0, 0]
        for yy in range(y, y + h):
            o = (yy * img[0] + x) * 3
            for k in range(w):
                for c in range(3):
                    acc[c] += img[1][o + k * 3 + c]
                n += 1
        return [v / n for v in acc]

    def delta(a, b):
        return max(abs(a[i] - b[i]) for i in range(3))

    shots = [px(n) for n in ("04-hover-other", "05-hover-selected", "06-hover-none", "07-down-other")]
    check(rect is not None and all(shots), "hover pictures and rects present")
    if rect is not None and all(shots):
        rx, ry, rw, rh = rect["tabl"]
        gx, gy, gw, gh = rx + 6, ry + 4, 110, rh - 8
        hov, sel, none, down = shots
        mh, ms, mn, md = (mean(s, gx, gy, gw, gh) for s in (hov, sel, none, down))
        check(delta(mh, mn) >= 6, "hover paints a plate on an entry, pointer pixels excluded (delta %.1f)" % delta(mh, mn))
        check(delta(ms, mn) <= 2, "pointer elsewhere leaves the entry plain (delta %.1f)" % delta(ms, mn))
        check(delta(md, mh) >= 4, "pressed entry is darker than hovered (delta %.1f)" % delta(md, mh))
        my = ry + rh // 2
        edge = [at(none, rx + 6 + k, my) for k in range(0, 3)]
        ref = at(none, rx - 4, my)
        check(all(e == ref for e in edge), "no left edge on an unselected entry")
print("SETTINGSWIN11 %s: %s" % (cfg, "FAIL" if fails else "OK"))
sys.exit(1 if fails else 0)
