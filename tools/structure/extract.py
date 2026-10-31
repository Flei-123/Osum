#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import argparse
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "english"))
import itemgraph  # noqa: E402
from firnlex import spans  # noqa: E402

LOCAL = re.compile(r"\b(?:let|var|for)\s+(?:mut\s+)?([A-Za-z_]\w*)|\b([A-Za-z_]\w*)\s*:\s*(?:u64|u32|u16|u8|i64|\[|\*)")


def strip_comments(text):
    out = []
    for kind, a, b in spans(text):
        if kind == "cmt":
            continue
        out.append(text[a:b])
    lines = [ln.rstrip() for ln in "".join(out).split("\n")]
    res = []
    for ln in lines:
        if ln.strip() == "" and (not res or res[-1].strip() == ""):
            continue
        res.append(ln)
    return "\n".join(res).rstrip("\n") + "\n"


def prefix_deps(body, module, fn_deps, val_deps):
    locals_ = {m.group(1) or m.group(2) for m in LOCAL.finditer("".join(body[a:b] for k, a, b in spans(body) if k == "code"))}
    out = []
    pat = re.compile(r"(?<![.\w])[A-Za-z_]\w*")
    for kind, a, b in spans(body):
        seg = body[a:b]
        if kind != "code":
            out.append(seg)
            continue

        def sub(m):
            n = m.group(0)
            tail = seg[m.end():m.end() + 1]
            if n in fn_deps and tail == "(" and n not in locals_:
                return "%s.%s" % (module, n)
            if n in val_deps and n not in locals_:
                return "%s.%s" % (module, n)
            return n

        out.append(pat.sub(sub, seg))
    return "".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", default="kernel/ui/wm.fi")
    ap.add_argument("--first", type=int, default=228)
    ap.add_argument("--names", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--module", default="wm")
    ap.add_argument("--header", required=True)
    ap.add_argument("--deps", default="/dev/null")
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()
    names = set(a.names.split(","))
    raw, lines = itemgraph.load(a.src)
    items = itemgraph.with_refs(lines, itemgraph.parse_items(lines, a.first))
    by = {it["name"]: it for it in items}
    missing = names - set(by)
    if missing:
        sys.exit("unknown: %s" % sorted(missing))
    sel = [it for it in items if it["name"] in names]
    deps = {}
    for it in sel:
        for u in it["uses"]:
            if u not in names:
                deps[u] = by[u]["kind"]
    fn_deps = {n for n, k in deps.items() if k == "fn"}
    val_deps = {n for n, k in deps.items() if k != "fn"}
    parts = []
    for it in sel:
        chunk = "\n".join(lines[it["head"]:it["end"]]) + "\n"
        chunk = strip_comments(chunk)
        parts.append(prefix_deps(chunk, a.module, fn_deps, val_deps))
    body = "\n".join(p.strip("\n") + "\n" for p in parts)
    with open(a.header, "r", encoding="latin-1") as fh:
        head = fh.read()
    print("items=%d lines=%d deps=%d" % (len(sel), body.count("\n"), len(deps)))
    print("DEPS " + ",".join(sorted(deps)))
    if not a.apply:
        return
    with open(a.out, "w", encoding="latin-1", newline="\n") as fh:
        fh.write(head.rstrip("\n") + "\n\n" + body)
    keep = []
    drop = set()
    for it in sel:
        drop.update(range(it["head"], it["end"]))
    for i, ln in enumerate(lines):
        if i not in drop:
            keep.append(ln)
    with open(a.src, "wb") as fh:
        fh.write("\n".join(keep).encode("latin-1"))
    with open(a.deps, "w") as fh:
        fh.write("\n".join(sorted(deps)) + "\n")


if __name__ == "__main__":
    main()
