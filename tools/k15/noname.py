#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    noname.py <quelldatei> <name>
"""
import re
import sys


def without_anmerkungen(text):
    aus = []
    i = 0
    n = len(text)
    in_str = False
    while i < n:
        c = text[i]
        if in_str:
            if c == "\\":
                aus.append(text[i:i + 2])
                i += 2
                continue
            if c == '"':
                in_str = False
            aus.append(c)
            i += 1
            continue
        if c == '"':
            in_str = True
            aus.append(c)
            i += 1
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                i += 1
            continue
        aus.append(c)
        i += 1
    return "".join(aus)


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    path_2, name = sys.argv[1], sys.argv[2]
    roh = open(path_2, encoding="utf-8", errors="replace").read()
    code = without_anmerkungen(roh)
    if name in code:
        for nr, line in enumerate(code.split("\n"), 1):
            if name in line:
                print("%s:%d: '%s' is in the code: %s"
                      % (path_2, nr, name, line.strip()[:80]))
                return 1
    inkomm = name in roh and name not in code
    print("'%s' is not in the code of %s%s"
          % (name, path_2, " (but in a remark)" if inkomm else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main())
