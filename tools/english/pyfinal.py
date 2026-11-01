#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import io
import os
import re
import sys
import tokenize

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import count  # noqa: E402
import pyrn  # noqa: E402

ROOT = pyrn.ROOT


def load_map():
    mapping = {}
    for line in open(os.path.join(HERE, "py_final.tsv"), encoding="utf-8"):
        a, b = line.rstrip("\n").split("\t")
        mapping[a] = b
    return mapping


ALT = {"suche": "lookup", "liste": "item_list", "lade": "loader", "zeilen": "line_rows", "links": "left_edge", "bauen": "assemble", "ziel": "dest", "geraet": "dev", "leiste": "taskbar", "schluessel": "key_name"}


def file_map(have, mapping):
    out = dict(mapping)
    for n in have & set(mapping):
        if mapping[n] in have or mapping[n] in pyrn.RESERVED:
            out[n] = ALT.get(n, mapping[n] + "_alt")
    return out


def german_files():
    out = []
    for f in count.tracked():
        if not f.endswith(".py") or f.startswith("tools/wlan/") or f.startswith("tools/usbnet/") or f.startswith("tools/english/"):
            continue
        names = set()
        count.scan_py_idents(open(os.path.join(ROOT, f), encoding="utf-8", errors="replace").read(), names)
        if names:
            out.append(f)
    return out


def flag_pass(path, mapping):
    src, toks = pyrn.tokens(path)
    lines = src.splitlines(keepends=True)
    edits = []
    for i, t in enumerate(toks):
        if t.type != tokenize.STRING or t.start[0] != t.end[0]:
            continue
        body = t.string

        def sub(m):
            n = m.group(2).replace("-", "_")
            if n in mapping:
                return m.group(1) + mapping[n].replace("_", "-")
            return m.group(0)

        new = re.sub(r"(--)([A-Za-z][A-Za-z0-9_-]*)", sub, body)
        prev = [x.string for x in toks[max(0, i - 3):i]]
        if new == body and prev[-2:] == ["add_argument", "("]:
            q = body[0]
            n = body.strip("'\"")
            if n in mapping:
                new = q + mapping[n] + q
        if new != body:
            edits.append((t.start, t.end, new))
    for (sr, sc), (er, ec), new in sorted(edits, reverse=True):
        ln = lines[sr - 1]
        lines[sr - 1] = ln[:sc] + new + ln[ec:]
    if edits:
        open(path, "w", encoding="utf-8").write("".join(lines))
    return len(edits)


def main():
    mapping = load_map()
    files = german_files()
    do = "--apply" in sys.argv
    clash = 0
    for f in files:
        p = os.path.join(ROOT, f)
        src, toks = pyrn.tokens(p)
        have = {t.string for t in toks if t.type == tokenize.NAME}
        fm = file_map(have, mapping)
        for n in set(fm) & have:
            if fm[n] in have or fm[n] in pyrn.RESERVED:
                clash += 1
                print("CLASH", f, n, fm[n])
    print("files", len(files), "clashes", clash)
    if not do or clash:
        return 1 if clash else 0
    for f in files:
        p = os.path.join(ROOT, f)
        src, toks = pyrn.tokens(p)
        fm = file_map({t.string for t in toks if t.type == tokenize.NAME}, mapping)
        pyrn.apply_file(p, fm)
        flag_pass(p, fm)
        try:
            compile(open(p, encoding="utf-8").read(), f, "exec")
        except Exception as e:
            print("COMPILE FAIL", f, str(e)[:100])
    return 0


if __name__ == "__main__":
    sys.exit(main())
