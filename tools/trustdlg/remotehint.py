import sys

from PIL import Image

DIALOG_W = 456
CLOSE_W = 44
TITLE_H = 36
HINT_MIN_PIXELS = 40
CONTROL_MAX_PIXELS = 5
CHANNEL_GAP = 24


def strip_box(x, y, k):
    left = x + (DIALOG_W // 2) * k
    right = x + (DIALOG_W - CLOSE_W) * k
    return left, y, right, y + TITLE_H * k


def diff_pixels(a, b, box):
    ca = a.crop(box)
    cb = b.crop(box)
    n = 0
    for pa, pb in zip(ca.getdata(), cb.getdata()):
        if max(abs(pa[i] - pb[i]) for i in range(3)) > CHANNEL_GAP:
            n += 1
    return n


def main():
    base_a, base_b, remote = (Image.open(p).convert("RGB") for p in sys.argv[1:4])
    x, y, k = int(sys.argv[4]), int(sys.argv[5]), int(sys.argv[6])
    box = strip_box(x, y, k)
    control = diff_pixels(base_a, base_b, box)
    hint = diff_pixels(base_b, remote, box)
    print("control_diff=%d hint_diff=%d box=%s" % (control, hint, box))
    if control <= CONTROL_MAX_PIXELS and hint >= HINT_MIN_PIXELS * k:
        print("HINT-OK")
        return 0
    print("HINT-BAD")
    return 1


sys.exit(main())
