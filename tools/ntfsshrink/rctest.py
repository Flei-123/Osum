#!/usr/bin/env python3
import os, random, subprocess, sys, zlib

D, FIRNC, EXE_NAME = sys.argv[1], sys.argv[2], sys.argv[3]
LIB = sys.argv[4] if len(sys.argv) > 4 else None
exe = os.path.join(D, EXE_NAME)
env = dict(os.environ)
if LIB:
    env["FIRNLIB"] = LIB
r = subprocess.run([FIRNC, "-o", exe, "tools/ntfsshrink/rcunit.fi"], capture_output=True, env=env)
if r.returncode != 0:
    print(r.stdout.decode()[:600], r.stderr.decode()[:600]); sys.exit(1)
QUICK = os.environ.get("RC_QUICK") == "1"
IMG = os.path.join(D, EXE_NAME + ".img")


def call(*args):
    o = subprocess.run([exe] + [str(a) for a in args], capture_output=True, timeout=60)
    res = {}
    for line in o.stdout.decode().split("\n"):
        if "=" in line:
            k, v = line.split("=", 1)
            res[k] = v
    if "code" not in res:
        raise RuntimeError("no code: %r %r" % (args[:3], o.stderr[:200]))
    return res


def fail(msg):
    print("FAIL", msg); sys.exit(1)


def enc_run(length, delta, sparse, lb=None, ob=None):
    if lb is None:
        lb = max(1, (length.bit_length() + 8) // 8)
    lbytes = length.to_bytes(lb, "little")
    if sparse:
        return bytes([lb]) + lbytes
    if ob is None:
        ob = 1
        while not (-(1 << (8 * ob - 1)) <= delta < (1 << (8 * ob - 1))):
            ob += 1
    return bytes([lb | (ob << 4)]) + lbytes + delta.to_bytes(ob, "little", signed=True)


def decode(buf):
    out, p, acc = [], 0, 0
    while p < len(buf) and buf[p] != 0:
        h = buf[p]; lb = h & 15; ob = h >> 4
        length = int.from_bytes(buf[p + 1:p + 1 + lb], "little")
        sparse = ob == 0
        if not sparse:
            acc += int.from_bytes(buf[p + 1 + lb:p + 1 + lb + ob], "little", signed=True)
        out.append({"start": p, "end": p + 1 + lb + ob, "lb": lb, "ob": ob, "len": length, "sparse": sparse,
                    "lcn": 0 if sparse else acc})
        p += 1 + lb + ob
    return out, p


def min_ob(delta):
    ob = 1
    while not (-(1 << (8 * ob - 1)) <= delta < (1 << (8 * ob - 1))):
        ob += 1
    return ob


def make_alloc_img(spc, clusters, bits):
    nbytes = (clusters + 7) // 8
    data = bytearray(nbytes)
    for i, b in enumerate(bits):
        if b:
            data[i // 8] |= 1 << (i % 8)
    nsec = (nbytes + 511) // 512
    data += bytes(nsec * 512 - len(data))
    ncl = (nsec + spc - 1) // spc
    parts, left = [], ncl
    while left > 0:
        n = min(left, random.randint(1, max(1, ncl // 2 + 1)))
        parts.append(n); left -= n
    img = bytearray(b"\xAA" * (spc * 512 * 4))
    runs, lcn_prev, vcn = [], 0, 0
    padded = bytes(data) + bytes(ncl * spc * 512 - len(data))
    for n in parts:
        img += b"\xAA" * (spc * 512 * 2)
        lcn = len(img) // (spc * 512)
        img += padded[vcn * spc * 512:(vcn + n) * spc * 512]
        runs.append(enc_run(n, lcn - lcn_prev, False)); lcn_prev = lcn
        vcn += n
    img += b"\xAA" * (spc * 512 * 2)
    return bytes(img), (b"".join(runs) + b"\0").hex(), len(img) // (spc * 512), lcn_prev


def bitmap_from_img(img, rl, spc, nbytes):
    runs, _ = decode(bytes.fromhex(rl))
    out = bytearray()
    for r in runs:
        out += img[r["lcn"] * spc * 512:(r["lcn"] + r["len"]) * spc * 512]
    return out


def gen_bits(C):
    mode = random.choice(["dense", "carved", "carved", "sparse", "empty"])
    bits = [1] * C
    if mode == "empty":
        bits = [0] * C
    elif mode == "sparse":
        bits = [1 if random.random() < 0.02 else 0 for _ in range(C)]
    elif mode == "dense":
        bits = [0 if random.random() < 0.05 else 1 for _ in range(C)]
    else:
        pos = 0
        while pos < C:
            pos += random.randint(0, 3000)
            n = random.choice([1, 2, 7, 8, 9, 63, 64, 300, 4095, 4096, 4097, 9000])
            for i in range(pos, min(C, pos + n)):
                bits[i] = 0
            pos += n + 1
    return bits


def model_find(bits, limit, ln):
    run, start = 0, 0
    for i in range(limit):
        if bits[i]:
            run = 0
        else:
            if run == 0:
                start = i
            run += 1
            if run >= ln:
                return start
    return None


def alloc_tests(count, check_set):
    n_find = n_set = 0
    for it in range(count):
        spc = random.choice([1, 2, 8])
        C = random.choice([9000, 12345, 20000, 33000])
        bits = gen_bits(C)
        img, rl, _, _ = make_alloc_img(spc, C, bits)
        open(IMG, "wb").write(img)
        nbytes = (C + 7) // 8
        first_free = next((i for i, b in enumerate(bits) if not b), C)
        runs_free, cur = [], 0
        for b in bits + [1]:
            if b:
                if cur: runs_free.append(cur)
                cur = 0
            else:
                cur += 1
        maxrun = max(runs_free) if runs_free else 0
        for _ in range(12):
            limit = random.choice([C, C, random.randint(1, C), (random.randint(1, C) // 8) * 8, 8, 4096])
            ln = random.choice([1, 2, 3, 8, 9, 16, 64, 100, 4096, 4097, maxrun, maxrun + 1, random.randint(1, 5000)])
            ln = max(1, min(ln, limit))
            hint = random.choice([0, first_free if first_free <= limit else 0])
            exp = model_find(bits, limit, ln)
            g = call("f", IMG, rl, spc, C, limit, ln, hint)
            if exp is None:
                if g["code"] != "9":
                    fail("find: want code 9 no space got %r (spc=%d C=%d limit=%d len=%d)" % (g, spc, C, limit, ln))
            elif g["code"] != "0" or int(g["res"]) != exp:
                fail("find: want %d got %r (spc=%d C=%d limit=%d len=%d hint=%d)" % (exp, g, spc, C, limit, ln, hint))
            n_find += 1
        if call("f", IMG, rl, spc, C, C + 1, 1, 0)["code"] != "10" or call("f", IMG, rl, spc, C, 10, 0, 0)["code"] != "10" \
                or call("f", IMG, rl, spc, C, 10, 11, 0)["code"] != "10" or call("f", IMG, rl, spc, C, 10, 1, 11)["code"] != "10":
            fail("find range errors")
        for _ in range(8):
            frm = random.randint(0, C - 1)
            ln = random.choice([1, 3, 8, 9, 100, 4096, 5000, C - frm])
            ln = min(ln, C - frm)
            exp_cnt = sum(bits[frm:frm + ln])
            g = call("c", IMG, rl, spc, C, frm, ln)
            if g["code"] != "0" or int(g["count"]) != exp_cnt or int(g["all_set"]) != (1 if exp_cnt == ln else 0) \
                    or int(g["all_clear"]) != (1 if exp_cnt == 0 else 0):
                fail("count: want %d got %r (from=%d len=%d)" % (exp_cnt, g, frm, ln))
            n_set += 1
        if call("c", IMG, rl, spc, C, C - 1, 2)["code"] != "10":
            fail("count range error")
        if check_set:
            before = open(IMG, "rb").read()
            for _ in range(4):
                frm = random.randint(0, C - 1)
                ln = min(random.choice([1, 5, 8, 17, 4096, 4100, 7000]), C - frm)
                on = random.choice([0, 1])
                for i in range(frm, frm + ln):
                    bits[i] = on
                g = call("s", IMG, rl, spc, C, frm, ln, on)
                if g["code"] != "0":
                    fail("set: %r" % g)
                after = open(IMG, "rb").read()
                got_bm = bitmap_from_img(after, rl, spc, nbytes)
                exp_bm = bytearray(bitmap_from_img(before, rl, spc, nbytes))
                for i in range(frm, frm + ln):
                    if on: exp_bm[i // 8] |= 1 << (i % 8)
                    else: exp_bm[i // 8] &= 255 - (1 << (i % 8))
                if got_bm != exp_bm:
                    fail("set: bitmap bytes differ (from=%d len=%d on=%d spc=%d)" % (frm, ln, on, spc))
                runs, _ = decode(bytes.fromhex(rl))
                mapped = set()
                for rr in runs:
                    for s in range(rr["lcn"] * spc, (rr["lcn"] + rr["len"]) * spc):
                        mapped.add(s)
                for s in range(len(after) // 512):
                    if s not in mapped and after[s * 512:(s + 1) * 512] != before[s * 512:(s + 1) * 512]:
                        fail("set: wrote outside the bitmap, sector %d" % s)
                before = after
                g2 = call("s", IMG, rl, spc, C, frm, ln, on)
                if open(IMG, "rb").read() != after:
                    fail("set: not idempotent")
            if call("s", IMG, rl, spc, C, C - 1, 2, 1)["code"] != "10":
                fail("set range error")
    return n_find, n_set


def rl_bytes(runs, alen):
    b = b"".join(runs) + b"\0"
    return b + bytes(max(0, alen - len(b)))


def patch_case(runs, alen, k, new_lcn):
    raw = rl_bytes(runs, alen)
    dec, term = decode(raw)
    g = call("p", IMG, raw.hex(), alen, k, new_lcn)
    rlout = bytes(int(x) for x in g["rl"].split(",") if x != "")
    if k >= len(dec):
        if g["code"] != "5":
            fail("patch: k out of range want 5 got %r" % g)
        return "range"
    run = dec[k]
    nxt = next((d for d in dec[k + 1:] if not d["sparse"]), None)
    if run["sparse"] or new_lcn == 0:
        if g["code"] != "15":
            fail("patch: sparse/zero target want 15 got %r k=%d runs=%s" % (g, k, raw.hex()))
        if rlout[:alen] != raw[:alen]:
            fail("patch: refused case changed the runlist")
        return "refused"
    prev = 0
    for d in dec[:k]:
        if not d["sparse"]:
            prev = d["lcn"]
    new = bytearray()
    new += enc_run(run["len"], new_lcn - prev, False, lb=run["lb"])
    mid_end = nxt["start"] if nxt else term
    new += raw[run["end"]:mid_end]
    after_next = nxt["end"] if nxt else term
    if nxt:
        new += enc_run(nxt["len"], nxt["lcn"] - new_lcn, False, lb=nxt["lb"])
    new += raw[after_next:term + 1]
    old_len = term + 1 - run["start"]
    win = max(len(new), old_len)
    if run["start"] + len(new) > alen or win > 376:
        if g["code"] != "15":
            fail("patch: want 15 got %r (new=%d old=%d win=%d alen=%d)" % (g, len(new), old_len, win, alen))
        if rlout[:alen] != raw[:alen]:
            fail("patch: refused case changed the runlist")
        return "refused"
    if g["code"] != "0":
        fail("patch: want 0 got %r runs=%s k=%d lcn=%d" % (g, raw.hex(), k, new_lcn))
    want = bytearray(raw)
    want[run["start"]:run["start"] + win] = bytes(new) + bytes(win - len(new))
    if rlout[:alen] != bytes(want):
        fail("patch: bytes differ\n got  %s\n want %s" % (rlout[:alen].hex(), bytes(want).hex()))
    if rlout[alen:] != bytes(len(rlout) - alen):
        fail("patch: bytes beyond the attribute changed")
    if int(g["off"]) != run["start"] or int(g["len"]) != win:
        fail("patch: window %r want off=%d len=%d" % (g, run["start"], win))
    out, _ = decode(rlout)
    exp = [dict(d) for d in dec]
    exp[k]["lcn"] = new_lcn
    if len(out) != len(exp):
        fail("patch: run count changed")
    for a, b in zip(out, exp):
        if (a["len"], a["lcn"], a["sparse"]) != (b["len"], b["lcn"], b["sparse"]):
            fail("patch: decoded runs differ %r %r" % (a, b))
    if out[k]["ob"] != min_ob(new_lcn - prev):
        fail("patch: offset width of run k not minimal")
    if nxt:
        j = dec.index(nxt)
        if out[j]["ob"] != min_ob(nxt["lcn"] - new_lcn):
            fail("patch: offset width of next run not minimal")
    return "ok"


def gen_runs(n):
    runs, lcn = [], 0
    for _ in range(n):
        length = random.choice([1, 5, 127, 128, 255, 256, 40000, 1 << 20, 1 << 33])
        extra = random.choice([None, None, None, 8])
        lb = None
        if extra and length < (1 << 40):
            lb = max(1, (length.bit_length() + 8) // 8) + random.choice([0, 1])
        if random.random() < 0.2:
            runs.append(enc_run(length, 0, True, lb=lb))
        else:
            tgt = random.choice([4, 100, 128, 5000, 40000, 70000, 1 << 20, 1 << 30, 5 << 33, lcn + 1, lcn + 127, max(1, lcn - 128)])
            runs.append(enc_run(length, tgt - lcn, False, lb=lb)); lcn = tgt
    return runs


def patch_tests(count):
    stats = {"ok": 0, "refused": 0, "range": 0}
    for _ in range(count):
        runs = gen_runs(random.randint(1, 7))
        used = sum(len(x) for x in runs) + 1
        alen = random.choice([used, used + 1, used + 3, used + 8, used + 24, ((used + 7) // 8) * 8 + 8])
        k = random.randint(0, len(runs))
        new_lcn = random.choice([1, 2, 127, 128, 129, 5000, 40000, 40001, 1 << 20, 1 << 31, (1 << 31) + 1, 7 << 33, random.randint(1, 1 << 40)])
        stats[patch_case(runs, alen, k, new_lcn)] += 1
    for base in (0, 1000, 70000):
        for delta in (127, 128, -128, -129, 32767, 32768, -32768, -32769, 8388607, 8388608, -8388608, -8388609, 1, -1):
            tgt = base + delta
            if tgt <= 0:
                continue
            runs = [enc_run(5, base if base else 3, False), enc_run(9, 7, False, ob=1), enc_run(4, 50, True), enc_run(3, 1, False)]
            if base == 0:
                base_run = runs[0]
                dec, _ = decode(bytes(base_run) + b"\0")
                runs[0] = enc_run(5, dec[0]["lcn"], False)
                tgt = dec[0]["lcn"] + delta
                if tgt <= 0:
                    continue
            stats[patch_case(runs, sum(len(x) for x in runs) + 12, 1, tgt)] += 1
    for nruns, wide in ((125, 0), (125, 1), (125, 2), (126, 0)):
        runs = [enc_run(5, 10, False, lb=1, ob=1)] + [enc_run(5, 1, False, lb=1, ob=1) for _ in range(nruns - 1)]
        for i in range(wide):
            runs[-1 - i] = enc_run(300, 1, False, lb=2, ob=1)
        alen = sum(len(x) for x in runs) + 1 + 20
        stats[patch_case(runs, alen, 0, 11)] += 1
    return stats


def journal_sector(state, ver=1, plen=0, patch=b"", crc_ok=True, magic=b"OSNTRLC1"):
    s = bytearray(512)
    s[0:8] = magic
    s[8:12] = ver.to_bytes(4, "little"); s[12:16] = state.to_bytes(4, "little")
    s[16:24] = (1234605616436508552).to_bytes(8, "little"); s[24:32] = (77).to_bytes(8, "little")
    s[32:40] = (5).to_bytes(8, "little"); s[44:48] = (200).to_bytes(4, "little"); s[48:52] = plen.to_bytes(4, "little")
    s[128:128 + len(patch)] = patch
    c = zlib.crc32(bytes(s[:508]))
    s[508:512] = (c if crc_ok else c ^ 1).to_bytes(4, "little")
    return bytes(s)


def journal_tests(count):
    S = 40
    n = 0
    for _ in range(count):
        boot = bytes(random.randrange(256) for _ in range(512))
        img = bytearray(boot + bytes(512 * 60))
        img[S * 512:(S + 1) * 512] = boot
        open(IMG, "wb").write(img)
        g = call("j", IMG, "r", S)
        if g["code"] != "0" or g["present"] != "0":
            fail("journal: plain boot sector must read as absent: %r" % g)
        plen = random.choice([1, 2, 17, 100, 375, 376])
        patch = bytes(random.randrange(256) for _ in range(plen))
        st = random.choice([1, 2]); rec_no = random.randint(0, 5000); src = random.randint(1, 1 << 40)
        dst = random.randint(1, 1 << 40); ln = random.randint(1, 1 << 30); poff = random.randint(0, 900)
        g = call("j", IMG, "w", S, st, rec_no, src, dst, ln, poff, patch.hex())
        if g["code"] != "0" or g["jslot"] != "1":
            fail("journal write: %r" % g)
        raw = open(IMG, "rb").read()
        if raw[:S * 512] != bytes(img[:S * 512]) or raw[(S + 1) * 512:] != bytes(img[(S + 1) * 512:]):
            fail("journal write touched a sector other than rel S")
        sec = raw[S * 512:(S + 1) * 512]
        if sec[:8] != b"OSNTRLC1" or int.from_bytes(sec[508:], "little") != zlib.crc32(sec[:508]):
            fail("journal sector layout / crc")
        g = call("j", IMG, "r", S)
        want = {"code": "0", "present": "1", "state": str(st), "serial": "1234605616436508552", "old_s": str(S),
                "rec_no": str(rec_no), "src": str(src), "dst": str(dst), "len": str(ln), "patch_off": str(poff),
                "patch_len": str(plen)}
        for k, v in want.items():
            if g.get(k) != v:
                fail("journal read %s: want %s got %r" % (k, v, g.get(k)))
        if bytes(int(x) for x in g["patch"].split(",") if x != "") != patch:
            fail("journal patch bytes")
        for pos in random.sample(range(8, 512), 6):
            bad = bytearray(sec); bad[pos] ^= 1 << random.randrange(8)
            im2 = bytearray(raw); im2[S * 512:(S + 1) * 512] = bad
            open(IMG, "wb").write(im2)
            g = call("j", IMG, "r", S)
            if g["code"] != "5" or g["present"] != "0":
                fail("journal: bit flip at %d must give code 5: %r" % (pos, g))
        bad = bytearray(sec); bad[random.randrange(8)] ^= 4
        im2 = bytearray(raw); im2[S * 512:(S + 1) * 512] = bad
        open(IMG, "wb").write(im2)
        g = call("j", IMG, "r", S)
        if g["code"] != "0" or g["present"] != "0":
            fail("journal: damaged magic must read as absent: %r" % g)
        for name, sector in (("state 0", journal_sector(0)), ("state 4", journal_sector(4)), ("version 2", journal_sector(1, ver=2)),
                             ("patch len 377", journal_sector(1, plen=377)), ("bad crc", journal_sector(1, crc_ok=False))):
            im2 = bytearray(raw); im2[S * 512:(S + 1) * 512] = sector
            open(IMG, "wb").write(im2)
            g = call("j", IMG, "r", S)
            if g["code"] != "5":
                fail("journal: %s must give code 5: %r" % (name, g))
        im2 = bytearray(raw)
        open(IMG, "wb").write(im2)
        g = call("j", IMG, "c", S)
        raw2 = open(IMG, "rb").read()
        if g["code"] != "0" or g["jslot"] != "0" or raw2[S * 512:(S + 1) * 512] != raw2[:512]:
            fail("journal close: backup boot slot must equal the primary boot sector: %r" % g)
        g = call("j", IMG, "r", S)
        if g["present"] != "0":
            fail("journal close: slot still reads as journal")
        n += 1
    return n


random.seed(int(os.environ.get("RC_SEED", "1998")))
open(IMG, "wb").write(bytes(1024))
what = os.environ.get("RC_ONLY", "abj")
msg = []
if "a" in what:
    f, s = alloc_tests(4 if QUICK else 40, True)
    msg.append("balloc: %d find + %d count cases and set/clear/idempotence equal to the bit model" % (f, s))
if "b" in what:
    st = patch_tests(60 if QUICK else 1500)
    msg.append("mpatch: %d patched, %d refused, %d out of range, all equal to the re-encoding model" % (st["ok"], st["refused"], st["range"]))
if "j" in what:
    n = journal_tests(2 if QUICK else 25)
    msg.append("rjournal: %d round trips, bit flips and format violations rejected, close restores the boot slot" % n)
print(" | ".join(msg))
