#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/english/rn.py -- rename identifiers of ONE module, code regions only.

  rn.py [--apply] <module.fi> old=new [old=new ...]

Renames `old` -> `new` in the code regions of <module.fi> (strings and comments are asserted to stay
byte-identical) and the qualified references `<module>.old` in the code regions of every other tracked
`.fi` file. Plain `old` in other files is NOT touched (it may be a different, local name).
Without --apply it only prints what would change. Refuses a `new` that already occurs in the module.
"""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
from firnlex import spans  # noqa: E402


def rewrite(text, fn):
    out = []
    for kind, a, b in spans(text):
        seg = text[a:b]
        out.append(fn(seg) if kind == "code" else seg)
    return "".join(out)


def same_non_code(a, b):
    sa = [a[x:y] for k, x, y in spans(a) if k != "code"]
    sb = [b[x:y] for k, x, y in spans(b) if k != "code"]
    return sa == sb


def main():
    args = sys.argv[1:]
    do = "--apply" in args
    args = [a for a in args if a != "--apply"]
    target = args[0]
    pairs = dict(p.split("=", 1) for p in args[1:])
    mod = os.path.splitext(os.path.basename(target))[0]
    files = subprocess.run(["git", "ls-files", "*.fi"], cwd=ROOT, capture_output=True, text=True).stdout.split()
    total = 0
    for f in files:
        if f.startswith("vendor/"):
            continue
        full = os.path.join(ROOT, f)
        text = open(full, encoding="utf-8", errors="surrogateescape").read()
        new = text
        if f == target:
            for o, n in pairs.items():
                if re.search(r"(?<![A-Za-z0-9_])" + re.escape(n) + r"(?![A-Za-z0-9_])", "".join(
                        text[a:b] for k, a, b in spans(text) if k == "code")):
                    sys.exit("refusing: %s already occurs in %s" % (n, f))
            pat = re.compile(r"(?<![A-Za-z0-9_])(" + "|".join(map(re.escape, pairs)) + r")(?![A-Za-z0-9_])")
            new = rewrite(text, lambda s: pat.sub(lambda m: pairs[m.group(1)], s))
        else:
            if mod + "." not in text:
                continue
            pat = re.compile(r"(?<![A-Za-z0-9_.])" + re.escape(mod) + r"\.(" + "|".join(map(re.escape, pairs)) +
                             r")(?![A-Za-z0-9_])")
            new = rewrite(text, lambda s: pat.sub(lambda m: mod + "." + pairs[m.group(1)], s))
        if new != text:
            assert same_non_code(text, new), "strings/comments moved in " + f
            cnt = sum(1 for _ in re.finditer(r"\n", new)) and sum(
                1 for x, y in zip(text.split("\n"), new.split("\n")) if x != y)
            total += cnt
            print("%s: %d lines" % (f, cnt))
            if do:
                open(full, "w", encoding="utf-8", errors="surrogateescape").write(new)
    print(("APPLIED" if do else "DRY RUN") + ": %d lines" % total)


if __name__ == "__main__":
    main()
