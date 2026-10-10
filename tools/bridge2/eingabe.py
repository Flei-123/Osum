#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/bridge2/eingabe.py -- checks of the Win+Esc / red-sign drive (tools/bridge2/eingabe.txt).
#   python3 tools/bridge2/eingabe.py <run dir with serial.txt + *.ppm>
import re, sys, os

def ppm(p):
    d = open(p, "rb").read()
    m = re.match(rb"P6\s+(\d+)\s+(\d+)\s+(\d+)\s", d)
    w, h = int(m.group(1)), int(m.group(2))
    return w, h, d[m.end():]

def red(p):
    # danger-colour pixels in the bar's sign area (right part, bottom 34 rows), as a set of (x, y)
    w, h, px = ppm(p)
    out = set()
    for y in range(h - 34, h):
        row = px[y * w * 3:(y + 1) * w * 3]
        for x in range(1000, w):
            r, g, b = row[3 * x], row[3 * x + 1], row[3 * x + 2]
            if r >= 170 and g <= 100 and b <= 100:
                out.add((x, y))
    return out

d = sys.argv[1]
ser = open(os.path.join(d, "serial.txt"), "rb").read().decode("latin-1")
fails = 0
def chk(c, t):
    global fails
    print(("  OK    " if c else "  FAIL  ") + t)
    if not c: fails += 1

r0 = red(os.path.join(d, "00-before.ppm"))
r1 = red(os.path.join(d, "01-sign.ppm"))
r2 = red(os.path.join(d, "02-gone.ppm"))
r3 = red(os.path.join(d, "03-refused.ppm"))
new = r1 - r0
if new:
    xs = [p[0] for p in new]; ys = [p[1] for p in new]
    print("  info  red sign box x=%d..%d y=%d..%d" % (min(xs), max(xs), min(ys), max(ys)))
chk(len(new) >= 15, "red sign visible after the injected key (%d new red pixels)" % len(new))
chk(len(r2 - r0) <= 3, "sign gone again after the timeout (%d red pixels left)" % len(r2 - r0))
inj = len(re.findall(r"termzeile \d+ \[injected\]", ser))
chk(inj >= 1, "the injection before the stop worked (%d injected lines; the terminal redraws rows)" % inj)
chk("input: emergency stop (Win+Esc)" in ser, "keyboard event Super+Esc engaged the stop in the kernel")
chk(re.search(r"termzeile \d+ \[.*ENGAGED", ser) is not None, "jarvisctl input shows the stop: ENGAGED")
chk(re.search(r"termzeile \d+ \[No permit", ser) is not None, "jarvisctl is told 'No permit' after the stop")
chk(len(r3 - r0) <= 3, "after the stop the second injection shows no sign (%d red pixels)" % len(r3 - r0))
print("EINGABE-GUI: %d failed" % fails)
sys.exit(1 if fails else 0)
