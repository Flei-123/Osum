#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/print/pwgcheck.py -- a SECOND, independent reader of PWG raster
(PWG 5102.4), written from the standard and not from kernel/app/drucke.fi.

    pwgcheck.py <file.pwg> <outdir>

Checks the sync word, every 1796-octet page header, and decodes every row
strictly: a run that overflows the row, a missing row or trailing octets
are errors, not warnings. Each page is written as <outdir>/page-<n>.pgm
(8-bit grey), which tesseract reads directly.

Output: one `key=value` line per fact, `ok=1` at the end if everything
held. Exit code 0 only then.
"""
import struct
import sys


def u32(h, off):
    return struct.unpack(">I", h[off:off + 4])[0]


def cstr(h, off, n=64):
    return h[off:off + n].split(b"\0", 1)[0].decode("ascii", "replace")


def main():
    data = open(sys.argv[1], "rb").read()
    out = sys.argv[2]
    errors = []
    if data[:4] != b"RaS2":
        print("sync=%r" % data[:4])
        print("ok=0")
        return 1
    print("sync=RaS2")
    pos = 4
    page = 0
    while pos < len(data):
        if pos + 1796 > len(data):
            errors.append("truncated header at %d" % pos)
            break
        h = data[pos:pos + 1796]
        pos += 1796
        page += 1
        w, hgt = u32(h, 372), u32(h, 376)
        bpc, bpp, bpl = u32(h, 384), u32(h, 388), u32(h, 392)
        cs, ncol = u32(h, 400), u32(h, 420)
        xres, yres = u32(h, 276), u32(h, 280)
        pw, ph = u32(h, 352), u32(h, 356)
        total = u32(h, 452)
        print("page%d=%dx%d dpi=%dx%d bpc=%d bpp=%d bpl=%d cs=%d ncol=%d "
              "pagesize=%dx%d total=%d type=%s size=%s"
              % (page, w, hgt, xres, yres, bpc, bpp, bpl, cs, ncol, pw, ph,
                 total, cstr(h, 0), cstr(h, 1732)))
        if bpp != 8 or bpc != 8 or bpl != w or ncol != 1:
            errors.append("page %d: not 8-bit single channel" % page)
            break
        rows = []
        while len(rows) < hgt:
            if pos >= len(data):
                errors.append("page %d: data ends after %d rows" % (page, len(rows)))
                break
            rep = data[pos] + 1
            pos += 1
            row = bytearray()
            while len(row) < w:
                if pos >= len(data):
                    errors.append("page %d: row cut" % page)
                    break
                c = data[pos]
                pos += 1
                if c == 128:
                    row.extend(b"\xff" * (w - len(row)))
                elif c < 128:
                    row.extend(data[pos:pos + 1] * (c + 1))
                    pos += 1
                else:
                    n = 257 - c
                    row.extend(data[pos:pos + n])
                    pos += n
            if len(row) != w:
                errors.append("page %d row %d: %d pixels, expected %d"
                              % (page, len(rows), len(row), w))
                break
            for _ in range(rep):
                rows.append(bytes(row))
        if len(rows) != hgt:
            errors.append("page %d: %d rows, header says %d" % (page, len(rows), hgt))
            break
        img = b"".join(rows)
        ink = sum(1 for v in img if v < 128)
        inked = [r for r in rows if min(r) < 128]
        top = next((y for y in range(hgt) if min(rows[y]) < 128), -1)
        bot = next((y for y in range(hgt - 1, -1, -1) if min(rows[y]) < 128), -1)
        lefts = [next(i for i, v in enumerate(r) if v < 128) for r in inked]
        rights = [w - 1 - next(i for i, v in enumerate(reversed(r)) if v < 128)
                  for r in inked]
        print("page%d_ink=%d box=%s,%s,%s,%s" % (
            page, ink, min(lefts) if lefts else -1, top,
            max(rights) if rights else -1, bot))
        with open("%s/page-%d.pgm" % (out, page), "wb") as f:
            f.write(b"P5\n%d %d\n255\n" % (w, hgt))
            f.write(img)
    print("pages=%d" % page)
    for e in errors:
        print("error=%s" % e)
    ok = not errors and page > 0
    print("ok=%d" % (1 if ok else 0))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
