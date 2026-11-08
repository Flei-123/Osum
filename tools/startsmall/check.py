#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import sys

GEOM = re.compile(r"launcher: geom x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
BAR = re.compile(r"taskbar: geom edge=0 x=0 y=(\d+)")
NORMAL_MIN_HEIGHT_POINTS = 592

passed = 0
failed = 0


def check(cond, text):
    global passed, failed
    if cond:
        passed += 1
        print("  OK    " + text)
    else:
        failed += 1
        print("  FAIL  " + text)


def evaluate(serial, height, scale):
    geoms = [tuple(int(v) for v in m.groups()) for m in GEOM.finditer(serial)]
    bars = [int(m.group(1)) for m in BAR.finditer(serial)]
    check(len(geoms) >= 1 and len(bars) >= 1, "launcher and taskbar reported their geometry")
    if not geoms or not bars:
        return
    bar_y = bars[-1]
    for number, (x, y, w, h) in enumerate(geoms):
        tag = "geometry %d (y=%d h=%d)" % (number, y, h)
        check(y >= 0, tag + ": top edge on the screen")
        check(y + h <= bar_y, tag + ": bottom edge above the taskbar (%d)" % bar_y)
    if scale == 1 and height >= 800:
        check(max(g[3] for g in geoms) >= NORMAL_MIN_HEIGHT_POINTS, "large screen keeps the full layout")


def selftest():
    clipped = "taskbar: geom edge=0 x=0 y=640\nlauncher: geom x=8 y=-80 w=1304 h=800\n"
    check(not _passes(clipped, 720, 2), "selftest: the clipped old geometry is red")
    fitting = "taskbar: geom edge=0 x=0 y=640\nlauncher: geom x=8 y=20 w=1304 h=600\n"
    check(_passes(fitting, 720, 2), "selftest: a fitting geometry is green")


def _passes(serial, height, scale):
    global passed, failed
    saved = (passed, failed)
    passed = failed = 0
    import io
    import contextlib
    with contextlib.redirect_stdout(io.StringIO()):
        evaluate(serial, height, scale)
    ok = failed == 0
    passed, failed = saved
    return ok


def main():
    if sys.argv[1] == "--selftest":
        selftest()
    else:
        out, res, scale = sys.argv[1], sys.argv[2], int(sys.argv[3])
        serial = open(out + "/serial.txt", "rb").read().decode("latin1")
        evaluate(serial, int(res.split("x")[1]), scale)
    print("STARTSMALL checks: %d passed, %d failed" % (passed, failed))
    sys.exit(1 if failed else 0)


main()
