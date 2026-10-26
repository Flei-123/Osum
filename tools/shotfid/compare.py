import struct
import sys
import zlib


def read_png(path):
    data = open(path, 'rb').read()
    assert data[:8] == b'\x89PNG\r\n\x1a\n'
    pos, idat, dims, depth, ctype = 8, b'', None, 0, 0
    while pos < len(data):
        n = struct.unpack('>I', data[pos:pos + 4])[0]
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + n]
        if kind == b'IHDR':
            dims = struct.unpack('>II', body[:8])
            depth, ctype = body[8], body[9]
        if kind == b'IDAT':
            idat += body
        pos += 12 + n
    assert depth == 8 and ctype in (2, 6), 'png format'
    bpp = 3 if ctype == 2 else 4
    w, h = dims
    raw = zlib.decompress(idat)
    stride = w * bpp
    prev = bytearray(stride)
    out = bytearray()
    for y in range(h):
        base = y * (stride + 1)
        ft = raw[base]
        cur = bytearray(raw[base + 1:base + 1 + stride])
        for i in range(stride):
            a = cur[i - bpp] if i >= bpp else 0
            b = prev[i]
            c = prev[i - bpp] if i >= bpp else 0
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
        if bpp == 4:
            out += b''.join(bytes(cur[x:x + 3]) for x in range(0, stride, 4))
        else:
            out += cur
        prev = cur
    return w, h, bytes(out)


def read_ppm(path):
    data = open(path, 'rb').read()
    parts = data.split(None, 4)
    assert parts[0] == b'P6'
    w, h = int(parts[1]), int(parts[2])
    off = len(data) - w * h * 3
    return w, h, data[off:]


def load(path):
    return read_png(path) if path.endswith('.png') else read_ppm(path)


def main():
    a_path, b_path, max_px, max_mean = sys.argv[1], sys.argv[2], int(sys.argv[3]), float(sys.argv[4])
    aw, ah, a = load(a_path)
    bw, bh, b = load(b_path)
    assert (aw, ah) == (bw, bh), 'size %dx%d vs %dx%d' % (aw, ah, bw, bh)
    diff = 0
    total = 0
    xs, ys = [], []
    for y in range(ah):
        ra = a[y * aw * 3:(y + 1) * aw * 3]
        rb = b[y * aw * 3:(y + 1) * aw * 3]
        if ra == rb:
            continue
        for x in range(aw):
            pa = ra[x * 3:x * 3 + 3]
            pb = rb[x * 3:x * 3 + 3]
            if pa != pb:
                diff += 1
                total += sum(abs(pa[i] - pb[i]) for i in range(3))
                xs.append(x)
                ys.append(y)
    mean = total / diff / 3 if diff else 0.0
    box = (min(xs), min(ys), max(xs), max(ys)) if diff else None
    print('size %dx%d differing %d mean %.2f box %s' % (aw, ah, diff, mean, box))
    assert diff <= max_px, 'differing pixels %d > %d' % (diff, max_px)
    assert mean <= max_mean, 'mean difference %.2f > %.2f' % (mean, max_mean)


main()
