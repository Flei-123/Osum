#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/usbhid/drive.py -- inject host input into the running guest through QMP input-send-event.

    drive.py <qmp-socket> <serial.txt> <scenario>        scenario: mouse | tablet | kbd | ps2

Waits (event driven) for the guest line `hidwin: open`, injects the scenario, then returns.
mouse/ps2: relative move, wheel up x3, wheel down x1, right button press+release, middle button.
tablet:    absolute move to the far corner (axis values 0..32767), wheel up, right button.
kbd:       key a, key b, key shift+c.
"""
import json
import socket
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

    def events(self, evs):
        r = self.call("input-send-event", {"events": evs})
        if "error" in r:
            print("qmp error:", r["error"], file=sys.stderr)


def btn(name, down):
    return {"type": "btn", "data": {"down": down, "button": name}}


def rel(axis, v):
    return {"type": "rel", "data": {"axis": axis, "value": v}}


def absv(axis, v):
    return {"type": "abs", "data": {"axis": axis, "value": v}}


def key(q, down):
    return {"type": "key", "data": {"down": down, "key": {"type": "qcode", "data": q}}}


def wait_line(path, needle, secs):
    t0 = time.time()
    while time.time() - t0 < secs:
        try:
            if needle.encode() in open(path, "rb").read():
                return True
        except OSError:
            pass
        time.sleep(0.2)
    return False


def main():
    sock, ser, scen = sys.argv[1:4]
    q = Qmp(sock)
    if not wait_line(ser, "hidwin: open", 60):
        print("drive: window never opened", file=sys.stderr)
        return 1
    time.sleep(0.5)
    if scen in ("mouse", "ps2"):
        for _ in range(5):
            q.events([rel("x", 20), rel("y", 10)])
            time.sleep(0.05)
        for _ in range(3):
            q.events([btn("wheel-up", True)])
            q.events([btn("wheel-up", False)])
            time.sleep(0.05)
        q.events([btn("wheel-down", True)])
        q.events([btn("wheel-down", False)])
        time.sleep(0.1)
        q.events([btn("right", True)])
        time.sleep(0.3)
        q.events([btn("right", False)])
        time.sleep(0.1)
        q.events([btn("middle", True)])
        time.sleep(0.3)
        q.events([btn("middle", False)])
    elif scen == "tablet":
        for v in (4000, 12000, 20000, 30000):
            q.events([absv("x", v), absv("y", v)])
            time.sleep(0.1)
        q.events([btn("wheel-up", True)])
        q.events([btn("wheel-up", False)])
        time.sleep(0.1)
        q.events([btn("right", True)])
        time.sleep(0.3)
        q.events([btn("right", False)])
    elif scen == "kbd":
        for k in ("a", "b"):
            q.events([key(k, True)])
            time.sleep(0.1)
            q.events([key(k, False)])
            time.sleep(0.1)
        q.events([key("shift", True), key("c", True)])
        time.sleep(0.1)
        q.events([key("c", False), key("shift", False)])
    print("drive: done")
    return 0


sys.exit(main())
