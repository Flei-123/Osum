#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    mouse.py <qmp-socket> <secs> <hz> [key=value ...]
    keys=<n>               danach n Tastendruecke (a..z) in 50-ms-Spacing
"""
import json
import math
import os
import socket
import sys
import time


def verbinden(path_2, deadline=30.0):
    bis = time.time() + deadline
    while time.time() < bis:
        try:
            s = socket.socket(socket.AF_UNIX)
            s.settimeout(5.0)
            s.connect(path_2)
            return s
        except OSError:
            time.sleep(0.1)
    return None


class Qmp:
    def __init__(self, s):
        self.s = s
        self.f = s.makefile("rb")
        self.gruss = json.loads(self.f.readline())
        self.cmd("qmp_capabilities")

    def cmd(self, name, **args):
        d = {"execute": name}
        if args:
            d["arguments"] = args
        self.s.sendall((json.dumps(d) + "\n").encode())
        while True:
            line = self.f.readline()
            if not line:
                raise RuntimeError("QMP: Verbindung weg")
            reply = json.loads(line)
            if "event" in reply:
                continue
            return reply

    def rel(self, dx, dy):
        ev = []
        if dx:
            ev.append({"type": "rel", "data": {"axis": "x", "value": int(dx)}})
        if dy:
            ev.append({"type": "rel", "data": {"axis": "y", "value": int(dy)}})
        if not ev:
            return
        self.cmd("input-send-event", events=ev)

    def key_2(self, down, name):
        self.cmd("input-send-event", events=[
            {"type": "btn", "data": {"down": down, "button": name}}])

    def key(self, down, qcode):
        self.cmd("input-send-event", events=[
            {"type": "key", "data": {"down": down,
                                     "key": {"type": "qcode", "data": qcode}}}])

    def screendump(self, target):
        if os.path.exists(target):
            os.unlink(target)
        a = self.cmd("screendump", filename=target)
        alt = -1
        eq = 0
        bis = time.time() + 20
        while time.time() < bis:
            if os.path.exists(target):
                n = os.path.getsize(target)
                if n == alt and n > 0:
                    eq += 1
                    if eq >= 3:
                        return True
                else:
                    eq = 0
                alt = n
            time.sleep(0.1)
        return "error" not in a


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        return 2
    sock = sys.argv[1]
    secs = float(sys.argv[2])
    hz = float(sys.argv[3])
    opt = {"breite": "3424", "hoehe": "1440", "klick_ms": "2000",
           "klickfeld": "", "tasten": "0", "shot": "", "heim": "1"}
    for a in sys.argv[4:]:
        k, _, v = a.partition("=")
        opt[k] = v
    W = int(opt["breite"])
    H = int(opt["hoehe"])
    klick_ms = int(opt["klick_ms"])
    field = None
    if opt["klickfeld"]:
        field = tuple(int(x) for x in opt["klickfeld"].split(","))

    s = verbinden(sock)
    if s is None:
        print("mouse: no QMP at %s" % sock)
        return 1
    q = Qmp(s)

    px, py = W // 2, H // 2
    if opt["heim"] == "1":
        for _ in range(80):
            q.rel(-120, -120)
            time.sleep(0.010)
        time.sleep(0.3)
        px, py = 0, 0

    ax = W / 2 - 40
    ay = H / 2 - 40
    cx = W / 2
    cy = H / 2
    Tx = 7.0
    Ty = 17.0
    n_soll = int(secs * hz)
    dt = 1.0 / hz
    sent = 0
    klicks = 0
    klick_bottom = False
    klick_seit = 0.0
    naechster_klick = klick_ms / 1000.0
    t0 = time.perf_counter()
    for i in range(n_soll):
        t = i * dt
        soll = t0 + t
        now = time.perf_counter()
        if soll > now:
            time.sleep(soll - now)
        tx = cx + ax * math.sin(2 * math.pi * t / Tx)
        ty = cy + ay * math.sin(2 * math.pi * t / Ty)
        dx = int(round(tx - px))
        dy = int(round(ty - py))
        dx = max(-4, min(4, dx))
        dy = max(-4, min(4, dy))
        if dx or dy:
            q.rel(dx, dy)
            px += dx
            py += dy
            sent += 1
        if klick_bottom and t - klick_seit >= 0.040:
            q.key_2(False, "left")
            klick_bottom = False
        if not klick_bottom and t >= naechster_klick:
            in_ = True
            if field is not None:
                in_ = field[0] <= px < field[2] and field[1] <= py < field[3]
            if in_:
                q.key_2(True, "left")
                klick_bottom = True
                klick_seit = t
                klicks += 1
                naechster_klick = t + klick_ms / 1000.0
    if klick_bottom:
        time.sleep(0.05)
        q.key_2(False, "left")
    dur = time.perf_counter() - t0
    rate = sent / dur if dur > 0 else 0

    keys = int(opt["tasten"])
    for k in range(keys):
        qc = chr(ord("a") + (k % 26))
        q.key(True, qc)
        time.sleep(0.025)
        q.key(False, qc)
        time.sleep(0.025)

    time.sleep(1.0)
    shot_ok = None
    if opt["shot"]:
        shot_ok = q.screendump(opt["shot"])
    print("maus: bewegungen=%d dauer_s=%.1f rate_hz=%.0f klicks=%d tasten=%d "
          "zeiger=%d,%d shot=%s" % (sent, dur, rate, klicks, keys,
                                    px, py, shot_ok))
    return 0


if __name__ == "__main__":
    sys.exit(main())
