#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/themestore/click.py -- turn screen coordinates into monitor commands.

    click.py <x,y> [<x,y> ...]      > monitorbefehle.txt

The QEMU monitor's `mouse_move` is RELATIVE, because the PS/2 device it
drives has nothing else: it sends differences, not places.  A runner
that hands it absolute coordinates clicks somewhere else and reports
nothing wrong -- which is exactly what the first attempt at this file
did, and the only symptom was a tab that never changed.

So the same route round K10 wrote down: drive into the top left corner
in several big steps, where the stop clears the history, and then walk
out to the wanted place in steps under 128.  From there the position is
arithmetic and not hope.

The output is a command file for `tools/wm/monitor.py`.
"""
import sys


def go(x, y):
    out = ["mouse_move -120 -120"] * 6
    dx, dy = x, y
    while dx > 0 or dy > 0:
        sx, sy = min(dx, 120), min(dy, 120)
        out.append("mouse_move %d %d" % (sx, sy))
        dx -= sx
        dy -= sy
    return out


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    lines = []
    for p in argv[1:]:
        x, y = (int(v) for v in p.split(","))
        lines += go(x, y)
        lines += ["warte 1", "mouse_button 1", "mouse_button 0", "warte 2"]
    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
