#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
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
    kernel/ui/wig.fi           the seam that hands out coverage fields
    kernel/ui/wm.fi            the window server
    kernel/gfx/ttf.fi           the rasteriser
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
    path_2 = os.path.join(wurzel, "assets", "icons", "icons.map")
    aus = {}
    for roh in open(path_2, encoding="ascii").read().splitlines():
        line = roh.split("#", 1)[0].strip()
        if "=" not in line:
            continue
        name, _, rest = line.partition("=")
        parts = rest.split()
        if len(parts) == 2 and parts[0] != "alias":
            aus[int(parts[0], 16)] = name.strip()
    return aus


def zeichencode(wurzel):
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


def without_kommentare(text):
    aus = []
    i = 0
    n = len(text)
    in_text = False
    zeichen = ''
    while i < n:
        c = text[i]
        if in_text:
            if c == '\\' and i + 1 < n:
                aus.append(c)
                aus.append(text[i + 1])
                i += 2
                continue
            if c == zeichen:
                in_text = False
            aus.append(c)
            i += 1
            continue
        if c in '"\'':
            in_text = True
            zeichen = c
            aus.append(c)
            i += 1
            continue
        if c == '/' and i + 1 < n and text[i + 1] == '/':
            while i < n and text[i] != '\n':
                aus.append(' ')
                i += 1
            continue
        if c == '/' and i + 1 < n and text[i + 1] == '*':
            ende = text.find('*/', i + 2)
            ende = n if ende < 0 else ende + 2
            for k in range(i, ende):
                aus.append('\n' if text[k] == '\n' else ' ')
            i = ende
            continue
        aus.append(c)
        i += 1
    return ''.join(aus)


def treffer(text, erlaubt_values):
    aus = []
    for art, muster, basis in (("hex", HEX, 16), ("escape", ESC, 16),
                               ("decimal", DEC, 10)):
        for m in muster.finditer(text):
            v = int(m.group(1), basis)
            if v in erlaubt_values:
                line = text.count("\n", 0, m.start()) + 1
                aus.append((line, art, v))
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
        text = without_kommentare(
            open(voll, encoding="utf-8", errors="replace").read())
        for line, art, value in treffer(text, karte):
            n += 1
            print("rawcp: %s:%d: raw code point (%s) U+%04X -- write %s"
                  % (rel, line, art, value, karte[value]))

    print("rawcp: %d raw code points in %d files of drawing code, "
          "%d code points given away"
          % (n, len(dateien), len(karte)))
    if laut:
        for w in sorted(karte):
            print("rawcp:   U+%04X %s" % (w, karte[w]))
    return 0 if n == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
