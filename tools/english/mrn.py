#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/english/mrn.py -- rename identifiers consistently across SEVERAL files, code regions only.

  mrn.py [--apply] old=new[,old=new...] file.fi [file.fi ...]

Every whole-word occurrence of `old` in the code regions of the listed files becomes `new`. Strings and
comments are asserted unchanged. A `new` that already occurs as a word in the code of any listed file is refused.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from firnlex import spans  # noqa: E402


def code_text(text):
    return "".join(text[a:b] for k, a, b in spans(text) if k == "code")


def main():
    args = sys.argv[1:]
    apply = False
    if args and args[0] == "--apply":
        apply = True
        args = args[1:]
    if len(args) < 2:
        print(__doc__)
        return 2
    pairs = []
    for p in args[0].split(","):
        o, n = p.split("=")
        pairs.append((o, n))
    files = args[1:]
    texts = {f: open(f, encoding="utf8", newline="").read() for f in files}
    allcode = "\n".join(code_text(t) for t in texts.values())
    bad = 0
    for o, n in pairs:
        if re.search(r"(?<![A-Za-z0-9_])" + re.escape(n) + r"(?![A-Za-z0-9_])", allcode):
            print("COLLISION: %s already in code" % n)
            bad = 1
    if bad:
        return 1
    table = dict(pairs)
    rx = re.compile(r"(?<![A-Za-z0-9_])(" + "|".join(re.escape(o) for o in table) + r")(?![A-Za-z0-9_])")
    total = 0
    for f, t in texts.items():
        out = []
        cnt = 0
        for k, a, b in spans(t):
            seg = t[a:b]
            if k == "code":
                seg, c = rx.subn(lambda m: table[m.group(1)], seg)
                cnt += c
            out.append(seg)
        new = "".join(out)
        if cnt:
            print("%s: %d" % (f, cnt))
        total += cnt
        if apply and cnt:
            open(f, "w", encoding="utf8", newline="").write(new)
    print("total %d%s" % (total, "" if apply else " (dry run)"))
    return 0


sys.exit(main())
