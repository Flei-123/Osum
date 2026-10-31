#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import itemgraph  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))


def external_users(module, names):
    out = subprocess.run(["git", "-C", ROOT, "ls-files", "*.fi"], capture_output=True, text=True).stdout.split()
    pat = re.compile(r"\b%s\.(%s)\b" % (re.escape(module), "|".join(sorted(map(re.escape, names), key=len, reverse=True)))) if names else None
    res = {}
    if not pat:
        return res
    for f in out:
        if f.endswith("/%s.fi" % module):
            continue
        with open(os.path.join(ROOT, f), "rb") as fh:
            t = fh.read().decode("latin-1")
        code = itemgraph.code_only(t)
        for m in pat.finditer(code):
            res.setdefault(m.group(1), set()).add(f)
    return res


def main():
    path = sys.argv[1]
    first = int(sys.argv[2])
    regex = re.compile(sys.argv[3])
    raw, lines = itemgraph.load(path)
    items = itemgraph.with_refs(lines, itemgraph.parse_items(lines, first))
    by = {it["name"]: it for it in items}
    inside = {it["name"] for it in items if regex.search(it["name"])}
    changed = True
    while changed:
        changed = False
        for n in list(inside):
            for u in by[n]["uses"]:
                it = by[u]
                if it["kind"] in ("const",) and u not in inside and all(
                        by[o]["name"] in inside for o in [x["name"] for x in items if u in x["uses"]]):
                    inside.add(u)
                    changed = True
    out_deps = {}
    for n in inside:
        for u in by[n]["uses"]:
            if u not in inside:
                out_deps.setdefault(u, set()).add(n)
    in_users = {}
    for n, it in by.items():
        if n in inside:
            continue
        for u in it["uses"]:
            if u in inside:
                in_users.setdefault(u, set()).add(n)
    total = sum(by[n]["end"] - by[n]["head"] for n in inside)
    print("cluster items=%d lines=%d" % (len(inside), total))
    print("OUT deps (cluster needs from rest): %d" % len(out_deps))
    for u in sorted(out_deps, key=lambda x: by[x]["start"]):
        print("  %s %s <- %d" % (by[u]["kind"], u, len(out_deps[u])))
    print("IN users (rest uses cluster): %d" % len(in_users))
    for u in sorted(in_users, key=lambda x: by[x]["start"]):
        print("  %s <- %s" % (u, ",".join(sorted(in_users[u]))[:100]))
    ext = external_users("wm", inside)
    print("EXTERNAL files using wm.<cluster>: %d" % len(ext))
    for k in sorted(ext):
        print("  %s: %s" % (k, ",".join(sorted(ext[k]))[:100]))


if __name__ == "__main__":
    main()
