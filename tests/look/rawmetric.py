#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tests/look/rawmetric.py -- COUNT THE SHAPES THAT ARE STILL WRITTEN
INTO CODE THAT PAINTS THE INTERFACE.

This is `tests/theme/rawcolour.py` for the fourth token layer, and it
makes the same argument. The promise of a form-token system is not "the
radii live in a file". It is "no painting routine names a size". Only
the second promise survives a second appearance, so only the second one
is worth making -- and a promise about the SHAPE OF THE SOURCE has to be
checked against the source, mechanically, or it is a sentence in a
document that stops being true in the first week.

    rawmetric.py [root]        exit 0 when the count is zero

WHAT IS SCANNED, AND WHY IT IS NARROWER THAN rawcolour.py.

A colour is unmistakable: six hex digits is a colour and nothing else,
so `rawcolour.py` can scan whole files. A SIZE is a small integer, and a
painting routine is full of small integers that are not sizes -- a loop
bound, an array index, a shift, a bit mask, a divisor, a code point. A
checker that flagged all of them would report hundreds of hits, nobody
would read it, and it would be switched off inside a week.

So this one is deliberately EXACT: it scans the ARGUMENT POSITIONS in
which a size can hide, in the calls that draw a box or lay one out, in
the widget library and the drawing core:

    rect(x, y, W, H, colour)              -- W and H
    rrect(x, y, W, H, R, colour)          -- W, H and R
    frame(x, y, W, H, colour)             -- W and H
    rframe(x, y, W, H, R, B, c, c)        -- W, H, R and B
    frame3(x, y, W, H, ...)               -- W and H
    add(KIND, text, W, H, focus)          -- W and H
    size(W, H)                            -- W and H

A LITERAL IN ONE OF THOSE POSITIONS IS A HIT. An expression that names
a token, a variable, a field or another call is not. There is no
pattern-shaped exception: the exceptions are listed below BY NAME, the
way round THEME listed its two.

WHAT IS ALLOWED, and why:

  * 0 and 1 in a WIDTH or HEIGHT position of a drawing call.
    `rect(x, y, 1, h, c)` is a vertical line and `rect(x, y, w, 1, c)`
    is a horizontal one; a line is not a size, it is the thinnest thing
    there is. 0 is "nothing".
  * 1 in the BORDER position of `rframe`, same argument.
  * 0 in a RADIUS position: "square", which is a statement and not a
    measurement.
  * The functions in ALLOWED_FN, which DEFINE the tokens or convert
    between them. The classic set is the old numbers written down;
    somewhere they must exist as digits, and the bottom of a token
    layer is where a raw value belongs. That is the same exception
    round THEME granted `primitives_builtin`.

Round LOOK ends with the count at 0, and the number in
docs/ROUNDLOOK.md is the number this script printed.
"""
import os
import re
import sys

ALLOWED_FN = {
    "kernel/user/wlibc.fi": (
        "fn metrics_classic",
        "fn shape_key",
        "fn corner_cov",
        "fn rrect",
        "fn rframe",
        "fn drop_shadow",
        "fn divider",
        "fn cap",
    ),
    "kernel/user/wlib.fi": (
        "fn ctrl_small",
        "fn ctrl_thin",
        "fn inset",
        "fn zeilen_hoehe",
    ),
}

FILES = [
    "kernel/user/wlibc.fi",
    "kernel/user/wlib.fi",
]

CALLS = {
    "wlibc.rect": (2, 3),
    "wlibc.rrect": (2, 3, 4),
    "wlibc.frame": (2, 3),
    "wlibc.rframe": (2, 3, 4, 5),
    "wlibc.frame3": (2, 3),
    "rect": (2, 3),
    "rrect": (2, 3, 4),
    "frame": (2, 3),
    "rframe": (2, 3, 4, 5),
    "add": (2, 3),
    "size": (0, 1),
    "wlib.size": (0, 1),
}
NUM = re.compile(r"^\d+$")


def split_args(text):
    out = []
    depth = 0
    cur = ""
    for ch in text:
        if ch in "([":
            depth += 1
        elif ch in ")]":
            if depth == 0:
                out.append(cur)
                return out
            depth -= 1
        if ch == "," and depth == 0:
            out.append(cur)
            cur = ""
            continue
        cur += ch
    return None


def scan(path, rel):
    raw = open(path, encoding="utf-8", errors="replace").read()
    lines = raw.split("\n")
    banned = ALLOWED_FN.get(rel, ())
    inside = False
    flat = []
    for line in lines:
        if line.startswith("fn "):
            inside = any(line.startswith(b) for b in banned)
        code = line.split("//", 1)[0]
        if inside:
            code = ""
        flat.append(code)
    text = "\n".join(flat)
    uses = sum(l.count("metric(") for l in flat)
    offs = []
    for no, line in enumerate(flat, 1):
        offs += [no] * (len(line) + 1)
    hits = []
    for name, positions in CALLS.items():
        for m in re.finditer(r"(?<![A-Za-z_.])" + re.escape(name) + r"\(",
                             text):
            args = split_args(text[m.end():])
            if args is None:
                continue
            for p in positions:
                if p >= len(args):
                    continue
                a = " ".join(args[p].replace("\n", " ").split())
                if not NUM.match(a):
                    continue
                v = int(a)
                if name in ("size", "wlib.size", "add"):
                    if v == 0:
                        continue
                else:
                    if p in (2, 3) and v in (0, 1):
                        continue
                    if p == 4 and v == 0:
                        continue
                    if p == 5 and v == 1:
                        continue
                at = m.start() if m.start() < len(offs) else len(offs) - 1
                hits.append((rel, offs[at], "%s arg %d = %d" % (name, p, v)))
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
    for rel, no, what in sorted(hits, key=lambda z: (z[0], z[1])):
        print("%s:%d: %s" % (rel, no, what))
    print("rawmetric: files %d tokens %d raw %d" % (seen, uses, len(hits)))
    return 0 if not hits else 1


if __name__ == "__main__":
    sys.exit(main())
