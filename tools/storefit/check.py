import re
import sys

RECT = re.compile(r"rect id=(\d+) kind=(\d+) x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
GEOM = re.compile(r"geom cols=(\d+) rows=(\d+) width=(\d+) height=(\d+)")
MIN_CARD_W = 224
MIN_CARD_H = 112
GAP = 12
TILE_INSET = 24
GRID_OVERHEAD = 236


def widest_rects(path):
    groups = []
    prev = -1
    for line in open(path, errors="replace"):
        m = RECT.search(line)
        if not m:
            continue
        rid = int(m.group(1))
        if rid <= prev or not groups:
            groups.append([])
        prev = rid
        groups[-1].append(tuple(int(v) for v in m.groups()))
    return max(groups, key=len) if groups else []


def main():
    res, scale, size, geom_path, rect_path = sys.argv[1:6]
    want_w, want_h = (int(v) for v in size.split("x"))
    scale = int(scale)
    dp_w = want_w // scale
    dp_h = want_h // scale
    geom = GEOM.search(open(geom_path, errors="replace").read())
    rects = [(r[0], r[1], r[2] // scale, r[3] // scale, r[4] // scale, r[5] // scale) for r in widest_rects(rect_path)]
    if not geom or not rects:
        print("FAIL no geometry or rect dump (geom=%s rects=%d)" % (bool(geom), len(rects)))
        return
    cols, rows, width, height = (int(v) for v in geom.groups())
    print("INFO res %s scale %d size %s geom cols=%d rows=%d width=%d height=%d rects=%d" % (res, scale, size, cols, rows, width, height, len(rects)))
    print(("OK" if abs(width - dp_w) <= 8 and abs(height - dp_h) <= 8 else "FAIL") + " the window took the requested size (%dx%d dp, wanted %dx%d)" % (width, height, dp_w, dp_h))
    exp_cols = max(1, min(5, (width - 76 - 32 + GAP) // (MIN_CARD_W + GAP)))
    print(("OK" if cols == exp_cols else "FAIL") + " columns follow the width: %d (expected %d)" % (cols, exp_cols))
    exp_rows = max(1, (height - 8 - GRID_OVERHEAD + GAP) // (MIN_CARD_H + GAP))
    while cols * exp_rows > 20:
        exp_rows -= 1
    print(("OK" if rows == exp_rows else "FAIL") + " rows follow the height: %d (expected %d)" % (rows, exp_rows))
    cards = [r for r in rects if r[4] > 150 and 40 < r[5] < 200 and r[3] > 90]
    xs = sorted(set(r[2] for r in cards))
    first_row_y = min(r[3] for r in cards) if cards else 0
    first_row = [r for r in cards if abs(r[3] - first_row_y) < 4]
    print(("OK" if len(first_row) == min(cols, 4) else "FAIL") + " first card row holds %d cards (cols %d, 4 apps)" % (len(first_row), cols))
    card_w = (width - 76 - 32 - (cols - 1) * GAP) // cols
    left = min(r[2] for r in first_row) if first_row else 0
    right = max(r[2] + r[4] for r in first_row) if first_row else 0
    want_right = left + len(first_row) * card_w + (len(first_row) - 1) * GAP - TILE_INSET
    print(("OK" if abs(right - want_right) <= 12 else "FAIL") + " the cards share the width: right edge %d (expected %d, card width %d)" % (right, want_right, card_w))
    outside = [r for r in rects if r[2] + r[4] > width + 2 or r[3] + r[5] > height + 2]
    print(("OK" if not outside else "FAIL") + " nothing sticks out of the window (%d rects outside %s)" % (len(outside), outside[:3]))
    top = min(r[3] for r in rects)
    left = min(r[2] for r in rects)
    print(("OK" if top <= 24 and left <= 12 else "FAIL") + " the content starts at the top left (x0=%d y0=%d)" % (left, top))


main()
