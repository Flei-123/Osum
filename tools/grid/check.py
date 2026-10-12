#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/grid/check.py <rows> -- asserts the rows dumped by tools/grid/host.fi against an independent model
(the model walks items one by one; the library uses closed formulas)."""
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


def group(g):
    return {k[1:]: v for k, v in rows.items() if k[0] == g}


CW, CH, GAP = 190, 90, 12

# 1 columns: the largest c with c*cw + (c-1)*gap <= avail, at least 1
bad1 = [(a, v) for (a, _), v in group(1).items()
        if v != max(1, max([c for c in range(1, 60) if c * CW + (c - 1) * GAP <= a] or [1]))]
chk("columns for %d widths" % len(group(1)), not bad1, bad1[:3])
# 2/3 rows and content height
g2, g3 = group(2), group(3)
chk("rows for %d (n, cols)" % len(g2), all(v == -(-n // c) for (n, c), v in g2.items()))
chk("content height for %d (n, cols)" % len(g3),
    all(v == (0 if n == 0 else (-(-n // c)) * CH + (-(-n // c) - 1) * GAP) for (n, c), v in g3.items()))
# 4/5 the visible range: walk the items and ask which rectangles touch the view
def vis(sc, view, n, cols=3):
    out = []
    for i in range(n):
        top = (i // cols) * (CH + GAP)
        if top < sc + view and top + CH > sc:
            out.append(i)
    return out

g4, g5 = group(4), group(5)
badf = [(sc, v) for (sc, _), v in g4.items() if (vis(sc, 100000, 40) or [40])[0] != v and not (v >= 40)]
chk("first visible item for %d scroll offsets" % len(g4), not badf, badf[:3])
badc = []
for (sc, view), v in g5.items():
    want = vis(sc, view, 40)
    first = g4[(sc, 0)]
    if want and (first != want[0] or v != len(want)):
        badc.append((sc, view, first, v, want[0], len(want)))
chk("visible count for %d (scroll, view)" % len(g5), not badc, badc[:3])
# 6 scroll_to: the item is fully visible afterwards, and the offset moved only when it had to
bads = []
for (i, sc), v in group(6).items():
    top = (i // 3) * (CH + GAP)
    fully = lambda s: top >= s and top + CH <= s + 200
    if not fully(v):
        bads.append((i, sc, v, "not visible"))
    if fully(sc) and v != sc:
        bads.append((i, sc, v, "moved although visible"))
    if not fully(sc) and v not in (top, max(0, top + CH - 200)):
        bads.append((i, sc, v, "not the nearest edge"))
chk("scroll_to for %d (item, scroll)" % len(group(6)), not bads, bads[:3])
# 7/8/9 pages
chk("pages", all(v == max(1, -(-n // pp)) for (n, pp), v in group(7).items()))
chk("items on a page", all(v == max(0, min(pp, n - pg * pp)) for (k, pp), v in group(8).items()
                           for n, pg in [(k // 100, k % 100)]))
chk("page_of / page_first", all(v == (n // pp) * 1000 + (n // pp) * pp for (n, pp), v in group(9).items()))
# 10 arrow keys: a step to a neighbour that exists, otherwise stay; never leaves 0..n-1
badm = []
for (jk, nc), v in group(10).items():
    j, k = jk // 10, jk % 10
    n, c = nc // 10, nc % 10
    r, col = divmod(j, c)
    want = j
    if k == 0 and col > 0: want = j - 1
    if k == 1 and col + 1 < c and j + 1 < n: want = j + 1
    if k == 2 and r > 0: want = j - c
    if k == 3 and j + c < n: want = j + c
    if v != want:
        badm.append((j, k, n, c, v, want))
chk("arrow keys for %d (item, key, n, cols)" % len(group(10)), not badm, badm[:3])
chk("cell position", rows[(11, 0, 0)] == (7 % 3) * (CW + GAP) and rows[(11, 1, 0)] == (7 // 3) * (CH + GAP))
print("GRID: %d passed, %d failed" % (ok, bad))
sys.exit(1 if bad else 0)
