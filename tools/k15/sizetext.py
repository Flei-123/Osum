#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/k15/sizetext.py <bytes>... -- a size as the file manager writes it (lib/fui/navnum.fi `size_text`).

The reference the pixel checks use for the Size column: "354 B", "1.5 KB", "12 KB", "3.4 MB", "5.0 GB".
Units of 1024; one decimal below 10 of a unit, none from there on (rounded half up)."""
import sys


def size_text(n):
    if n < 1024:
        return "%d B" % n
    unit, name = 1024, " KB"
    if n >= 1024 ** 3:
        unit, name = 1024 ** 3, " GB"
    elif n >= 1024 ** 2:
        unit, name = 1024 ** 2, " MB"
    tenths = (n * 10 + unit // 2) // unit
    if tenths >= 100:
        return "%d%s" % ((n + unit // 2) // unit, name)
    return "%d.%d%s" % (tenths // 10, tenths % 10, name)


if __name__ == "__main__":
    for a in sys.argv[1:]:
        print(size_text(int(a)))
