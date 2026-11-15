#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import sys


def main() -> int:
    if len(sys.argv) < 5:
        print("usage: mutant.py <tree> <file> <function> <statement>", file=sys.stderr)
        return 2
    tree, rel, name, statement = sys.argv[1:5]
    path = f"{tree}/{rel}"
    with open(path, encoding="utf-8") as handle:
        lines = handle.read().split("\n")
    head = re.compile(r"^fn\s+" + re.escape(name) + r"\(.*\{\s*$")
    hits = [index for index, line in enumerate(lines) if head.match(line)]
    if len(hits) != 1:
        print(f"mutant: {len(hits)} matches for fn {name} in {rel}", file=sys.stderr)
        return 1
    lines.insert(hits[0] + 1, "    " + statement)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines))
    return 0


sys.exit(main())
