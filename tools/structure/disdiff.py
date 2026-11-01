#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import hashlib
import re
import sys

HEAD = re.compile(r"^[0-9a-f]+ <([^>]+)>:$")
INSN = re.compile(r"^\s+[0-9a-f]+:\s+(.*)$")


def load(path, rename, skip=()):
    funcs = {}
    cur = None
    with open(path) as fh:
        for ln in fh:
            ln = ln.rstrip("\n")
            m = HEAD.match(ln)
            if m:
                if m.group(1) in skip:
                    cur = None
                    continue
                cur = rename(m.group(1))
                funcs[cur] = []
                continue
            m = INSN.match(ln)
            if m and cur is not None:
                t = m.group(1)
                if re.match(r"^(nop|data16|cs nop|xchg\s+ax,ax)\b", t):
                    continue
                t = re.sub(r"<([^>+]+)(\+0x[0-9a-f]+)?>", lambda x: "<" + rename(x.group(1)) + ("+N" if x.group(2) else "") + ">", t)
                t = re.sub(r"^(mov\s+esi,)0x[0-9a-f]+$", r"\1FILE", t)
                t = re.sub(r"0x[0-9a-f]{3,}", "N", t)
                t = re.sub(r"\b[0-9a-f]{5,}\b", "N", t)
                funcs[cur].append(t)
    return funcs


def main():
    args = sys.argv[1:]
    wrap = False
    if args and args[0] == "--wrap":
        wrap = True
        args = args[1:]
    before, after = args[0], args[1]
    mapping = {}
    for a in args[2:]:
        old, new = a.split("=")
        mapping[old] = new

    def rename_old(n):
        return mapping.get(n, n)

    def ident(n):
        return n

    b = load(before, rename_old)
    if wrap:
        a = load(after, rename_old, skip=set(mapping))
    else:
        a = load(after, ident)
    only_b = sorted(set(b) - set(a))
    only_a = sorted(set(a) - set(b))
    diff = [n for n in b if n in a and b[n] != a[n]]
    print("functions before=%d after=%d only_before=%d only_after=%d body_diff=%d" % (len(b), len(a), len(only_b), len(only_a), len(diff)))
    for n in only_b[:20]:
        print("ONLY_BEFORE", n)
    for n in only_a[:20]:
        print("ONLY_AFTER", n)
    for n in diff[:20]:
        print("DIFF", n, len(b[n]), len(a[n]))
    sys.exit(1 if only_b or only_a or diff else 0)


if __name__ == "__main__":
    main()
