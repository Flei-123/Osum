#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/settingsnarrow/check.py <cfg> <serial.txt> <outdir> -- checks of tools/settingsnarrow/run.sh (exit 1 on any FAIL).
import re, sys, os

cfg, serial, outdir = sys.argv[1:4]
txt = open(serial, "rb").read().decode("latin1")
txt = re.sub(r"(?<=[^\n])wm: schlieren grow=\d+ alpha=\d+ blur=\d+ aus=\d+ unterpx=\d+\n", "", txt)
fails = 0


def ok(c, m):
    global fails
    print(("  OK    " if c else "  FAIL  ") + m)
    if not c:
        fails += 1


lay_re = re.compile(r"settings: layout nav=(\d+) detail=(\d+) scroll=(\d+) content=(\d+) view=(\d+) off=(\d+)")
rect_re = re.compile(r"settings: rect name=(\w+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
lays = []   # (nav, detail, scroll, content, view, off, rects since the last waa)
rects = {}
for ln in txt.splitlines():
    m = rect_re.search(ln)
    if m:
        n = m.group(1)
        if n == "waa":
            rects = {}
        rects[n] = tuple(int(m.group(i)) for i in range(2, 6))
        continue
    m = lay_re.search(ln)
    if m:
        lays.append(tuple(int(m.group(i)) for i in range(1, 7)) + (dict(rects),))

ok(len(lays) > 0, "layout lines reported (%d)" % len(lays))
if not lays:
    print("SETTINGSNARROW %s: no layout lines" % cfg)
    sys.exit(1)
ok(not re.search(r"ABSTURZ|EXCEPTION", txt), "no crash lines")

nav = cfg.startswith("nav")
first = lays[0]
ok(first[0] == (1 if nav else 0), "first report: navigation mode %s" % ("on" if nav else "off"))
ok(first[2] == 1, "first report: scrolling areas on (scroll=1)")

if nav:
    lst = [l for l in lays if l[1] == 0]
    pg = [l for l in lays if l[1] == 1]
    ok(len(lst) > 0 and lst[0][0] == 1, "list view shown first")
    ok(any(l[3] > l[4] > 0 for l in lst), "list is longer than the window (content > view) and scrolls")
    ok(any(l[5] > 0 for l in lst), "wheel over the list scrolled it (off > 0)")
    ok(len(pg) > 0, "picking 'Updates' opened the page (detail=1)")
    ok(any(l[3] > 0 and l[4] > 0 for l in pg), "page reports content and view sizes")
    long_page = any(l[3] > l[4] for l in pg)
    ok(long_page, "page is longer than the window (content > view)")
    ok(any(l[5] > 0 for l in pg), "wheel over the page scrolled it (off > 0)")
    # keyboard focus: the wheel is idle during the Tab phase, so the pane can only move because the focus reveal scrolls it.
    # A page with few Tab stops makes the focus WRAP (offsets fall again); a page with many stops only rises. Both are fine:
    # the wheel phase makes at most 3 page reports (down, down, back up), so 2 rises in the tail can only come from the reveal.
    # (serial lines of other programs may eat single reports, so 4 intact reports are enough: open + 3 reveal steps.)
    offs = [l[5] for l in pg]
    tail = offs[-6:]
    rises = sum(1 for i in range(len(tail) - 1) if tail[i] < tail[i + 1])
    falls = sum(1 for i in range(len(tail) - 1) if tail[i] > tail[i + 1])
    maxoff = max((l[3] - l[4] for l in pg), default=0)
    seq_ok = len(offs) >= 4 and rises >= 2 and max(tail) > 0 and max(offs) <= maxoff
    ok(seq_ok, "Tab focus scrolled the page (reveal moves the pane while the focus walks, wrap optional: %s)" % tail)
    ok(lays[-1][1] == 0, "Back returned to the list (detail=0)")
    ok(any("whp" in l[6] for l in pg), "Back button reported on the page")
    # nothing cut off at the right edge: every reported control of the page (first page report, offset 0)
    pgr = [l[6] for l in pg if "waa" in l[6]]
    if pgr:
        r = pgr[0]
        if "waa" in r:
            wx, wy, ww, wh = r["waa"]
            sk = max(1, wx // 8)
            right = ww + 16 * sk
            bad = [n for n, (x, y, w, h) in r.items() if n != "waa" and w > 0 and x + w > right + 1]
            ok(not bad, "no reported control past the right edge (%s)" % ",".join(bad[:6]))
else:
    ok(first[0] == 0, "no navigation mode in an 800 point window")
    pg = [l for l in lays if l[3] > 0]
    ok(any(l[3] > 0 and l[4] > 0 for l in pg), "page area reports content and view sizes")
    if any(l[3] > l[4] for l in pg):
        ok(any(l[5] > 0 for l in pg), "page longer than the window scrolls with the wheel (off > 0)")
    else:
        ok(True, "page fits the window (no scrolling needed)")

# pictures: taken, and the page differs from the list
def ppm(n):
    p = os.path.join(outdir, n + ".ppm")
    return open(p, "rb").read() if os.path.exists(p) else None

names = ["00-start", "01-wheel1", "02-wheel2", "03-page", "04-page-wheel1", "05-page-wheel2", "06-back"]
got = [ppm(n) for n in names]
ok(all(g for g in got), "all pictures taken")
if all(got):
    if nav:
        ok(got[0] != got[3], "the page looks different from the list")
        ok(got[3] != got[4] or got[3] != got[5], "page picture changes with the wheel")
        ok(got[6] == got[0] or got[6] != got[3], "Back shows the list again")
print("SETTINGSNARROW %s: %s" % (cfg, "FAIL" if fails else "OK"))
sys.exit(1 if fails else 0)
