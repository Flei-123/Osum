# SPDX-License-Identifier: GPL-2.0-only
# tools/usbhid/desktop.py -- OHCI tablet on the REAL desktop (stick image), called by tools/usbhid/desktop.sh.
# usage: desktop.py <monitor sock> <qmp sock> <serial file> <out base> <settle seconds>
# Logs in through the PS/2 keyboard (monitor sendkey), waits for the desktop, then injects absolute tablet events through QMP
# input-send-event and writes <base>.res:  <pulse lines> <max wmpolls> <max reports> <max errors>
# (parsed from the serial lines `ohci: pulse polls=N wmpolls=N reports=N errors=N ...` printed on every input pulse).
import json
import os
import re
import socket
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "vmsvga"))
from vnclib import Mon  # noqa: E402

mon_sock, qmp_sock, serial, base, settle = sys.argv[1:6]
settle = float(settle)


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
            d = self.s.recv(4096)
            if not d:
                raise SystemExit("qmp: closed")
            self.buf += d
        l, self.buf = self.buf.split(b"\n", 1)
        return json.loads(l)

    def call(self, cmd, args=None):
        m = {"execute": cmd}
        if args is not None:
            m["arguments"] = args
        self.s.sendall((json.dumps(m) + "\n").encode())
        while True:
            r = self.line()
            if "return" in r or "error" in r:
                return r

    def abs(self, x, y):
        self.call("input-send-event", {"events": [
            {"type": "abs", "data": {"axis": "x", "value": x}},
            {"type": "abs", "data": {"axis": "y", "value": y}}]})

    def btn(self, name, down):
        self.call("input-send-event", {"events": [{"type": "btn", "data": {"button": name, "down": down}}]})


def main():
    mon = Mon(mon_sock)
    if not wait_for(lambda t: "glogin: bereit" in t, 200):
        open(base + ".login", "w").write("0")
        mon.quit()
        return
    time.sleep(6)
    for c in "startkennwort":
        mon.cmd("sendkey " + c, 0.12)
    mon.cmd("sendkey ret", 0.3)
    ok = wait_for(lambda t: "glogin: angemeldet als" in t, 60)
    open(base + ".login", "w").write("1" if ok else "0")
    if not ok:
        mon.quit()
        return
    time.sleep(settle)
    q = Qmp(qmp_sock)
    # a sweep over the screen plus a click: every step is one USB report that must reach the window server
    for rnd in range(3):
        for i in range(0, 33):
            q.abs(i * 1000, i * 900)
            time.sleep(0.05)
        for i in range(32, -1, -1):
            q.abs(i * 1000, 20000)
            time.sleep(0.05)
    q.btn("left", True)
    time.sleep(0.1)
    q.btn("left", False)
    time.sleep(2)
    t = read_serial()
    lines = re.findall(r"ohci: pulse polls=(\d+) wmpolls=(\d+) reports=(\d+) errors=(\d+)", t)
    mx = [0, 0, 0]
    for p, w, r, e in lines:
        mx[0] = max(mx[0], int(w))
        mx[1] = max(mx[1], int(r))
        mx[2] = max(mx[2], int(e))
    open(base + ".res", "w").write("%d %d %d %d\n" % (len(lines), mx[0], mx[1], mx[2]))
    mon.quit()


main()
