#!/usr/bin/env python3
import sys


def fui_close(d, sb):
    if d == 0 or sb == 0 or sb > d:
        return set()
    kn = d - (sb - 1)
    wide = kn + sb - 1
    up = kn
    ox = (d - wide) // 2 if d > wide else 0
    oy = (d - up) // 2 if d > up else 0
    p = set()
    for k in range(kn):
        for t in range(sb):
            p.add((ox + k + t, oy + k))
            p.add((ox + kn - 1 - k + t, oy + k))
    return p

def _border(x, y, w, h, st):
    if w == 0 or h == 0 or st == 0:
        return set()
    s = st
    if 2 * s > w or 2 * s > h:
        s = 1
    p = set()
    for yy in range(s):
        for xx in range(w):
            p.add((x + xx, y + yy)); p.add((x + xx, y + h - s + yy))
    for yy in range(h - 2 * s):
        for xx in range(s):
            p.add((x + xx, y + s + yy)); p.add((x + w - s + xx, y + s + yy))
    return p

def fui_maximize(d, sb):
    return _border(0, 0, d, d, sb) if d and sb else set()

def fui_restore(d, sb):
    if d == 0 or sb == 0:
        return set()
    v = 2 * sb
    if d <= v:
        return _border(0, 0, d, d, sb)
    k = d - v
    return _border(v, 0, k, k, sb) | _border(0, v, k, k, sb)

def fui_minimize(d, sb):
    if d == 0 or sb == 0:
        return set()
    oy = d // 2
    if sb > 1:
        oy = oy - sb // 2 if oy >= sb // 2 else 0
    return {(x, oy + t) for x in range(d) for t in range(sb)}


def wm_alt_close(d, sb):
    kn = d - (sb - 1)
    off = (d - (kn + sb - 1)) // 2
    p = set()
    for k in range(kn):
        for t in range(sb):
            p.add((off + k + t, off + k))
            p.add((off + kn - 1 - k + t, off + k))
    return p

def wm_alt_box_thick(x, y, w, h, sb):
    p = set()
    for t in range(sb):
        for k in range(w):
            p.add((x + k, y + t)); p.add((x + k, y + h - 1 - t))
        for k in range(h):
            p.add((x + t, y + k)); p.add((x + w - 1 - t, y + k))
    return p

def wm_alt_max(d, sb):
    return wm_alt_box_thick(0, 0, d, d, sb)

def wm_alt_restore(d, sb, sk):
    e = 2 * sk
    return wm_alt_box_thick(e, 0, d - e, d - e, sb) | \
           wm_alt_box_thick(0, e, d - e, d - e, sb)

def wm_alt_min(d, sb):
    return {(x, d // 2 + t) for x in range(d) for t in range(sb)}

def show(p, d, name):
    print(f"      {name}:")
    for y in range(d):
        print("      " + "".join("#" if (x, y) in p else "." for x in range(d)))

def main():
    alt = "--alt" in sys.argv
    char = [
        ("Minimieren",       fui_minimize, lambda d, sb, sk: wm_alt_min(d, sb)),
        ("Maximieren",       fui_maximize, lambda d, sb, sk: wm_alt_max(d, sb)),
        ("Wiederherstellen", fui_restore,  wm_alt_restore),
        ("Schliessen",       fui_close,    lambda d, sb, sk: wm_alt_close(d, sb)),
    ]
    print("THE KERNEL NOW PAINTS WITH fui.core -- the shape comes from ONE file.")
    print()
    print("After the switch kernel/ui/wm.fi `cap_glyph` calls the routines from")
    print("lib/fui/core.fi of the toolchain. The first column is therefore by")
    print("construction zero: it IS the same source. The second column shows")
    print("what the old, self-painted version would have done differently.")
    print()
    print(f"{'uisc':>4} {'d':>3} {'sb':>3} | {'Char':<17} "
          f"{'Points':>7} | {'new!=fUi':>9} {'alt!=fUi':>9}")
    print("-" * 72)
    schlimm = 0
    for sk in (1, 2, 3, 4):
        d, sb = 10 * sk, sk
        for name, ff, wf in char:
            f = ff(d, sb)
            a = wf(d, sb, sk)
            d_new = 0
            d_alt = len(f ^ a)
            schlimm = max(schlimm, d_alt)
            print(f"{sk:>4} {d:>3} {sb:>3} | {name:<17} {len(f):>7} | "
                  f"{d_new:>9} {d_alt:>9}")
    print("-" * 72)
    print(f"largest deviation of the OLD version: {schlimm} pixels")
    print()
    if schlimm:
        print("THAT WAS THE BUG: the cross of the old version computed ONE")
        print("offset for both axes, although width (kn + sb - 1) and")
        print("height (kn) differ. At uisc 1 and 2 it is not")
        print("noticeable -- from uisc 3 the cross sticks to the top.")
    if alt:
        for sk in (2, 3):
            d, sb = 10 * sk, sk
            print()
            print(f"--- Schliessen, uisc={sk} (d={d}, sb={sb}) ---")
            show(fui_close(d, sb), d, "fui.core / Kern NEU")
            if fui_close(d, sb) != wm_alt_close(d, sb):
                show(wm_alt_close(d, sb), d, "wm.fi ALT")
    return 0

if __name__ == "__main__":
    sys.exit(main())
