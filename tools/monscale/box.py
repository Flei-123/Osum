import sys
from PIL import Image

def bbox(path):
    img = Image.open(path).convert("RGB")
    xs = []
    ys = []
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            if px[x, y] == (255, 0, 255):
                xs.append(x)
                ys.append(y)
    if not xs:
        return 0, 0
    return max(xs) - min(xs) + 1, max(ys) - min(ys) + 1

w, h = bbox(sys.argv[1])
print(w, h)
