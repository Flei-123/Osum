#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import re
import sys

HEAD = re.compile(r"#\s+(\S+)\s+len=([0-9a-fA-F]+)\s+idx=([0-9a-fA-F]+)")
ROW = re.compile(r"([0-9a-fA-F]{8})\s+([0-9a-fA-F]+)\s*$")


def parse(text):
    tables = []
    for raw in text.splitlines():
        line = raw.replace("\r", "").rstrip()
        head = HEAD.match(line)
        if head:
            tables.append([head.group(1), int(head.group(2), 16), bytearray()])
            continue
        row = ROW.match(line)
        if row and tables:
            tables[-1][2].extend(bytes.fromhex(row.group(2)))
    return tables


def names(tables):
    total = {}
    for sig, _, _ in tables:
        total[sig] = total.get(sig, 0) + 1
    seen = {}
    out = []
    for sig, _, _ in tables:
        seen[sig] = seen.get(sig, 0) + 1
        out.append(sig if total[sig] == 1 else "%s%d" % (sig, seen[sig]))
    return out


def main(argv):
    if len(argv) != 3:
        print("usage: fromdump.py ACPIDUMP_TEXT OUTDIR", file=sys.stderr)
        return 2
    with open(argv[1], "r", errors="replace") as f:
        tables = parse(f.read())
    os.makedirs(argv[2], exist_ok=True)
    status = 0
    for (sig, length, data), name in zip(tables, names(tables)):
        if len(data) != length or sum(data) & 0xFF:
            print("%s: %d of %d bytes, checksum %d" % (name, len(data), length, sum(data) & 0xFF), file=sys.stderr)
            status = 1
        with open(os.path.join(argv[2], name), "wb") as f:
            f.write(bytes(data))
        print(name, length)
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv))
