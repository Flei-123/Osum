#!/usr/bin/env python3
"""tools/desktop/rects.py -- CHECK THE TASKBAR AND THE WORK AREA BY
ARITHMETIC, not by looking at the picture.

A screenshot cannot answer the question this addendum is about. A window
that is one pixel under the taskbar and a window that is flush against
it look the same at a glance, and a window that is exactly as large as
the screen looks right until something is drawn on the strip the taskbar
occupies. So the numbers are compared instead, and they come from three
independent places:

  `wm: win ...`       the server's own window table, one line per window
                      (kernel/kmain.fi, `say_wins`). Carries x, y, the
                      OUTER size, the layer and the strut.
  `wm: work ...`      the work area as the SERVER computes it.
  `taskbar: work ...` the work area as the TASKBAR reads it back through
                      WM_INFO, from ring 3.

What is checked:

  1. The bar sits ON its edge, with its full length along that edge.
  2. work area = screen minus the bar, exactly. No pixel unaccounted for.
  3. The server's work area and the taskbar's agree. Two paths, one
     answer -- if they disagree, one of them is a cached copy, which is
     precisely the mistake this design set out not to make.
  4. The maximized window's OUTER rectangle IS the work area.
  5. The maximized window and the bar do not overlap by a single pixel,
     and they do not leave a gap either: the union covers the screen
     along the bar's axis.

Usage:
    rects.py <serial-log> <edge> <thickness> [--nostrut]

`--nostrut` inverts claims 2, 4 and 5: with the counter-test the work
area IS the screen and the maximized window DOES cover the bar. Without
that inversion the counter-test could not fail, and a counter-test that
cannot fail proves nothing.
"""
import re
import sys

SCREEN_W = 800
SCREEN_H = 600
EDGES = {"bottom": 0, "top": 1, "left": 2, "right": 3}


def wins(text):
    out = []
    for line in text.splitlines():
        if not line.startswith("wm: win "):
            continue
        d = dict(re.findall(r"([a-z]+)=(-?\d+)", line))
        m = re.search(r"t=\[([^\]]*)\]", line)
        d["title"] = m.group(1) if m else ""
        out.append({k: (int(v) if k != "title" else v) for k, v in d.items()})
    return out


def one(text, prefix):
    for line in reversed(text.splitlines()):
        if prefix in line:
            i = line.index(prefix)
            return dict((k, int(v)) for k, v in
                        re.findall(r"([a-z]+)=(-?\d+)", line[i:]))
    return None


def overlap(a, b):
    """Overlapping area of two (x, y, w, h) rectangles."""
    x0 = max(a[0], b[0])
    y0 = max(a[1], b[1])
    x1 = min(a[0] + a[2], b[0] + b[2])
    y1 = min(a[1] + a[3], b[1] + b[3])
    if x1 <= x0 or y1 <= y0:
        return 0
    return (x1 - x0) * (y1 - y0)


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    text = open(sys.argv[1], "rb").read().decode("utf-8", "replace")
    edge = sys.argv[2]
    thick = int(sys.argv[3])
    nostrut = "--nostrut" in sys.argv
    if edge not in EDGES:
        print("unknown edge: %s" % edge)
        return 2
    e = EDGES[edge]

    bad = []
    ws = wins(text)
    bar = [w for w in ws if w.get("layer") == 2 and w.get("strut", 0) > 0]
    if not bar and nostrut:
        bar = [w for w in ws if w.get("layer") == 2]
    if len(bar) != 1:
        print("expected exactly one panel window (layer 2 with a strut), "
              "found %d" % len(bar))
        return 1
    bar = bar[0]
    mx = [w for w in ws if w.get("max") == 1]
    if len(mx) != 1:
        print("expected exactly one maximized window, found %d" % len(mx))
        return 1
    mx = mx[0]

    # 1. the bar on its edge
    br = (bar["x"], bar["y"], bar["ow"], bar["oh"])
    want = {
        0: (0, SCREEN_H - thick, SCREEN_W, thick),
        1: (0, 0, SCREEN_W, thick),
        2: (0, 0, thick, SCREEN_H),
        3: (SCREEN_W - thick, 0, thick, SCREEN_H),
    }[e]
    if br != want:
        bad.append("the bar is at %s, expected %s" % (br, want))
    if bar["strutedge"] != e:
        bad.append("the bar reserves edge %d, expected %d"
                   % (bar["strutedge"], e))

    # 2. + 3. the work area
    srv = one(text, "wm: work ")
    r3 = one(text, "taskbar: work ")
    if srv is None or r3 is None:
        print("no work area reported (server: %s, taskbar: %s)"
              % (srv is not None, r3 is not None))
        return 1
    sr = (srv["x"], srv["y"], srv["w"], srv["h"])
    tr = (r3["x"], r3["y"], r3["w"], r3["h"])
    if sr != tr:
        bad.append("server work area %s, taskbar reads %s -- one of them "
                   "is a copy" % (sr, tr))
    if nostrut:
        expect = (0, 0, SCREEN_W, SCREEN_H)
    else:
        expect = {
            0: (0, 0, SCREEN_W, SCREEN_H - thick),
            1: (0, thick, SCREEN_W, SCREEN_H - thick),
            2: (thick, 0, SCREEN_W - thick, SCREEN_H),
            3: (0, 0, SCREEN_W - thick, SCREEN_H),
        }[e]
    if sr != expect:
        bad.append("work area %s, expected %s" % (sr, expect))

    # 4. the maximized window IS the work area
    mr = (mx["x"], mx["y"], mx["ow"], mx["oh"])
    if mr != sr:
        bad.append("maximized window %s is not the work area %s" % (mr, sr))

    # 5. no overlap, and no gap
    ov = overlap(mr, br)
    if nostrut:
        if ov == 0:
            bad.append("COUNTER-TEST FAILED: with nostrut the maximized "
                       "window should cover the bar, and it does not")
    else:
        if ov != 0:
            bad.append("the maximized window covers %d pixels of the bar"
                       % ov)
        total = mr[2] * mr[3] + br[2] * br[3]
        if total != SCREEN_W * SCREEN_H:
            bad.append("window %d + bar %d = %d pixels, screen is %d -- "
                       "there is a gap" % (mr[2] * mr[3], br[2] * br[3],
                                           total, SCREEN_W * SCREEN_H))

    if bad:
        for b in bad:
            print("    " + b)
        return 1
    print("bar %s, work %s, maximized %s, overlap %d px"
          % (br, sr, mr, ov))
    return 0


if __name__ == "__main__":
    sys.exit(main())
