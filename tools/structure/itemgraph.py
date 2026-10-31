#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "english"))
from firnlex import spans  # noqa: E402

ITEM = re.compile(r"^(?:export\s+)?(fn|static|const|struct|type)\s+(?:mut\s+)?([A-Za-z_]\w*)")
IDENT = re.compile(r"(?<![.\w])[A-Za-z_]\w*")


def code_only(text):
    out = []
    for kind, a, b in spans(text):
        out.append(text[a:b] if kind == "code" else re.sub(r"[^\n]", " ", text[a:b]))
    return "".join(out)


def load(path):
    with open(path, "rb") as fh:
        raw = fh.read().decode("latin-1")
    return raw, raw.split("\n")


def parse_items(lines, first=0):
    starts = []
    for i in range(first, len(lines)):
        m = ITEM.match(lines[i])
        if m:
            starts.append((i, m.group(1), m.group(2)))
    items = []
    for k, (i, kind, name) in enumerate(starts):
        nxt = starts[k + 1][0] if k + 1 < len(starts) else len(lines)
        end = nxt
        while end - 1 > i and (lines[end - 1].startswith("//") or lines[end - 1].strip() == ""):
            end -= 1
        head = items[-1]["end"] if items else first
        items.append({"kind": kind, "name": name, "start": i, "end": end, "head": head})
    return items


def with_refs(lines, items):
    names = {it["name"] for it in items}
    for it in items:
        txt = code_only("\n".join(lines[it["start"]:it["end"]]))
        used = set(IDENT.findall(txt)) & names
        used.discard(it["name"])
        it["uses"] = used
    return items


def main():
    path = sys.argv[1]
    first = int(sys.argv[2]) if len(sys.argv) > 2 else 0
    raw, lines = load(path)
    items = with_refs(lines, parse_items(lines, first))
    for it in items:
        print("%d\t%d\t%s\t%s\t%s" % (it["start"] + 1, it["end"] - it["start"], it["kind"], it["name"], ",".join(sorted(it["uses"]))))


if __name__ == "__main__":
    main()
