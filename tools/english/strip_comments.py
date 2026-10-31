#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/english/strip_comments.py -- delete the German comment paragraphs of .fi files.

  strip_comments.py [--apply] file.fi [file.fi ...]

A paragraph is a run of non-empty `//` lines. It goes when count.py reads any of its lines as German.
Trailing German `//` comments and German block comments go as well. English comments stay.
Everything outside comments is compared before and after (whitespace-normalised); a difference aborts.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from count import german_text  # noqa: E402
from firnlex import spans  # noqa: E402


def non_comment(text):
    return re.sub(r"\s+", "", "".join(text[a:b] for k, a, b in spans(text) if k != "cmt"))


def is_german(line):
    return german_text(line.strip().lstrip("/* ").strip())


def drop_block_comments(text):
    out = []
    pos = 0
    for kind, a, b in spans(text):
        if kind == "cmt" and text[a:a + 2] == "/*" and any(is_german(x) for x in text[a:b].splitlines()):
            out.append(text[pos:a])
            pos = b
    out.append(text[pos:])
    return "".join(out)


def trailing_comment_start(line):
    for kind, a, b in spans(line):
        if kind == "cmt" and line[a:a + 2] == "//" and line[:a].strip():
            return a
    return -1


def strip_lines(lines):
    kept = []
    i = 0
    while i < len(lines):
        line = lines[i]
        s = line.strip()
        if s.startswith("//") and not s.startswith("///"):
            j = i
            while j < len(lines) and lines[j].strip().startswith("//") and lines[j].strip().strip("/").strip():
                j += 1
            if j > i:
                block = lines[i:j]
                if any(is_german(x) for x in block):
                    i = j
                    continue
                kept.extend(block)
                i = j
                continue
            kept.append(line)
            i += 1
            continue
        cut = trailing_comment_start(line)
        if cut >= 0 and is_german(line[cut:]):
            line = line[:cut].rstrip()
        kept.append(line)
        i += 1
    return kept


def drop_orphan_bars(lines):
    out = []
    for idx, line in enumerate(lines):
        if line.strip() == "//" and not line.rstrip("\n").strip("/ "):
            prev_real = idx > 0 and lines[idx - 1].strip().startswith("//") and lines[idx - 1].strip() != "//"
            next_real = idx + 1 < len(lines) and lines[idx + 1].strip().startswith("//") and lines[idx + 1].strip() != "//"
            if not (prev_real and next_real):
                continue
        out.append(line)
    return out


def collapse_blank(lines):
    out = []
    for line in lines:
        if not line.strip() and out and not out[-1].strip():
            continue
        out.append(line)
    return out


def strip_text(text):
    text = drop_block_comments(text)
    lines = text.split("\n")
    lines = strip_lines(lines)
    lines = drop_orphan_bars(lines)
    lines = collapse_blank(lines)
    return "\n".join(lines)


def main():
    args = sys.argv[1:]
    apply = bool(args) and args[0] == "--apply"
    if apply:
        args = args[1:]
    if not args:
        print(__doc__)
        return 2
    for path in args:
        text = open(path, encoding="utf-8").read()
        new = strip_text(text)
        if non_comment(text) != non_comment(new):
            print("%s: REFUSED, code changed" % path)
            return 1
        before = sum(1 for ln in text.splitlines() if is_german(ln) and "//" in ln)
        print("%s: %d -> %d lines, german comment lines %d" % (path, len(text.splitlines()), len(new.splitlines()), before))
        if apply:
            open(path, "w", encoding="utf-8").write(new)
    return 0


if __name__ == "__main__":
    sys.exit(main())
