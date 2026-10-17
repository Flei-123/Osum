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
# W-L (17.10.2026): the 60 Hz slot is gone (lj_wait/lj_may_compose: a frame as soon as there is something to paint, at most every 6 ms).
# The cadence lines are printed on every F12 AND on every desktop pulse, so single lines cannot be told apart by phase. The pass/fail
# verdict for latency is tools/latency (statistical judge, counter-proof nolatfix); here the cadence is only REPORTED per case
# (frame intervals < 17.5 ms / 17.5-34 ms / >= 34 ms, summed over all lines) so a regression is visible in the log.
for case in ("paced", "nolatfix"):
    rows = cadence(case)
    tot = [0] * 8
    for r in rows:
        for i, c in enumerate(r["fach"][:8]):
            tot[i] += c
    n = max(sum(tot), 1)
    print("== %s: %d cadence lines, %d intervals: <17.5 ms %d%%, 17.5-34 ms %d%%, >=34 ms %d%%  fach=%s" % (
        case, len(rows), sum(tot), sum(tot[:4]) * 100 // n, (tot[4] + tot[5]) * 100 // n, (tot[6] + tot[7]) * 100 // n, tot))


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
