#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import re
import sys

ALLOWED_FN = {
    "kernel/user/wlibc.fi": (
        "fn metrics_classic",
        "fn shape_key",
        "fn corner_cov",
        "fn rrect",
        "fn rframe",
        "fn drop_shadow",
        "fn divider",
        "fn cap",
    ),
    "kernel/user/fuiapp/wlib.fi": (
        "fn ctrl_small",
        "fn ctrl_thin",
        "fn inset",
        "fn zeilen_hoehe",
    ),
}

FILES = [
    "kernel/user/wlibc.fi",
    "kernel/user/fuiapp/wlib.fi",
]

CALLS = {
    "uidraw.rect": (2, 3),
    "uidraw.rrect": (2, 3, 4),
    "uidraw.frame": (2, 3),
    "uidraw.rframe": (2, 3, 4, 5),
    "uidraw.frame3": (2, 3),
    "rect": (2, 3),
    "rrect": (2, 3, 4),
    "frame": (2, 3),
    "rframe": (2, 3, 4, 5),
    "add": (2, 3),
    "size": (0, 1),
    "wlib.size": (0, 1),
}
NUM = re.compile(r"^\d+$")


def split_args(text):
    out = []
    depth = 0
    cur = ""
    for ch in text:
        if ch in "([":
            depth += 1
        elif ch in ")]":
            if depth == 0:
                out.append(cur)
                return out
            depth -= 1
        if ch == "," and depth == 0:
            out.append(cur)
            cur = ""
            continue
        cur += ch
    return None


def scan(path, rel):
    raw = open(path, encoding="utf-8", errors="replace").read()
    lines = raw.split("\n")
    banned = ALLOWED_FN.get(rel, ())
    inside = False
    flat = []
    for line in lines:
        if line.startswith("fn "):
            inside = any(line.startswith(b) for b in banned)
        code = line.split("//", 1)[0]
        if inside:
            code = ""
        flat.append(code)
    text = "\n".join(flat)
    uses = sum(l.count("metric(") for l in flat)
    offs = []
    for no, line in enumerate(flat, 1):
        offs += [no] * (len(line) + 1)
    hits = []
    for name, positions in CALLS.items():
        for m in re.finditer(r"(?<![A-Za-z_.])" + re.escape(name) + r"\(",
                             text):
            args = split_args(text[m.end():])
            if args is None:
                continue
            for p in positions:
                if p >= len(args):
                    continue
                a = " ".join(args[p].replace("\n", " ").split())
                if not NUM.match(a):
                    continue
                v = int(a)
                if name in ("size", "wlib.size", "add"):
                    if v == 0:
                        continue
                else:
                    if p in (2, 3) and v in (0, 1):
                        continue
                    if p == 4 and v == 0:
                        continue
                    if p == 5 and v == 1:
                        continue
                at = m.start() if m.start() < len(offs) else len(offs) - 1
                hits.append((rel, offs[at], "%s arg %d = %d" % (name, p, v)))
    return hits, uses


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    hits = []
    uses = 0
    seen = 0
    for rel in FILES:
        p = os.path.join(root, rel)
        if not os.path.isfile(p):
            continue
        seen += 1
        h, u = scan(p, rel)
        hits += h
        uses += u
    for rel, no, what in sorted(hits, key=lambda z: (z[0], z[1])):
        print("%s:%d: %s" % (rel, no, what))
    print("rawmetric: files %d tokens %d raw %d" % (seen, uses, len(hits)))
    return 0 if not hits else 1


if __name__ == "__main__":
    sys.exit(main())
