#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import sys


def tables(text):
    found = {}
    current = None
    for raw in text.splitlines():
        line = raw.replace("\r", "").replace("\x00", "")
        head = re.match(r"amltab (\d+) sig=(\S{4}) len=(\d+)", line)
        if head:
            current = [head.group(2), int(head.group(3)), bytearray()]
            found.setdefault(head.group(2), []).append(current)
            continue
        body = re.match(r"amlhex ([0-9a-fA-F]+)$", line)
        if body and current is not None:
            current[2].extend(bytes.fromhex(body.group(1)))
    return found


def main(argv):
    if len(argv) != 4:
        print("usage: dumptab.py SERIAL_LOG SIG OUT", file=sys.stderr)
        return 2
    with open(argv[1], "r", errors="replace") as f:
        found = tables(f.read())
    entries = found.get(argv[2])
    if not entries:
        print("table %s not in the dump" % argv[2], file=sys.stderr)
        return 1
    sig, length, data = entries[0]
    if len(data) != length:
        print("table %s: %d of %d bytes" % (sig, len(data), length), file=sys.stderr)
        return 1
    with open(argv[3], "wb") as f:
        f.write(bytes(data))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
