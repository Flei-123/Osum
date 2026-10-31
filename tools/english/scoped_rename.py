#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/english/scoped_rename.py -- rename the LOCAL identifiers of one .fi file, function by function.

  scoped_rename.py [--apply] file.fi old=new [old=new ...]

An identifier declared outside any top-level function body (fn, const, static, export list, struct) is GLOBAL
and is left to rn.py. Every other listed `old` is renamed inside each top-level function on its own. When
`new` already occurs in that function or is a global name of the file, `cur_<new>` is used there instead.
Only code regions change; a dotted use `x.old` is never touched.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from firnlex import spans  # noqa: E402

FN_START = re.compile(r"^(export\s+)?fn\s")


def split_regions(text):
    lines = text.split("\n")
    regions = []
    cur = []
    in_fn = False
    for ln in lines:
        if not in_fn and FN_START.match(ln):
            if cur:
                regions.append((False, cur))
            cur = [ln]
            in_fn = True
            if ln.rstrip().endswith("}") and ln.count("{") == ln.count("}") and "{" in ln:
                regions.append((True, cur))
                cur = []
                in_fn = False
            continue
        cur.append(ln)
        if in_fn and ln.startswith("}"):
            regions.append((True, cur))
            cur = []
            in_fn = False
    if cur:
        regions.append((in_fn, cur))
    return regions


def code_of(text):
    return "".join(text[a:b] for k, a, b in spans(text) if k == "code")


def rewrite_code(text, fn):
    out = []
    for kind, a, b in spans(text):
        seg = text[a:b]
        out.append(fn(seg) if kind == "code" else seg)
    return "".join(out)


def globals_of(regions):
    names = set()
    for is_fn, lines in regions:
        body = "\n".join(lines)
        if is_fn:
            m = re.match(r"(?:export\s+)?fn\s+([A-Za-z_0-9]+)", lines[0])
            if m:
                names.add(m.group(1))
        else:
            names.update(re.findall(r"[A-Za-z_][A-Za-z0-9_]*", code_of(body)))
    return names


def main():
    args = sys.argv[1:]
    apply = bool(args) and args[0] == "--apply"
    if apply:
        args = args[1:]
    path = args[0]
    pairs = dict(p.split("=", 1) for p in args[1:])
    text = open(path, encoding="utf-8", errors="surrogateescape").read()
    regions = split_regions(text)
    glob = globals_of(regions)
    local = {o: n for o, n in pairs.items() if o not in glob}
    skipped = sorted(o for o in pairs if o in glob)
    new_regions = []
    changed = 0
    renamed = {}
    for is_fn, lines in regions:
        body = "\n".join(lines)
        if not is_fn:
            new_regions.append(body)
            continue
        words = set(re.findall(r"[A-Za-z_][A-Za-z0-9_]*", code_of(body)))
        table = {}
        for o, n in local.items():
            if o in words:
                use = n
                if use in words or use in glob:
                    use = "cur_" + n
                    if use in words or use in glob:
                        sys.exit("no free name for %s in function %s" % (o, lines[0][:60]))
                table[o] = use
                renamed[(o, use)] = renamed.get((o, use), 0) + 1
        if table:
            rx = re.compile(r"(?<![A-Za-z0-9_.])(" + "|".join(map(re.escape, table)) + r")(?![A-Za-z0-9_])")
            body = rewrite_code(body, lambda s: rx.sub(lambda m: table[m.group(1)], s))
            changed += 1
        new_regions.append(body)
    new = "\n".join(new_regions)
    plain = sum(1 for k, v in renamed.items() if k[1].startswith("cur_"))
    print("%s: %d functions changed, %d renames, %d via cur_ fallback, global (left): %s" % (
        path, changed, len(renamed), plain, ",".join(skipped)))
    if apply:
        ns = [text[a:b] for k, a, b in spans(text) if k != "code"]
        ns2 = [new[a:b] for k, a, b in spans(new) if k != "code"]
        if ns != ns2:
            sys.exit("strings or comments moved")
        open(path, "w", encoding="utf-8", errors="surrogateescape").write(new)
    return 0


if __name__ == "__main__":
    sys.exit(main())
