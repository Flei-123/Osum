#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    python3 tools/alltag/pad.py <file> [...]
"""
import re
import sys

LINE = re.compile(
    r'^(?P<kopf>\s*(?:static\s+mut|static|var|let)\s+[A-Za-z_][A-Za-z_0-9]*'
    r'\s*:\s*\[u8;\s*)\?(?P<mitte>\s*\]\s*=\s*)"(?P<text>(?:[^"\\]|\\.)*)"'
    r'(?P<rest>.*)$'
)

ESCAPES = {"0": "\0", "n": "\n", "t": "\t", "r": "\r",
           "\\": "\\", '"': '"', "'": "'"}


def oktette(roh: str) -> bytes:
    out = bytearray()
    i = 0
    while i < len(roh):
        c = roh[i]
        if c == "\\" and i + 1 < len(roh):
            n = roh[i + 1]
            if n in ESCAPES:
                out += ESCAPES[n].encode("utf-8")
                i += 2
                continue
            if n == "x" and i + 3 < len(roh):
                out.append(int(roh[i + 2:i + 4], 16))
                i += 4
                continue
        out += c.encode("utf-8")
        i += 1
    return bytes(out)


def file(path: str) -> int:
    alt = open(path, "r", encoding="utf-8").read()
    aus = []
    n = 0
    for line in alt.split("\n"):
        m = LINE.match(line)
        if not m:
            aus.append(line)
            continue
        text = m.group("text")
        len_2 = len(oktette(text)) + 1
        aus.append('%s%d%s"%s\\0"%s' % (m.group("kopf"), len_2,
                                        m.group("mitte"), text,
                                        m.group("rest")))
        n += 1
    open(path, "w", encoding="utf-8").write("\n".join(aus))
    return n


def main() -> int:
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    for p in sys.argv[1:]:
        print("pad.py: %s: %d Textkonstanten nachgerechnet" % (p, file(p)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
