#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import argparse
import array
import math
import sys
import wave


def goertzel(seg, fr, f):
    k = 2 * math.pi * f / fr
    re = im = 0.0
    for i, v in enumerate(seg):
        re += v * math.cos(k * i)
        im += v * math.sin(k * i)
    return math.hypot(re, im) / max(1, len(seg))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("datei")
    ap.add_argument("--hz", type=int, default=440)
    ap.add_argument("--zweite", type=int, default=0)
    ap.add_argument("--rate", type=int, default=0)
    ap.add_argument("--schwelle", type=int, default=64)
    ap.add_argument("--nur-rms", action="store_true")
    ap.add_argument("--luecke-still", action="store_true")
    ap.add_argument("--von-ms", type=int, default=0)
    ap.add_argument("--bis-ms", type=int, default=0)
    a = ap.parse_args()

    try:
        w = wave.open(a.datei)
    except Exception as e:                       # noqa: BLE001
        print("fehler=1 grund=%s" % e)
        return 1
    fr = w.getframerate()
    nch = w.getnchannels()
    n = w.getnframes()
    d = array.array("h")
    d.frombytes(w.readframes(n))
    links = list(d[0::nch]) if nch else []
    print("rate=%d kanaele=%d frames=%d" % (fr, nch, n))
    if a.rate and fr != a.rate:
        print("ratefehler=1")
    nz = [i for i, v in enumerate(links) if v != 0]
    if not nz:
        print("nutz=0 gaps=0 still=0 luecke_rest=0 max=0 min=0 rms=0 peak_hz=0 p1=0 p2=0")
        return 0
    lo, hi = nz[0], nz[-1]
    if a.von_ms or a.bis_ms:
        v = lo + a.von_ms * fr // 1000
        b = lo + a.bis_ms * fr // 1000 if a.bis_ms else hi + 1
        lo, hi = max(lo, v), min(hi, b - 1)
        if hi <= lo:
            print("fensterfehler=1")
            return 1
    seg = links[lo:hi + 1]
    print("nutz=%d ab=%d" % (len(seg), lo))

    luecken = []
    lauf = 0
    start = 0
    for i, v in enumerate(seg):
        if v == 0:
            if lauf == 0:
                start = i
            lauf += 1
        else:
            if lauf > a.schwelle:
                luecken.append((start, lauf))
            lauf = 0
    still = sum(x[1] for x in luecken)
    print("gaps=%d still=%d" % (len(luecken), still))

    rest = 0
    if a.luecke_still and luecken:
        for i in range(len(luecken) - 1):
            e = luecken[i][0] + luecken[i][1]
            s2 = luecken[i + 1][0]
            if s2 - e < a.schwelle:
                rest = max(rest, max(abs(x) for x in seg[e:s2]) if s2 > e else 0)
    print("luecke_rest=%d" % rest)

    print("max=%d min=%d" % (max(seg), min(seg)))
    q = sum(v * v for v in seg) // max(1, len(seg))
    print("rms=%d" % int(math.isqrt(q)))
    if a.nur_rms:
        return 0

    anf = 0
    if luecken:
        anf = luecken[-1][0] + luecken[-1][1]
        if anf + 8192 > len(seg):
            anf = 0
    stueck = seg[anf:anf + 8192]
    if len(stueck) < 2048:
        stueck = seg[:8192]
    best = (0, 0.0)
    f = max(20, a.hz - 40)
    while f <= a.hz + 40:
        p = goertzel(stueck, fr, f)
        if p > best[1]:
            best = (f, p)
        f += 1
    print("peak_hz=%d peak_p=%d" % (best[0], int(best[1])))
    print("p1=%d" % int(goertzel(stueck, fr, a.hz)))
    if a.zweite:
        print("p2=%d" % int(goertzel(stueck, fr, a.zweite)))
        mitte = (a.hz + a.zweite) // 2
        print("pmitte=%d" % int(goertzel(stueck, fr, mitte)))
    else:
        print("p2=0")
    return 0


if __name__ == "__main__":
    sys.exit(main())
