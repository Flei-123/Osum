# SPDX-License-Identifier: GPL-2.0-only
# tools/fullhd/fullhd.py -- driver + judge of the Full HD gate (r1226), called by tools/fullhd/run.sh.
# usage: fullhd.py <monitor sock> <vnc sock> <base> <serial file> <settle seconds> <steps>      (boots nothing itself)
#        fullhd.py --selftest                                                                   (judge on synthetic pictures, no VM)
# Logs in, then judges the screendump (a) right after the login when the boot fit (1920x1080) is still the live mode, (b) after every
# hint of the kernel's hint player (`vmsvga: testhint WxH rc=N now=WxH`, words vmsvgahints vmsvgafull). One line per judged picture in <base>.res:
#   <n> <w> <h> <expected w> <expected h> <q1> <q2> <q3> <q4> <bar share> <bar right third ink> <dup share> <last row share> <rough>
# q1..q4 = share of non-black pixels in the four quadrants of the area above the taskbar; bar share = non-black share of the last 56 rows;
# bar right third ink = number of pixels in the right third of the last 56 rows that differ from the bar's own base colour (tray, clock);
# rough = mean absolute vertical difference of the area above the taskbar (smooth wallpaper 1.3-1.6; a wrong stride is line garbage 57-98);
# dup share = share of taskbar pixels that equal the pixel `d` columns to the left (a stale stride shows the bar again, shifted).
import os
import re
import sys
import time

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "vmsvga"))

BAR_ROWS = 56


def judge_image(img):
    """img: h x w x 3 uint8. Returns (q1, q2, q3, q4, bar_share, right_ink, dup, last_row_share, rough)."""
    h, w, _ = img.shape
    nb = img.max(axis=2) >= 8
    top = h - BAR_ROWS
    hh, hw = top // 2, w // 2
    q = [
        float(nb[:hh, :hw].mean()),
        float(nb[:hh, hw:].mean()),
        float(nb[hh:top, :hw].mean()),
        float(nb[hh:top, hw:].mean()),
    ]
    bar = img[h - BAR_ROWS :]
    bar_share = float(nb[h - BAR_ROWS :].mean())
    last = float(nb[h - 1].mean())
    # bar base colour = the most frequent colour of the bar's left 8 columns
    flat = bar[:, :8].reshape(-1, 3)
    vals, cnt = np.unique(flat, axis=0, return_counts=True)
    base = vals[int(np.argmax(cnt))]
    r = bar[:, (2 * w) // 3 :].astype(np.int16)
    right_ink = int(np.sum(np.abs(r - base.astype(np.int16)).max(axis=2) > 24))
    b2 = img[h - 46 : h - 6].astype(np.int16)
    ink = b2.min(axis=2) < 200
    dup = 0.0
    for d in range(300, w - 100, 4):
        n = int(ink[:, d:].sum())
        if n < 200:
            continue
        eq = np.all(b2[:, d:] == b2[:, :-d], axis=2) & ink[:, d:]
        dup = max(dup, float(eq.sum()) / n)
    t16 = img[:top].astype(np.int16)
    rough = float(np.abs(t16[1:] - t16[:-1]).mean())
    return (*q, bar_share, right_ink, dup, last, rough)


# the verdict, shared by the live gate and the selftest. Thresholds: measured on the fixed kernel (see run.sh NOTE lines), with margin.
Q_MIN = 0.40  # the lower right of the (dark) wallpaper measures 0.66 non-black at 1920x1080; the bug picture is < 0.3 in 2 of 4 quadrants
BAR_MIN = 0.95
INK_MIN = 150
DUP_MAX = 0.5
ROUGH_MAX = 10.0


def verdict(res):
    q1, q2, q3, q4, bar, ink, dup, last, rough = res
    why = []
    for i, v in enumerate((q1, q2, q3, q4)):
        if v < Q_MIN:
            why.append("quadrant %d non-black share %.3f < %.2f" % (i + 1, v, Q_MIN))
    if bar < BAR_MIN:
        why.append("taskbar rows non-black share %.3f < %.2f" % (bar, BAR_MIN))
    if ink < INK_MIN:
        why.append("right third of the taskbar empty (ink %d < %d)" % (ink, INK_MIN))
    if dup >= DUP_MAX:
        why.append("taskbar repeated by a stale stride (dup %.3f)" % dup)
    if rough >= ROUGH_MAX:
        why.append("line garbage above the taskbar (vertical roughness %.1f >= %.0f: wrong stride)" % (rough, ROUGH_MAX))
    return why


def selftest():
    # 1. a full picture is green, 2. the bug picture (a small 1024x768 rectangle in a black 1920x1080 screen) is red
    w, h = 1920, 1080
    rng = np.random.RandomState(1)
    full = np.zeros((h, w, 3), np.uint8)
    gx = (np.arange(w) * 0.1).astype(np.uint8)[None, :, None]  # a smooth wallpaper gradient (a wrong stride shows as jumps)
    gy = (np.arange(h) * 0.05).astype(np.uint8)[:, None, None]
    full[:, :] = (40, 70, 110)
    full[:, :] += gx + gy
    full[h - BAR_ROWS :, :] = (240, 240, 244)
    full[h - 40 : h - 12, w - 300 : w - 20] = rng.randint(0, 200, (28, 280, 3)).astype(np.uint8)
    full[h - 40 : h - 12, 40:200] = rng.randint(0, 200, (28, 160, 3)).astype(np.uint8)
    small = np.zeros_like(full)
    small[:768, :1024] = full[:768, :1024]
    small[768 - BAR_ROWS : 768, :1024] = full[h - BAR_ROWS :, :1024]
    shifted = full.copy()
    shifted[h - BAR_ROWS :, w // 2 :] = full[h - BAR_ROWS :, : w - w // 2]
    garbage = full.copy()
    for y in range(h - BAR_ROWS):  # every row shifted by a wrong stride
        garbage[y] = np.roll(full[y], (y * 301) % w, axis=0)
    bad = 0
    for name, img, want_red in (("full", full, False), ("small-rectangle", small, True), ("bar-shifted-copy", shifted, True), ("stride-garbage", garbage, True)):
        why = verdict(judge_image(img))
        red = bool(why)
        print("  %s  selftest %s: %s" % ("OK  " if red == want_red else "FAIL", name, "red (%s)" % why[0] if red else "green"))
        bad += red != want_red
    return bad


def main():
    from vnclib import Mon, ppm_rgb  # noqa: E402

    mon_sock, vnc_sock, base, serial, settle, steps = sys.argv[1:7]
    settle = float(settle)
    steps = int(steps)

    def read_serial():
        try:
            return open(serial, errors="replace").read()
        except OSError:
            return ""

    def wait_for(pred, timeout):
        end = time.time() + timeout
        while time.time() < end:
            if pred(read_serial()):
                return True
            time.sleep(0.3)
        return False

    def shot(mon, tag):
        f = mon.dump("%s.%s.ppm" % (base, tag))
        w, h, b = ppm_rgb(f)
        img = np.frombuffer(b, dtype=np.uint8).reshape(h, w, 3)
        return w, h, judge_image(img)

    def put(out, n, w, h, ew, eh, r):
        out.write("%d %d %d %d %d %.3f %.3f %.3f %.3f %.3f %d %.3f %.3f %.2f\n" % (n, w, h, ew, eh, *r))
        out.flush()

    mon = Mon(mon_sock)
    if not wait_for(lambda t: "glogin: bereit" in t or t.count("glogin: rect id=") >= 3, 200):
        open(base + ".login", "w").write("0")
        mon.quit()
        return
    time.sleep(6)
    for c in "startkennwort":
        mon.cmd("sendkey " + c, 0.12)
    mon.cmd("sendkey ret", 0.3)
    ok = wait_for(lambda t: "glogin: angemeldet als" in t or "glogin: autostart" in t or "glogin: uid=" in t, 60)
    open(base + ".login", "w").write("1" if ok else "0")
    if not ok:
        mon.quit()
        return
    out = open(base + ".res", "w")
    # step 0: the boot fit mode, only while the hint player has not played its first hint yet (it starts 45 s after the first call)
    time.sleep(min(settle, 6.0))
    if read_serial().count("vmsvga: testhint ") == 0:
        w, h, r = shot(mon, "0")
        if read_serial().count("vmsvga: testhint ") == 0:
            # the boot size the kernel reports (`vmsvga: bootfit -> WxH rc=N`; a card with little video memory shrinks it), default 1920x1080
            bm = re.findall(r"vmsvga: bootfit +-> (\d+)x(\d+) rc=", read_serial())
            put(out, 0, w, h, int(bm[-1][0]) if bm else 1920, int(bm[-1][1]) if bm else 1080, r)
    time.sleep(max(0.0, settle - 6.0))
    last = read_serial().count("vmsvga: testhint ")
    for n in range(1, steps + 1):
        wait_for(lambda t: t.count("vmsvga: testhint ") > last, 170 if n == 1 else 70)  # the first hint comes 150 s after the hint player starts (word vmsvgafull)
        time.sleep(settle)
        t = read_serial()
        last = t.count("vmsvga: testhint ")
        m = re.findall(r"vmsvga: testhint (\d+)x(\d+) rc=(\d+) now=(\d+)x(\d+)", t)
        ew, eh = (int(m[-1][3]), int(m[-1][4])) if m else (0, 0)
        w, h, r = shot(mon, str(n))
        put(out, n, w, h, ew, eh, r)
    out.close()
    mon.quit()


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "--selftest":
        sys.exit(1 if selftest() else 0)
    main()
