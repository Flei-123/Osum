import sys
from PIL import Image

STRONG_STEP = 40
FULL_FRACTION = 0.6


def luma(px):
    return (px[0] * 299 + px[1] * 587 + px[2] * 114) // 1000


def edge_sharpness(path, x0, y0, x1, y1):
    im = Image.open(path).convert("RGB")
    steps = []
    for y in range(y0, y1):
        row = [luma(im.getpixel((x, y))) for x in range(x0, x1)]
        for a, b in zip(row, row[1:]):
            if abs(a - b) >= STRONG_STEP:
                steps.append(abs(a - b))
    if not steps:
        return 0.0
    top = max(steps)
    full = sum(1 for s in steps if s >= FULL_FRACTION * top)
    return full / len(steps)


if __name__ == "__main__":
    path = sys.argv[1]
    box = [int(v) for v in sys.argv[2:6]]
    print("%.3f" % edge_sharpness(path, *box))
