#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "english"))
from firnlex import spans  # noqa: E402


def code_only(text):
    return re.sub(r"\s+", "", "".join(text[a:b] for k, a, b in spans(text) if k != "cmt"))


def strip_text(text):
    parts = []
    pos = 0
    for kind, a, b in spans(text):
        if kind == "cmt":
            parts.append(text[pos:a])
            pos = b
    parts.append(text[pos:])
    lines = "".join(parts).split("\n")
    out = []
    for ln in lines:
        ln = ln.rstrip()
        if not ln and out and not out[-1]:
            continue
        out.append(ln)
    spdx = "// SPDX-License-Identifier: GPL-2.0-only"
    return spdx + "\n" + "\n".join(out).lstrip("\n")


def main():
    for path in sys.argv[1:]:
        enc = "utf-8"
        raw = open(path, "rb").read()
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError:
            enc = "latin-1"
            text = raw.decode("latin-1")
        new = strip_text(text)
        if code_only(text) != code_only(new):
            print(path, "REFUSED")
            return 1
        open(path, "wb").write(new.encode(enc))
        print(path, len(text.splitlines()), "->", len(new.splitlines()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
