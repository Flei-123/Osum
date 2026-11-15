import sys

COLORS = [(255, 0, 0), (0, 255, 0), (0, 0, 255), (255, 255, 255)]
ALT_COLORS = [(0, 0, 255), (255, 255, 255), (255, 0, 0), (0, 255, 0)]
MIN_SHARE = 0.9


def read_ppm(path):
    data = open(path, "rb").read()
    fields = []
    pos = 0
    while len(fields) < 4:
        while data[pos:pos + 1].isspace():
            pos += 1
        start = pos
        while not data[pos:pos + 1].isspace():
            pos += 1
        fields.append(data[start:pos])
    w, h = int(fields[1]), int(fields[2])
    return w, h, data[pos + 1:]


def share(pixels, w, h, qx, qy, color):
    hits = total = 0
    for y in range(qy * h // 2, (qy + 1) * h // 2, 4):
        for x in range(qx * w // 2, (qx + 1) * w // 2, 4):
            i = (y * w + x) * 3
            total += 1
            hits += tuple(pixels[i:i + 3]) == color
    return hits / max(total, 1)


def main():
    w, h, pixels = read_ppm(sys.argv[1])
    colors = ALT_COLORS if len(sys.argv) > 2 and sys.argv[2] == "alt" else COLORS
    shares = [share(pixels, w, h, q % 2, q // 2, colors[q]) for q in range(4)]
    text = " ".join("%.3f" % s for s in shares)
    if min(shares) >= MIN_SHARE:
        print("quadrants ok %dx%d %s" % (w, h, text))
        return 0
    print("quadrants wrong %dx%d %s" % (w, h, text))
    return 1


sys.exit(main())
