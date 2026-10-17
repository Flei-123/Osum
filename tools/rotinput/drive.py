#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/rotinput/drive.py -- INPUT FOLLOWS THE OUTPUT: click the Start button of a ROTATED desktop through an absolute tablet.

    drive.py <qmp-socket> <monitor-socket> <serial.txt> <outdir> <rot>

The desktop booted with `deskrot<rot>` (rot 0 = no word). The taskbar reports its own geometry in LOGICAL (unrotated) pixels
(`taskbar: geom`, `taskbar: start`). The oracle below turns the Start button centre into a PANEL pixel with the rotation of
`fb.present` (written from the definition, not from the new kernel code) and a QMP absolute tablet event goes exactly there.
If the click really hits the button that is DRAWN there, the taskbar reports `taskbar: click ... hits=start` with a local
position inside the Start rectangle, and the start menu opens (`taskbar: startmenue auf`).
Facts go to scenes.txt as key=value lines. Waits are event driven (serial lines).
"""
import json
import os
import re
import socket
import subprocess
import sys
import time


class Qmp:
    def __init__(self, path):
        self.s = None
        for _ in range(300):
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            try:
                s.connect(path)
                self.s = s
                break
            except OSError:
                s.close()
                time.sleep(0.1)
        if self.s is None:
            raise SystemExit("qmp: cannot connect")
        self.buf = b""
        self.line()
        self.call("qmp_capabilities")

    def line(self):
        while b"\n" not in self.buf:
            c = self.s.recv(65536)
            if not c:
                raise EOFError("qmp closed")
            self.buf += c
        l, _, self.buf = self.buf.partition(b"\n")
        return json.loads(l)

    def call(self, cmd, **args):
        self.s.sendall((json.dumps({"execute": cmd, "arguments": args}) + "\n").encode())
        while True:
            r = self.line()
            if "return" in r or "error" in r:
                return r

    def abs_move(self, px, py, pw, ph):
        ax = round(px * 32767 / max(pw - 1, 1))
        ay = round(py * 32767 / max(ph - 1, 1))
        self.call("input-send-event", events=[
            {"type": "abs", "data": {"axis": "x", "value": ax}},
            {"type": "abs", "data": {"axis": "y", "value": ay}}])
        time.sleep(0.25)

    def rel_push(self, sx, sy, n=60):
        # many relative steps in ONE call: far more than the panel is wide, so the pointer ends clamped at a screen edge/corner
        ev = []
        for _ in range(n):
            ev.append({"type": "rel", "data": {"axis": "x", "value": 100 * sx}})
            ev.append({"type": "rel", "data": {"axis": "y", "value": 100 * sy}})
        self.call("input-send-event", events=ev)
        time.sleep(1.0)

    def button(self, down):
        self.call("input-send-event", events=[{"type": "btn", "data": {"down": down, "button": "left"}}])
        time.sleep(0.25)


def serial_text(path):
    try:
        return open(path, "rb").read().decode("latin1")
    except OSError:
        return ""


def wait_for(path, pattern, start, timeout=40.0):
    end = time.time() + timeout
    rx = re.compile(pattern)
    while time.time() < end:
        m = rx.search(serial_text(path), start)
        if m:
            return m.end(), m
        time.sleep(0.15)
    return start, None


def shot(mon, out):
    subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "gfx", "screenshot.py"), mon, out, "25"],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def ppm(path):
    d = open(path, "rb").read()
    parts = d.split(b"\n", 3)
    w, h = [int(x) for x in parts[1].split()]
    return w, h, parts[3]


def logical_to_panel(rot, lx, ly, pw, ph):
    """the rotation of fb.present, forwards: logical pixel -> panel pixel"""
    if rot == 0:
        return lx, ly
    if rot == 180:
        return pw - 1 - lx, ph - 1 - ly
    if rot == 90:      # logical x = panel y, logical y = lh-1-panel x  (lh = pw)
        return pw - 1 - ly, lx
    if rot == 270:     # logical x = lw-1-panel y, logical y = panel x  (lw = ph)
        return ly, ph - 1 - lx
    raise SystemExit("bad rotation")


def main():
    qmp_path, mon, ser, out, rot = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], int(sys.argv[5])
    q = Qmp(qmp_path)
    facts = []

    def fact(k, v):
        facts.append(f"{k}={v}")

    pos, m = wait_for(ser, r"taskbar: start x=(\d+) y=(\d+) w=(\d+) h=(\d+)", 0, 90)
    if not m:
        fact("desktop", 0)
        open(os.path.join(out, "scenes.txt"), "w").write("\n".join(facts) + "\n")
        return
    fact("desktop", 1)
    sx, sy, sw, sh = [int(v) for v in m.groups()]
    time.sleep(2.0)                                   # let the bar settle
    txt = serial_text(ser)
    g = re.findall(r"taskbar: geom x=(\d+) y=(\d+) w=(\d+) h=(\d+)", txt)
    bx, by = (int(g[-1][0]), int(g[-1][1])) if g else (0, 0)
    sm = re.findall(r"taskbar: start x=(\d+) y=(\d+) w=(\d+) h=(\d+)", txt)[-1]
    sx, sy, sw, sh = [int(v) for v in sm]
    shot(mon, os.path.join(out, "before.ppm"))
    pw, ph, data = ppm(os.path.join(out, "before.ppm"))
    fact("panel", f"{pw}x{ph}")
    fact("bar", f"{bx},{by}")
    fact("start", f"{sx},{sy},{sw},{sh}")
    lx, ly = bx + sx + sw // 2, by + sy + sh // 2
    px, py = logical_to_panel(rot, lx, ly, pw, ph)
    fact("logical_centre", f"{lx},{ly}")
    fact("panel_target", f"{px},{py}")
    # the old (unrotated) place of the button on the panel, for the report
    mark = len(serial_text(ser))
    q.abs_move(px, py, pw, ph)
    q.button(True)
    q.button(False)
    _, mc = wait_for(ser, r"taskbar: click x=(\d+) y=(\d+)[^\n]*", mark, 8)
    if mc:
        cx, cy = int(mc.group(1)), int(mc.group(2))
        fact("click_local", f"{cx},{cy}")
        fact("click_line", mc.group(0).strip().replace(" ", "_"))
        fact("click_in_start", 1 if (sx <= cx < sx + sw and sy <= cy < sy + sh) else 0)
        # read the next lines as well: `hits=` / `startmenue auf`
    else:
        fact("click_local", "none")
        fact("click_in_start", 0)
    _, mo = wait_for(ser, r"taskbar: startmenue auf", mark, 8)
    fact("menu_open", 1 if mo else 0)
    fact("hits_start", 1 if re.search(r"taskbar: click x=\d+ y=\d+[^\n]*\n[^\n]*hits=start", serial_text(ser)[mark:]) or re.search(r"hits=start", serial_text(ser)[mark:]) else 0)
    time.sleep(1.0)
    shot(mon, os.path.join(out, "after.ppm"))
    # --- relative mouse: push the pointer PHYSICALLY toward the panel corner that shows the LOGICAL bottom-right corner (inside the
    # taskbar). Clamping makes it independent of pointer acceleration. The click must land at the end of the bar.
    gw = re.findall(r"taskbar: geom x=(\d+) y=(\d+) w=(\d+) h=(\d+)", serial_text(ser))
    bw, bh = (int(gw[-1][2]), int(gw[-1][3])) if gw else (0, 0)
    lw, lh = (pw, ph) if rot in (0, 180) else (ph, pw)
    cxp, cyp = logical_to_panel(rot, lw - 1, lh - 1, pw, ph)
    sgx = 1 if cxp > pw // 2 else -1
    sgy = 1 if cyp > ph // 2 else -1
    q.abs_move(pw // 2, ph // 2, pw, ph)
    q.rel_push(sgx, sgy)
    mark2 = len(serial_text(ser))
    q.button(True)
    q.button(False)
    _, mr = wait_for(ser, r"taskbar: click x=(\d+) y=(\d+)[^\n]*", mark2, 8)
    if mr:
        rx, ry = int(mr.group(1)), int(mr.group(2))
        fact("rel_click_local", f"{rx},{ry}")
        fact("rel_ok", 1 if (rx >= bw - 3 and ry >= bh - 3) else 0)
    else:
        fact("rel_click_local", "none")
        fact("rel_ok", 0)
    fact("rel_push", f"{sgx},{sgy}")
    open(os.path.join(out, "scenes.txt"), "w").write("\n".join(facts) + "\n")


if __name__ == "__main__":
    main()
