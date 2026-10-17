#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/tablet/qmp.py -- drive a QEMU usb-tablet through QMP input-send-event.

    qmp.py <qmp-socket> <step>...

steps:  abs:X,Y          absolute position, 0..32767 on both axes
        down:left|right  press a button       up:left|right  release it
        wheel:up|down[:N] N wheel notches (default 1)
        sleep:SECONDS
"""
import json
import socket
import sys
import time


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    s = None
    for _ in range(300):
        # a fresh socket per attempt: re-connecting a socket whose connect() failed gives EINVAL later
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            s.connect(sys.argv[1])
            break
        except OSError:
            s.close()
            s = None
            time.sleep(0.1)
    if s is None:
        print("qmp: cannot connect")
        return 1
    buf = b""

    def readline():
        nonlocal buf
        while b"\n" not in buf:
            chunk = s.recv(65536)
            if not chunk:
                raise EOFError("qmp closed")
            buf += chunk
        line, _, buf = buf.partition(b"\n")
        return line.decode()

    readline()  # greeting

    def call(cmd, **args):
        s.sendall((json.dumps({"execute": cmd, "arguments": args}) + "\n").encode())
        while True:
            r = json.loads(readline())
            if "return" in r or "error" in r:
                return r

    call("qmp_capabilities")
    for st in sys.argv[2:]:
        k, _, v = st.partition(":")
        ev = []
        if k == "abs":
            x, y = v.split(",")
            ev = [{"type": "abs", "data": {"axis": "x", "value": int(x)}},
                  {"type": "abs", "data": {"axis": "y", "value": int(y)}}]
        elif k in ("down", "up"):
            ev = [{"type": "btn", "data": {"down": k == "down", "button": v}}]
        elif k == "wheel":
            d, _, n = v.partition(":")
            for _ in range(int(n or 1)):
                for down in (True, False):
                    r = call("input-send-event", events=[{"type": "btn",
                             "data": {"down": down, "button": "wheel-" + d}}])
                    if "error" in r:
                        print("qmp error:", r["error"])
            continue
        elif k == "sleep":
            time.sleep(float(v))
            continue
        r = call("input-send-event", events=ev)
        if "error" in r:
            print("qmp error:", r["error"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
