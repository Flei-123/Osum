#!/usr/bin/env python3
"""tools/icons/rawcp.py -- count raw icon code points in the drawing code.

The promise of round ICONS is not that icons exist.  It is that NOBODY
EVER WRITES A CODE POINT.  `0xE041` in a drawing routine is unsearchable
and unowned: nothing tells a reader what it is, nothing stops a second
routine from picking the same number for something else, and nothing
notices when the map changes underneath it.  `icons.WINDOW_MINIMISE` has
a definition, one owner and one place to change.

So the rule is checked instead of stated.

WHAT COUNTS AS A CODE POINT HERE.  Not the whole private use area --
`0xE000` and `0xF000` appear all over this kernel as ADDRESSES and
masks, and a check that flags those is a check people learn to ignore.
What is counted is exactly the values `assets/icons/icons.map` has
GIVEN AWAY: today 42 numbers.  A number that is not an icon cannot be a
raw icon code point.

WHAT COUNTS AS DRAWING CODE.  The files that put pixels on a screen or
hand glyphs to something that does:

    kernel/user/*.fi        Ring 3 -- every interface in this system
    kernel/wig.fi           the seam that hands out coverage fields
    kernel/wm.fi            the window server
    kernel/ttf.fi           the rasteriser
    lib/*.fi                shared modules, except the generated one

Not the documentation, which quotes the numbers on purpose, and not
`tools/icons/`, which produces them.

It looks for three spellings, because there are three ways to write the
same number and a check that knows one is a check that can be walked
around: `0xE041`, plain decimal `57409`, and the escape `\\uE041`.

Usage:
    rawcp.py [--root DIR] [--verbose]
Exit code 0 when the count is zero, 1 otherwise.
"""

import glob
import os
import re
import sys

HEX = re.compile(r"0[xX]([0-9a-fA-F]{4,6})\b")
ESC = re.compile(r"\\u\{?([0-9a-fA-F]{4,6})\}?")
DEC = re.compile(r"(?<![\w.])(\d{5})(?![\w.])")


def belegte(wurzel):
    """The code points icons.map has given away -> {value: name}."""
    pfad = os.path.join(wurzel, "assets", "icons", "icons.map")
    aus = {}
    for roh in open(pfad, encoding="ascii").read().splitlines():
        zeile = roh.split("#", 1)[0].strip()
        if "=" not in zeile:
            continue
        name, _, rest = zeile.partition("=")
        teile = rest.split()
        if len(teile) == 2 and teile[0] != "alias":
            aus[int(teile[0], 16)] = name.strip()
    return aus


def zeichencode(wurzel):
    """The files that draw, in a fixed order so the count is stable."""
    aus = []
    aus += sorted(glob.glob(os.path.join(wurzel, "kernel", "user", "*.fi")))
    for n in ("wig.fi", "wm.fi", "ttf.fi"):
        p = os.path.join(wurzel, "kernel", n)
        if os.path.exists(p):
            aus.append(p)
    for p in sorted(glob.glob(os.path.join(wurzel, "lib", "*.fi"))):
        if os.path.basename(p) != "icons.fi":
            aus.append(p)
    return aus


def treffer(text, erlaubt_werte):
    aus = []
    for art, muster, basis in (("hex", HEX, 16), ("escape", ESC, 16),
                               ("decimal", DEC, 10)):
        for m in muster.finditer(text):
            v = int(m.group(1), basis)
            if v in erlaubt_werte:
                zeile = text.count("\n", 0, m.start()) + 1
                aus.append((zeile, art, v))
    return sorted(aus)


def main(argv):
    wurzel = os.path.dirname(os.path.dirname(os.path.dirname(
        os.path.abspath(__file__))))
    laut = False
    i = 1
    while i < len(argv):
        if argv[i] == "--root":
            wurzel = argv[i + 1]
            i += 2
        elif argv[i] == "--verbose":
            laut = True
            i += 1
        else:
            print(__doc__)
            return 2

    karte = belegte(wurzel)
    dateien = zeichencode(wurzel)
    n = 0
    for voll in dateien:
        rel = os.path.relpath(voll, wurzel)
        text = open(voll, encoding="utf-8", errors="replace").read()
        for zeile, art, wert in treffer(text, karte):
            n += 1
            print("rawcp: %s:%d: raw code point (%s) U+%04X -- write %s"
                  % (rel, zeile, art, wert, karte[wert]))

    print("rawcp: %d raw code points in %d files of drawing code, "
          "%d code points given away"
          % (n, len(dateien), len(karte)))
    if laut:
        for w in sorted(karte):
            print("rawcp:   U+%04X %s" % (w, karte[w]))
    return 0 if n == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
