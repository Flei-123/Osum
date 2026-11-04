# SPDX-License-Identifier: GPL-2.0-only
import sys
from PIL import Image, ImageChops


def load(root, name):
    return Image.open("%s/%s.png" % (root, name)).convert("RGB")


def diff(a, b):
    box = ImageChops.difference(a, b).getbbox()
    if box is None:
        return 0
    d = ImageChops.difference(a, b).convert("L").point(lambda v: 255 if v > 24 else 0)
    return sum(1 for v in d.getdata() if v)


def main(root):
    names = ["m1-message", "m4-warning", "m5-error", "m6-critical", "m9-error-again"]
    try:
        shots = {n: load(root, n) for n in names}
    except OSError as e:
        print("PIXELS-FAIL missing shot: %s" % e)
        return 1
    bad = 0
    same = diff(shots["m5-error"], shots["m9-error-again"])
    print("identical error dialogs: %d differing px" % same)
    if same > 0:
        bad += 1
    for a, b in (("m1-message", "m5-error"), ("m4-warning", "m5-error"), ("m5-error", "m6-critical")):
        d = diff(shots[a], shots[b])
        print("%s vs %s: %d differing px" % (a, b, d))
        if d < 200:
            bad += 1
    w, h = shots["m1-message"].size
    lit = sum(1 for p in shots["m1-message"].getdata() if p != shots["m1-message"].getpixel((0, 0)))
    print("screen %dx%d, non-background px: %d" % (w, h, lit))
    if lit < 2000:
        bad += 1
    print("PIXELS-OK" if bad == 0 else "PIXELS-FAIL %d" % bad)
    return 0 if bad == 0 else 1


sys.exit(main(sys.argv[1]))
