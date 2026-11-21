#!/usr/bin/env python3
import struct
import sys

MAGIC = b"OBL2"
DEFAULT_HEIGHT = 384
INK_THRESHOLD = 8
HOLE_DILATE = 5
CROP_PAD = 1
RING_COLOR = (11, 13, 16)
RING_TOLERANCE = 40


def blacken_ring(image):
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, a = pixels[x, y]
            if abs(r - RING_COLOR[0]) + abs(g - RING_COLOR[1]) + abs(b - RING_COLOR[2]) <= RING_TOLERANCE:
                pixels[x, y] = (0, 0, 0, a)
    return image


def hole_region(image):
    from PIL import ImageDraw, ImageFilter
    alpha = image.getchannel("A")
    inverse = alpha.point(lambda v: 255 if v <= INK_THRESHOLD else 0)
    seed = (image.width * 3 // 10, image.height // 2)
    if inverse.getpixel(seed) == 0:
        return None
    ImageDraw.floodfill(inverse, seed, 128)
    hole = inverse.point(lambda v: 255 if v == 128 else 0)
    return hole.filter(ImageFilter.MaxFilter(HOLE_DILATE))


def fill_hole(image, region):
    from PIL import Image
    white = Image.new("RGBA", image.size, (255, 255, 255, 255))
    flat = Image.alpha_composite(white, image)
    flat.putalpha(255)
    return Image.composite(flat, image, region)


def crop_square(image, box):
    from PIL import Image
    side = max(box[2] - box[0], box[3] - box[1]) + 2 * CROP_PAD
    cx = (box[0] + box[2]) // 2
    cy = (box[1] + box[3]) // 2
    left, top = cx - side // 2, cy - side // 2
    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(image, (-left, -top))
    return canvas


def prepare(src):
    from PIL import Image
    image = blacken_ring(Image.open(src).convert("RGBA"))
    region = hole_region(image)
    if region is None:
        return crop_square(image, image.getchannel("A").point(lambda v: 255 if v > INK_THRESHOLD else 0).getbbox())
    return crop_square(fill_hole(image, region), region.getbbox())


def convert(src, dst, height):
    from PIL import Image
    image = prepare(src)
    image = image.convert("RGBa")
    width = max(1, round(image.width * height / image.height))
    image = image.resize((width, height), Image.LANCZOS).convert("RGBA")
    with open(dst, "wb") as out:
        out.write(MAGIC + struct.pack("<II", width, height))
        out.write(image.tobytes())
    return width, height


def main(argv):
    if len(argv) < 3:
        sys.stderr.write("usage: mklogo.py <logo.png> <osboot.logo> [--height N]\n")
        return 2
    height = DEFAULT_HEIGHT
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
