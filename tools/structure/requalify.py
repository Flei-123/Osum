#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "english"))
from firnlex import spans  # noqa: E402

IDENT = re.compile(r"(?<![.\w])[A-Za-z_]\w*")
EXPORT = re.compile(r"(^export \{)(.*?)(\n\})", re.S | re.M)


def read(path):
    with open(path, "rb") as fh:
        return fh.read().decode("latin-1")


def write(path, text):
    with open(path, "wb") as fh:
        fh.write(text.encode("latin-1"))


def qualify_unqualified(text, names, module):
    out = []
    hits = 0
    for kind, a, b in spans(text):
        seg = text[a:b]
        if kind != "code":
            out.append(seg)
            continue

        def sub(m):
            nonlocal hits
            if m.group(0) in names:
                hits += 1
                return module + "." + m.group(0)
            return m.group(0)

        out.append(IDENT.sub(sub, seg))
    return "".join(out), hits


def retarget_users(text, old, new, names):
    pat = re.compile(r"(?<![.\w])%s\.([A-Za-z_]\w*)" % re.escape(old))
    out = []
    hits = 0
    for kind, a, b in spans(text):
        seg = text[a:b]
        if kind != "code":
            out.append(seg)
            continue

        def sub(m):
            nonlocal hits
            if m.group(1) in names:
                hits += 1
                return new + "." + m.group(1)
            return m.group(0)

        out.append(pat.sub(sub, seg))
    return "".join(out), hits


def prune_export(text, drop):
    m = EXPORT.search(text)
    if not m:
        return text, 0
    removed = 0
    lines = []
    for ln in m.group(2).split("\n"):
        cut = ln.find("//")
        if cut >= 0:
            ln = ln[:cut]
        toks = [t.strip() for t in ln.split(",") if t.strip()]
        keep = [t for t in toks if t not in drop]
        removed += len(toks) - len(keep)
        if keep:
            lines.append("    " + ", ".join(keep) + ",")
    body = "\n" + "\n".join(lines)
    return text[: m.start(2)] + body + text[m.end(2):], removed


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--module", required=True)
    ap.add_argument("--names", required=True)
    ap.add_argument("--src", default="kernel/ui/wm.fi")
    ap.add_argument("--keep", default="")
    ap.add_argument("--users", default="")
    ap.add_argument("--old", default="wm")
    a = ap.parse_args()
    with open(a.names) as fh:
        names = set(json.load(fh))
    keep = set(filter(None, a.keep.split(",")))
    moved = names - keep
    text = read(a.src)
    text, n2 = prune_export(text, moved)
    m = EXPORT.search(text)
    head, block, tail = text[: m.start()], text[m.start(): m.end()], text[m.end():]
    head, h1 = qualify_unqualified(head, names, a.module)
    tail, h2 = qualify_unqualified(tail, names, a.module)
    n1 = h1 + h2
    text = head + block + tail
    print("src: qualified=%d export_removed=%d" % (n1, n2))
    write(a.src, text)
    for path in filter(None, a.users.split(",")):
        t = read(path)
        t, n = retarget_users(t, a.old, a.module, moved)
        write(path, t)
        print("%s: retargeted=%d" % (path, n))


if __name__ == "__main__":
    main()
