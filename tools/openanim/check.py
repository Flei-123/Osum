#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import re
import sys

import numpy as np

slow, off, fast = sys.argv[1:4]
ok = bad = 0

POP_MS = 110
WIN_MS = 150
SLOW_FACTOR = 2400 / 160
CLOCK_BOX = (1000, 760, 1280, 800)
PIXEL_STEP = 60
END_EQUAL_PERCENT = 1.0
MAX_FRAME_GAP_MS = 80
MIN_FAST_FRAMES = 3


def chk(cond, msg):
    global ok, bad
    if cond:
        ok += 1
        print("  OK    " + msg)
    else:
        bad += 1
        print("  FAIL  " + msg)


def serial(out):
    with open(os.path.join(out, "serial.txt"), "rb") as f:
        return f.read().decode("latin1").split("\n")


def runs(lines):
    result = []
    cur = {}
    pattern = re.compile(r"wm: animf id=(\d+) kind=(\d+) layer=(\d+) p=(\d+) t=(\d+) ms=(\d+)")
    for ln in lines:
        m = pattern.search(ln)
        if not m:
            continue
        wid, kind, layer, p, t, ms = (int(v) for v in m.groups())
        key = (wid, kind)
        if key in cur and p < cur[key]["p"][-1]:
            result.append(cur.pop(key))
        if key not in cur:
            cur[key] = {"id": wid, "kind": kind, "layer": layer, "ms": ms, "p": [], "t": []}
        cur[key]["p"].append(p)
        cur[key]["t"].append(t)
    result.extend(cur.values())
    return result


def image(out, name):
    path = os.path.join(out, name + ".ppm")
    if not os.path.exists(path):
        return None
    with open(path, "rb") as f:
        data = f.read()
    m = re.match(rb"P6\s+(\d+)\s+(\d+)\s+(\d+)\s", data)
    if not m:
        return None
    w, h = int(m[1]), int(m[2])
    return np.frombuffer(data[m.end():], dtype=np.uint8)[: w * h * 3].reshape(h, w, 3).astype(np.int16)


def changed(a, b):
    mask = np.abs(a - b).sum(axis=2) > PIXEL_STEP
    x0, y0, x1, y1 = CLOCK_BOX
    mask[y0:y1, x0:x1] = False
    return mask


def bbox(mask):
    ys, xs = np.nonzero(mask)
    if len(xs) == 0:
        return None
    return int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1


def series_levels(out, base, name, box, count):
    levels = []
    x0, y0, x1, y1 = box
    for i in range(count):
        frame = image(out, "%s-%03d" % (name, i))
        if frame is None:
            levels.append(-1)
            continue
        levels.append(int(changed(frame, base)[y0:y1, x0:x1].sum()))
    return levels


def select(runs_list, which):
    pops = [r for r in runs_list if r["kind"] == 4 and r["layer"] == 4]
    if which == "window":
        return [r for r in runs_list if r["kind"] == 1 and r["layer"] == 1]
    if not pops:
        return []
    start_id = pops[0]["id"]
    if which == "start":
        return [r for r in pops if r["id"] == start_id]
    return [r for r in pops if r["id"] != start_id]


def check_trace(label, runs_list, which, base_ms):
    sel = select(runs_list, which)
    chk(len(sel) >= 1, "%s: animation runs found %d" % (label, len(sel)))
    if not sel:
        return
    r = sel[0]
    chk(len(r["p"]) >= 8, "%s: %d frames in the slow run" % (label, len(r["p"])))
    chk(all(b >= a for a, b in zip(r["p"], r["p"][1:])), "%s: progress never goes back" % label)
    chk(r["p"][-1] == 1000, "%s: ends at 1000" % label)
    want = int(base_ms * SLOW_FACTOR)
    chk(abs(r["ms"] - want) <= 2, "%s: duration %d ms follows the theme (want %d)" % (label, r["ms"], want))


def check_series(label, base, end, box, levels):
    final = int(changed(end, base)[box[1]:box[3], box[0]:box[2]].sum())
    chk(final > 200, "%s: end picture differs from the empty desktop (%d px)" % (label, final))
    mid = [v for v in levels if final * 0.03 < v < final * 0.97]
    chk(len(mid) >= 2, "%s: %d intermediate pictures between 3%% and 97%% of the end state" % (label, len(mid)))
    ordered = [v for v in levels if v >= 0]
    rising = sum(1 for a, b in zip(ordered, ordered[1:]) if b >= a - final * 0.05)
    chk(rising >= len(ordered) - 2, "%s: the changed area grows over the series" % label)
    return final


def check_end(label, a, b, box):
    if a is None or b is None:
        chk(False, "%s: end pictures exist" % label)
        return
    x0, y0, x1, y1 = box
    area = (x1 - x0) * (y1 - y0)
    diff = int(changed(a, b)[y0:y1, x0:x1].sum())
    chk(diff * 100.0 / area <= END_EQUAL_PERCENT,
        "%s: end picture equals the one without animation (%d of %d px differ)" % (label, diff, area))


def main():
    s_lines = serial(slow)
    o_lines = serial(off)
    f_lines = serial(fast)
    s_runs = runs(s_lines)
    o_runs = runs(o_lines)
    f_runs = runs(f_lines)

    print("== slow run: trace")
    check_trace("start menu", s_runs, "start", POP_MS)
    check_trace("context menu", s_runs, "ctx", POP_MS)
    check_trace("program window", s_runs, "window", WIN_MS)

    print("== control: animations off")
    chk(len(o_runs) == 0, "no animation frames with the word noanim (%d runs)" % len(o_runs))

    print("== slow run: picture series")
    desk = image(slow, "a0-desk")
    desk2 = image(slow, "a2-desk2")
    start_end = image(slow, "a1-start-end")
    ctx_end = image(slow, "a2-ctx-end")
    have = all(v is not None for v in (desk, desk2, start_end, ctx_end))
    chk(have, "pictures exist")
    if have:
        box_s = bbox(changed(start_end, desk))
        box_c = bbox(changed(ctx_end, desk2))
        chk(box_s is not None and box_c is not None, "menu areas found")
        if box_s and box_c:
            check_series("start menu", desk, start_end, box_s, series_levels(slow, desk, "st", box_s, 16))
            check_series("context menu", desk2, ctx_end, box_c, series_levels(slow, desk2, "cx", box_c, 16))
            print("== control: end pictures")
            check_end("start menu", start_end, image(off, "a1-start-end"), box_s)
            check_end("context menu", ctx_end, image(off, "a2-ctx-end"), box_c)
            off_desk = image(off, "a0-desk")
            off_levels = series_levels(off, off_desk, "st", box_s, 16)
            off_final = int(changed(image(off, "a1-start-end"), off_desk)[box_s[1]:box_s[3], box_s[0]:box_s[2]].sum())
            off_mid = [v for v in off_levels if off_final * 0.03 < v < off_final * 0.97]
            chk(len(off_mid) <= 2, "control: start menu appears at once, %d intermediate pictures" % len(off_mid))

    win_slow = image(slow, "a3-win-end")
    win_off = image(off, "a3-win-end")
    if win_slow is not None and win_off is not None:
        base = image(slow, "a1-start-closed")
        box_w = bbox(changed(win_slow, base)) if base is not None else None
        chk(box_w is not None, "program window area found")
        if box_w:
            levels = series_levels(slow, base, "wn", box_w, 16)
            check_series("program window", base, win_slow, box_w, levels)
            check_end("program window", win_slow, win_off, box_w)
    else:
        chk(False, "window end pictures exist")

    print("== fast run: shipping speed")
    for label, which, base_ms in (("start menu", "start", POP_MS), ("context menu", "ctx", POP_MS), ("program window", "window", WIN_MS)):
        sel = select(f_runs, which)
        chk(len(sel) >= 1, "%s: animation runs in the fast run" % label)
        if not sel:
            continue
        r = sel[0]
        gaps = [(q - p) * r["ms"] / 1000.0 for p, q in zip(r["p"], r["p"][1:])]
        first = r["p"][0] * r["ms"] / 1000.0
        worst = max(gaps + [first])
        chk(r["ms"] == base_ms, "%s: planned %d ms" % (label, r["ms"]))
        chk(len(r["p"]) >= MIN_FAST_FRAMES, "%s: %d frames in the fast run" % (label, len(r["p"])))
        chk(worst <= MAX_FRAME_GAP_MS, "%s: longest stall %.0f ms (first frame after %.0f ms)" % (label, worst, first))
        print("  INFO  %s: frames=%d first=%.0f ms max_gap=%.0f ms" % (label, len(r["p"]), first, max(gaps) if gaps else 0))

    print("== result")
    print("  %d ok, %d failed" % (ok, bad))


main()
