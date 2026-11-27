import sys

BLUE = (0x14, 0x14, 0xC8)
GREEN = (0x14, 0xC8, 0x14)
RED = (0xC8, 0x14, 0x14)
EXPECT_BLUE = (40, 30, 60, 40)


def load(path):
    data = open(path, "rb").read()
    parts = data.split(None, 4)
    w, h = int(parts[1]), int(parts[2])
    return data[len(data) - w * h * 3:], w, h


def bbox(raw, w, h, colour, tol=6):
    xs, ys = [], []
    for y in range(h):
        row = raw[y * w * 3:(y + 1) * w * 3]
        for x in range(w):
            p = row[x * 3:x * 3 + 3]
            if all(abs(p[i] - colour[i]) <= tol for i in range(3)):
                xs.append(x)
                ys.append(y)
    if not xs:
        return None
    return min(xs), min(ys), max(xs) - min(xs) + 1, max(ys) - min(ys) + 1


raw, w, h = load(sys.argv[1])
red = bbox(raw, w, h, RED)
blue = bbox(raw, w, h, BLUE)
green = bbox(raw, w, h, GREEN)
print("red", red, "blue", blue, "green", green)
if red is None or blue is None:
    sys.exit(1)
rel = (blue[0] - red[0], blue[1] - red[1], blue[2], blue[3])
print("blue_rel", rel, "green_visible", green is not None)
sys.exit(0 if rel == EXPECT_BLUE and green is None else 2)
