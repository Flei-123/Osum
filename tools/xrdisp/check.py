import sys

from PIL import Image


def main():
    path, want_w, want_h = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
    img = Image.open(path).convert("RGB")
    w, h = img.size
    if (w, h) != (want_w, want_h):
        print("SIZE-BAD %dx%d want %dx%d" % (w, h, want_w, want_h))
        return 1
    colours = len(set(img.resize((64, 48)).getdata()))
    band = max(24, h // 20)
    top = list(img.crop((0, 0, w, band)).resize((32, 4)).getdata())
    bottom = list(img.crop((0, h - band, w, h)).resize((32, 4)).getdata())
    differs = sum(1 for a, b in zip(top, bottom) if a != b)
    print("SIZE-OK %dx%d colours=%d bar-diff=%d" % (w, h, colours, differs))
    if colours < 4:
        print("PAINT-BAD")
        return 1
    if differs < 8:
        print("BAR-BAD")
        return 1
    return 0


sys.exit(main())
