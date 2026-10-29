# SPDX-License-Identifier: GPL-2.0-only
import json
import socket
import sys
import time

qmp_path, serial, settle = sys.argv[1], sys.argv[2], float(sys.argv[3])
PASSWORD = "startkennwort"


def text():
    try:
        return open(serial, "rb").read().decode("latin-1")
    except OSError:
        return ""


def wait_for(needle, timeout):
    end = time.time() + timeout
    while time.time() < end:
        t = text()
        if needle in t:
            return True
        if "EXCEPTION" in t:
            return False
        time.sleep(1)
    return False


class Qmp:
    def __init__(self, path):
        for _ in range(100):
            try:
                self.s = socket.socket(socket.AF_UNIX)
                self.s.connect(path)
                break
            except OSError:
                time.sleep(0.2)
        self.f = self.s.makefile("rw")
        self.f.readline()
        self.call("qmp_capabilities")

    def call(self, cmd, args=None):
        msg = {"execute": cmd}
        if args:
            msg["arguments"] = args
        self.f.write(json.dumps(msg) + "\n")
        self.f.flush()
        while True:
            r = json.loads(self.f.readline())
            if "return" in r or "error" in r:
                return r

    def key(self, k, pause=0.12):
        self.call("human-monitor-command", {"command-line": "sendkey " + k})
        time.sleep(pause)


def main():
    q = Qmp(qmp_path)
    ready = wait_for("glogin: bereit", 240)
    print("login-screen", 1 if ready else 0)
    if not ready:
        return
    time.sleep(2)
    for c in PASSWORD:
        q.key(c)
    q.key("ret", 0.3)
    ok = wait_for("glogin: angemeldet als", 90)
    print("logged-in", 1 if ok else 0)
    if not ok:
        return
    end = time.time() + settle
    while time.time() < end and "EXCEPTION" not in text():
        time.sleep(1)
    print("settled", 1)


main()
