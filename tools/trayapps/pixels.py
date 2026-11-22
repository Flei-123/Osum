import re
import sys


def load(path):
    data = open(path, "rb").read()
    fields = []
    at = 2
    while len(fields) < 3:
        while data[at:at + 1].isspace():
            at += 1
        start = at
        while not data[at:at + 1].isspace():
            at += 1
        fields.append(int(data[start:at]))
    return fields[0], fields[1], data[at + 1:]


def pixel(width, body, x, y):
    o = (y * width + x) * 3
    return body[o:o + 3]


def ink_report(path, x0, y0, w, h):
    width, _, body = load(path)
    corner = pixel(width, body, x0, y0)
    colours = set()
    xs = []
    ys = []
    for y in range(y0, y0 + h):
        for x in range(x0, x0 + w):
            px = pixel(width, body, x, y)
            colours.add(px)
            if px != corner:
                xs.append(x)
                ys.append(y)
    if not xs:
        return len(colours), 0, 0, 0
    cx2 = min(xs) + max(xs) - 2 * x0 - w
    cy2 = min(ys) + max(ys) - 2 * y0 - h
    return len(colours), len(xs), cx2, cy2


def diff_count(a, b, x0, y0, w, h):
    wa, _, ba = load(a)
    wb, _, bb = load(b)
    n = 0
    for y in range(y0, y0 + h):
        for x in range(x0, x0 + w):
            if pixel(wa, ba, x, y) != pixel(wb, bb, x, y):
                n += 1
    return n


def app_rect(serial, index):
    text = open(serial, "rb").read().decode("latin-1")
    geom = re.findall(r"taskbar: geom edge=\d+ x=(\d+) y=(\d+) w=\d+ h=\d+", text)
    icons = re.findall(r"taskbar: app icon %d id=\d+ glyph=\d+ x=(\d+) y=(\d+) w=(\d+) h=(\d+)" % index, text)
    if not geom or not icons:
        return None
    gx, gy = int(geom[-1][0]), int(geom[-1][1])
    x, y, w, h = (int(v) for v in icons[-1])
    return gx + x, gy + y, w, h


def main():
    cmd = sys.argv[1]
    if cmd == "rect":
        r = app_rect(sys.argv[2], int(sys.argv[3]))
        print("%d %d %d %d" % r if r else "none")
        return
    nums = [int(v) for v in sys.argv[-4:]]
    if cmd == "ink":
        colours, inked, cx2, cy2 = ink_report(sys.argv[2], *nums)
        print(colours, inked, cx2, cy2)
    elif cmd == "diff":
        print(diff_count(sys.argv[2], sys.argv[3], *nums))


main()
