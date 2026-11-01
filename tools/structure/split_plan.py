#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import argparse
import heapq
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import itemgraph  # noqa: E402


def sccs(nodes, edges):
    index = {}
    low = {}
    stack = []
    on = set()
    out = []
    counter = [0]
    sys.setrecursionlimit(100000)

    def strong(v):
        index[v] = low[v] = counter[0]
        counter[0] += 1
        stack.append(v)
        on.add(v)
        for w in edges.get(v, ()):
            if w not in index:
                strong(w)
                low[v] = min(low[v], low[w])
            elif w in on:
                low[v] = min(low[v], index[w])
        if low[v] == index[v]:
            comp = []
            while True:
                w = stack.pop()
                on.discard(w)
                comp.append(w)
                if w == v:
                    break
            out.append(comp)

    for v in nodes:
        if v not in index:
            strong(v)
    return out


def stem_of(name, depth):
    parts = name.split("_")
    return "_".join(parts[:depth]) if len(parts) > depth else name


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True)
    ap.add_argument("--first", type=int, default=0)
    ap.add_argument("--cap", type=int, default=2400)
    ap.add_argument("--depth", type=int, default=1)
    ap.add_argument("--stay", default="")
    ap.add_argument("--stems", default="")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    raw, lines = itemgraph.load(a.src)
    items = itemgraph.with_refs(lines, itemgraph.parse_items(lines, a.first))
    by = {it["name"]: it for it in items}
    pos = {it["name"]: i for i, it in enumerate(items)}
    size = {n: it["end"] - it["head"] for n, it in by.items()}
    stay = set(filter(None, a.stay.split(",")))
    fns = [n for n, it in by.items() if it["kind"] == "fn" and n not in stay]
    fnset = set(fns)
    override = {}
    for kv in filter(None, a.stems.split(",")):
        k, v = kv.split("=")
        override[k] = v
    group = {}
    for n in fns:
        group[n] = override.get(n) or override.get(stem_of(n, a.depth)) or stem_of(n, a.depth)
    gedges = {}
    for n in fns:
        for u in by[n]["uses"]:
            if u in fnset and group[u] != group[n]:
                gedges.setdefault(group[n], set()).add(group[u])
    gnodes = sorted(set(group.values()))
    comps = sccs(gnodes, gedges)
    comp_of = {}
    for ci, comp in enumerate(comps):
        for g in comp:
            comp_of[g] = ci
    cedges = {}
    for g, ds in gedges.items():
        for d in ds:
            if comp_of[g] != comp_of[d]:
                cedges.setdefault(comp_of[g], set()).add(comp_of[d])
    csize = {}
    cfirst = {}
    cmembers = {}
    for n in fns:
        c = comp_of[group[n]]
        csize[c] = csize.get(c, 0) + size[n]
        cfirst[c] = min(cfirst.get(c, 10 ** 9), pos[n])
        cmembers.setdefault(c, []).append(n)
    indeg = {c: 0 for c in csize}
    rev = {}
    for c, ds in cedges.items():
        for d in ds:
            rev.setdefault(d, set()).add(c)
    for c in csize:
        indeg[c] = len(cedges.get(c, ()))
    heap = [(cfirst[c], c) for c in csize if indeg[c] == 0]
    heapq.heapify(heap)
    order = []
    while heap:
        _, c = heapq.heappop(heap)
        order.append(c)
        for p in rev.get(c, ()):
            indeg[p] -= 1
            if indeg[p] == 0:
                heapq.heappush(heap, (cfirst[p], p))
    assign = {}
    mods = []
    cur = []
    cursz = 0
    for c in order:
        if cur and cursz + csize[c] > a.cap:
            mods.append(cur)
            cur = []
            cursz = 0
        cur.append(c)
        cursz += csize[c]
    if cur:
        mods.append(cur)
    result = {"modules": [], "assign": {}}
    for mi, cs in enumerate(mods):
        mname = "m%02d" % mi
        names = []
        for c in cs:
            names += cmembers[c]
        names.sort(key=lambda n: pos[n])
        gs = sorted({group[n] for n in names})
        result["modules"].append({"name": mname, "lines": sum(size[n] for n in names), "groups": gs, "fns": names})
        for n in names:
            result["assign"][n] = mname
    big = [(sum(size[n] for n in cmembers[c]), [g for g in comps[c]]) for c in csize if len(comps[c]) > 1]
    result["merged_groups"] = sorted(big, reverse=True)[:10]
    json.dump(result, open(a.out, "w"), indent=1)
    for m in result["modules"]:
        print(m["name"], m["lines"], len(m["fns"]), " ".join(m["groups"])[:150])
    print("merged:", result["merged_groups"][:4])


if __name__ == "__main__":
    main()
