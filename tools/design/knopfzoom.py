#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import sys, zlib, struct


def ppm_read(p):
    d = open(p, 'rb').read()
    if not d.startswith(b'P6'):
        raise SystemExit("kein P6-PPM: " + p)
    tok, i = [], 2
    while len(tok) < 3:
        while i < len(d) and d[i:i + 1].isspace():
            i += 1
        if d[i:i + 1] == b'#':
            while d[i:i + 1] not in (b'\n', b''):
                i += 1
            continue
        j = i
        while j < len(d) and not d[j:j + 1].isspace():
            j += 1
        tok.append(int(d[i:j]))
        i = j
    i += 1
    w, h, _ = tok
    return w, h, d[i:i + w * h * 3]


def png(path_2, w, h, px):
    raw = b''.join(b'\x00' + bytes(px[y * w * 3:(y + 1) * w * 3])
                   for y in range(h))
    def chunk(t, d):
        c = struct.pack('>I', len(d)) + t + d
        return c + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)
    open(path_2, 'wb').write(
        b'\x89PNG\r\n\x1a\n'
        + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
        + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b''))


def ausschnitt(w, h, px, x0, y0, bw, bh, zoom):
    ow, oh = bw * zoom, bh * zoom
    out = [0] * (ow * oh * 3)
    for y in range(bh):
        for x in range(bw):
            sx, sy = x0 + x, y0 + y
            if 0 <= sx < w and 0 <= sy < h:
                i = (sy * w + sx) * 3
                r, g, b = px[i], px[i + 1], px[i + 2]
            else:
                r = g = b = 0
            for dy in range(zoom):
                for dx in range(zoom):
                    o = ((y * zoom + dy) * ow + x * zoom + dx) * 3
                    out[o], out[o + 1], out[o + 2] = r, g, b
    return ow, oh, out


if __name__ == '__main__':
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    src, dst = sys.argv[1], sys.argv[2]
    zoom = int(sys.argv[3]) if len(sys.argv) > 3 else 12
    w, h, px = ppm_read(src)

    def color_2(x, y):
        i = (y * w + x) * 3
        return (px[i], px[i + 1], px[i + 2])

    hg = color_2(w - 5, 5)
    y0 = None
    for y in range(0, h // 2):
        changed = sum(1 for x in range(w // 2, w - 1, 7) if color_2(x, y) != hg)
        if changed > 8:
            y0 = y
            break
    if y0 is None:
        y0 = 0
    bw, bh = 260, 80
    x0 = max(0, w - bw - 20)
    ow, oh, out = ausschnitt(w, h, px, x0, y0, bw, bh, zoom)
    png(dst, ow, oh, out)
    print("%s -> %s  (Ausschnitt %d,%d %dx%d, Zoom %d)"
          % (src.split('/')[-1], dst, x0, y0, bw, bh, zoom))

    zaehl = {}
    for y in range(y0, min(h, y0 + bh)):
        for x in range(x0, min(w, x0 + bw)):
            zaehl[color_2(x, y)] = zaehl.get(color_2(x, y), 0) + 1
    top = sorted(zaehl.items(), key=lambda kv: -kv[1])[:6]
    print("   haeufigste Farben im Knopfbereich:")
    for c, n in top:
        print("     rgb%-18s %6d" % (str(c), n))
