#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import math
import sys

import numpy as np
from scipy import stats

CHI_LOW = 0.001
CHI_HIGH = 0.999
MONOBIT_Z = 4.0
RUNS_Z = 4.0
SERIAL_R = 0.005
ENTROPY_MIN = 7.999
MIN_SAMPLE = 262144
BLOCK = 64


def read_sample(path):
    out = bytearray()
    with open(path, "rb") as f:
        for line in f:
            if line.startswith(b"RND ") and not line.startswith((b"RND getrandom", b"RND wrote")):
                try:
                    out += bytes.fromhex(line[4:].strip().decode("ascii"))
                except ValueError:
                    pass
    return bytes(out)


def battery(data):
    a = np.frombuffer(data, dtype=np.uint8)
    n = len(a)
    res = {}
    counts = np.bincount(a, minlength=256)
    chi, p = stats.chisquare(counts)
    res["chi2"] = (chi, p, CHI_LOW < p < CHI_HIGH)
    bits = np.unpackbits(a)
    ones = int(bits.sum())
    z = (2.0 * ones - len(bits)) / math.sqrt(len(bits))
    res["monobit"] = (ones / len(bits), z, abs(z) < MONOBIT_Z)
    runs = 1 + int(np.count_nonzero(bits[1:] != bits[:-1]))
    total = len(bits)
    n1 = ones
    n0 = total - n1
    mu = 2.0 * n1 * n0 / total + 1
    var = max((mu - 1) * (mu - 2) / (total - 1), 1e-9)
    zr = (runs - mu) / math.sqrt(var)
    res["runs"] = (runs, zr, abs(zr) < RUNS_Z)
    af = a.astype(np.float64)
    r = float(np.corrcoef(af[:-1], af[1:])[0, 1])
    res["serial_corr"] = (r, 0.0, abs(r) < SERIAL_R)
    pr = counts / n
    ent = float(-(pr[pr > 0] * np.log2(pr[pr > 0])).sum())
    res["entropy"] = (ent, 0.0, ent > ENTROPY_MIN)
    blocks = [data[i:i + BLOCK] for i in range(0, n - BLOCK + 1, BLOCK)]
    res["no_repeats"] = (len(blocks) - len(set(blocks)), 0.0, len(set(blocks)) == len(blocks))
    return res


def passed(res):
    return all(v[2] for v in res.values())


def show(res):
    for k, v in res.items():
        print("   %-12s %s %s" % (k, " ".join("%.6g" % x for x in v[:2]), "ok" if v[2] else "REJECTED"))


def self_check():
    rng = np.random.default_rng(1)
    good = rng.integers(0, 256, 524288, dtype=np.uint8).tobytes()
    bad = {
        "constant": bytes([0x5A]) * 524288,
        "counter": bytes(i & 255 for i in range(524288)),
        "biased": bytes(int(x) for x in np.where(rng.random(524288) < 0.3, 0, rng.integers(0, 256, 524288))),
        "lcg16": b"".join(((i * 25173 + 13849) & 0xFFFF).to_bytes(2, "little") for i in range(262144)),
        "repeating-block": rng.integers(0, 256, 64, dtype=np.uint8).tobytes() * 8192,
    }
    ok = passed(battery(good))
    print("%s battery accepts a numpy random sample" % ("OK  " if ok else "FAIL"))
    fails = 0 if ok else 1
    for name, data in bad.items():
        rejected = not passed(battery(data))
        print("%s battery rejects the %s stream" % ("OK  " if rejected else "FAIL", name))
        if not rejected:
            fails += 1
    return fails


def main():
    mode = sys.argv[1]
    if mode == "selfcheck":
        sys.exit(1 if self_check() else 0)
    data = read_sample(sys.argv[2])
    label = sys.argv[3] if len(sys.argv) > 3 else sys.argv[2]
    if len(data) < MIN_SAMPLE:
        print("FAIL %s: only %d octets of sample (need %d)" % (label, len(data), MIN_SAMPLE))
        sys.exit(1)
    res = battery(data)
    good = passed(res)
    if mode == "expect-pass":
        print("%s %s: %d octets, %s" % ("OK  " if good else "FAIL", label, len(data), "all tests passed" if good else "REJECTED"))
        if not good:
            show(res)
        sys.exit(0 if good else 1)
    if mode == "expect-fail":
        print("%s %s: %d octets, the battery %s" % ("OK  " if not good else "FAIL", label, len(data), "rejects it" if not good else "ACCEPTS IT"))
        if good:
            show(res)
        sys.exit(0 if not good else 1)
    if mode == "differ":
        other = read_sample(sys.argv[4])
        same = data[:4096] == other[:4096]
        print("%s %s: first 4096 octets of two boots %s" % ("OK  " if not same else "FAIL", label, "differ" if not same else "are IDENTICAL"))
        sys.exit(1 if same else 0)
    sys.exit(2)


main()
