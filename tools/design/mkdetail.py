#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/design/mkdetail.py -- the zoomed detail boards of the design audit (r399).

    mkdetail.py <outdir> <main-dir> <after-dir> [<web-text.png>]

Each board crops the same box out of the "main" and the "after" picture, zooms by an integer
(nearest neighbour: every pixel stays visible) and labels them.  The crops are the places the
numbers of docs/DESIGN-AUDIT.md section 2 were measured at.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mkboards import board  # noqa: E402


def main(argv):
    out, before, after = argv[:3]
    web = argv[3] if len(argv) > 3 else None
    os.makedirs(out, exist_ok=True)

    def two(name, view, box, zoom, extra=None, labels=("main before", "after")):
        panels = [(labels[0], os.path.join(before, view + ".png")),
                  (labels[1], os.path.join(after, view + ".png"))]
        if extra:
            panels.append(extra)
        ok = board(os.path.join(out, name + ".png"), panels, crop=box, zoom=zoom)
        print(name, "ok" if ok else "missing")

    # the face: label + first row of the start menu, x3; plus the same face in Chromium
    two("detail-schrift", "02-startmenue", (8, 306, 232, 440), 3,
        ("Chromium, Inter 15 px", web) if web else None)
    # the wallpaper: the tree line, x3
    two("detail-hintergrund", "01-schreibtisch", (1000, 400, 1160, 480), 5)
    # the corner behind the start menu, and the tooltip, x10
    two("detail-ecke-menue", "02-startmenue", (4, 296, 44, 332), 10)
    two("detail-ecke-tooltip", "02-startmenue", (0, 728, 60, 760), 10)
    # icons: the bar pins, x4; the first start menu rows, x3
    two("detail-icons-leiste", "02-startmenue", (84, 762, 204, 798), 5)
    two("detail-icons-menue", "02-startmenue", (16, 384, 232, 520), 3)
    # the selection in the explorer list, x3
    two("detail-auswahl", "04-explorer", (272, 296, 560, 360), 3)
    # sliders and dropdowns of the Appearance page
    two("detail-regler", "03-einstellungen", (370, 330, 780, 480), 2)
    two("detail-dropdowns", "03-einstellungen", (30, 330, 360, 392), 3)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
