#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import sys

PAD_POINTS = 8
ROW_POINTS = 36
PREVIEW = r"taskview: preview n=(\d+) app=(\w+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)"
passed = 0
failed = 0


def ok(msg):
    global passed
    passed += 1
    print("  OK    " + msg)


def bad(msg):
    global failed
    failed += 1
    print("  FAIL  " + msg)


def check(cond, good, wrong):
    ok(good) if cond else bad(wrong)


def serial_of(folder):
    try:
        return open(folder + "/serial.txt", "rb").read().decode("latin-1")
    except OSError:
        return ""


def load(folder, name):
    try:
        d = open("%s/%s.ppm" % (folder, name), "rb").read()
    except OSError:
        return None
    f = []
    at = 2
    while len(f) < 3:
        while d[at:at + 1].isspace():
            at += 1
        s = at
        while not d[at:at + 1].isspace():
            at += 1
        f.append(int(d[s:at]))
    return (f[0], f[1], d[at + 1:])


def px(im, x, y):
    w, _, d = im
    o = (y * w + x) * 3
    return tuple(d[o:o + 3])


def dist(a, b):
    return sum(abs(a[i] - b[i]) for i in range(3))


def previews(ser):
    return [(int(m.group(1)), m.group(2), *(int(m.group(i)) for i in range(3, 7))) for m in re.finditer(PREVIEW, ser)]


def coords(serial_path, sc):
    ser = open(serial_path, "rb").read().decode("latin-1")
    hit = [p for p in previews(ser) if p[1] == "terminal"]
    if not hit:
        print("0 0")
        return 1
    _, _, x, y, w, _ = hit[0]
    print("%d %d" % (x + w - (PAD_POINTS + ROW_POINTS // 2) * sc, y + (PAD_POINTS + ROW_POINTS // 2) * sc))
    return 0


def differing(a, b, rect):
    x, y, w, h = rect
    n = 0
    total = 0
    for yy in range(y + 2, y + h - 2, 2):
        for xx in range(x + 2, x + w - 2, 2):
            total += 1
            if dist(px(a, xx, yy), px(b, xx, yy)) >= 12:
                n += 1
    return n / max(total, 1)


def corners(im, rect, inset):
    x, y, w, h = rect
    return [px(im, x + inset, y + inset), px(im, x + w - inset - 1, y + inset),
            px(im, x + inset, y + h - inset - 1), px(im, x + w - inset - 1, y + h - inset - 1)]


def geometry(ser, sc):
    geom = list(re.finditer(r"taskbar: geom edge=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)", ser))
    btn = list(re.finditer(r"taskbar: btn i=0 id=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)", ser))
    return (int(geom[-1].group(2)), int(geom[-1].group(3))) if geom else (0, 0), \
        (int(btn[0].group(1)), int(btn[0].group(3))) if btn else (0, 0)


def check_all(folder, folder_close, sc):
    ser = serial_of(folder)
    pv = previews(ser)
    check(len(pv) == 2, "exactly two previews opened (idle pin gave none): %s" % [(p[1], p[0]) for p in pv],
          "preview count %d, expected 2 (terminal button, explorer pin): %s" % (len(pv), pv))
    if len(pv) < 2:
        return
    (bar_y, bar_w), (bx, bw) = geometry(ser, sc)
    names = ["00-rest", "02-preview-button", "03-gone", "04-preview-pin"]
    im = {n: load(folder, n) for n in names}
    check(None not in im.values(), "pictures present", "pictures missing")
    if None in im.values():
        return
    n1, app1, x1, y1, w1, h1 = pv[0]
    n2, app2, x2, y2, w2, h2 = pv[1]
    check(app1 == "terminal" and n1 == 1, "button preview: app terminal, 1 window", "button preview %s n=%d" % (app1, n1))
    check(app2 == "explorer" and n2 == 1, "pinned preview: app explorer, 1 window", "pinned preview %s n=%d" % (app2, n2))
    check(y1 + h1 <= bar_y and y2 + h2 <= bar_y, "both plates sit above the bar (y+h %d <= %d)" % (y1 + h1, bar_y),
          "a plate overlaps the bar: %d/%d > %d" % (y1 + h1, y2 + h2, bar_y))
    check(abs(x1 + w1 // 2 - (bx + bw // 2)) <= 2, "button preview centred on the button (%d vs %d)" % (x1 + w1 // 2, bx + bw // 2),
          "button preview off centre: %d vs %d" % (x1 + w1 // 2, bx + bw // 2))
    check(w1 == 300 * sc and h1 == (2 * PAD_POINTS + ROW_POINTS + 4) * sc, "plate size %dx%d = design size x scale" % (w1, h1),
          "plate size %dx%d unexpected" % (w1, h1))
    shown = differing(im["02-preview-button"], im["00-rest"], (x1, y1, w1, h1))
    check(shown >= 0.5, "button preview visible: %.0f%% of the plate differs from the rest picture" % (100 * shown),
          "button preview not on screen: only %.0f%% differs" % (100 * shown))
    gone = differing(im["03-gone"], im["00-rest"], (x1, y1, w1, h1))
    check(gone <= 0.03, "preview gone after the pointer left (%.1f%% differs)" % (100 * gone),
          "preview still on screen after leaving (%.1f%% differs)" % (100 * gone))
    fill_a = corners(im["02-preview-button"], (x1, y1, w1, h1), 3 * sc)
    fill_b = corners(im["04-preview-pin"], (x2, y2, w2, h2), 3 * sc)
    check(max(dist(a, fill_a[0]) for a in fill_a) <= 6, "plate fill uniform at the corners %s" % (fill_a[0],),
          "plate corners differ: %s" % (fill_a,))
    check(all(dist(a, fill_a[0]) <= 6 for a in fill_b), "pinned preview has the same plate fill %s" % (fill_b[0],),
          "pinned preview plate differs from the button one: %s vs %s" % (fill_b, fill_a[0]))
    ser_c = serial_of(folder_close)
    close = re.search(r"taskview: close id=(\d+) rc=(\d+)", ser_c)
    check(close is not None and close.group(2) == "0", "close icon closes the window: %s" % (close.group(0) if close else ""),
          "no successful close line in run B")
    after = ser_c[close.end():] if close else ""
    check("taskview: shut" in after, "preview shuts after the close click", "preview stays open after the close click")


if sys.argv[1] == "coords":
    sys.exit(coords(sys.argv[2], int(sys.argv[3])))
check_all(sys.argv[2], sys.argv[3], int(sys.argv[4]))
print("TBPREVIEW-CHECK: %d passed, %d failed" % (passed, failed))
sys.exit(1 if failed else 0)
