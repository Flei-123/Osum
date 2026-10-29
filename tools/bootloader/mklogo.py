#!/usr/bin/env python3
import struct
import sys

MAGIC = b"OBL1"


def convert(src, dst, height):
    from PIL import Image
    image = Image.open(src).convert("RGBA")
    width = max(1, round(image.width * height / image.height))
    image = image.resize((width, height), Image.LANCZOS)
    with open(dst, "wb") as out:
        out.write(MAGIC + struct.pack("<II", width, height))
        out.write(image.tobytes())
    return width, height


def main(argv):
    if len(argv) < 3:
        sys.stderr.write("usage: mklogo.py <logo.png> <osboot.logo> [--height N]\n")
        return 2
    height = 192
    rest = argv[3:]
    while rest:
        flag = rest.pop(0)
        if flag == "--height":
            height = int(rest.pop(0))
    width, height = convert(argv[1], argv[2], height)
    print("mklogo: %dx%d" % (width, height))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
