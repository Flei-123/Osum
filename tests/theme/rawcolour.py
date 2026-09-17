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
programs with a window, and `kernel/ui/wm.fi`, which paints frame and
title bar because it composites the screen. Not the whole tree --
`kernel/gfx/fb.fi` maps a framebuffer and does not decide what a button
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
    "kernel/ui/wm.fi",
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
# file -> the functions in it that may hold raw values.
#
# ROUND FARBE (15.09.2026), A-022: this was one name per file and is
# now a LIST, because `kernel/wm.fi` has three separate reasons and
# collapsing them into one entry would have hidden two of them.
# EVERY entry is still a FUNCTION NAME, never a pattern -- the rule at
# the top of this file has not moved.
#
# WHAT DOES *NOT* BELONG IN HERE, and this is the whole point of the
# list: a colour that decides what a BUTTON, a WINDOW or the DESKTOP
# looks like. Those must come from a token, and none of the entries
# below is one of them. Each is a colour that is NOT styling:
# a wire format, an opacity mask, or a debug board that must stay
# readable in every theme precisely BECAUSE it ignores the theme.
ALLOWED_FN = {
    "kernel/user/wlibc.fi": ["fn primitives_builtin"],
    "kernel/ui/wm.fi": [
        # The server paints frame and title bar because it composites the
        # screen. Ring 3 hands it eight numbers (WM_DECO); `deco_fallback`
        # is what it draws with until somebody does, and a machine whose
        # taskbar has not started yet may not be black on black.
        "fn deco_fallback",
        # ---------------------------------------------- A-022, reason 1
        # `sig_colour` IS A WIRE FORMAT, NOT A STYLE.
        #
        # In signature mode (`wmsig`) the server stains a strip at the
        # top and bottom of every window with a colour derived from the
        # FRAME NUMBER. `tools/vsync/zerreiss.py` then reads a PPM back
        # and counts tearing: two different signature colours inside one
        # window means the screenshot caught a half-transferred frame.
        # That reader carries the same eight triples in its own table
        # (`zerreiss.py:50`), so these values are a CONTRACT BETWEEN TWO
        # PROGRAMS -- the same kind of shared constant as a packet
        # header, and the comment above the function already says why
        # they are eight saturated tones: "ein Foto wird maschinell
        # gelesen und ein Unterschied von eins waere keiner."
        #
        # A theme token here would break tearing detection outright: the
        # eight would stop being far apart, and in a dark scheme several
        # would collapse onto near-identical greys. `sig_nr` also maps
        # the colour BACK to its number, which only works while the
        # mapping is fixed.
        "fn sig_colour",
        # ---------------------------------------------- A-022, reason 2
        # 0xFFFFFF HERE IS AN OPACITY, NOT A COLOUR.
        #
        # `cg_mal` fills the glyph buffer for a window caption button.
        # The buffer holds COVERAGE; which colour it becomes is decided
        # later, by `cap_glyph`, from the server's theme. White is the
        # neutral element of that multiplication -- writing a token in
        # here would apply the theme TWICE. The comment above the
        # function states this ("Die Farbe ist 0xFFFFFF und nicht die
        # echte: der Puffer haelt DECKUNGEN").
        "fn cg_mal",
        # ---------------------------------------------- A-022, reason 3
        # THE MEASUREMENT BOARD DELIBERATELY IGNORES THE THEME.
        #
        # The six functions below paint the diagnostic board that Justin
        # PHOTOGRAPHS off a real screen (`mess_grund`, `messzeile` and
        # the four ink colours; the ground is painted by
        # `measure_reason` -- the older name `mess_grund` survives only
        # in comments). It is not part of the desktop: it is
        # drawn over everything, before the taskbar exists, and it has
        # to stay legible on a machine whose theme is broken -- which is
        # exactly the machine it gets used on. Black ground with green /
        # red / white / yellow ink is chosen for the CAMERA, not for
        # taste, and `mess_ampel` uses green-vs-red as a MEANING
        # ("hier kam etwas an" / "hier nicht").
        #
        # Binding this board to the token system would make the one
        # instrument that has to work when the token system is wrong
        # depend on the token system being right.
        "fn measure_reason",
        "fn messzeile",
        "fn mess_gruen",
        "fn mess_rot",
        "fn mess_weiss",
        "fn mess_gelb",
    ],
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
    allowed = ALLOWED_FN.get(rel, [])
    for no, line in enumerate(text.split("\n"), 1):
        if allowed:
            if any(line.startswith(fn) for fn in allowed):
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
