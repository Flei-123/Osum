#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/netui/model.py -- independent Python model of lib/netui/netui.fi (LW-5) and the check driver.

usage: python3 -I tools/netui/model.py <oracle binary>
Prints "  OK    ..." / "  FAIL  ..." lines and "RESULT pass=N fail=M". The model is written from the rules in the
task (bars thresholds, sort order, password limits), not from the Firn source.
"""
import random
import subprocess
import sys

passed = 0
failed = 0


def check(name, cond):
    global passed, failed
    if cond:
        passed += 1
        print("  OK    " + name)
    else:
        failed += 1
        print("  FAIL  " + name)


def run(binpath, lines):
    p = subprocess.run([binpath], input="\n".join(lines) + "\n", capture_output=True, text=True, timeout=60)
    return p.stdout.splitlines()


# ---- model -----------------------------------------------------------------

def m_bars(r):
    if r >= 0:
        return 0
    if r >= -55:
        return 4
    if r >= -65:
        return 3
    if r >= -75:
        return 2
    if r >= -85:
        return 1
    return 0


SEC_WEAK = {0, 1, 2, 7}
SEC_PW = {1, 2, 3, 4, 5}


def m_sec(kind):
    cls = kind if 0 <= kind <= 6 else 7
    return cls, cls in SEC_WEAK, cls in SEC_PW


def m_conn(z):
    if z == 0:
        return 0
    if z == 1:
        return 1
    if z in (2, 3, 4):
        return 2
    if z in (5, 6, 7):
        return 3
    if z == 8:
        return 4
    return 5


class Model:
    def __init__(self):
        self.items = []   # dicts in arrival order

    def add(self, ssid, rssi, kind, known):
        cls = kind if 0 <= kind <= 6 else 7
        if len(ssid) > 32:
            return False
        if len(ssid) > 0:
            for it in self.items:
                if it["cls"] == cls and it["ssid"] == ssid:
                    eff = lambda r: -127 if r >= 0 else r
                    if eff(rssi) > eff(it["rssi"]):
                        it["rssi"] = rssi
                    if known:
                        it["known"] = 1
                    return True
        if len(self.items) >= 16:
            return False
        self.items.append({"ssid": ssid, "rssi": rssi, "cls": cls, "known": 1 if known else 0, "src": len(self.items)})
        return True

    def sorted(self):
        def hidden(it):
            return len(it["ssid"]) == 0 or all(b == 0 for b in it["ssid"])
        eff = lambda r: -127 if r >= 0 else r
        # python sort is stable: arrival order breaks the remaining ties
        return sorted(self.items, key=lambda it: (hidden(it), -eff(it["rssi"]), -it["known"]))


class Pw:
    def __init__(self):
        self.buf = []

    def key(self, ch):
        if 32 <= ch <= 126:
            if len(self.buf) >= 63:
                return 6
            self.buf.append(ch)
            return 1
        if ch in (8, 127):
            if not self.buf:
                return 0
            self.buf.pop()
            return 2
        if ch in (10, 13):
            return 3 if 8 <= len(self.buf) <= 63 else 4
        if ch == 27:
            self.buf = []
            return 5
        return 0

    def state(self):
        n = len(self.buf)
        return 0 if n == 0 else (1 if n < 8 else 2)

    def line(self, pk):
        n = len(self.buf)
        return "K pk=%d n=%d st=%d miss=%d submit=%d" % (pk, n, self.state(), max(0, 8 - n), 1 if 8 <= n else 0)


def hx(b):
    return b.hex() if b else "-"


def parse_rank(line):
    f = line.split()
    return {"rank": int(f[1]), "ssid": f[2], "rssi": int(f[3]), "bars": int(f[4]), "cls": int(f[5]),
            "known": int(f[6]), "hidden": int(f[7]), "src": int(f[8])}


def main():
    binpath = sys.argv[1]
    rng = random.Random(20261021)

    # ---- bars: every dBm from +5 to -127 against the model, and the thresholds by hand
    cmds = ["b %d" % r for r in range(5, -128, -1)]
    out = run(binpath, cmds)
    ok = len(out) == len(cmds) and all(out[i] == "b %d" % m_bars(5 - i) for i in range(len(cmds)))
    check("bars: all 133 values from +5 to -127 dBm equal the model", ok)
    o = run(binpath, ["b -55", "b -56", "b -65", "b -66", "b -75", "b -76", "b -85", "b -86", "b 0"])
    check("bars: thresholds at -55/-65/-75/-85, 0 = no measurement = 0 bars",
          o == ["b 4", "b 3", "b 3", "b 2", "b 2", "b 1", "b 1", "b 0", "b 0"])

    # ---- security class
    out = run(binpath, ["s %d" % k for k in range(0, 12)])
    good = True
    for k in range(0, 12):
        c, w, pw = m_sec(k)
        good = good and out[k] == "s cls=%d weak=%d pw=%d" % (c, 1 if w else 0, 1 if pw else 0)
    check("security: kinds 0..11 (0..6 known, rest unknown = weak, no password prompt) equal the model", good)

    # ---- connection class
    out = run(binpath, ["c %d" % z for z in range(0, 14)])
    check("connection: states 0..13 map to off/scanning/connecting/keys/connected/failed (unknown = failed)",
          out == ["c %d" % m_conn(z) for z in range(0, 14)])

    # ---- list: fixed case
    A = lambda s, r, k, kn: "A %s %d %d %d" % (hx(s), r, k, kn)
    script = ["L",
              A(b"far", -80, 3, 0),          # src 0
              A(b"near", -45, 3, 0),         # src 1
              A(b"", -30, 3, 0),             # src 2 hidden: last although strongest
              A(b"mid", -60, 5, 0),          # src 3
              A(b"mid", -50, 5, 0),          # same name + kind: stronger wins, still one entry
              A(b"mid", -40, 3, 0),          # same name, other kind: a second entry (src 4)
              A(b"nosig", 0, 3, 0),          # no measurement: weakest visible
              A(b"known", -80, 3, 1),        # ties with "far" at -80: known first
              A(b"\x00\x00", -20, 0, 0),     # all-zero name: hidden
              "P"]
    out = run(binpath, script)
    mdl = Model()
    for s, r, k, kn in [(b"far", -80, 3, 0), (b"near", -45, 3, 0), (b"", -30, 3, 0), (b"mid", -60, 5, 0),
                        (b"mid", -50, 5, 0), (b"mid", -40, 3, 0), (b"nosig", 0, 3, 0), (b"known", -80, 3, 1),
                        (b"\x00\x00", -20, 0, 0)]:
        mdl.add(s, r, k, kn)
    check("list: every add answers ok", out[:10] == ["L ok"] + ["A ok"] * 9)
    n = int(out[10].split()[1])
    rows = [parse_rank(l) for l in out[11:11 + n]]
    exp = mdl.sorted()
    check("list: duplicate name+kind merged (one mid at -50), 8 entries" , n == len(exp) == 8)
    check("list: order, signal, bars, class, known, hidden equal the model",
          [(r["ssid"], r["rssi"], r["bars"], r["cls"], r["known"], r["hidden"]) for r in rows] ==
          [(hx(e["ssid"]), e["rssi"], m_bars(e["rssi"]), e["cls"], e["known"], 1 if (len(e["ssid"]) == 0 or all(b == 0 for b in e["ssid"])) else 0) for e in exp])
    vis = [r for r in rows if not r["hidden"]]
    check("list: visible networks sorted by signal, strongest first",
          all((-127 if a["rssi"] >= 0 else a["rssi"]) >= (-127 if b["rssi"] >= 0 else b["rssi"]) for a, b in zip(vis, vis[1:])))
    check("list: hidden names come after every visible one", all(r["hidden"] for r in rows[len(vis):]) and len(vis) < len(rows))
    names = [r["ssid"] for r in rows]
    check("list: known network ahead of an unknown one on the same signal (-80)",
          names.index(hx(b"known")) < names.index(hx(b"far")))
    check("list: 'no measurement' is the weakest visible entry", rows[len(vis) - 1]["ssid"] == hx(b"nosig"))

    # ---- list: limits
    script = ["L"] + [A(b"net%02d" % i, -50 - i, 3, 0) for i in range(17)] + [A(b"x" * 33, -50, 3, 0)]
    out = run(binpath, script)
    check("list: the 17th network is refused (full), a 33-octet name is refused",
          out[1:17] == ["A ok"] * 16 and out[17] == "A full" and out[18] in ("A full", "A bad"))

    # ---- list: random fuzz against the model (re-sorting after every add must not change the result)
    bad = 0
    for run_no in range(40):
        mdl = Model()
        script = ["L"]
        for _ in range(rng.randint(1, 14)):
            ssid = bytes(rng.choice(b"abcxyz") for _ in range(rng.choice([0, 1, 2, 3])))
            rssi = rng.choice([0, -30, -50, -50, -60, -70, -80, -90, rng.randint(-110, -20)])
            kind = rng.randint(0, 7)
            known = rng.randint(0, 1)
            mdl.add(ssid, rssi, kind, known)
            script.append(A(ssid, rssi, kind, known))
            if rng.random() < 0.3:
                script.append("P")   # sorting in the middle must not disturb later adds
        script.append("P")
        out = run(binpath, script)
        # the last "P" block: find it
        idx = max(i for i, l in enumerate(out) if l.startswith("P "))
        cnt = int(out[idx].split()[1])
        rws = [parse_rank(l) for l in out[idx + 1:idx + 1 + cnt]]
        exp = mdl.sorted()
        got = [(r["ssid"], r["rssi"], r["cls"], r["known"]) for r in rws]
        want = [(hx(e["ssid"]), e["rssi"], e["cls"], e["known"]) for e in exp]
        if got != want:
            bad += 1
    check("list: 40 random scans (0..14 results, duplicates, hidden, unknown kinds) equal the model", bad == 0)

    # ---- password
    keys = [ord(c) for c in "abcdefg"]
    out = run(binpath, ["W"] + ["K %d" % c for c in keys] + ["K 13", "K 104", "K 13", "Q"])
    pw = Pw()
    exp = ["W ok"]
    for c in keys:
        exp.append(pw.line(pw.key(c)))
    exp.append(pw.line(pw.key(13)))
    exp.append(pw.line(pw.key(104)))
    exp.append(pw.line(pw.key(13)))
    exp.append("Q " + hx(bytes(pw.buf)))
    check("password: 7 chars -> Enter rejected, 8th char -> Enter submits", out == exp)
    check("password: the model agrees the submit path ends in pk=3", exp[-2].startswith("K pk=3") and "submit=1" in exp[-2])

    script = ["W"] + ["K 97"] * 63 + ["K 98", "K 98", "K 13", "K 8", "K 8", "K 13", "Q"]
    out = run(binpath, script)
    pw = Pw()
    exp = ["W ok"]
    for c in [97] * 63 + [98, 98, 13, 8, 8, 13]:
        exp.append(pw.line(pw.key(c)))
    exp.append("Q " + hx(bytes(pw.buf)))
    check("password: 63 characters is the maximum (64th refused pk=6), Enter still submits at 63, delete works", out == exp)

    script = ["W", "K 97", "K 98", "K 27", "K 8", "K 1", "K 200", "K 31", "K 127", "K 126", "K 32", "Q"]
    out = run(binpath, script)
    pw = Pw()
    exp = ["W ok"]
    for c in [97, 98, 27, 8, 1, 200, 31, 127, 126, 32]:
        exp.append(pw.line(pw.key(c)))
    exp.append("Q " + hx(bytes(pw.buf)))
    check("password: Escape clears, backspace on empty and control bytes ignored, 126 and 32 accepted", out == exp)

    bad = 0
    for run_no in range(60):
        seq = [rng.choice([rng.randint(32, 126)] * 6 + [8, 127, 13, 10, 27, 0, 200, 31]) for _ in range(rng.randint(1, 90))]
        out = run(binpath, ["W"] + ["K %d" % c for c in seq] + ["Q"])
        pw = Pw()
        exp = ["W ok"] + [pw.line(pw.key(c)) for c in seq] + ["Q " + hx(bytes(pw.buf))]
        if out != exp:
            bad += 1
    check("password: 60 random key sequences (up to 90 keys, controls, overflow) equal the model", bad == 0)

    print("RESULT pass=%d fail=%d" % (passed, failed))
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
