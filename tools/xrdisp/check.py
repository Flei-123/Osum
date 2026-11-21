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
    print("SIZE-OK %dx%d colours=%d" % (w, h, colours))
    if colours < 4:
        print("PAINT-BAD")
        return 1
    return 0


sys.exit(main())
