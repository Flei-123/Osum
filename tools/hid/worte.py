#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import re
import sys

SCANNER_DEF = re.compile(r"^fn (find|find_word)\((hay|heu): u64, (needle|nadel): u64, n: u64", re.M)
RAW_CALL = re.compile(r"\b(?:bootscan|fbdraw)\.(?:find|find_word)\(")
WORD_DECL = re.compile(r'var (w_\w+): \[u8; \d+\] = "([a-z0-9._=/-]+)\\0')


def kernel_files(root):
    found = []
    for base, dirs, names in os.walk(root):
        dirs[:] = [d for d in dirs if d not in ("user", "app")]
        found += [os.path.join(base, n) for n in names if n.endswith(".fi")]
    return sorted(found)


def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "kernel"
    words = {}
    problems = 0
    for path in kernel_files(root):
        text = open(path, "r", encoding="utf-8", errors="replace").read()
        rel = os.path.relpath(path, root)
        if rel != os.path.join("lib", "cmdword.fi") and SCANNER_DEF.search(text):
            print("  FAIL  %s defines its own substring scanner" % rel)
            problems += 1
        if RAW_CALL.search(text):
            print("  FAIL  %s calls a raw substring scanner" % rel)
            problems += 1
        for name, word in WORD_DECL.findall(text):
            words.setdefault(word, []).append(os.path.basename(path))
    shared = sum(1 for a in words for b in words if a != b and a in b)
    if problems:
        print("  %d scanners bypass lib/cmdword" % problems)
        return 1
    print("  ok    %d mode words, %d substring pairs, all matched as whole words"
          % (len(words), shared))
    return 0


if __name__ == "__main__":
    sys.exit(main())
