#!/usr/bin/env python3
"""tools/fps/judge.py -- W-E: judge the frame cadence cases and the FPS overlay. usage: judge.py <outdir>"""
import os, re, sys

PH = {1: "boot rest", 2: "idle 6 s", 3: "pointer sweep", 4: "window drag", 5: "start menu"}
fail = 0


def chk(ok, msg):
    global fail
    print(("OK   " if ok else "FAIL ") + msg)
    if not ok:
        fail += 1


def cadence(case):
    p = os.path.join(sys.argv[1], case, "serial.txt")
    rows = []
    if not os.path.exists(p):
        return rows
    for line in open(p, "rb").read().decode("latin1").splitlines():
        m = re.match(r"wm: cadence n=(\d+) mittel=(\d+) max=(\d+) ueber17=(\d+) idle=(\d+) fach=([\d ]+) total=(\d+)", line)
        if m:
            f = [int(x) for x in m.group(6).split()]
            rows.append(dict(n=int(m.group(1)), mean=int(m.group(2)), max=int(m.group(3)), over=int(m.group(4)),
                             idle=int(m.group(5)), fach=f, total=int(m.group(7))))
    return rows


def p95_bucket(f):
    n = sum(f)
    if not n:
        return 0
    acc = 0
    for i, c in enumerate(f):
        acc += c
        if acc * 100 >= n * 95:
            return i
    return 7


EDGE = ["<8", "<12", "<15.5", "<17.5", "<21", "<34", "<51", ">=51"]
share = {}
for case in ("paced", "nopace"):
    rows = cadence(case)
    print("== %s: %d cadence lines" % (case, len(rows)))
    for i, r in enumerate(rows[:5], 1):
        n = max(r["n"], 1)
        fps = 1e6 / r["mean"] if r["mean"] else 0
        good = (r["fach"][2] + r["fach"][3]) * 100 // n
        print("  phase %d %-14s n=%-4d mean=%6d us (%.1f fps) max=%6d p95=%s ms in15.5-17.5=%d%%  fach=%s" % (
            i, PH.get(i, "?"), r["n"], r["mean"], fps, r["max"], EDGE[p95_bucket(r["fach"])], good, r["fach"]))
        if i in (3, 4):
            share[(case, i)] = (good, r["mean"], r["n"])
for ph in (3, 4):
    if ("paced", ph) in share:
        g, mean, n = share[("paced", ph)]
        chk(n >= 30 and 15000 <= mean <= 18500 and g >= 70,
            "paced %s: mean %d us within 15-18.5 ms and >= 70%% of intervals in 15.5-17.5 ms (is %d%%, n=%d)" % (PH[ph], mean, g, n))
    else:
        chk(False, "paced phase %d missing" % ph)
    if ("nopace", ph) in share:
        g, mean, n = share[("nopace", ph)]
        chk(g < 50, "counter-proof nopace %s: NOT on the 60 Hz slot (only %d%% in 15.5-17.5 ms, mean %d us)" % (PH[ph], g, mean))


def green(case):
    p = os.path.join(sys.argv[1], case, "fps-overlay.ppm")
    if not os.path.exists(p):
        return None
    d = open(p, "rb").read()
    m = re.match(rb"P6\s+(\d+)\s+(\d+)\s+(\d+)\s", d)
    if not m:
        return None
    w, h = int(m.group(1)), int(m.group(2))
    off = m.end()
    cnt = 0
    for y in range(0, 16):
        for x in range(0, 280):
            i = off + (y * w + x) * 3
            if d[i] < 40 and d[i + 1] > 215 and d[i + 2] < 40:
                cnt += 1
    return cnt


on, offv = green("fpson"), green("fpsoff")
print("== overlay: green pixels top-left 280x16: on=%s off=%s" % (on, offv))
chk(on is not None and on >= 100, "fps on: the overlay text is at the top-left (%s green pixels)" % on)
chk(offv is not None and offv == 0, "fps off (counter-proof): nothing drawn top-left (%s green pixels)" % offv)
print("RESULT %s" % ("ALL OK" if not fail else "%d FAIL" % fail))
sys.exit(1 if fail else 0)
