import sys

MIN_PIXELS = 150
NOISE_MAX = 60
MAX_PIXELS = 30000
CENTER_SLACK = 0.08


def load(path):
    with open(path, "rb") as f:
        data = f.read()
    parts = []
    pos = 0
    while len(parts) < 4:
        while data[pos:pos + 1].isspace():
            pos += 1
        if data[pos:pos + 1] == b"#":
            while data[pos:pos + 1] != b"\n":
                pos += 1
            continue
        end = pos
        while not data[end:end + 1].isspace():
            end += 1
        parts.append(data[pos:end])
        pos = end
    pos += 1
    width, height = int(parts[1]), int(parts[2])
    return width, height, data[pos:pos + width * height * 3]


def diff_box(a, b, width, height):
    xs, ys, lit = [], [], 0
    for y in range(height):
        row = y * width * 3
        if a[row:row + width * 3] == b[row:row + width * 3]:
            continue
        for x in range(width):
            i = row + x * 3
            if a[i:i + 3] != b[i:i + 3]:
                xs.append(x)
                ys.append(y)
                if sum(b[i:i + 3]) > sum(a[i:i + 3]):
                    lit += 1
    if not xs:
        return None
    return min(xs), min(ys), max(xs), max(ys), len(xs), lit


def verdict(label, ok, detail):
    print("  %s  %s%s" % ("OK  " if ok else "FAIL", label, (" -- " + detail) if detail else ""))
    return ok


def main():
    mode, off_path, on_path = sys.argv[1], sys.argv[2], sys.argv[3]
    w0, h0, off = load(off_path)
    w1, h1, on = load(on_path)
    if (w0, h0) != (w1, h1):
        verdict("same size", False, "%dx%d vs %dx%d" % (w0, h0, w1, h1))
        sys.exit(1)
    box = diff_box(off, on, w0, h0)
    if mode == "same":
        sys.exit(0 if verdict("no hint pixels (counter-proof)", box is None or box[4] <= NOISE_MAX, str(box)) else 1)
    if not verdict("hint pixels appear", box is not None, "no difference"):
        sys.exit(1)
    x0, y0, x1, y1, count, lit = box
    centre = (x0 + x1) / 2.0 / w0
    results = [
        verdict("pixel count in range", MIN_PIXELS <= count <= MAX_PIXELS, str(count)),
        verdict("hint is centred", abs(centre - 0.5) <= CENTER_SLACK, "%.3f" % centre),
        verdict("hint is below the middle block top", y0 > h0 * 0.3, str(y0)),
        verdict("hint is lighter than its background", lit * 2 >= count, "%d of %d" % (lit, count)),
        verdict("nothing clipped at the screen edge", x0 > 0 and x1 < w0 - 1 and y1 < h0 - 1, str(box[:4])),
    ]
    sys.exit(0 if all(results) else 1)


main()
