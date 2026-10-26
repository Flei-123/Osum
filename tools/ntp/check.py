#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import random
import struct
import subprocess
import sys

ORACLE = sys.argv[1]
NTP_UNIX = 2208988800
ERA = 1 << 32
NS = 10**9
rnd = random.Random(20261026)
fails = 0
checks = 0


def ok(cond, what):
    global fails, checks
    checks += 1
    print(("OK   " if cond else "FAIL ") + what)
    if not cond:
        fails += 1


def run(lines):
    out = subprocess.run([ORACLE], input="\n".join(lines) + "\n", capture_output=True,
                         text=True, timeout=120).stdout.split("\n")
    return [l.split() for l in out[:len(lines)]]


def model_unix(secs, pivot):
    best, bd = 0, None
    for era in range(3):
        total = secs + era * ERA
        if total >= NTP_UNIX:
            cand = total - NTP_UNIX
            d = abs(cand - pivot)
            if bd is None or d < bd:
                best, bd = cand, d
    return best


def ts_pack(unix_ns):
    secs = unix_ns // NS + NTP_UNIX
    frac = ((unix_ns % NS) << 32) // NS
    return struct.pack(">II", secs % ERA, frac)


def ts_ns(raw, pivot):
    secs, frac = struct.unpack(">II", raw)
    return model_unix(secs, pivot) * NS + ((frac * NS) >> 32)


def short_ns(v):
    return (v >> 16) * NS + (((v & 0xFFFF) * NS) >> 16)


def make_packet(nonce, rx_ns, tx_ns, li=0, vn=4, mode=4, stratum=2, refid=b"\x7f\x00\x00\x01",
                root_delay=0x00010000, root_disp=0x00010000, zero_tx=False):
    b0 = (li << 6) | (vn << 3) | mode
    pkt = bytearray(48)
    pkt[0] = b0
    pkt[1] = stratum
    pkt[4:8] = struct.pack(">I", root_delay)
    pkt[8:12] = struct.pack(">I", root_disp)
    pkt[12:16] = refid
    pkt[24:32] = nonce
    pkt[32:40] = ts_pack(rx_ns)
    pkt[40:48] = b"\0" * 8 if zero_tx else ts_pack(tx_ns)
    return pkt


def model_parse(pkt, nonce, pivot):
    if len(pkt) < 48:
        return 1, None
    b0 = pkt[0]
    if (b0 & 7) != 4:
        return 2, None
    vn = (b0 >> 3) & 7
    if vn < 3 or vn > 4:
        return 3, None
    if bytes(pkt[24:32]) != bytes(nonce):
        return 5, None
    stratum = pkt[1]
    if stratum == 0:
        ref = bytes(pkt[12:16])
        if ref == b"RATE":
            return 9, None
        if ref in (b"DENY", b"RSTR"):
            return 10, None
        return 11, None
    li = b0 >> 6
    if li == 3 or stratum > 15:
        return 4, None
    tx = ts_ns(bytes(pkt[40:48]), pivot)
    rx = ts_ns(bytes(pkt[32:40]), pivot)
    if bytes(pkt[40:48]) == b"\0" * 8:
        return 6, None
    if tx < rx:
        return 7, None
    rd = struct.unpack(">I", bytes(pkt[4:8]))[0]
    rdisp = struct.unpack(">I", bytes(pkt[8:12]))[0]
    root = short_ns(rd) // 2 + short_ns(rdisp)
    if root > 1500000000:
        return 8, None
    return 0, (stratum, li, root, rx, tx)


PIVOT = 1790812800
NOW_NS = (PIVOT + 86400 * 20) * NS + 123456789


def tdiv(a, b):
    q = abs(a) // abs(b)
    return q if (a >= 0) == (b >= 0) else -q


def main():
    cases = []
    exp = []
    for _ in range(3000):
        secs = rnd.randrange(0, ERA)
        pivot = rnd.choice([PIVOT, PIVOT + rnd.randrange(0, 10**9), 4102444800, 2208988800 + 1])
        cases.append("u %d %d" % (secs, pivot))
        exp.append([str(model_unix(secs, pivot))])
    got = run(cases)
    ok(got == exp, "unix_secs_of: %d random (era pick) equal the model" % len(cases))
    for secs, pivot, want in [
        (((PIVOT + NTP_UNIX) % ERA), PIVOT, PIVOT),
        (((2040 - 1970) * 365 * 86400 + NTP_UNIX) % ERA, PIVOT, None),
    ]:
        pass
    y2036 = 2085978496
    got = run(["u %d %d" % ((y2036 + NTP_UNIX + 100) % ERA, PIVOT)])
    ok(got[0][0] == str(y2036 + 100), "NTP era 1: seconds past the 2036 rollover read as 2036+")

    cases, exp = [], []
    for _ in range(3000):
        t1 = rnd.randrange(PIVOT, PIVOT + 10**8) * NS + rnd.randrange(NS)
        up = rnd.randrange(-10**11, 10**11)
        d1 = rnd.randrange(0, 5 * 10**8)
        d2 = rnd.randrange(0, 5 * 10**8)
        hold = rnd.randrange(0, 10**7)
        t2 = t1 + d1 + up
        t3 = t2 + hold
        t4 = t3 - up + d2
        cases.append("o %d %d %d %d" % (t1, t2, t3, t4))
        off = tdiv((t2 - t1) + (t3 - t4), 2)
        dly = max(0, (t4 - t1) - (t3 - t2))
        exp.append([str(off), str(dly)])
    ok(run(cases) == exp, "offset/delay: %d random 4-timestamp sets equal the model" % len(cases))
    got = run(["o 1000 1010 1012 1030"])
    ok(got[0] == ["-4", "28"], "offset/delay: hand example theta=-4 delta=28")

    nonce = bytes(rnd.randrange(256) for _ in range(8))
    base_rx = NOW_NS + 5000
    base_tx = base_rx + 2000
    variants = {
        "good": (make_packet(nonce, base_rx, base_tx), nonce),
        "good v3": (make_packet(nonce, base_rx, base_tx, vn=3), nonce),
        "short 47": (make_packet(nonce, base_rx, base_tx)[:47], nonce),
        "mode 3": (make_packet(nonce, base_rx, base_tx, mode=3), nonce),
        "mode 5": (make_packet(nonce, base_rx, base_tx, mode=5), nonce),
        "version 2": (make_packet(nonce, base_rx, base_tx, vn=2), nonce),
        "version 5": (make_packet(nonce, base_rx, base_tx, vn=5), nonce),
        "spoofed nonce": (make_packet(bytes(8), base_rx, base_tx), nonce),
        "kod RATE": (make_packet(nonce, base_rx, base_tx, stratum=0, refid=b"RATE"), nonce),
        "kod DENY": (make_packet(nonce, base_rx, base_tx, stratum=0, refid=b"DENY"), nonce),
        "kod RSTR": (make_packet(nonce, base_rx, base_tx, stratum=0, refid=b"RSTR"), nonce),
        "kod other": (make_packet(nonce, base_rx, base_tx, stratum=0, refid=b"INIT"), nonce),
        "kod with wrong nonce is no kod": (make_packet(bytes(8), base_rx, base_tx, stratum=0, refid=b"RATE"), nonce),
        "li 3": (make_packet(nonce, base_rx, base_tx, li=3), nonce),
        "stratum 16": (make_packet(nonce, base_rx, base_tx, stratum=16), nonce),
        "zero transmit": (make_packet(nonce, base_rx, base_tx, zero_tx=True), nonce),
        "transmit before receive": (make_packet(nonce, base_rx, base_rx - 1), nonce),
        "root distance 2 s": (make_packet(nonce, base_rx, base_tx, root_disp=0x00020000), nonce),
        "root distance just ok": (make_packet(nonce, base_rx, base_tx, root_delay=0, root_disp=0x00017000), nonce),
    }
    for name, (pkt, nn) in variants.items():
        want, fields = model_parse(pkt, nn, PIVOT)
        got = run(["p %d %s %s" % (PIVOT, bytes(pkt).hex(), bytes(nn).hex())])[0]
        good = int(got[0]) == want
        if good and fields is not None:
            stratum, li, root, rx, tx = fields
            good = got[1:] == [str(stratum), str(li), str(root), str(rx), str(tx)]
        ok(good, "parse: %s -> status %d" % (name, want))
    expected = {"good": 0, "short 47": 1, "mode 3": 2, "version 2": 3, "spoofed nonce": 5,
                "kod RATE": 9, "kod DENY": 10, "kod RSTR": 10, "kod other": 11,
                "kod with wrong nonce is no kod": 5, "li 3": 4, "stratum 16": 4, "zero transmit": 6,
                "transmit before receive": 7, "root distance 2 s": 8}
    for name, st in expected.items():
        pkt, nn = variants[name]
        ok(model_parse(pkt, nn, PIVOT)[0] == st, "model sanity: %s is status %d" % (name, st))

    cases, exp = [], []
    for _ in range(1500):
        nn = bytes(rnd.randrange(256) for _ in range(8))
        pkt = bytearray(make_packet(nn, NOW_NS + rnd.randrange(10**6), NOW_NS + 2 * 10**6 + rnd.randrange(10**6),
                                    li=rnd.choice([0, 0, 1, 2, 3]), vn=rnd.choice([3, 4, 4, 4, 2]),
                                    mode=rnd.choice([4, 4, 4, 3]), stratum=rnd.choice([1, 2, 3, 15, 16, 0]),
                                    root_delay=rnd.randrange(0, 0x40000), root_disp=rnd.randrange(0, 0x40000),
                                    refid=rnd.choice([b"RATE", b"DENY", b"XXXX", b"GPS\0"])))
        if rnd.random() < 0.15:
            pkt[24 + rnd.randrange(8)] ^= 1 << rnd.randrange(8)
        if rnd.random() < 0.1:
            pkt = pkt[:rnd.randrange(30, 48)]
        want, fields = model_parse(pkt, nn, PIVOT)
        cases.append("p %d %s %s" % (PIVOT, bytes(pkt).hex(), nn.hex()))
        if fields is None:
            exp.append(("s", want))
        else:
            exp.append(("f", want, fields))
    got = run(cases)
    bad = 0
    for g, e in zip(got, exp):
        if int(g[0]) != e[1]:
            bad += 1
        elif e[0] == "f":
            stratum, li, root, rx, tx = e[2]
            if g[1:] != [str(stratum), str(li), str(root), str(rx), str(tx)]:
                bad += 1
    ok(bad == 0, "parse: %d random mutated packets equal the model (%d differ)" % (len(cases), bad))

    def model_select(samples, min_agree, tol):
        n = len(samples)
        if n == 0 or n < min_agree or n > 8:
            return (1, 0, 0, 0, 0)
        s = sorted(samples, key=lambda x: x[0])
        bs, bl = 0, 0
        for i in range(n):
            j = i
            while j + 1 < n and s[j + 1][0] - s[i][0] <= tol:
                j += 1
            if j - i + 1 > bl:
                bl, bs = j - i + 1, i
        if bl < min_agree or bl * 2 <= n:
            return (2, 0, 0, 0, 0)
        mid = bs + bl // 2
        med = s[mid][0]
        if bl % 2 == 0:
            med = tdiv(s[mid - 1][0] + s[mid][0], 2)
        dl = min(x[1] for x in s[bs:bs + bl])
        return (0, med, dl, bl, s[bs + bl - 1][0] - s[bs][0])

    cases, exp = [], []
    for _ in range(4000):
        n = rnd.randrange(0, 9)
        center = rnd.randrange(-10**10, 10**10)
        samples = []
        for _ in range(n):
            if rnd.random() < 0.25:
                o = rnd.randrange(-10**13, 10**13)
            else:
                o = center + rnd.randrange(-6 * 10**8, 6 * 10**8)
            samples.append((o, rnd.randrange(0, 3 * 10**8)))
        ma = rnd.choice([1, 2, 2, 3])
        tol = rnd.choice([10**9, 5 * 10**8, 10**7])
        cases.append("s %d %d %d %s" % (ma, tol, n, " ".join("%d %d" % x for x in samples)))
        exp.append([str(v) for v in model_select(samples, ma, tol)])
    ok(run(cases) == exp, "select: %d random sample sets equal the model" % len(cases))

    def sel(samples, ma=2, tol=10**9):
        return run(["s %d %d %d %s" % (ma, tol, len(samples), " ".join("%d %d" % x for x in samples))])[0]

    g = sel([(5 * 10**7, 10**7), (6 * 10**7, 2 * 10**7), (86400 * NS, 10**7)])
    ok(g[0] == "0" and g[3] == "2" and abs(int(g[1]) - 55 * 10**6) <= 1, "select: one liar among three is outvoted")
    g = sel([(0, 10**7), (86400 * NS, 10**7)])
    ok(g[0] == "2", "select: two sources a day apart give NO quorum")
    g = sel([(0, 10**7), (10**6, 10**7), (86400 * NS, 10**7), (86400 * NS + 10**6, 10**7)])
    ok(g[0] == "2", "select: two against two give NO quorum")
    g = sel([(0, 10**7)])
    ok(g[0] == "1", "select: a single source is too few when two must agree")
    g = sel([(123 * NS, 10**7)], ma=1)
    ok(g[0] == "0" and g[1] == str(123 * NS), "select: a single source passes when one is enough")

    for off, synced, act in [
        (0, 0, 0), (999999, 1, 0), (-999999, 1, 0), (1000000, 1, 1), (-1000000, 0, 1),
        (128 * 10**6, 1, 1), (128 * 10**6 + 1, 1, 2), (-(128 * 10**6 + 1), 0, 2),
        (10**12, 1, 2), (10**12 + 1, 1, 3), (-(10**12 + 1), 1, 3),
        (10**12 + 1, 0, 2), (86400 * 365 * NS, 0, 2), (86400 * 365 * NS, 1, 3),
    ]:
        got = run(["d %d %d" % (off, synced)])[0]
        ok(got == [str(act)], "decide: offset %d ns synced=%d -> action %d" % (off, synced, act))
    got = run(["r %d" % i for i in (1, 6, 7, 12, 13, 99)])
    ok([g[0] for g in got] == ["10", "10", "30", "30", "300", "300"], "retry_delay_s: 10/30/300 schedule")
    got = run(["k %d" % i for i in (0, 10, 64, 1000, 2000, 3600)])
    ok([g[0] for g in got] == ["64", "64", "128", "2000", "3600", "3600"], "kod_delay_s: doubles within 64..3600")

    print("RESULT %s (%d checks, %d failed)" % ("OK" if fails == 0 else "FAIL", checks, fails))
    return 1 if fails else 0


sys.exit(main())
