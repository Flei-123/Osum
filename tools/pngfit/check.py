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
        assert raw[base] == 0, 'filter'
        rows.append(list(raw[base + 1:base + 1 + w * 3]))
    return len(data), w, h, rows


def main():
    path, w, h, cap, steps = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), int(sys.argv[5])
    size, pw, ph, rows = read_png(path)
    exp = lcg_image(w, h)
    ew, eh = w, h
    for _ in range(steps):
        exp, ew, eh = halve(exp, ew, eh)
    assert (pw, ph) == (ew, eh), 'dims %dx%d expected %dx%d' % (pw, ph, ew, eh)
    assert rows == exp, 'pixels differ'
    assert cap == 0 or size <= cap, 'size %d over cap %d' % (size, cap)
    print('%d %dx%d' % (size, pw, ph))


main()
