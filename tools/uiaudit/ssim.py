import sys
import numpy as np
from PIL import Image

def gray(path, box):
    im = Image.open(path).convert("L")
    if box:
        im = im.crop(box)
    return np.asarray(im, dtype=np.float64)

def box_filter(a, k):
    c = np.cumsum(np.cumsum(np.pad(a, ((1, 0), (1, 0))), axis=0), axis=1)
    s = c[k:, k:] - c[:-k, k:] - c[k:, :-k] + c[:-k, :-k]
    return s / (k * k)

def ssim(a, b, k=7):
    c1, c2 = (0.01 * 255) ** 2, (0.03 * 255) ** 2
    ma, mb = box_filter(a, k), box_filter(b, k)
    va = box_filter(a * a, k) - ma * ma
    vb = box_filter(b * b, k) - mb * mb
    cov = box_filter(a * b, k) - ma * mb
    m = ((2 * ma * mb + c1) * (2 * cov + c2)) / ((ma * ma + mb * mb + c1) * (va + vb + c2))
    return float(m.mean())

if __name__ == "__main__":
    box = tuple(int(v) for v in sys.argv[3].split(",")) if len(sys.argv) > 3 else None
    print("SSIM %.4f" % ssim(gray(sys.argv[1], box), gray(sys.argv[2], box)))
