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


# r1039 (17.10.2026): hard thresholds. The `wm: cadence` lines do not describe the active phases (they are printed on every desktop pulse and
# every F12; their intervals are dominated by idle repaints), so the verdict uses the slices of tools/latency: every F12 and every pulse prints
# `wm: bild` (frame times) + `wm: lat` (poll gaps, frames driven by the pointer). A slice with >= 3 pointer-driven frames is an ACTIVE slice;
# the first two slices (boot rest, idle) are not judged. The drehbuch tools/fps/fps.txt now runs through tools/design/audit.sh (PS/2 mouse
# from the QEMU monitor), so the pointer sweep / window drag / start menu phases really get fed.
LIM_GAP = 2           # poll gaps > 33 ms per active slice (the serial pulse itself is one)
MIN_POLLS = 2000      # median polls per active slice of the shipping loop (the old 10-20 ms tick loop makes < 1000)
MIN_FRAMES = 12       # median painted frames per active slice (a sweep must be seen, not skipped)


def slices(case):
    p = os.path.join(sys.argv[1], case, "serial.txt")
    out = []
    if not os.path.exists(p):
        return out
    last = None
    for line in open(p, "rb").read().decode("latin1").splitlines():
        m = re.search(r"wm: bild n=(\d+) mittel=(\d+) max=(\d+) ueber16=(\d+) fach=([\d ]+)", line)
        if m:
            last = (int(m.group(1)), int(m.group(3)), [int(x) for x in m.group(5).split()])
            continue
        m = re.search(r"wm: lat gapn=(\d+) gapmean=(\d+) gapwait=(\d+) gapmax=(\d+) gap8=(\d+) gap16=(\d+) gap33=(\d+) latn=(\d+)", line)
        if m and last is not None:
            out.append(dict(frames=last[0], fmax=last[1], f32=sum(last[2][6:8]), polls=int(m.group(1)), gap33=int(m.group(7)),
                            latn=int(m.group(8))))
            last = None
    return out[2:]


def active(case):
    return [r for r in slices(case) if r["latn"] >= 3]


def median(v):
    v = sorted(v)
    return v[len(v) // 2] if v else 0


for case in ("paced", "nolatfix"):
    act = active(case)
    print("== %s: %d active slices, median polls %d, median frames %d, slices with > %d gaps > 33 ms: %d, frames >= 32 ms: %d of %d" % (
        case, len(act), median([r["polls"] for r in act]), median([r["frames"] for r in act]), LIM_GAP,
        sum(1 for r in act if r["gap33"] > LIM_GAP), sum(r["f32"] for r in act), sum(r["frames"] for r in act)))
act = active("paced")
if os.path.exists(os.path.join(sys.argv[1], "paced", "serial.txt")):
    chk(len(act) >= 20, "paced: %d active slices (need 20: the pointer phases are fed)" % len(act))
    if act:
        chk(median([r["frames"] for r in act]) >= MIN_FRAMES, "paced: median %d frames per active slice (need %d)" % (median([r["frames"] for r in act]), MIN_FRAMES))
        calm = sum(1 for r in act if r["gap33"] <= LIM_GAP) * 100 // len(act)
        chk(calm >= 90, "paced: %d%% of the active slices have <= %d poll gaps > 33 ms (need 90%%)" % (calm, LIM_GAP))
        chk(median([r["polls"] for r in act]) >= MIN_POLLS, "paced: median %d polls per active slice (need %d)" % (median([r["polls"] for r in act]), MIN_POLLS))
        fr = sum(r["frames"] for r in act)
        f32 = sum(r["f32"] for r in act)
        chk(f32 * 100 <= fr and sum(1 for r in act if r["f32"]) <= 3, "paced: frames >= 32 ms: %d of %d (limit 1%%, at most 3 slices)" % (f32, fr))
old = active("nolatfix")
if os.path.exists(os.path.join(sys.argv[1], "nolatfix", "serial.txt")):
    mp = median([r["polls"] for r in old])
    chk(mp < MIN_POLLS // 2, "nolatfix (counter-proof): median %d polls per active slice (must be < %d: the old loop is slower)" % (mp, MIN_POLLS // 2))


def green(case, name="fps-overlay"):
    p = os.path.join(sys.argv[1], case, name + ".ppm")
    if not os.path.exists(p):
        return None
    d = open(p, "rb").read()
    m = re.match(rb"P6\s+(\d+)\s+(\d+)\s+(\d+)\s", d)
    if not m:
        return None
    w, h = int(m.group(1)), int(m.group(2))
    off = m.end()
    cnt = 0
    for y in range(0, 64):
        for x in range(w - 210, w):
            i = off + (y * w + x) * 3
            if d[i] < 40 and d[i + 1] > 215 and d[i + 2] < 40:
                cnt += 1
    return cnt


on, offv = green("fpson"), green("fpsoff")
print("== overlay: green pixels top-right 210x64: on=%s off=%s" % (on, offv))
chk(on is not None and on >= 100, "fps on: the overlay text is at the top-right (%s green pixels)" % on)
chk(offv is not None and offv == 0, "fps off (counter-proof): nothing drawn top-right (%s green pixels)" % offv)


# ---- FPS-OV: Ctrl+Alt+F, numbers from the real clocks (serial `wm: fpsov`), photos, counter-proofs
def ov_phases(case):
    """list of phases (cut at `wm: cadence` lines), each a list of dicts of the `wm: fpsov` lines in it"""
    p = os.path.join(sys.argv[1], case, "serial.txt")
    out, cur = [], []
    if not os.path.exists(p):
        return None, ""
    txt = open(p, "rb").read().decode("latin1")
    for line in txt.splitlines():
        if line.startswith("wm: cadence"):
            out.append(cur)
            cur = []
        m = re.match(r"wm: fpsov fps=(\d+) ft=(\d+) avg=(\d+) max=(\d+) pres=(\d+) drv=(\d)", line)
        if m:
            cur.append(dict(fps=int(m.group(1)), ft=int(m.group(2)), avg=int(m.group(3)), max=int(m.group(4)), pres=int(m.group(5)), drv=int(m.group(6))))
    out.append(cur)
    return out, txt


ph, txt = ov_phases("ovon")
if ph is not None:
    chk("wm: fps overlay on" in txt, "ovon: Ctrl+Alt+F switched the overlay on (serial: wm: fps overlay on)")
    chk("ptrcfg: fps saved on" in txt, "ovon: the switch was written to /etc/mouse.conf (serial: ptrcfg: fps saved on)")
    allv = [r for p in ph for r in p]
    chk(len(allv) >= 10, "ovon: %d fpsov lines (the overlay clocks run)" % len(allv))
    idle = ph[2] if len(ph) > 2 else []
    chk(any(r["fps"] == 0 and r["pres"] == 0 for r in idle), "ovon idle: a line with fps=0 pres=0 (the overlay says IDLE, no presents of its own: %s)" % idle[-3:])
    drag = ph[4] if len(ph) > 4 else []
    best = max([r["fps"] for r in drag] or [0])
    print("== ovon window drag: fpsov lines %s" % drag)
    chk(best >= 30, "ovon drag: fps up to %d (need >= 30 while dragging)" % best)
    act = [r for r in drag if r["fps"] >= 20]
    chk(bool(act) and all(8000 <= r["avg"] <= 40000 for r in act), "ovon drag: mean frame time between 8 and 40 ms on every active line")
    chk(bool(act) and all(r["max"] >= r["avg"] for r in act), "ovon drag: max >= mean")
    chk(bool(act) and all(r["drv"] == 1 for r in act) and all(r["pres"] * 2 >= r["fps"] and r["pres"] <= r["fps"] * 3 // 2 + 3 for r in act),
        "ovon drag: present clock follows the frame rate (half .. 1.5x + 3) with a driver")
    g_idle, g_drag = green("ovon", "ov-idle"), green("ovon", "ov-drag")
    chk(g_idle is not None and g_idle >= 60, "ovon idle photo: overlay text top-right (%s green pixels)" % g_idle)
    chk(g_drag is not None and g_drag >= 100, "ovon drag photo: overlay text top-right (%s green pixels)" % g_drag)
ph, txt = ov_phases("ovoff")
if ph is not None:
    chk(sum(len(p) for p in ph) == 0 and "wm: fps overlay on" not in txt, "ovoff (counter-proof): no overlay line, no switch")
    go = green("ovoff", "ov-idle")
    chk(go == 0, "ovoff (counter-proof): no green pixels top-right (%s)" % go)
ph, txt = ov_phases("ovplain")
if ph is not None:
    allv = [r for p in ph for r in p]
    chk(bool(allv) and all(r["drv"] == 0 for r in allv), "ovplain: plain VGA reports no present driver (drv=0, text PRESENT n/a)")
print("RESULT %s" % ("ALL OK" if not fail else "%d FAIL" % fail))
sys.exit(1 if fail else 0)
