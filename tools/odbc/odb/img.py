# SPDX-License-Identifier: GPL-2.0-only
"""Tiny PNG reader + screenshot comparison for the host side (stdlib only).

The agent's `shot` returns 8-bit RGB PNGs. `decode_png` returns (w, h, rows) with one bytearray of w*3 octets per row.
`diff` compares two decoded images and reports how many pixels differ by more than `tol` per channel and the bounding
box of the differences. Used by `odbc imgdiff` and tools/odb/loop.py (screenshot before/after checks).
"""
import struct
import zlib


def decode_png(data):
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("no PNG signature")
    pos, idat, ihdr = 8, [], None
    while pos + 12 <= len(data):
        n, typ = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + n]
        if zlib.crc32(typ + body) & 0xFFFFFFFF != struct.unpack(">I", data[pos + 8 + n:pos + 12 + n])[0]:
            raise ValueError("bad CRC in chunk %r" % typ)
        if typ == b"IHDR":
            ihdr = struct.unpack(">IIBBBBB", body)
        elif typ == b"IDAT":
            idat.append(body)
        pos += 12 + n
    if ihdr is None:
        raise ValueError("no IHDR")
    w, h, depth, ctype = ihdr[:4]
    if depth != 8 or ctype != 2:
        raise ValueError("not 8-bit RGB (depth %d type %d)" % (depth, ctype))
    raw = zlib.decompress(b"".join(idat))
    stride = w * 3
    if len(raw) != h * (stride + 1):
        raise ValueError("raw size %d != %d" % (len(raw), h * (stride + 1)))
    rows, prev = [], bytearray(stride)
    for y in range(h):
        f = raw[y * (stride + 1)]
        cur = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        if f == 2:
            cur = bytearray((c + b) & 255 for c, b in zip(cur, prev))
        elif f in (1, 3, 4):
            for i in range(stride):
                a = cur[i - 3] if i >= 3 else 0
                b = prev[i]
                c = prev[i - 3] if i >= 3 else 0
                if f == 1:
                    cur[i] = (cur[i] + a) & 255
                elif f == 3:
                    cur[i] = (cur[i] + ((a + b) >> 1)) & 255
                else:
                    p = a + b - c
                    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                    cur[i] = (cur[i] + (a if (pa <= pb and pa <= pc) else (b if pb <= pc else c))) & 255
        elif f != 0:
            raise ValueError("bad filter %d" % f)
        rows.append(cur)
        prev = cur
    return w, h, rows


def diff(a, b, tol=8, region=None):
    """Compare two decoded images of the same size. region = (x, y, w, h) in pixels or None.
    Returns dict: pixels (compared), changed, frac, bbox=(x0, y0, x1, y1) or None."""
    (aw, ah, ar), (bw, bh, br) = a, b
    if (aw, ah) != (bw, bh):
        raise ValueError("size differs: %dx%d vs %dx%d" % (aw, ah, bw, bh))
    x0, y0, rw, rh = region or (0, 0, aw, ah)
    x1, y1 = min(aw, x0 + rw), min(ah, y0 + rh)
    changed, minx, miny, maxx, maxy = 0, aw, ah, -1, -1
    for y in range(y0, y1):
        ra, rb = ar[y][x0 * 3:x1 * 3], br[y][x0 * 3:x1 * 3]
        if ra == rb:
            continue
        for i in range(0, len(ra), 3):
            if (abs(ra[i] - rb[i]) > tol or abs(ra[i + 1] - rb[i + 1]) > tol or abs(ra[i + 2] - rb[i + 2]) > tol):
                changed += 1
                x = x0 + i // 3
                minx, maxx = min(minx, x), max(maxx, x)
                miny, maxy = min(miny, y), max(maxy, y)
    n = max(1, (x1 - x0) * (y1 - y0))
    return {"pixels": n, "changed": changed, "frac": changed / n,
            "bbox": (minx, miny, maxx, maxy) if changed else None}


def mean_rgb(img, region=None):
    w, h, rows = img
    x0, y0, rw, rh = region or (0, 0, w, h)
    x1, y1 = min(w, x0 + rw), min(h, y0 + rh)
    s = [0, 0, 0]
    for y in range(y0, y1):
        r = rows[y][x0 * 3:x1 * 3]
        for c in range(3):
            s[c] += sum(r[c::3])
    n = max(1, (x1 - x0) * (y1 - y0))
    return tuple(v / n for v in s)
