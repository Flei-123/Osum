#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import sys


def fahre(aus, dx, dy):
    """In Schritten unter 128 -- ein Paket, ein Schritt."""
    while dx or dy:
        sx = max(-120, min(120, dx))
        sy = max(-120, min(120, dy))
        aus.append("mouse_move %d %d" % (sx, sy))
        dx -= sx
        dy -= sy


def klick(aus, x, y, von=(0, 0)):
    fahre(aus, x - von[0], y - von[1])
    aus.append("warte 0.3")
    aus.append("mouse_button 1")
    aus.append("warte 0.2")
    aus.append("mouse_button 0")
    aus.append("warte 0.8")
    return (x, y)


def main():
    roh = sys.argv[1:]
    park = None
    if "--park" in roh:
        i = roh.index("--park")
        park = (int(roh[i + 1]), int(roh[i + 2]))
        roh = roh[:i] + roh[i + 3:]
    a = [int(v) for v in roh]
    if len(a) < 2 or len(a) % 2 != 0:
        print(__doc__)
        return 2
    aus = []
    aus.append("# into the top left corner -- the stop erases the history")
    for _ in range(12):
        aus.append("mouse_move -120 -120")
    aus.append("warte 0.5")
    hier = (0, 0)
    for i in range(0, len(a), 2):
        hier = klick(aus, a[i], a[i + 1], hier)
    if park is not None:
        aus.append("# move the pointer away from the button -- WITHOUT clicking")
        fahre(aus, park[0] - hier[0], park[1] - hier[1])
        aus.append("warte 1.0")
    aus.append("warte 2.0")
    print("\n".join(aus))
    return 0


sys.exit(main())
