import collections, glob, sys
from PIL import Image

LEFT_MIN, LEFT_MAX = 44, 60
MIN_RUN = 6
TOL = 10


def load(path):
    im = Image.open(path).convert("RGB")
    return im.size, im.load()


def find_accent(frames):
    hist = collections.Counter()
    for _, px in frames:
        for y in range(40, 780, 2):
            for x in range(40, 770, 2):
                r, g, b = px[x, y]
                if b > 200 and b - r > 150 and r < 80:
                    hist[(r, g, b)] += 1
    return hist.most_common(1)[0][0] if hist else None


def near(c, a):
    return abs(c[0] - a[0]) <= TOL and abs(c[1] - a[1]) <= TOL and abs(c[2] - a[2]) <= TOL


def fill_width(frame, accent):
    (w, h), px = frame
    best = 0
    for y in range(120, 700):
        x = LEFT_MIN
        while x <= LEFT_MAX and not near(px[x, y], accent):
            x += 1
        if x > LEFT_MAX:
            continue
        run = 0
        while x + run < w and near(px[x + run, y], accent):
            run += 1
        if run >= MIN_RUN and run > best:
            best = run
    return best


def monotonic(seq):
    return all(b >= a for a, b in zip(seq, seq[1:]))


def main():
    files = sorted(glob.glob(sys.argv[1] + "/f*.ppm"))
    frames = [load(f) for f in files]
    if len(frames) < 5:
        print("FAIL enough frames captured (%d)" % len(frames))
        return
    accent = find_accent(frames)
    if accent is None:
        print("FAIL accent colour found in the frames")
        return
    widths = [fill_width(f, accent) for f in frames]
    print("accent=%s widths=%s" % (accent, widths))
    seen = [w for w in widths if w > 0]
    first = next((i for i, w in enumerate(widths) if w > 0), None)
    last = max((i for i, w in enumerate(widths) if w > 0), default=None)
    print("OK the first bar frame is narrow (%d px)" % seen[0] if seen and seen[0] * 4 <= max(seen) else "FAIL the first bar frame is narrow")
    print("OK bar visible in %d frames" % len(seen) if len(seen) >= 3 else "FAIL bar visible in at least 3 frames (%d)" % len(seen))
    distinct = sorted(set(seen))
    print("OK bar fill takes %d distinct widths" % len(distinct) if len(distinct) >= 3 else "FAIL bar fill takes at least 3 distinct widths (%d)" % len(distinct))
    run = widths[first:last + 1] if first is not None else []
    print("OK bar fill never shrinks while the shrink runs" if run and monotonic(run) else "FAIL bar fill never shrinks while the shrink runs")
    print("OK bar grows from %d to %d px" % (min(seen), max(seen)) if len(seen) >= 2 and max(seen) >= 4 * min(seen) else "FAIL bar grows at least fourfold")
    print("OK bar ends nearly full width (%d px)" % max(seen) if seen and max(seen) >= 600 else "FAIL bar ends nearly full width (max %d)" % (max(seen) if seen else 0))
    rev = list(reversed(run))
    print("OK counter-check: the reversed series is detected as shrinking" if len(set(run)) > 1 and not monotonic(rev) else "FAIL counter-check: the reversed series must fail the monotonic test")
    print("OK frames after the shrink carry no bar" if last is not None and last < len(widths) - 1 and all(w == 0 for w in widths[last + 1:]) else "FAIL frames after the shrink carry no bar")


main()
