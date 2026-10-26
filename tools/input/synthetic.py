#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "corpus", "synthetic")
NAME = "hybrid-touch"
SLOTS = 2
XMAX = 4095
YMAX = 4095

FRAMES = [
    (3, [(1, 1, 1000, 1000), (1, 2, 2000, 1000)]),
    (0, [(1, 3, 3000, 1000), (0, 0, 0, 0)]),
    (3, [(1, 1, 1100, 1000), (1, 2, 2000, 1000)]),
    (0, [(0, 3, 3000, 1000), (0, 0, 0, 0)]),
    (0, [(0, 0, 0, 0), (0, 0, 0, 0)]),
]


def descriptor():
    d = [0x05, 0x0D, 0x09, 0x04, 0xA1, 0x01, 0x85, 0x01]
    for _ in range(SLOTS):
        d += [0x09, 0x22, 0xA1, 0x02, 0x05, 0x0D]
        d += [0x09, 0x42, 0x15, 0x00, 0x25, 0x01, 0x75, 0x01, 0x95, 0x01, 0x81, 0x02]
        d += [0x75, 0x07, 0x95, 0x01, 0x81, 0x03]
        d += [0x09, 0x51, 0x75, 0x08, 0x95, 0x01, 0x25, 0x0F, 0x81, 0x02]
        d += [0x05, 0x01, 0x09, 0x30, 0x26, XMAX & 255, XMAX >> 8, 0x75, 0x10, 0x95, 0x01, 0x81, 0x02]
        d += [0x09, 0x31, 0x26, YMAX & 255, YMAX >> 8, 0x81, 0x02]
        d += [0x05, 0x0D, 0xC0]
    d += [0x05, 0x0D, 0x09, 0x54, 0x75, 0x08, 0x95, 0x01, 0x15, 0x00, 0x25, 0x0A, 0x81, 0x02, 0xC0]
    return bytes(d)


def report(count, slots):
    r = [1]
    for tip, cid, x, y in slots:
        r += [tip & 1, cid, x & 255, x >> 8, y & 255, y >> 8]
    r.append(count)
    return bytes(r)


def fields(count, slots):
    parts = ["count=%d" % count]
    for i, (tip, cid, x, y) in enumerate(slots):
        parts.append("contact%d=tip:%d,id:%d,x:%d,y:%d" % (i, tip, cid, x, y))
    return " ".join(parts)


def main():
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, NAME + ".desc.hex"), "w") as f:
        f.write(descriptor().hex() + "\n")
    lines = ["# Synthetic hybrid-mode touch screen: 2 contact slots per report, Contact Count = frame total in the first report, 0 in the continuation.",
             "# Format: <device> <name> <hex> | fields: <decoded values>"]
    for i, (count, slots) in enumerate(FRAMES):
        lines.append("%s r%d %s | fields: %s" % (NAME, i + 1, report(count, slots).hex(), fields(count, slots)))
    with open(os.path.join(OUT, "reports.txt"), "w") as f:
        f.write("\n".join(lines) + "\n")
    print("wrote", OUT)


if __name__ == "__main__":
    sys.exit(main())
