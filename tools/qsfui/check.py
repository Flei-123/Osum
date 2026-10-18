#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/qsfui/check.py -- is the quick-settings panel laid out like Windows 11?

    check.py <serial.txt> <shot.ppm> <ui_scale> [--shift]

Reads the panel's own scene report (`qs: open`, `qs: kachel`, `qs: platte`,
`qs: label`, `qs: regler`, `qs: medien`, `qs: fussb`) and the picture, and
judges:

  1. five tiles, three to a row (3 + 2), every cell and every plate EQUAL in size
  2. nothing outside the panel: tiles, labels, sliders, media tile, footer buttons
  3. the label stands UNDER the plate (below its bottom edge), inside its cell
  4. the sliders lie inside the panel with a margin (they used to run out of it)
  5. PIXELS: the label ink lies inside its cell -- the gaps between the cells and
     the strip right of the last cell are free of ink at label height
  6. PIXELS: every label has ink (it was painted), the media tile has ink
  7. the gear is the right-most footer button, the battery glyph stands left of it

`--shift` is the counter-proof: every rectangle moved half a cell to the right --
the check must complain, otherwise it measures nothing.
Exit code 0 = all OK.
"""
import re
import sys


def ppm(path):
    d = open(path, "rb").read()
    f = []
    at = 2
    while len(f) < 3:
        while d[at:at + 1].isspace():
            at += 1
        s = at
        while not d[at:at + 1].isspace():
            at += 1
        f.append(int(d[s:at]))
    at += 1
    w, h, _ = f
    return w, h, d[at:]


def kv(line):
    d = {k: int(v) for k, v in re.findall(r"(\w+)=(\d+)", line)}
    # a line torn by other serial output (loaded host) lacks a key: it is not a report
    return d if all(k in d for k in ("x", "y", "w", "h")) else {}


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    shift = "--shift" in sys.argv
    serial = open(args[0], "rb").read().decode("latin1")
    pw, ph, pix = ppm(args[1])
    sc = int(args[2])
    out = []

    def ok(c, msg):
        out.append(("OK    " if c else "FAIL  ") + msg)

    lines = serial.splitlines()
    op = [d for d in (kv(l) for l in lines if l.startswith("qs: open ")) if d]
    if not op:
        ok(False, "no 'qs: open'")
        print("\n".join(out))
        return 1
    qx, qy, qw, qh = op[-1]["x"], op[-1]["y"], op[-1]["w"], op[-1]["h"]

    def last(prefix):
        got = {}
        for l in lines:
            if l.startswith(prefix):
                d = kv(l)
                if d and "n" in d:
                    got[d["n"]] = d
        return got

    cells = last("qs: kachel n=")
    plates = last("qs: platte n=")
    labels = last("qs: label n=")
    reg = {}
    for l in lines:
        for nm in ("hell", "vol"):
            if l.startswith("qs: regler " + nm):
                if kv(l):
                    reg[nm] = kv(l)
    med = [d for d in (kv(l) for l in lines if l.startswith("qs: medien ")) if d][-1:]
    fuss = last("qs: fussb n=")
    dx = (100 * sc) // 2 if shift else 0

    def inside(r, what, margin=0):
        x, y, w, h = r["x"] + dx, r["y"], r["w"], r["h"]
        good = x >= margin and y >= margin and x + w <= qw - margin and y + h <= qh - margin
        ok(good, "%s inside the panel %dx%d (x=%d y=%d w=%d h=%d)" % (what, qw, qh, x, y, w, h))

    # 1. the grid
    ok(len(cells) >= 5, "%d tiles reported (need 5)" % len(cells))
    if len(cells) < 5 or len(plates) < 5 or len(labels) < 5:
        ok(False, "plates %d / labels %d reported (need 5 each)" % (len(plates), len(labels)))
        print("\n".join(out))
        return 1
    ws = {c["w"] for c in cells.values()}
    hs = {c["h"] for c in cells.values()}
    ok(len(ws) == 1 and len(hs) == 1, "every cell has the same size (w %s, h %s)" % (sorted(ws), sorted(hs)))
    pws = {p["w"] for p in plates.values()}
    phs = {p["h"] for p in plates.values()}
    ok(len(pws) == 1 and len(phs) == 1 and pws == ws,
       "every plate has the same size, as wide as its cell (w %s, h %s)" % (sorted(pws), sorted(phs)))
    ok(ws == {100 * sc}, "a cell is %d pixels wide (100 points)" % (100 * sc))
    ys = sorted({c["y"] for c in cells.values()})
    perrow = [sum(1 for c in cells.values() if c["y"] == y) for y in ys]
    ok(perrow == [3, 2], "three tiles to a row, then two (rows: %s)" % perrow)
    xs = sorted({c["x"] for c in cells.values()})
    ok(len(xs) == 3 and xs[1] - xs[0] == xs[2] - xs[1], "three equal columns (x: %s)" % xs)
    # 2. nothing outside
    for n, c in sorted(cells.items()):
        inside(c, "tile %d" % n)
    for nm, r in sorted(reg.items()):
        inside(r, "slider %s" % nm, 8 * sc)
        ok(r["w"] >= 120 * sc, "slider %s is wide enough to use (%d px)" % (nm, r["w"]))
    ok(len(med) == 1, "the media tile is reported")
    if med:
        inside(med[0], "media tile", 8 * sc)
    for n, f in sorted(fuss.items()):
        inside({"x": f["x"] - qx, "y": f["y"] - qy, "w": f["w"], "h": f["h"]}, "footer button %d" % n)
    if 0 in fuss and 1 in fuss:
        ok(fuss[1]["x"] > fuss[0]["x"], "the gear stands right of the task manager button (gear is right-most)")
        right = qx + qw - 16 * sc
        ok(abs(fuss[1]["x"] + fuss[1]["w"] - right) <= 4 * sc,
           "the gear stands bottom right: its right edge %d is at the card's inner edge %d" % (fuss[1]["x"] + fuss[1]["w"], right))
    # 3. label under plate
    for n in sorted(cells):
        p, l, c = plates[n], labels[n], cells[n]
        ok(l["y"] >= p["y"] + p["h"] and l["y"] + l["h"] <= c["y"] + c["h"] + 1,
           "tile %d: the label (y %d..%d) is under the plate (bottom %d), inside the cell" %
           (n, l["y"], l["y"] + l["h"], p["y"] + p["h"]))
    # 5/6 pixels
    def px(x, y):
        o = (y * pw + x) * 3
        return pix[o], pix[o + 1], pix[o + 2]

    def far(a, b):
        return abs(a[0] - b[0]) + abs(a[1] - b[1]) + abs(a[2] - b[2]) > 90

    # the card colour: the pixel in the panel's top-left padding
    bg = px(qx + 3 * sc, qy + qh // 2)
    row_by_y = {}
    for n, c in cells.items():
        row_by_y.setdefault(c["y"], []).append(n)
    # the harness paints a measurement strip over the top of the screen (fb.band);
    # 'qs: open ... ay=' reports where the free work area starts. Pixels above it are not the panel.
    free_top = 0
    for l in lines:
        if l.startswith("qs: open "):
            m = re.search(r" ay=(\d+)", l)
            if m:
                free_top = int(m.group(1))
    for y, ns in sorted(row_by_y.items()):
        ns.sort(key=lambda n: cells[n]["x"])
        l0 = labels[ns[0]]
        band = range(qy + l0["y"], qy + l0["y"] + l0["h"])
        if qy + l0["y"] < free_top:
            ok(True, "row at y=%d: label band (screen y %d) lies under the harness strip (free area starts at %d), pixel check skipped"
               % (y, qy + l0["y"], free_top))
            continue
        # gaps between cells and right of the last
        edges = []
        for i, n in enumerate(ns):
            c = cells[n]
            right = c["x"] + c["w"]
            nxt = cells[ns[i + 1]]["x"] if i + 1 < len(ns) else qw - 2 * sc
            edges.append((right + dx, nxt + dx))
        left_gap = (2 * sc, cells[ns[0]]["x"] + dx)
        bad = 0
        for (a, b) in edges + [left_gap]:
            for yy in band:
                for xx in range(qx + a, qx + b):
                    if 0 <= xx < pw and yy < ph and far(px(xx, yy), bg):
                        bad += 1
        ok(bad == 0, "row at y=%d: no label ink in the gaps between the cells / beside the row (%d stray pixels)" % (y, bad))
        for n in ns:
            c = cells[n]
            ink = 0
            for yy in band:
                for xx in range(qx + c["x"] + dx, qx + c["x"] + dx + c["w"]):
                    if 0 <= xx < pw and yy < ph and far(px(xx, yy), bg):
                        ink += 1
            ok(ink >= 12 * sc, "tile %d: the label has ink under its plate (%d pixels)" % (n, ink))
    if med:
        m = med[0]
        mp = px(qx + m["x"] + m["w"] // 2, qy + m["y"] + 3 * sc)
        ok(far(mp, bg) or mp != bg, "the media tile is drawn as a plate (%s vs card %s)" % (mp, bg))
        ink = 0
        for yy in range(qy + m["y"] + 4 * sc, qy + m["y"] + m["h"] - 4 * sc):
            for xx in range(qx + m["x"] + 40 * sc, qx + m["x"] + m["w"] - 8 * sc):
                if far(px(xx, yy), mp):
                    ink += 1
        ok(ink >= 30 * sc, "the media tile carries text (%d pixels)" % ink)
    print("\n".join(out))
    return 0 if all(o.startswith("OK") for o in out) else 1


sys.exit(main())
