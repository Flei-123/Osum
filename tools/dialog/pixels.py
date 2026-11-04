# SPDX-License-Identifier: GPL-2.0-only
import sys
from PIL import Image, ImageChops

PANEL = (32, 34, 44)


def load(root, name):
    return Image.open("%s/%s.png" % (root, name)).convert("RGB")


def panel_box(im):
    px = im.load()
    w, h = im.size
    xs = []
    ys = []
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            if px[x, y] == PANEL:
                xs.append(x)
                ys.append(y)
    if len(xs) < 500:
        return None
    return (min(xs), min(ys), max(xs) + 2, max(ys) + 2)


def union(a, b):
    return (min(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), max(a[3], b[3]))


def diff(a, b):
    box = union(panel_box(a), panel_box(b))
    d = ImageChops.difference(a.crop(box), b.crop(box)).convert("L").point(lambda v: 255 if v > 24 else 0)
    return sum(d.histogram()[255:])


def main(root, scale):
    names = ["m1-message", "m4-warning", "m5-error", "m6-critical", "m9-error-again"]
    try:
        shots = {n: load(root, n) for n in names}
    except OSError as e:
        print("PIXELS-FAIL missing shot: %s" % e)
        return 1
    bad = 0
    for n in names:
        if panel_box(shots[n]) is None:
            print("%s: no dialog panel found" % n)
            bad += 1
    if bad:
        print("PIXELS-FAIL %d" % bad)
        return 1
    want = 512 * scale - 2 * scale
    for n in names:
        box = panel_box(shots[n])
        width = box[2] - box[0]
        print("%s: panel %d px wide (want %d at scale %d)" % (n, width, want, scale))
        if abs(width - want) > 6 * scale:
            bad += 1
    same = diff(shots["m5-error"], shots["m9-error-again"])
    print("identical error dialogs: %d differing px in the panel" % same)
    if same > 0:
        bad += 1
    for a, b in (("m1-message", "m5-error"), ("m4-warning", "m5-error"), ("m5-error", "m6-critical")):
        d = diff(shots[a], shots[b])
        print("%s vs %s: %d differing px in the panel" % (a, b, d))
        if d < 20:
            bad += 1
    print("PIXELS-OK" if bad == 0 else "PIXELS-FAIL %d" % bad)
    return 0 if bad == 0 else 1


sys.exit(main(sys.argv[1], int(sys.argv[2])))
