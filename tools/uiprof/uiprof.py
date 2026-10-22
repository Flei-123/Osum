#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/uiprof/uiprof.py -- MON-4: one library for pixel-diff series and the flicker detector (lockflicker, menuflick, settingsflick, framebudget).

Library:
  read_ppm(path) -> (w, h, ndarray h*w*3 uint8)
  diff_mask(a, b, thr=8, ignore=()) -> bool mask of pixels whose largest channel difference is above thr (ignore = boxes x0,y0,x1,y1)
  series_vs_base(base, frames, ignore, maxpx, thr) -> list of (name, differing pixel count, bbox or None)
  flicker_events(frames, thr, ignore, minpx, window) -> list of (index, pixels, bbox): a pixel flickers when it leaves its value at frame k
      and is back at that value within `window` frames (A-B-A). A change that stays (A-B-B) is a normal update, not flicker.
  write_strip(frames, events, path) -> PNG strip of the frames (downscaled), pixels changed against the previous frame painted red

CLI (exit 0 = clean, 1 = difference/flicker found, 2 = no frames):
  uiprof.py base <run dir> <base> <prefix> <px> <py> [max_px]     every <prefix>-NNN.ppm against <base>.ppm, 48 px box around the pointer ignored
  uiprof.py flicker <dir> <prefix> [--minpx N] [--window N] [--strip out.png] [--ignore x0,y0,x1,y1]
"""
import glob
import os
import re
import struct
import sys
import zlib

import numpy as np


def read_ppm(path):
    d = open(path, "rb").read()
    m = re.match(rb"P6\s+(\d+)\s+(\d+)\s+255\s", d)
    w, h = int(m.group(1)), int(m.group(2))
    return w, h, np.frombuffer(d[m.end():m.end() + w * h * 3], dtype=np.uint8).reshape(h, w, 3)


def diff_mask(a, b, thr=8, ignore=()):
    m = np.abs(a.astype(np.int16) - b.astype(np.int16)).max(axis=2) > thr
    for x0, y0, x1, y1 in ignore:
        m[max(0, y0):y1, max(0, x0):x1] = False
    return m


def bbox(m):
    ys, xs = np.nonzero(m)
    if len(xs) == 0:
        return None
    return int(xs.min()), int(xs.max()), int(ys.min()), int(ys.max())


def pointer_box(px, py, r=48):
    return (px - r, py - r, px + r, py + r)


def series_vs_base(base, frames, ignore=(), maxpx=0, thr=8):
    out = []
    for name, f in frames:
        if f.shape != base.shape:
            out.append((name, -1, None))
            continue
        m = diff_mask(f, base, thr, ignore)
        n = int(m.sum())
        out.append((name, n if n > maxpx else 0, bbox(m) if n > maxpx else None))
    return out


def flicker_events(frames, thr=8, ignore=(), minpx=0, window=2):
    events = []
    n = len(frames)
    for k in range(1, n - 1):
        left = diff_mask(frames[k], frames[k - 1], thr, ignore)
        if not left.any():
            continue
        back = np.zeros_like(left)
        for j in range(1, window + 1):
            if k + j >= n:
                break
            back |= ~diff_mask(frames[k + j], frames[k - 1], thr, ignore)
        flick = left & back
        c = int(flick.sum())
        if c > minpx:
            events.append((k, c, bbox(flick)))
    return events


def _png(rgb):
    h, w, _ = rgb.shape
    raw = b"".join(b"\x00" + rgb[y].tobytes() for y in range(h))

    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))


def write_strip(frames, events, path, cell_w=320, max_cells=12):
    if not frames:
        return
    h0, w0, _ = frames[0].shape
    step = max(1, w0 // cell_w)
    flagged = {k for k, _, _ in events}
    pick = sorted(flagged | set(range(min(len(frames), max_cells))))[:max_cells]
    cells = []
    for k in pick:
        img = frames[k][::step, ::step].copy()
        if k > 0 and frames[k - 1].shape == frames[k].shape:
            m = diff_mask(frames[k], frames[k - 1])[::step, ::step]
            img[m] = (255, 0, 0)
        if k in flagged:
            img[:3, :] = (255, 0, 0)
            img[-3:, :] = (255, 0, 0)
        cells.append(img)
    gap = np.full((cells[0].shape[0], 4, 3), 255, dtype=np.uint8)
    row = cells[0]
    for c in cells[1:]:
        row = np.concatenate([row, gap, c], axis=1)
    open(path, "wb").write(_png(row))


def load_frames(directory, prefix):
    files = sorted(glob.glob(os.path.join(directory, prefix + "-[0-9][0-9][0-9].ppm")))
    return [(os.path.basename(f), read_ppm(f)[2]) for f in files]


def cmd_base(argv):
    run, base, pre, px, py = argv[0], argv[1], argv[2], int(argv[3]), int(argv[4])
    maxpx = int(argv[5]) if len(argv) > 5 else 0
    frames = load_frames(run, pre)
    if not frames:
        print("SERIES frames=0")
        return 2
    b = read_ppm(os.path.join(run, base + ".ppm"))[2]
    differing, mx = 0, 0
    for name, n, bb in series_vs_base(b, frames, [pointer_box(px, py)], maxpx):
        if n == -1:
            print("%s size differs" % name)
            differing += 1
        elif n > 0:
            print("%s differs: %d px, box x %d..%d y %d..%d" % (name, n, bb[0], bb[1], bb[2], bb[3]))
            differing += 1
            mx = max(mx, n)
    print("SERIES frames=%d differing=%d max=%d" % (len(frames), differing, mx))
    return 1 if differing else 0


def cmd_flicker(argv):
    directory, pre = argv[0], argv[1]
    opts = {"--minpx": "0", "--window": "2", "--strip": "", "--ignore": ""}
    i = 2
    while i + 1 < len(argv):
        opts[argv[i]] = argv[i + 1]
        i += 2
    frames = load_frames(directory, pre)
    if not frames:
        print("FLICKER frames=0")
        return 2
    ign = [tuple(int(v) for v in opts["--ignore"].split(","))] if opts["--ignore"] else []
    arrs = [f for _, f in frames]
    ev = flicker_events(arrs, 8, ign, int(opts["--minpx"]), int(opts["--window"]))
    for k, c, bb in ev:
        print("%s flickers: %d px, box x %d..%d y %d..%d" % (frames[k][0], c, bb[0], bb[1], bb[2], bb[3]))
    if opts["--strip"]:
        write_strip(arrs, ev, opts["--strip"])
    print("FLICKER frames=%d events=%d max=%d" % (len(frames), len(ev), max([c for _, c, _ in ev] or [0])))
    return 1 if ev else 0


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ("base", "flicker"):
        print(__doc__)
        return 2
    return (cmd_base if sys.argv[1] == "base" else cmd_flicker)(sys.argv[2:])


if __name__ == "__main__":
    sys.exit(main())
