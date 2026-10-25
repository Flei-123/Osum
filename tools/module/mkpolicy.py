#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import argparse
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MAX_KEYS = 4
MAX_FLOOR = 64


def read_hex_lines(path, width, limit, what):
    items = []
    for raw in open(path).read().splitlines():
        line = raw.split("#", 1)[0].strip().lower()
        if not line:
            continue
        if not re.fullmatch(r"[0-9a-f]{%d}" % width, line):
            sys.exit("mkpolicy: bad %s line in %s: %r" % (what, path, raw))
        if line in items:
            sys.exit("mkpolicy: duplicate %s in %s" % (what, path))
        items.append(line)
    if len(items) > limit:
        sys.exit("mkpolicy: at most %d %s entries" % (limit, what))
    return items


def render(keys, floor):
    kh = "".join(keys)
    fh = "".join(floor)
    out = []
    out.append("// SPDX-License-Identifier: GPL-2.0-only")
    out.append("profile kernel")
    out.append("")
    out.append("export { KEYS_N, FLOOR_N, key_char, floor_char }")
    out.append("")
    out.append("const KEYS_N: u64 = %d" % len(keys))
    out.append("const FLOOR_N: u64 = %d" % len(floor))
    out.append("")
    out.append('static mut KEYS_HEX: [u8; %d] = "%s\\0"' % (len(kh) + 1, kh))
    out.append('static mut FLOOR_HEX: [u8; %d] = "%s\\0"' % (len(fh) + 1, fh))
    out.append("")
    out.append("fn key_char(i: u64) -> u64 {")
    out.append("    return KEYS_HEX[i as usize] as u64")
    out.append("}")
    out.append("")
    out.append("fn floor_char(i: u64) -> u64 {")
    out.append("    return FLOOR_HEX[i as usize] as u64")
    out.append("}")
    out.append("")
    return "\n".join(out)


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--keys", default=os.path.join(HERE, "keys.default"))
    ap.add_argument("--floor", default=os.path.join(HERE, "banfloor.txt"))
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args(argv)
    keys = read_hex_lines(a.keys, 64, MAX_KEYS, "key")
    if not keys:
        sys.exit("mkpolicy: no trusted key")
    floor = read_hex_lines(a.floor, 128, MAX_FLOOR, "floor")
    text = render(keys, floor)
    if a.check:
        cur = open(a.out).read() if os.path.exists(a.out) else ""
        if cur != text:
            sys.exit("mkpolicy: %s is stale" % a.out)
        print("mkpolicy: %s up to date" % a.out)
        return 0
    open(a.out, "w").write(text)
    print("mkpolicy: %d keys, %d floor entries -> %s" % (len(keys), len(floor), a.out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
