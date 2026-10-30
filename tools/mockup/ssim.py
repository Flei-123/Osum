#!/usr/bin/env python3
import json
import sys

import numpy as np
from PIL import Image


def gray(img):
    a = np.asarray(img.convert("RGB"), dtype=np.float64)
    return 0.299 * a[..., 0] + 0.587 * a[..., 1] + 0.114 * a[..., 2]


def gauss(size=11, sigma=1.5):
    ax = np.arange(size) - size // 2
    k = np.exp(-(ax ** 2) / (2 * sigma ** 2))
    return k / k.sum()


def filt(img, k):
    r = len(k)
    h, w = img.shape
    tmp = np.zeros((h, w - r + 1))
    for i in range(r):
        tmp += k[i] * img[:, i:i + w - r + 1]
    out = np.zeros((h - r + 1, w - r + 1))
    for i in range(r):
        out += k[i] * tmp[i:i + h - r + 1, :]
    return out


def ssim(a, b):
    k = gauss()
    c1, c2 = (0.01 * 255) ** 2, (0.03 * 255) ** 2
    ma, mb = filt(a, k), filt(b, k)
    saa = filt(a * a, k) - ma * ma
    sbb = filt(b * b, k) - mb * mb
    sab = filt(a * b, k) - ma * mb
    m = ((2 * ma * mb + c1) * (2 * sab + c2)) / ((ma * ma + mb * mb + c1) * (saa + sbb + c2))
    return float(m.mean())


def locate(shot, ref):
    s, r = gray(shot), gray(ref)
    f = 4
    ss, rs = s[::f, ::f], r[::f, ::f]
    best = (1e18, 0, 0)
    for y in range(0, ss.shape[0] - rs.shape[0] + 1):
        for x in range(0, ss.shape[1] - rs.shape[1] + 1):
            d = np.abs(ss[y:y + rs.shape[0], x:x + rs.shape[1]] - rs).mean()
            if d < best[0]:
                best = (d, y * f, x * f)
    _, y0, x0 = best
    best = (1e18, y0, x0)
    for y in range(max(0, y0 - f), min(s.shape[0] - r.shape[0], y0 + f) + 1):
        for x in range(max(0, x0 - f), min(s.shape[1] - r.shape[1], x0 + f) + 1):
            d = np.abs(s[y:y + r.shape[0], x:x + r.shape[1]] - r).mean()
            if d < best[0]:
                best = (d, y, x)
    return best[2], best[1]


def main():
    if len(sys.argv) < 3:
        raise SystemExit("usage: ssim.py MOCKUP.png SHOT.png [x,y] [crop_out.png]")
    ref = Image.open(sys.argv[1]).convert("RGB")
    shot = Image.open(sys.argv[2]).convert("RGB")
    if len(sys.argv) > 3 and sys.argv[3] != "auto":
        x, y = (int(v) for v in sys.argv[3].split(","))
    else:
        x, y = locate(shot, ref)
    crop = shot.crop((x, y, x + ref.width, y + ref.height))
    if len(sys.argv) > 4:
        crop.save(sys.argv[4])
    a, b = gray(ref), gray(crop)
    mad = float(np.abs(np.asarray(ref, dtype=np.float64) - np.asarray(crop, dtype=np.float64)).mean())
    print(json.dumps({"ssim": round(ssim(a, b), 4), "mad": round(mad, 2), "x": x, "y": y, "w": ref.width, "h": ref.height}))


if __name__ == "__main__":
    main()
