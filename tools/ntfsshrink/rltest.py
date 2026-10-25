#!/usr/bin/env python3
import os, random, subprocess, sys

D, FIRNC = sys.argv[1], sys.argv[2]
exe = os.path.join(D, "rlunit")
r = subprocess.run([FIRNC, "-o", exe, "tools/ntfsshrink/rlunit.fi"], capture_output=True)
if r.returncode != 0:
    print(r.stdout.decode()[:600], r.stderr.decode()[:600]); sys.exit(1)

def enc_run(length, delta, sparse):
    lb = max(1, (length.bit_length() + 8) // 8)
    lbytes = length.to_bytes(lb, "little")
    if sparse:
        return bytes([lb]) + lbytes
    ob = 1
    while not (-(1 << (8 * ob - 1)) <= delta < (1 << (8 * ob - 1))):
        ob += 1
    return bytes([lb | (ob << 4)]) + lbytes + delta.to_bytes(ob, "little", signed=True)

def model(runs):
    out, vcn, lcn = [], 0, 0
    for length, delta, sparse in runs:
        if not sparse:
            lcn += delta
        out.append((vcn, 0 if sparse else lcn, length, 1 if sparse else 0))
        vcn += length
    return out, vcn

def call(buf):
    o = subprocess.run([exe, buf.hex()], capture_output=True).stdout.decode().strip().split("\n")
    return o[:-1], o[-1]

random.seed(7)
cases = 0
for _ in range(300):
    runs, lcn = [], 0
    for _ in range(random.randint(1, 6)):
        length = random.choice([1, 7, 255, 256, 40000, 1 << 20, 1 << 33])
        if random.random() < 0.25:
            runs.append((length, 0, True))
        else:
            tgt = random.choice([4, 100, 70000, 1 << 20, 1 << 30, 5 << 33])
            runs.append((length, tgt - lcn, False)); lcn = tgt
    buf = b"".join(enc_run(*x) for x in runs) + b"\0"
    exp, tot = model(runs)
    got, tail = call(buf)
    want = ["%d %d %d %d" % e for e in exp]
    if got != want or tail != "bad=0 total=%d" % tot:
        print("MISMATCH", buf.hex(), got, want, tail); sys.exit(1)
    cases += 1

bad = {
    "length bytes zero": bytes([0x10, 0x01, 0]),
    "zero length": bytes([0x11, 0x00, 0x04, 0]),
    "length top bit": bytes([0x11, 0x80, 0x04, 0]),
    "truncated length": bytes([0x21, 0x05]),
    "truncated offset": bytes([0x21, 0x05, 0x00]),
    "offset bytes 9": bytes([0x91] + [1] + [0] * 9),
    "negative lcn": bytes([0x11, 0x05, 0xf0, 0]),
}
for name, buf in bad.items():
    got, tail = call(buf)
    if "bad=1" not in tail or tail.endswith("total=%d" % 5) and name == "x":
        print("BAD NOT REJECTED", name, got, tail); sys.exit(1)
    cases += 1
got, tail = call(bytes([0x11, 0x03, 0x04, 0x11, 0x02, 0xf0, 0x00]))
if tail != "bad=1 total=0" or len(got) != 1:
    print("second run negative:", got, tail); sys.exit(1)
print("runlist decoder: %d cases equal to the model, 7 broken lists rejected" % (cases))
