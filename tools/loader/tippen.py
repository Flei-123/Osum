#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    tippen.py "ota search" [--wait 3] [--without-input] > befehle.txt
    `sendkey <key>` per chars, am Ende `sendkey ret`.
"""
import sys

KEYS = {
    " ": "spc", "-": "minus", "/": "slash", ".": "dot", ",": "comma",
    "=": "equal", ";": "semicolon", "\\": "backslash",
    ">": "shift-dot", "<": "shift-comma", ":": "shift-semicolon",
}


def key(c):
    if c in KEYS:
        return KEYS[c]
    if ("a" <= c <= "z") or ("0" <= c <= "9"):
        return c
    raise SystemExit("tippen: fuer '%s' ist keine Taste eingetragen" % c)


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    wait = 3
    input_ = True
    text = []
    i = 1
    while i < len(argv):
        a = argv[i]
        if a == "--wait":
            i += 1
            wait = float(argv[i])
        elif a == "--ohne-eingabe":
            input_ = False
        else:
            text.append(a)
        i += 1
    lines = []
    for satz in text:
        for c in satz:
            lines.append("sendkey " + key(c))
        if input_:
            lines.append("sendkey ret")
        lines.append("warte %g" % wait)
    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
