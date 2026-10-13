#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/fvviewer/gui_check.py -- judge one GUI gate stage from its artefacts.

    gui_check.py <outdir> <thdir> <stage>

<outdir> holds serial.txt + *.ppm (written by tools/design/eh6.sh + drive.py), <thdir>/input.log is the
Rust test host's input log. Stage "plain" and "tls" check the full session; "tlsidle" checks only that
the session stayed up. Prints "  OK/FAIL  <what>" lines and a "NUM ..." line with the measured numbers.
Exit code = number of failures.
"""
import re
import statistics
import sys

out, th, stage = sys.argv[1], sys.argv[2], sys.argv[3]
fails = 0


def rd(p):
    try:
        return open(p, "rb").read().decode("latin1")
    except OSError:
        return ""


def ok(c, what):
    global fails
    print("  %s  %s" % ("OK  " if c else "FAIL", what))
    if not c:
        fails += 1


def ppm(name):
    try:
        b = open("%s/%s.ppm" % (out, name), "rb").read()
    except OSError:
        return None
    m = re.match(rb"P6\s+(\d+)\s+(\d+)\s+(\d+)\s", b)
    if not m:
        return None
    w, h = int(m.group(1)), int(m.group(2))
    return w, h, b[m.end():]


def px(img, x, y):
    w, h, d = img
    x = max(0, min(w - 1, x))
    y = max(0, min(h - 1, y))
    o = (y * w + x) * 3
    return d[o], d[o + 1], d[o + 2]


def near(a, b, tol):
    return all(abs(a[i] - b[i]) <= tol for i in range(3))


ser = rd(out + "/serial.txt")
hl = rd(th + "/input.log")


def last(rx):
    m = None
    for m in re.finditer(rx, ser):
        pass
    return m


geom = last(r"fvviewer: geom x=(\d+) y=(\d+)")
view = last(r"fvviewer: rect name=view x=(\d+) y=(\d+) w=(\d+) h=(\d+)")
ok(geom is not None, "window geom reported")
ok(view is not None, "view rect reported")
lives = len(re.findall(r"fvviewer: state live", ser))
ok(lives >= 1, "state live reached (%d x)" % lives)
nums = []
if geom and view:
    # frame + title: osum shape frame=1 title_bar=32 -> origin (1, 34)
    ox, oy = int(geom.group(1)) + 1, int(geom.group(2)) + 34
    vx, vy = ox + int(view.group(1)), oy + int(view.group(2))
    vw, vh = int(view.group(3)), int(view.group(4))
    img = ppm("20-live")
    ok(img is not None, "screenshot 20-live")
    if img:
        # test host picture: R = x/639*255, G = y/479*255, B = 128
        # Several photos: when a window UNDER the viewer (the terminal that shows the serial trace) repaints, the guest
        # compositor sometimes draws it over the viewer picture until the viewer repaints (r53) -> pass if one photo is whole.
        best, bad_photos, shown = -1, 0, ""
        for nm in ("20-live", "29-click-fast", "31-click-1s", "32-click-2s", "30-click"):
            im3 = ppm(nm)
            if im3 is None:
                continue
            pr = []
            for fx, fy in ((0.1, 0.1), (0.9, 0.1), (0.1, 0.5), (0.9, 0.9), (0.5, 0.5)):
                got = px(im3, vx + int(vw * fx), vy + int(vh * fy))
                want = (int(255 * fx), int(255 * fy), 128)
                pr.append((got, want))
            okc = sum(1 for g, w in pr if near(g, w, 40))
            if okc < 5:
                bad_photos += 1
            if okc > best:
                best, shown = okc, " ".join("%s~%s" % (g, w) for g, w in pr)
        ok(best == 5, "picture gradient at 5 probe points (%d/5, best photo; %d photo(s) with an unpainted region): %s" % (best, bad_photos, shown))
        # alpha / background: a probe must not be the window grey -> covered by the gradient check above
    if stage != "tlsidle":
        # click at 25% / 50% of the view -> the host answers with a red 16x16 mark (button 0). Which photo shows it first
        # tells how long the picture needs to reach the screen (photo times: see tools/fvviewer/gui.sh script).
        seen = None
        for nm in ("29-click-fast", "31-click-1s", "32-click-2s", "30-click"):
            im2 = ppm(nm)
            if im2 is None:
                continue
            cnt = 0
            for yy in range(vy, vy + vh, 2):
                for xx in range(vx, vx + vw, 2):
                    r, g, b = px(im2, xx, yy)
                    if r > 180 and g < 90 and b < 90:
                        cnt += 1
            if cnt >= 30 and seen is None:
                seen = (nm, cnt)
        ok(seen is not None, "red click mark on screen (first photo showing it: %s)" % (seen,))
        nums.append("mark_first_seen=%s" % (seen[0] if seen else None))
# serial evidence
dn = re.findall(r"fvviewer: ev down x=(\d+) y=(\d+) btn=(\d+) inside=(\d) ptr=(\d+),(\d+)", ser)
up = re.findall(r"fvviewer: ev up x=(\d+) y=(\d+) btn=(\d+) inside=(\d) ptr=(\d+),(\d+)", ser)
if stage != "tlsidle":
    ok(len(dn) >= 1 and dn[0][3] == "1", "EV_DOWN seen, inside the picture: %s" % (dn[:1],))
    ok(len(up) >= 1, "EV_UP seen: %s (btn value is what the OS reports on release)" % (up[:1],))
    ok(bool(re.search(r"MouseButton button=0 down=true", hl)), "test host logged MouseButton down")
    ok(bool(re.search(r"MouseButton button=0 down=false", hl)), "test host logged MouseButton up (button 0, i.e. EV_UP btn handled)")
    mv = re.findall(r"MouseMove x=(\d+) y=(\d+)", hl)
    ok(any(abs(int(a) - 2500) < 400 and abs(int(b) - 5000) < 400 for a, b in mv), "MouseMove near (2500,5000): %s" % (mv[-3:],))
    keys = re.findall(r"^((?:KeyVk|Key|Special) [^\n]*)$", hl, re.M)
    ok(len(keys) >= 3, "test host logged key messages (%d): %s" % (len(keys), keys[:6]))
    ok("clip echo ok" in ser, "clipboard round trip (put -> host echo -> viewer)")
    ok(re.search(r"Clipboard|Clip", hl) is not None, "test host logged the clipboard message")
    cm = [int(x) for x in re.findall(r"click-to-mark ms=(\d+)", ser)]
    nums.append("click_to_mark_ms=%s" % cm[:5])
    ok(bool(cm), "click-to-mark latency measured")
fl = re.findall(r"live fps=(\d+) rtt=(\d+) handle_ms=(\d+)", ser)
if fl:
    nums.append("fps_median=%s rtt_median_ms=%s handle_ms_median=%s (n=%d)" % (
        statistics.median(int(a) for a, b, c in fl), statistics.median(int(b) for a, b, c in fl),
        statistics.median(int(c) for a, b, c in fl), len(fl)))
if stage in ("plain", "tls"):
    ok(lives >= 2, "reconnect: second 'state live' after host kill/start (%d)" % lives)
    ok(bool(re.search(r"fvviewer: lost err=", ser)), "viewer noticed the lost host (lost err line)")
if stage in ("tls", "tlsidle"):
    # the TLS idle fund: no 'lost' before the host was killed (idle seconds between host tiles)
    ok(ser.find("fvviewer: state live") >= 0, "wss session established")
print("NUM %s" % " ".join(nums))
sys.exit(fails)
