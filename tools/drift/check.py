import re
import statistics
import sys


def latencies(log_path):
    rows = []
    for line in open(log_path, errors="replace"):
        m = re.match(r"warteneu \(\?m\)\^launcher: start /apps/explorer -> (da|NICHT DA) \(([0-9.]+) s\)", line)
        if m:
            rows.append((m.group(1) == "da", float(m.group(2))))
    return rows


def changed(a, b, box):
    from PIL import Image
    ia = Image.open(a).convert("RGB")
    ib = Image.open(b).convert("RGB")
    pa, pb = ia.load(), ib.load()
    x0, y0, x1, y1 = box
    n = 0
    for y in range(y0, min(y1, ia.size[1])):
        for x in range(x0, min(x1, ia.size[0])):
            if pa[x, y] != pb[x, y]:
                n += 1
    return n


def cmd_summary(log_path, slack_s, ratio):
    rows = latencies(log_path)
    total = len(rows)
    good = [t for ok, t in rows if ok]
    print("cycles=%d answered=%d" % (total, len(good)))
    if len(good) < 6:
        print("verdict=insufficient")
        return 1
    third = len(good) // 3
    head = statistics.median(good[:third])
    tail = statistics.median(good[-third:])
    print("first_third_median=%.2f last_third_median=%.2f max=%.2f" % (head, tail, max(good)))
    stable = len(good) == total and tail <= head * ratio + slack_s
    print("verdict=%s" % ("stable" if stable else "drift"))
    return 0 if stable else 2


def cmd_diff(out_dir, box):
    import glob
    import os
    menus = sorted(glob.glob(os.path.join(out_dir, "c*-menu.ppm")))
    if not menus:
        print("shots=0")
        return 1
    counts = []
    for m in menus:
        t = m.replace("-menu.ppm", "-typed.ppm")
        if not os.path.exists(t):
            print("missing=%s" % t)
            return 1
        counts.append(changed(m, t, box))
    print("shots=%d typed_changed=%s min=%d" % (len(counts), ",".join(map(str, counts)), min(counts)))
    return 0


if __name__ == "__main__":
    if sys.argv[1] == "summary":
        sys.exit(cmd_summary(sys.argv[2], float(sys.argv[3]), float(sys.argv[4])))
    if sys.argv[1] == "diff":
        sys.exit(cmd_diff(sys.argv[2], tuple(int(v) for v in sys.argv[3:7])))
    sys.exit(64)
