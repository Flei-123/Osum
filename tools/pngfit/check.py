import struct
import sys
import zlib


def lcg_image(w, h):
    state = 12345
    rows = []
    for _ in range(h):
        row = []
        for _ in range(w * 3):
            state = (state * 1664525 + 1013904223) & 0xFFFFFFFF
            row.append((state >> 16) & 255)
        rows.append(row)
    return rows


def smooth_image(w, h):
    return [[((x // 3) * 255 // w + y * 255 // h + (x % 3) * 40) & 255 for x in range(w * 3)] for y in range(h)]


def halve(rows, w, h):
    nw, nh = (w + 1) // 2, (h + 1) // 2
    out = []
    for dy in range(nh):
        r0 = dy * 2
        r1 = r0 + 1 if r0 + 1 < h else r0
        row = []
        for dx in range(nw):
            x0 = dx * 2
            x1 = x0 + 1 if x0 + 1 < w else x0
            for c in range(3):
                s = rows[r0][x0 * 3 + c] + rows[r0][x1 * 3 + c] + rows[r1][x0 * 3 + c] + rows[r1][x1 * 3 + c]
                row.append((s + 2) // 4)
        out.append(row)
    return out, nw, nh


def quantize(rows, bits):
    keep = (255 >> bits) ^ 255
    return [[(v & keep) | (v >> (8 - bits)) for v in row] for row in rows]


def read_png(path):
    data = open(path, 'rb').read()
    assert data[:8] == b'\x89PNG\r\n\x1a\n', 'signature'
    pos = 8
    idat = b''
    dims = None
    while pos < len(data):
        n = struct.unpack('>I', data[pos:pos + 4])[0]
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + n]
        crc = struct.unpack('>I', data[pos + 8 + n:pos + 12 + n])[0]
        assert zlib.crc32(kind + body) & 0xFFFFFFFF == crc, 'crc ' + kind.decode()
        if kind == b'IHDR':
            dims = struct.unpack('>II', body[:8])
            assert body[8] == 8 and body[9] == 2, 'ihdr format'
        if kind == b'IDAT':
            idat += body
        pos += 12 + n
    w, h = dims
    raw = zlib.decompress(idat)
    assert len(raw) == h * (1 + w * 3), 'raw length'
    rows = []
    for y in range(h):
        base = y * (1 + w * 3)
        ft = raw[base]
        assert ft <= 4, 'filter'
        cur = list(raw[base + 1:base + 1 + w * 3])
        prev = rows[-1] if rows else [0] * (w * 3)
        for i in range(w * 3):
            a = cur[i - 3] if i >= 3 else 0
            b = prev[i]
            c = prev[i - 3] if i >= 3 else 0
            if ft == 1:
                p = a
            elif ft == 2:
                p = b
            elif ft == 3:
                p = (a + b) // 2
            elif ft == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                p = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
            else:
                p = 0
            cur[i] = (cur[i] + p) & 255
        rows.append(cur)
    return len(data), w, h, rows


def main():
    path, w, h, cap, steps, quants, kind = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5]), int(sys.argv[6]), sys.argv[7]
    size, pw, ph, rows = read_png(path)
    exp = smooth_image(w, h) if kind == 'smooth' else lcg_image(w, h)
    for bits in (2, 3)[:quants]:
        exp = quantize(exp, bits)
    ew, eh = w, h
    for _ in range(steps):
        exp, ew, eh = halve(exp, ew, eh)
    assert (pw, ph) == (ew, eh), 'dims %dx%d expected %dx%d' % (pw, ph, ew, eh)
    assert rows == exp, 'pixels differ'
    assert cap == 0 or size <= cap, 'size %d over cap %d' % (size, cap)
    if kind == 'smooth':
        flat = b''.join(b'\0' + bytes(r) for r in rows)
        base = len(zlib.compress(flat, 6))
        assert size * 2 < base, 'filters save too little: %d vs %d unfiltered' % (size, base)
    print('%d %dx%d' % (size, pw, ph))


main()
