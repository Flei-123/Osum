import sys

from PIL import Image

BAR_ROWS_DIVISOR = 10
DARK_LEVEL = 90


def main(path):
    image = Image.open(path).convert("RGB")
    width, height = image.size
    bar = image.crop((width // 4, height - height // BAR_ROWS_DIVISOR, 3 * width // 4, height))
    ink = sum(1 for pixel in bar.getdata() if max(pixel) < DARK_LEVEL)
    print(width, height, ink)


main(sys.argv[1])
