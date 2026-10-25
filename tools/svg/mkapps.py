#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import re
import subprocess
import sys

SIZE = 72
ROW_SIZES = (44, 64)
PAD = 1.25
STROKE = 2.2


def glyph_inner(text):
    return re.search(r"<svg[^>]*>(.*)</svg>", text, re.S).group(1).strip()


def compose(inner, top, bottom, tint):
    lo = -PAD
    span = 24 + 2 * PAD
    fill = 'fill="url(#g)" fill-opacity="0.38"' if tint else 'fill="none"'
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="%g %g %g %g">\n'
        '<defs><linearGradient id="g" gradientUnits="userSpaceOnUse" x1="0" y1="%g" x2="0" y2="%g">'
        '<stop offset="0" stop-color="#%s"/><stop offset="1" stop-color="#%s"/></linearGradient></defs>\n'
        '<g %s stroke="url(#g)" stroke-width="%g" stroke-linecap="round" stroke-linejoin="round">%s</g>\n'
        '</svg>\n'
    ) % (SIZE, SIZE, lo, lo, span, span, lo, 24 + PAD, top, bottom, fill, STROKE, inner)


def rows(table):
    for line in open(table, encoding="ascii").read().splitlines():
        if line.strip():
            yield line.split("\t")


def main(argv):
    root, bake = argv[0], argv[1]
    only = set(argv[2:])
    for app, glyph, top, bottom, tint, folder in rows(os.path.join(root, "tools/svg/apps.tsv")):
        if only and app not in only:
            continue
        d = os.path.join(root, folder)
        if not os.path.isdir(d):
            print("skip", app)
            continue
        inner = glyph_inner(open(os.path.join(root, "assets/icons/svg", glyph + ".svg"), encoding="utf-8").read())
        svg = os.path.join(d, "symbol.svg")
        with open(svg, "w", encoding="ascii") as f:
            f.write(compose(inner, top, bottom, tint == "1"))
        rc = subprocess.run([bake, svg, os.path.join(d, "symbol.osym"), str(SIZE)]).returncode
        if rc != 0:
            print("bake failed", app, rc)
            return 1
        for rs in ROW_SIZES:
            rc = subprocess.run([bake, svg, os.path.join(d, "symbol%d.osym" % rs), str(rs)]).returncode
            if rc != 0:
                print("bake failed", app, rs, rc)
                return 1
        print("%s: symbol.svg -> symbol.osym %dx%d + rows %s" % (app, SIZE, SIZE, ROW_SIZES))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
