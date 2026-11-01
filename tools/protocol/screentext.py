#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/protocol/screentext.py -- read the text from a screen photo.

Decodes a PPM by cutting it into 8x16 cells and looking each cell up in the
glyph table of kernel/gfx/font.fi (exact inverse of drawing; unknown cells
become '?').

Usage:
    python3 tools/protocol/screentext.py IMAGE.ppm [kernel/gfx/font.fi]
Output: the screen text, line by line, on standard output.
"""
import re
import sys

GLYPH_W = 8
GLYPH_H = 16
FIRST = 0x20
LAST = 0x7E


def load_glyphs(path):
    text = open(path, encoding="utf-8", errors="surrogateescape").read()
    raw = bytearray()
    for m in re.finditer(r'b"((?:\\x[0-9a-fA-F]{2})+)"', text):
        for h in re.findall(r"\\x([0-9a-fA-F]{2})", m.group(1)):
            raw.append(int(h, 16))
    table = {}
    for c in range(FIRST, LAST + 1):
        i = (c - FIRST) * GLYPH_H
        if i + GLYPH_H > len(raw):
            break
        table.setdefault(bytes(raw[i:i + GLYPH_H]), chr(c))
    return table


def read_ppm(path):
    with open(path, "rb") as f:
        data = f.read()
    if not data.startswith(b"P6"):
        raise SystemExit("not a binary PPM (P6): " + path)
    fields = []
    i = 2
    while len(fields) < 3:
        while i < len(data) and data[i:i + 1].isspace():
            i += 1
        if data[i:i + 1] == b"#":
            while data[i:i + 1] not in (b"\n", b""):
                i += 1
            continue
        j = i
        while j < len(data) and not data[j:j + 1].isspace():
            j += 1
        fields.append(int(data[i:j]))
        i = j
    i += 1
    w, h, _mx = fields
    return w, h, data[i:i + w * h * 3]


def main():
    if len(sys.argv) < 2:
        sys.stderr.write(__doc__)
        return 1
    image = sys.argv[1]
    font = sys.argv[2] if len(sys.argv) > 2 else "kernel/gfx/font.fi"
    table = load_glyphs(font)
    if not table:
        sys.stderr.write("screentext: no font in " + font + "\n")
        return 1
    w, h, px = read_ppm(image)

    def pixel(x, y):
        o = (y * w + x) * 3
        return (px[o], px[o + 1], px[o + 2])

    counts = {}
    for y in range(0, h, 4):
        for x in range(0, w, 4):
            p = pixel(x, y)
            counts[p] = counts.get(p, 0) + 1
    bg = max(counts.items(), key=lambda kv: kv[1])[0]

    lines = []
    for zy in range(h // GLYPH_H):
        line = []
        for zx in range(w // GLYPH_W):
            pattern = bytearray()
            for r in range(GLYPH_H):
                b = 0
                for c in range(GLYPH_W):
                    if pixel(zx * GLYPH_W + c, zy * GLYPH_H + r) != bg:
                        b |= 0x80 >> c
                pattern.append(b)
            m = bytes(pattern)
            if not any(m):
                line.append(" ")
            else:
                line.append(table.get(m, "?"))
        lines.append("".join(line).rstrip())
    while lines and not lines[-1]:
        lines.pop()
    for z in lines:
        print(z)
    return 0


if __name__ == "__main__":
    sys.exit(main())
