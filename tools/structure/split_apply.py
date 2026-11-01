#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import argparse
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "english"))
import itemgraph  # noqa: E402
from firnlex import spans  # noqa: E402

TOKEN = re.compile(r"(?<![.\w])[A-Za-z_]\w*")
LOCALS = re.compile(r"\b(?:let|var|for)\s+(?:mut\s+)?([A-Za-z_]\w*)|\b([A-Za-z_]\w*)\s*:(?!:)")
IMPORT = re.compile(r"^import ([\w.]+)\s*$", re.M)


def code_text(text):
    return "".join(text[a:b] for k, a, b in spans(text) if k == "code")


def qualify(text, own, defmod, localset, violations, item):
    out = []
    for kind, a, b in spans(text):
        seg = text[a:b]
        if kind != "code":
            out.append(seg)
            continue

        def sub(m):
            n = m.group(0)
            d = defmod.get(n)
            if d is None or d == own or n in localset:
                if d is not None and d != own and n in localset:
                    violations.append(("shadow", item, n))
                return n
            return d + "." + n

        out.append(TOKEN.sub(sub, seg))
    return "".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--src", required=True)
    ap.add_argument("--first", type=int, default=0)
    ap.add_argument("--plan", required=True)
    ap.add_argument("--names", required=True)
    ap.add_argument("--dir", required=True)
    ap.add_argument("--import-prefix", required=True)
    ap.add_argument("--base", default="base")
    ap.add_argument("--map", required=True)
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args()
    plan = json.load(open(a.plan))
    names = json.load(open(a.names))
    order = [m["name"] for m in plan["modules"]]
    final = {k: names.get(k, k) for k in order}
    base = names.get("_base", a.base)
    raw, lines = itemgraph.load(a.src)
    items = itemgraph.with_refs(lines, itemgraph.parse_items(lines, a.first))
    items[0]["head"] = items[0]["start"]
    by = {it["name"]: it for it in items}
    users = {n: set() for n in by}
    for n, it in by.items():
        for u in it["uses"]:
            users[u].add(n)
    place = {}
    for n, it in by.items():
        if it["kind"] == "fn":
            m = plan["assign"].get(n)
            place[n] = final[m] if m else "main"
    pending = [n for n, it in by.items() if it["kind"] != "fn"]
    changed = True
    while changed:
        changed = False
        for n in list(pending):
            us = users[n]
            if not us:
                place[n] = "main"
                pending.remove(n)
                changed = True
                continue
            if all(u in place for u in us):
                ms = {place[u] for u in us}
                place[n] = ms.pop() if len(ms) == 1 else base
                pending.remove(n)
                changed = True
    for n in pending:
        place[n] = base
    rank = {base: -1, "main": 10 ** 6}
    for i, k in enumerate(order):
        rank[final[k]] = i
    bad = []
    for n, it in by.items():
        for u in it["uses"]:
            if place[u] != place[n] and rank[place[u]] > rank[place[n]]:
                bad.append((n, place[n], u, place[u]))
    if bad:
        print("LAYER VIOLATIONS", len(bad))
        for b in bad[:20]:
            print(" ", b)
        if a.apply:
            sys.exit(1)
    head_end = items[0]["start"] if items else len(lines)
    header = lines[:head_end]
    imports = IMPORT.findall("\n".join(header))
    seg = {i.split(".")[-1]: i for i in imports}
    profile = next((ln for ln in header if ln.startswith("profile ")), "")
    modfiles = {}
    violations = []
    main_name = os.path.splitext(os.path.basename(a.src))[0]
    members = {}
    for n in by:
        members.setdefault(place[n], []).append(n)
    sizes = {}
    for mod, ns in sorted(members.items(), key=lambda x: rank[x[0]]):
        ns.sort(key=lambda n: by[n]["start"])
        parts = []
        used_mods = set()
        for n in ns:
            it = by[n]
            txt = "\n".join(lines[it["head"]:it["end"]]).strip("\n")
            locs = {x or y for x, y in LOCALS.findall(code_text(txt))}
            q = qualify(txt, mod, place, locs - {n}, violations, n)
            parts.append(q)
        body = "\n\n".join(parts) + "\n"
        refs = set(re.findall(r"(?<![.\w])([A-Za-z_]\w*)\.", code_text(body)))
        mod_refs = sorted(r for r in refs if r in members and r != mod and r != "main")
        ext = [seg[r] for r in sorted(refs) if r in seg]
        modfiles[mod] = (mod_refs, ext, body)
        sizes[mod] = body.count("\n")
    for mod in modfiles:
        mr, ext, body = modfiles[mod]
        if mod == "main":
            continue
        text = "// SPDX-License-Identifier: GPL-2.0-only\n"
        if profile:
            text += profile + "\n"
        text += "\n"
        imps = ["import " + e for e in ext] + ["import %s.%s" % (a.import_prefix, m) for m in mr]
        if imps:
            text += "\n".join(imps) + "\n\n"
        text += re.sub(r'__include_str\("(?!\.\./)', '__include_str("../', body)
        modfiles[mod] = text
    mr, ext, body = modfiles["main"] if "main" in modfiles else ([], [], "")
    orig_text = "\n".join(lines[items[0]["start"]:])
    orig_refs = set(re.findall(r"(?<![.\w])([A-Za-z_]\w*)\.", code_text(orig_text)))
    new_refs = set(re.findall(r"(?<![.\w])([A-Za-z_]\w*)\.", code_text(body)))
    hdr_out = []
    for ln in header:
        m = IMPORT.match(ln)
        if m:
            s = m.group(1).split(".")[-1]
            if s in orig_refs and s not in new_refs:
                continue
        hdr_out.append(ln)
    while hdr_out and not hdr_out[-1].strip():
        hdr_out.pop()
    new_imps = ["import %s.%s" % (a.import_prefix, m) for m in mr]
    idx = max((i for i, ln in enumerate(hdr_out) if ln.startswith("import ")), default=len(hdr_out) - 1)
    hdr_out = hdr_out[:idx + 1] + new_imps + hdr_out[idx + 1:]
    main_text = "\n".join(hdr_out) + "\n\n" + body
    print("violations:", len(violations))
    for v in violations[:15]:
        print(" ", v)
    for mod, sz in sorted(sizes.items(), key=lambda x: rank[x[0]]):
        print("%-14s %5d lines" % (mod, sz))
    mp = []
    for n in by:
        if place[n] != "main":
            mp.append("_F0.%s=_F0.%s__%s" % (n, place[n], n))
    if not a.apply:
        return
    os.makedirs(a.dir, exist_ok=True)
    for mod, text in modfiles.items():
        if mod == "main":
            continue
        with open(os.path.join(a.dir, mod + ".fi"), "wb") as fh:
            fh.write(text.encode("latin-1"))
    with open(a.src, "wb") as fh:
        fh.write(main_text.encode("latin-1"))
    with open(a.map, "w") as fh:
        fh.write("\n".join(mp) + "\n")


if __name__ == "__main__":
    main()
