#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Rewrite the length of every `static mut NAME: [u8; N] = "text\\0"` in a Firn file to the
real byte count of its string (UTF-8, escapes \\0 \\n \\t \\\\ \\" count one octet).
usage: fixlens.py kernel/user/store.fi"""
import re, sys

def blen(lit):
    n = 0; i = 0
    b = lit.encode()
    while i < len(b):
        if b[i] == 0x5c:
            i += 2
        else:
            i += 1
        n += 1
    return n

p = sys.argv[1]
out = []
fixed = 0
for ln in open(p, encoding="utf-8").read().split("\n"):
    m = re.match(r'^(static mut [A-Za-z_0-9]+: \[u8; )(\d+)(\] = ")(.*)("\s*)$', ln)
    if m and not m.group(4).startswith("[") :
        n = blen(m.group(4))
        if str(n) != m.group(2):
            fixed += 1
            ln = m.group(1) + str(n) + m.group(3) + m.group(4) + m.group(5)
    out.append(ln)
open(p, "w", encoding="utf-8").write("\n".join(out))
print("fixed", fixed)
