import re
import sys
from PIL import Image

PIXEL_BACKGROUND = (500, 150)
PIXEL_FIELD = (500, 131)
PIXEL_BUTTON_CORNER = (84, 123)

def serial_rows(path):
    text = open(path, "rb").read().decode("latin-1")
    found = re.findall(r"explorer: navrows ([a-z]+)", text)
    return found[0] if found else ""

def main():
    out = sys.argv[1]
    rows = serial_rows(out + "/serial.txt")
    img = Image.open(out + "/01-explorer.ppm").convert("RGB")
    background = img.getpixel(PIXEL_BACKGROUND)
    checks = [
        ("navigation rows are only headings and places", rows != "" and set(rows) <= {"h", "p"}),
        ("first navigation row is a place, not a heading", rows[:1] == "p"),
        ("back button has no box at rest", img.getpixel(PIXEL_BUTTON_CORNER) == background),
        ("address bar is a filled field", img.getpixel(PIXEL_FIELD) != background),
    ]
    failed = 0
    for name, ok in checks:
        print("  %s  %s" % ("OK  " if ok else "FAIL", name))
        failed += 0 if ok else 1
    sys.exit(1 if failed else 0)

main()
