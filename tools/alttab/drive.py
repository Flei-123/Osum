#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/alttab/drive.py -- drive the Alt+Tab switcher through QMP key events (Alt can be HELD, which `sendkey` cannot).

    drive.py <qmp-socket> <monitor-socket> <serial.txt> <outdir>

Opens three windows (Win+E, Win+E, Win+I), then runs four scenes and writes `scenes.txt` (one `key=value` line per fact):
  A  Alt down, Tab, Tab, Shift+Tab, release   -> open, step forward, step back, commit (focus changes only at release)
  B  Alt down, Tab, Esc, release              -> cancel, focus unchanged
  C  quick Alt+Tab tap (Alt already up)       -> open + commit in one go
  D  Alt down, Tab, hold, screenshot, release -> overlay pixels differ while open and are gone after the commit
Each wait is event driven (a serial line), never a fixed sleep for a result.
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

    def key(self, name, down):
        self.call("input-send-event", events=[{"type": "key", "data": {"down": down, "key": {"type": "qcode", "data": name}}}])
        time.sleep(0.08)

    def tap(self, *names):
        for n in names:
            self.key(n, True)
        for n in reversed(names):
            self.key(n, False)


def serial_text(path):
    try:
        return open(path, "rb").read().decode("latin1")
    except OSError:
        return ""


def wait_for(path, pattern, start, timeout=25.0):
    """wait for a regex in the serial text after offset `start`; returns (match end offset, match) or (start, None)"""
    end = time.time() + timeout
    rx = re.compile(pattern)
    while time.time() < end:
        t = serial_text(path)
        m = rx.search(t, start)
        if m:
            return m.end(), m
        time.sleep(0.15)
    return start, None


def shot(mon, out):
    subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "gfx", "screenshot.py"), mon, out, "25"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def ppm(path):
    d = open(path, "rb").read()
    parts = d.split(b"\n", 3)
    w, h = [int(x) for x in parts[1].split()]
    return w, h, parts[3]


def diff_px(a, b):
    wa, ha, da = a
    wb, hb, db = b
    if (wa, ha) != (wb, hb):
        return -1
    n = 0
    for i in range(0, len(da), 3):
        if da[i:i + 3] != db[i:i + 3]:
            n += 1
    return n


def main():
    qmp_path, mon, ser, out = sys.argv[1:5]
    q = Qmp(qmp_path)
    facts = []

    def fact(k, v):
        facts.append(f"{k}={v}")

    pos = 0
    pos, _ = wait_for(ser, r"eingabe: ber=", 0, 90)
    time.sleep(1.0)
    q.tap("shift")  # warm-up: the first key after the first pulse was lost once on a loaded host
    time.sleep(1.0)
    for combo, pat in ((("meta_l", "e"), r"taskbar: hk start /apps/explorer\.osp/start"),
                       (("meta_l", "e"), r"taskbar: hk start /apps/explorer\.osp/start"),
                       (("meta_l", "i"), r"taskbar: hk start /apps/settings\.osp/start")):
        before = len(re.findall(r"wm: fokus", serial_text(ser)))
        q.tap(*combo)
        end = time.time() + 40
        while time.time() < end and len(re.findall(r"wm: fokus", serial_text(ser))) <= before:
            time.sleep(0.2)
        time.sleep(1.5)
    pos = len(serial_text(ser))
    fact("windows_focus_lines", len(re.findall(r"wm: fokus", serial_text(ser))))
    shot(mon, out + "/before.ppm")

    # ---- scene A: Alt held, Tab, Tab, Shift+Tab, release
    pos = len(serial_text(ser))
    q.key("alt", True)
    q.tap("tab")
    pos, m = wait_for(ser, r"wm: switcher open n=(\d+) sel=(\d+) win=(\d+)", pos, 15)
    fact("A_open", "1" if m else "0")
    if m:
        fact("A_open_n", m.group(1))
        fact("A_open_sel", m.group(2))
    mark = len(serial_text(ser))
    q.tap("tab")
    pos, m = wait_for(ser, r"wm: switcher step n=(\d+) sel=(\d+)", pos, 10)
    fact("A_step", m.group(2) if m else "none")
    q.key("shift", True)
    q.tap("tab")
    q.key("shift", False)
    pos, m = wait_for(ser, r"wm: switcher step n=(\d+) sel=(\d+)", pos, 10)
    fact("A_back", m.group(2) if m else "none")
    t = serial_text(ser)
    fact("A_focus_changed_while_held", "1" if re.search(r"wm: fokus", t[mark:]) else "0")
    q.key("alt", False)
    pos, m = wait_for(ser, r"wm: switcher commit n=(\d+) sel=(\d+) win=(\d+)", pos, 10)
    fact("A_commit", "1" if m else "0")
    if m:
        fact("A_commit_win", m.group(3))
        pos2, f = wait_for(ser, r"wm: fokus id=(\d+)", pos, 8)
        fact("A_focus_after", f.group(1) if f else "none")
    time.sleep(1.0)

    # ---- scene B: Esc cancels
    pos = len(serial_text(ser))
    q.key("alt", True)
    q.tap("tab")
    pos, m = wait_for(ser, r"wm: switcher open", pos, 15)
    fact("B_open", "1" if m else "0")
    mark = len(serial_text(ser))
    q.tap("esc")
    pos, m = wait_for(ser, r"wm: switcher cancel", pos, 10)
    fact("B_cancel", "1" if m else "0")
    q.key("alt", False)
    time.sleep(1.5)
    t = serial_text(ser)
    fact("B_commit_after_cancel", "1" if re.search(r"wm: switcher commit", t[mark:]) else "0")
    fact("B_focus_changed", "1" if re.search(r"wm: fokus", t[mark:]) else "0")

    # ---- scene C: quick tap
    pos = len(serial_text(ser))
    q.key("alt", True)
    q.key("tab", True)
    q.key("tab", False)
    q.key("alt", False)
    pos, m = wait_for(ser, r"wm: switcher commit", pos, 15)
    fact("C_commit", "1" if m else "0")
    time.sleep(1.0)

    # ---- scene D: pixels while open
    pos = len(serial_text(ser))
    shot(mon, out + "/idle.ppm")
    q.key("alt", True)
    q.tap("tab")
    pos, m = wait_for(ser, r"wm: switcher open", pos, 15)
    time.sleep(1.0)
    shot(mon, out + "/open.ppm")
    q.key("alt", False)
    pos, m = wait_for(ser, r"wm: switcher commit", pos, 15)
    time.sleep(1.5)
    shot(mon, out + "/after.ppm")
    # ---- scene E: a second quick tap switches back to the window of `idle`; the picture must equal `idle` again (no panel left over)
    pos = len(serial_text(ser))
    q.key("alt", True)
    q.key("tab", True)
    q.key("tab", False)
    q.key("alt", False)
    pos, m = wait_for(ser, r"wm: switcher commit", pos, 15)
    time.sleep(2.0)
    shot(mon, out + "/back.ppm")
    try:
        idle, opn, aft, back = ppm(out + "/idle.ppm"), ppm(out + "/open.ppm"), ppm(out + "/after.ppm"), ppm(out + "/back.ppm")
        fact("D_screen", f"{idle[0]}x{idle[1]}")
        fact("D_open_vs_idle_px", diff_px(idle, opn))
        # the commit raised another window, so `after` differs from `idle`; compare the panel strip (centre band) instead
        w, h = idle[0], idle[1]
        y0, y1 = h * 2 // 5, h * 3 // 5
        def band(img):
            return (w, y1 - y0, img[2][(y0 * w) * 3:(y1 * w) * 3])
        fact("D_band_open_vs_idle_px", diff_px(band(idle), band(opn)))
        fact("D_band_open_vs_after_px", diff_px(band(opn), band(aft)))
        fact("E_band_back_vs_idle_px", diff_px(band(idle), band(back)))
        fact("E_full_back_vs_idle_px", diff_px(idle, back))
        # X1: the tiles have no black letterbox -- count pure 0x101010 pixels in the panel band of the open picture (the old code
        # filled every thumbnail box with 0x101010 and left the side/bottom margins black)
        bo = band(opn)[2]
        fact("D_black_px", sum(1 for i in range(0, len(bo), 3) if bo[i:i + 3] == b"\x10\x10\x10"))
    except Exception as e:  # noqa
        fact("D_error", repr(e))
    # ---- scene F (X1): a MINIMIZED window is listed (mins>=1), Tab reaches it, releasing Alt restores it
    try:
        pos = len(serial_text(ser))
        q.tap("meta_l", "down")  # the focused floating window minimizes
        time.sleep(2.5)
        pos = len(serial_text(ser))
        q.key("alt", True)
        q.tap("tab")
        pos, m = wait_for(ser, r"wm: switcher open n=(\d+) sel=(\d+) win=(\d+) hid=(\d) mins=(\d+)", pos, 15)
        fact("F_open", "1" if m else "0")
        hid = 0
        if m:
            fact("F_open_n", m.group(1))
            fact("F_open_mins", m.group(5))
            hid = int(m.group(4))
        tries = 0
        while m and hid != 1 and tries < 6:
            tries += 1
            q.tap("tab")
            pos, m2 = wait_for(ser, r"wm: switcher step n=(\d+) sel=(\d+) win=(\d+) hid=(\d) mins=(\d+)", pos, 10)
            hid = int(m2.group(4)) if m2 else 0
            if not m2:
                break
        fact("F_sel_minimized", "1" if hid == 1 else "0")
        time.sleep(1.0)
        shot(mon, out + "/open_min.ppm")
        q.key("alt", False)
        pos, m3 = wait_for(ser, r"wm: switcher commit n=(\d+) sel=(\d+) win=(\d+) hid=(\d) mins=(\d+)", pos, 10)
        fact("F_commit_hid", m3.group(4) if m3 else "none")
        pos2, f = wait_for(ser, r"wm: fokus id=(\d+)", pos, 8)
        fact("F_focus_after", f.group(1) if f else "none")
        fact("F_commit_win", m3.group(3) if m3 else "none")
        time.sleep(1.5)
        # the window is back: a new switcher lists no minimized window any more
        pos = len(serial_text(ser))
        q.key("alt", True)
        q.tap("tab")
        pos, m4 = wait_for(ser, r"wm: switcher open n=(\d+) sel=(\d+) win=(\d+) hid=(\d) mins=(\d+)", pos, 15)
        fact("F_after_mins", m4.group(5) if m4 else "none")
        q.tap("esc")
        q.key("alt", False)
        time.sleep(1.0)
    except Exception as e:  # noqa
        fact("F_error", repr(e))
    open(out + "/scenes.txt", "w").write("\n".join(facts) + "\n")
    print("\n".join(facts))
    return 0


if __name__ == "__main__":
    sys.exit(main())
