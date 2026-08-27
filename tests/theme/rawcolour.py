#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tests/theme/rawcolour.py -- COUNT THE COLOURS THAT ARE STILL WRITTEN
INTO CODE THAT PAINTS THE INTERFACE.

The promise of a token system is not "the colours live in a file". It
is "no painting routine names a colour". Those are different promises,
and only the second one survives a second theme -- so only the second
one is worth making, and a promise about the SHAPE OF THE SOURCE has to
be checked against the source, mechanically, or it is a sentence in a
document that stops being true in the first week.

    rawcolour.py [root]        exit 0 when the count is zero

WHAT IS SCANNED. The files that decide what the interface LOOKS LIKE,
listed by name below: the drawing core, the widget library, the six
programs with a window, and `kernel/wm.fi`, which paints frame and
title bar because it composites the screen. Not the whole tree --
`kernel/fb.fi` maps a framebuffer and does not decide what a button
looks like, and a checker whose output is mostly noise is a checker
nobody reads.

WHAT COUNTS AS A COLOUR. A hexadecimal literal of exactly six digits,
or of eight digits whose top two are zero: 0x00RRGGBB is how this
system spells a 24-bit colour. Shorter literals (0xFFFF, a field mask)
and longer ones (0xFFFFFFFFFFFFFFFF) are not counted.

THE ALLOWED PLACES, and there are exactly two, both in wlibc.fi:

  1. `fn primitives_builtin` -- the ramp a machine falls back on when
     /etc is empty. It has to exist somewhere, and the bottom of the
     primitive layer is where a raw value belongs.
  2. The named constants RGB24, RGB_WHITE, RGB_BLACK, RGB_BAD,
     ACCENT_BLACK. RGB24 is a field mask, RGB_BAD and ACCENT_BLACK are
     markers, and white and black are the two ends the ramp generator
     mixes towards -- which is arithmetic, not styling.

Both are listed here by name. An exception granted by a pattern is an
exception that grows.
"""
import os
import re
import sys

PAT = re.compile(r"0x(?:00)?([0-9A-Fa-f]{6})\b")
# The OTHER way a colour hides in this tree: three channel literals in
# a row. `fb.rgb(state, 0x10, 0x14, 0x1A)` is every bit as much a
# hardcoded colour as 0x0010141A, and the first version of this script
# walked straight past four of them -- the terminal window kept its
# dark background in a light theme and the screenshot showed it.
PAT_RGB = re.compile(r"\brgb\(\s*state\s*,\s*(0x[0-9A-Fa-f]{1,2}|\d{1,3})"
                     r"\s*,\s*(0x[0-9A-Fa-f]{1,2}|\d{1,3})"
                     r"\s*,\s*(0x[0-9A-Fa-f]{1,2}|\d{1,3})\s*\)")

# The files that paint the interface. wlibc draws the shapes, wlib the
# widgets, and the six programs are everything with a window in it.
FILES = [
    "kernel/wm.fi",
    "kernel/user/wlibc.fi",
    "kernel/user/wlib.fi",
    "kernel/user/taskbar.fi",
    "kernel/user/desktop.fi",
    "kernel/user/settings.fi",
    "kernel/user/explorer.fi",
    "kernel/user/launcher.fi",
    "kernel/user/locate.fi",
    "kernel/user/widgetdemo.fi",
]

# Named constants that are shaped like a colour and are not one: a
# field mask, two markers, the two ends the ramp generator mixes
# towards, a size bound, and the two probe values of the window
# server's self test. Every one of them is listed BY NAME. An exception
# granted by a pattern is an exception that grows.
ALLOWED_CONSTS = ("const RGB24", "const RGB_WHITE", "const RGB_BLACK",
                  "const RGB_BAD", "const ACCENT_BLACK",
                  "const STRUT_MAX", "const PROBE_IN", "const PROBE_OUT",
                  "const CURSOR_BODY", "const CURSOR_EDGE")
# file -> the one function in it that may hold raw values
ALLOWED_FN = {
    "kernel/user/wlibc.fi": "fn primitives_builtin",
    # The server paints frame and title bar because it composites the
    # screen. Ring 3 hands it eight numbers (WM_DECO); `deco_fallback`
    # is what it draws with until somebody does, and a machine whose
    # taskbar has not started yet may not be black on black.
    "kernel/wm.fi": "fn deco_fallback",
}


def is_colour(code, m):
    end = m.end()
    if end < len(code) and code[end] in "0123456789abcdefABCDEF":
        return False
    return len(code[m.start():end]) in (8, 10)


def scan(path, rel):
    text = open(path, encoding="utf-8", errors="replace").read()
    inside = False
    hits = []
    uses = 0
    for no, line in enumerate(text.split("\n"), 1):
        if rel in ALLOWED_FN:
            if line.startswith(ALLOWED_FN[rel]):
                inside = True
            elif line.startswith("}"):
                inside = False
        code = line.split("//", 1)[0]
        uses += code.count("theme(") + code.count("theme_semantic(")
        if not code.strip() or inside:
            continue
        if any(code.lstrip().startswith(c) for c in ALLOWED_CONSTS):
            continue
        for m in PAT.finditer(code):
            if is_colour(code, m):
                hits.append((rel, no, code.strip()))
        for m in PAT_RGB.finditer(code):
            hits.append((rel, no, code.strip()))
    return hits, uses


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    hits = []
    uses = 0
    seen = 0
    # A NAME IN THIS LIST THAT IS NOT A FILE IS AN ERROR, NOT A SKIP.
    #
    # It used to `continue`, and that is how the list came to hold
    # "kernel/user/settings.fi" for weeks before any such file existed,
    # right next to "einstellungen.fi", which was the same program under
    # its old name. The checker reported "files 10" and nobody counted
    # the eleven entries. A checker that quietly examines one file fewer
    # than it says it does is worse than no checker: it is a green light
    # with a hole in it.
    # ...ON THE CURRENT TREE. Given an explicit root -- the historical
    # checkout the counter-test below unpacks, or a directory a test
    # builds with one file in it -- files are missing ON PURPOSE, and
    # the list of this tree says nothing about that one.
    given = len(sys.argv) > 1
    missing = [] if given else [
        r for r in FILES if not os.path.isfile(os.path.join(root, r))]
    if missing:
        for r in missing:
            print("rawcolour: LISTED BUT NOT THERE: %s" % r)
        print("rawcolour: files 0 tokens 0 raw %d" % len(missing))
        return 2
    dupes = sorted({r for r in FILES if FILES.count(r) > 1})
    if dupes:
        for r in dupes:
            print("rawcolour: LISTED TWICE: %s" % r)
        return 2
    for rel in FILES:
        p = os.path.join(root, rel)
        if not os.path.isfile(p):
            continue          # only reachable with an explicit root
        seen += 1
        h, u = scan(p, rel)
        hits += h
        uses += u
    for rel, no, code in hits:
        print("%s:%d: %s" % (rel, no, code))
    print("rawcolour: files %d tokens %d raw %d" % (seen, uses, len(hits)))
    return 0 if not hits else 1


if __name__ == "__main__":
    sys.exit(main())
