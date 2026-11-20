#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import re
import sys

out = sys.argv[1]
ok = fail = 0


def say(good, msg):
    global ok, fail
    if good:
        ok += 1
    else:
        fail += 1
    print(("  OK    " if good else "  FAIL  ") + msg)


def load_ppm(path):
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
    return f[0], f[1], d[at + 1:]


ser = open(os.path.join(out, "serial.txt"), "rb").read().decode("latin1").replace("\r", "")
scrolls = [tuple(int(v) for v in m) for m in re.findall(r"notifc: scroll first=(\d+) of=(\d+) n=(\d+)", ser)]
say(len(scrolls) >= 5, "scroll reports present (%d)" % len(scrolls))
if not scrolls:
    print("RESULT ok=%d fail=%d" % (ok, fail))
    sys.exit(1)
first0, total, shown0 = scrolls[0]
say(first0 == 0 and total >= 12, "opening lists from the top, %d notifications reachable (>= 12)" % total)
say(0 < shown0 < total, "not all fit at once (%d of %d shown), so scrolling is needed" % (shown0, total))
firsts = [s[0] for s in scrolls]
say(max(firsts) > 0, "keys/wheel move the window (first rows %s)" % firsts)
last_page = [s for s in scrolls if s[0] + s[2] >= s[1]]
say(bool(last_page), "the last notification is reached (window end >= total)")
say(any(s[0] == 0 for s in scrolls[1:]), "Home returns to the top")
opens = re.findall(r"calpop: open today=\d+-\d+-\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)", ser)
if opens:
    x, y, w, h = [int(v) for v in opens[0]]
    say(y >= 0 and y + h <= 800, "the card stays on the screen (y=%d h=%d)" % (y, h))
rects = re.findall(r"calpop: rect name=today x=(\d+) y=(\d+)", ser)
say(len(set(rects)) == 1 and len(rects) >= 2, "the calendar stays fixed while the list scrolls (today rect %s)" % sorted(set(rects)))
try:
    w0, h0, a = load_ppm(os.path.join(out, "01-open.ppm"))
    w1, h1, b = load_ppm(os.path.join(out, "03-end.ppm"))
    if opens:
        diff = 0
        for yy in range(y, y + 280, 2):
            for xx in range(x + 20, x + w - 20, 4):
                o = (yy * w0 + xx) * 3
                if max(abs(a[o + c] - b[o + c]) for c in range(3)) > 24:
                    diff += 1
        say(diff > 60, "the list area repaints after scrolling (%d samples differ)" % diff)
except OSError as e:
    say(False, "pictures missing: %s" % e)
print("RESULT ok=%d fail=%d" % (ok, fail))
sys.exit(1 if fail else 0)
