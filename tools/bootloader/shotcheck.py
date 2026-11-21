#!/usr/bin/env python3
import struct
import sys

REF_HEIGHT = 1080
LOGO_REF_SIZE = 176
GAP_REF = 48
SPIN_BOX_REF = 40
SPIN_CHECK_REF = 21
LIT_MIN = 40
CHANGED_MIN = 20
EDGE_LOW = 8
EDGE_HIGH = 247
MATCH_TOLERANCE = 16
SHARP_MAX_DIFF = 2.5
BLOCKY_MIN_FACTOR = 2.0
LIVE_RATIO = 0.75


def read_ppm(path):
    from PIL import Image
    return Image.open(path).convert("RGB")


def read_logo(path):
    from PIL import Image
    data = open(path, "rb").read()
    width, height = struct.unpack("<II", data[4:12])
    return Image.frombytes("RGBA", (width, height), data[12:12 + width * height * 4])


def unit(sh, n):
    return max(1, n * sh // REF_HEIGHT)


def layout(sw, sh, lw, lh):
    dh = unit(sh, LOGO_REF_SIZE)
    dw = max(1, lw * dh // lh)
    total = unit(sh, SPIN_BOX_REF) + dh + unit(sh, GAP_REF)
    top = (sh - total) // 2 if total < sh else 0
    left = (sw - dw) // 2
    cy = top + unit(sh, SPIN_BOX_REF) // 2 + dh + unit(sh, GAP_REF)
    return left, top, dw, dh, cy


def reference(logo, dw, dh):
    from PIL import Image
    small = logo.convert("RGBa").resize((dw, dh), Image.BOX).convert("RGBA")
    black = Image.new("RGBA", (dw, dh), (0, 0, 0, 255))
    black.alpha_composite(small)
    return black.convert("RGB")


def blocky(ref, factor):
    from PIL import Image
    half = ref.resize((max(1, ref.width // factor), max(1, ref.height // factor)), Image.BOX)
    return half.resize(ref.size, Image.NEAREST)


def edge_diff(a, b, ref):
    total = count = 0
    pa, pb, pr = a.load(), b.load(), ref.load()
    for y in range(ref.height):
        for x in range(ref.width):
            luma = sum(pr[x, y]) // 3
            if EDGE_LOW <= luma <= EDGE_HIGH or any(
                    sum(pr[nx, ny]) // 3 != luma
                    for nx, ny in ((x + 1, y), (x, y + 1))
                    if nx < ref.width and ny < ref.height):
                total += sum(abs(pa[x, y][i] - pb[x, y][i]) for i in range(3)) / 3
                count += 1
    return total / max(1, count)


def logo_crop(screen, logo):
    left, top, dw, dh, _ = layout(screen.width, screen.height, logo.width, logo.height)
    return screen.crop((left, top, left + dw, top + dh)), reference(logo, dw, dh)


def logo_match(ppm, logo_path):
    logo = read_logo(logo_path)
    shot, ref = logo_crop(read_ppm(ppm), logo)
    good = total = 0
    ps, pr = shot.load(), ref.load()
    for y in range(0, ref.height, 2):
        for x in range(0, ref.width, 2):
            if sum(pr[x, y]) < 90:
                continue
            total += 1
            if all(abs(ps[x, y][i] - pr[x, y][i]) <= MATCH_TOLERANCE for i in range(3)):
                good += 1
    return good, total


def sharp(ppm, logo_path):
    logo = read_logo(logo_path)
    shot, ref = logo_crop(read_ppm(ppm), logo)
    ours = edge_diff(shot, ref, ref)
    worse = edge_diff(blocky(ref, 2), ref, ref)
    print("edge diff %.2f blocky counter-proof %.2f size %dx%d" % (ours, worse, ref.width, ref.height))
    return ours <= SHARP_MAX_DIFF and worse >= BLOCKY_MIN_FACTOR * max(ours, 1.0)


def spinner_pixels(ppm, logo_path):
    logo = read_logo(logo_path)
    screen = read_ppm(ppm)
    _, _, _, _, cy = layout(screen.width, screen.height, logo.width, logo.height)
    half = unit(screen.height, SPIN_CHECK_REF)
    cx = screen.width // 2
    return screen.crop((cx - half, cy - half, cx + half, cy + half)).convert("L").tobytes()


def changed_pixels(a, b):
    return sum(1 for p, q in zip(a, b) if p != q)


def main(argv):
    mode, logo = argv[1], argv[3]
    if mode == "logo":
        good, total = logo_match(argv[2], logo)
        print("logo match %d/%d" % (good, total))
        return 0 if total > 100 and good * 100 >= total * 97 else 1
    if mode == "nologo":
        good, total = logo_match(argv[2], logo)
        print("logo match %d/%d" % (good, total))
        return 0 if total > 100 and good * 100 < total * 50 else 1
    if mode == "sharp":
        return 0 if sharp(argv[2], logo) else 1
    if mode == "spinner":
        a = spinner_pixels(argv[2], logo)
        b = spinner_pixels(argv[4], logo)
        lit = sum(1 for p in a if p)
        changed = changed_pixels(a, b)
        print("spinner lit %d changed %d" % (lit, changed))
        return 0 if lit >= LIT_MIN and changed >= CHANGED_MIN else 1
    if mode == "live":
        shots = [spinner_pixels(p, logo) for p in argv[2].split(",")]
        pairs = len(shots) - 1
        moved = sum(1 for i in range(pairs) if changed_pixels(shots[i], shots[i + 1]) >= CHANGED_MIN)
        print("spinner moved in %d of %d intervals" % (moved, pairs))
        return 0 if pairs >= 2 and moved >= pairs * LIVE_RATIO else 1
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
