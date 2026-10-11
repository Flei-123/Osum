#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/caret/check.py <run dir> <prefix> <x0> <y0> <x1> <y1> -- per frame of a burst series: is a caret in the text field?

A caret is a thin dark VERTICAL bar: inside the box (x0..x1, y0..y1) a column with at least 60 % dark pixels (luminance < 110) that is at most
3 columns wide. A password dot is round and about 6 px tall, a letter never fills a column, so neither counts. Frame times come from the
file times of the dumps (the monitor writes them back to back, one every ~16 ms).
Prints `FRAMES n`, `STATE <01-string>`, `TRANSITIONS k`, `RUNS <ms of each complete on/off run>`, `FIRSTON <index of the first caret frame or -1>`.
"""
import glob, os, re, sys
import numpy as np

def read_ppm(path):
    d = open(path, "rb").read()
    m = re.match(rb"P6\s+(\d+)\s+(\d+)\s+255\s", d)
    w, h = int(m.group(1)), int(m.group(2))
    return np.frombuffer(d[m.end():], dtype=np.uint8).reshape(h, w, 3).astype(int)

def caret_in(img, x0, y0, x1, y1):
    box = img[y0:y1, x0:x1]
    lum = (box[:, :, 0] * 3 + box[:, :, 1] * 6 + box[:, :, 2]) // 10
    dark = lum < 110
    col = dark.sum(axis=0) >= max(8, int(0.6 * (y1 - y0)))
    # at most 3 columns wide in a row
    run = 0
    for c in col:
        run = run + 1 if c else 0
        if run > 3:
            return False
    return bool(col.any())

def main():
    run, pre = sys.argv[1], sys.argv[2]
    x0, y0, x1, y1 = [int(v) for v in sys.argv[3:7]]
    files = sorted(glob.glob(os.path.join(run, pre + "-[0-9][0-9][0-9].ppm")))
    if not files:
        print("FRAMES 0")
        return 2
    st = [1 if caret_in(read_ppm(f), x0, y0, x1, y1) else 0 for f in files]
    tm = [os.stat(f).st_mtime for f in files]
    print("FRAMES %d" % len(files))
    print("STATE " + "".join(str(v) for v in st))
    tr = [i for i in range(1, len(st)) if st[i] != st[i - 1]]
    print("TRANSITIONS %d" % len(tr))
    runs = [int(round((tm[tr[k + 1]] - tm[tr[k]]) * 1000)) for k in range(len(tr) - 1)]
    print("RUNS " + " ".join(str(r) for r in runs))
    print("FIRSTON %d" % (st.index(1) if 1 in st else -1))
    print("ONFRAMES %d" % sum(st))
    print("SPAN_MS %d" % int(round((tm[-1] - tm[0]) * 1000)))
    return 0

sys.exit(main())
