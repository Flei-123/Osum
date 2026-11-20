import sys
from PIL import Image

COLOUR_STEP = 24


def lum(p):
    return p[0] + p[1] + p[2]


def measure(path):
    img = Image.open(path).convert("RGB")
    width, height = img.size
    px = img.load()
    fringe = 0
    right_order = 0
    wrong_order = 0
    for y in range(height // 4, height - 60):
        for x in range(1, width // 2):
            r, g, b = px[x, y]
            blue_minus_red = b - r
            if max(r, g, b) - min(r, g, b) <= COLOUR_STEP or abs(blue_minus_red) <= COLOUR_STEP:
                continue
            fringe += 1
            slope = lum(px[x + 1, y]) - lum(px[x - 1, y])
            if slope * blue_minus_red > 0:
                right_order += 1
            elif slope * blue_minus_red < 0:
                wrong_order += 1
    return fringe, right_order, wrong_order


print(*measure(sys.argv[1]))
