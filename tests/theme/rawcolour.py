#!/usr/bin/env python3
"""tests/theme/rawcolour.py -- COUNT THE COLOURS THAT ARE STILL WRITTEN
INTO CODE THAT PAINTS THE INTERFACE.

The promise of a token system is not "the colours live in a file". It
is "no painting routine names a colour". Those are different promises,
and only the second one survives a second theme -- so only the second
one is worth making, and a promise about the SHAPE OF THE SOURCE has to
be checked against the source, mechanically, or it is a sentence in a
document that stops being true in the first week.

    rawcolour.py [root]        exit 0 when the count is zero

WHAT IS SCANNED. The ring-3 files that paint the interface, listed by
name below. Not the whole tree: `kernel/fb.fi` maps a framebuffer and
`kernel/wm.fi` composites buffers -- neither decides what a button
looks like, and both legitimately contain a test pattern and a size
mask. A checker whose output is mostly noise is a checker nobody reads.

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

# The files that paint the interface. wlibc draws the shapes, wlib the
# widgets, and the six programs are everything with a window in it.
FILES = [
    "kernel/user/wlibc.fi",
    "kernel/user/wlib.fi",
    "kernel/user/leiste.fi",
    "kernel/user/schreibtisch.fi",
    "kernel/user/einstellungen.fi",
    "kernel/user/settings.fi",
    "kernel/user/explorer.fi",
    "kernel/user/starter.fi",
    "kernel/user/suchen.fi",
    "kernel/user/wigdemo.fi",
]

ALLOWED_CONSTS = ("const RGB24", "const RGB_WHITE", "const RGB_BLACK",
                  "const RGB_BAD", "const ACCENT_BLACK")
ALLOWED_FN_FILE = "kernel/user/wlibc.fi"
ALLOWED_FN = "fn primitives_builtin"


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
        if rel == ALLOWED_FN_FILE:
            if line.startswith(ALLOWED_FN):
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
    return hits, uses


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    hits = []
    uses = 0
    seen = 0
    for rel in FILES:
        p = os.path.join(root, rel)
        if not os.path.isfile(p):
            continue
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
