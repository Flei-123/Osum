import hashlib
import os
import random

try:
    import cbor2
except ImportError:
    cbor2 = None

NOW = 1700000000000


def enc(x):
    return cbor2.dumps(x, canonical=True)


def login(i, c, m, title, origins, user, pw, notes, pwc):
    r = {0: i, 1: 1, 2: c, 3: m, 11: origins}
    for k, v in ((10, title), (12, user), (13, pw), (14, notes)):
        if v:
            r[k] = v
    if pwc:
        r[16] = pwc
    return r


def store(recs):
    return enc(sorted(recs, key=lambda r: r[0]))


def ver(r):
    return (r[3], 1 if r.get(4) else 0, enc(r))


def merge_ref(a, b):
    out = {r[0]: r for r in a}
    for r in b:
        cur = out.get(r[0])
        if cur is None or ver(r) > ver(cur):
            out[r[0]] = r
    return list(out.values())


def rid(n):
    return hashlib.sha256(b"id%d" % n).digest()[:16]


def rec_checks(r):
    vt, w = r.vt, r.write
    i1, i2, i3 = rid(1), rid(2), rid(3)
    L1 = login(i1, 10, 20, "T1", ["https://a.example", "https://b.example"], "alice", "pw1", "n1", 15)
    N1 = {0: i2, 1: 3, 2: 5, 3: 6, 10: "note", 14: "body"}
    res = vt("mklogin", r.p("l1"), i1.hex(), 10, 20, "T1", "https://a.example,https://b.example", "alice", "pw1", "n1", 15)
    r.check("rec: login bytes == cbor2", res.returncode == 0 and r.read("l1") == enc(L1))
    res = vt("mknote", r.p("n1"), i2.hex(), 5, 6, "note", "body")
    r.check("rec: note bytes == cbor2", res.returncode == 0 and r.read("n1") == enc(N1))
    res = vt("mkmeta", r.p("m1"), 7, "aabb", 0)
    r.check("rec: meta bytes == cbor2", res.returncode == 0 and r.read("m1") == enc({0: bytes(16), 1: 9, 2: 7, 3: 7, 40: 1, 41: bytes.fromhex("aabb")}))
    cred, priv, uh = bytes(range(32)), bytes(range(1, 33)), b"\x01\x02\x03"
    P1 = {0: i3, 1: 2, 2: 1, 3: 2, 20: "rp.example", 21: "RP", 22: uh, 23: "u", 24: "U", 25: cred, 26: -7, 27: priv, 28: b"\x04" * 65, 29: 3, 30: 3, 31: 1, 32: 2, 33: 9, 34: "https://rp.example"}
    res = vt("mkpasskey", r.p("p1"), i3.hex(), 1, 2, "rp.example", "RP", uh.hex(), "u", "U", cred.hex(), -7, priv.hex(), (b"\x04" * 65).hex(), 3, 3, 1, 2, 9, "https://rp.example")
    r.check("rec: passkey bytes == cbor2", res.returncode == 0 and r.read("p1") == enc(P1))

    cur = "-"
    for name in ("p1", "l1", "n1"):
        res = vt("sput", cur if cur == "-" else r.p(cur), r.p("s_" + name), r.p(name))
        r.check("rec: sput " + name, res.returncode == 0)
        cur = "s_" + name
    r.check("rec: store sorted == cbor2", r.read(cur) == store([L1, N1, P1]))
    r.check("rec: scheck ok", vt("scheck", r.p(cur)).returncode == 0)
    r.write("unsorted", enc(sorted([L1, N1], key=lambda x: x[0], reverse=True)))
    r.check("rec: unsorted store refused (26)", vt("scheck", r.p("unsorted")).returncode == 26)
    L1u = dict(L1)
    L1u[99] = "future"
    r.write("unk", enc([L1u]))
    r.check("rec: unknown key accepted", vt("scheck", r.p("unk")).returncode == 0)

    L2 = {**L1, 3: 30, 13: "pw2"}
    r.write("l2", enc(L2))
    res = vt("sput", r.p(cur), r.p("s_l2"), r.p("l2"))
    r.check("rec: newer record replaces", res.returncode == 0 and r.read("s_l2") == store([L2, N1, P1]))
    r.check("rec: stale record refused (24)", vt("sput", r.p("s_l2"), r.p("s_x"), r.p("l1")).returncode == 24)
    dupc = {**P1, 0: rid(4), 3: 9}
    r.write("dup", enc(dupc))
    r.check("rec: duplicate credential id refused (22)", vt("sput", r.p("s_l2"), r.p("s_x"), r.p("dup")).returncode == 22)

    res = vt("sdel", r.p("s_l2"), r.p("s_d"), i1.hex(), 25)
    T1 = {0: i1, 1: 1, 2: 10, 3: 31, 4: True}
    r.check("rec: delete == tombstone", res.returncode == 0 and r.read("s_d") == store([T1, N1, P1]))
    res = vt("spurge", r.p("s_d"), r.p("s_pu"), 31 + 7776000000, 7776000000)
    r.check("rec: purge drops old tombstone", res.returncode == 0 and r.read("s_pu") == store([N1, P1]))
    res = vt("spurge", r.p("s_d"), r.p("s_pk"), 31 + 7776000000 - 1, 7776000000)
    r.check("rec: purge keeps young tombstone", res.returncode == 0 and r.read("s_pk") == store([T1, N1, P1]))

    rng = random.Random(7)
    ok = True
    for n in range(12):
        ids = [rid(100 + k) for k in range(6)]

        def pick():
            recs = []
            for i in ids:
                if rng.random() < 0.7:
                    m = rng.choice([5, 6, 7])
                    rec = login(i, 1, m, "t%d" % rng.randint(0, 3), ["https://x.example"], "u", "p%d" % rng.randint(0, 3), "", 0)
                    if rng.random() < 0.3:
                        rec = {0: i, 1: 1, 2: 1, 3: m, 4: True}
                    recs.append(rec)
            return recs
        a, b = pick(), pick()
        r.write("ma", store(a))
        r.write("mb", store(b))
        r1 = vt("smerge", r.p("ma"), r.p("mb"), r.p("mo1"))
        r2 = vt("smerge", r.p("mb"), r.p("ma"), r.p("mo2"))
        want = store(merge_ref(a, b))
        ok = ok and r1.returncode == 0 and r2.returncode == 0 and r.read("mo1") == want and r.read("mo2") == want
    r.check("rec: merge == python reference, commutative (12 random)", ok)


def v1_seal(pw, plain, kdf, field, lanes, argon):
    salt, nonce = os.urandom(16), os.urandom(12)
    head = b"CERTUSTRESOR" + bytes([1, kdf, 1, lanes]) + field.to_bytes(4, "big") + salt
    import hmac as hm
    from cryptography.hazmat.primitives.ciphers import Cipher, algorithms
    if kdf == 1:
        mk = hashlib.pbkdf2_hmac("sha256", pw, salt, field, 32)
    else:
        mk = argon(pw, salt, field & 255, field >> 8, lanes)
    sub = lambda l: hm.new(mk, l, hashlib.sha256).digest()
    ek, ak, chk = sub(b"certus tresor v1 enc"), sub(b"certus tresor v1 mac"), sub(b"certus tresor v1 check")
    head += chk + nonce + len(plain).to_bytes(4, "big")
    c = Cipher(algorithms.ChaCha20(ek, (1).to_bytes(4, "little") + nonce), mode=None).encryptor()
    body = head + c.update(plain) + c.finalize()
    return body + hm.new(ak, body, hashlib.sha256).digest()


def v1_checks(r, argon):
    vt = r.vt
    lines = b"https://a.example\talice\ts3cret\n!https://never.example\nhttps://b.example\tbob\tp\\tw\\nd\nhttps://a.example\talice\tnewer\n"
    pw = "hunter22 ünï"
    for kdf, field, lanes, name in ((1, 200000, 0, "pb"), (2, (64 << 8) | 2, 2, "ar")):
        r.write("v1_" + name, v1_seal(pw.encode(), lines, kdf, field, lanes, argon))
        res = vt("v1open", r.p("v1_" + name), pw, r.p("v1p_" + name))
        r.check("v1: firn opens python-made kdf%d" % kdf, res.returncode == 0 and r.read("v1p_" + name) == lines)
        r.check("v1: wrong password gives CRED (6) kdf%d" % kdf, vt("v1open", r.p("v1_" + name), "nope", r.p("x")).returncode == 6)
    raw = bytearray(r.read("v1_pb"))
    raw[-1] ^= 1
    r.write("v1_tag", bytes(raw))
    r.check("v1: flipped tag byte gives TAG (7)", vt("v1open", r.p("v1_tag"), pw, r.p("x")).returncode == 7)
    raw = bytearray(r.read("v1_pb"))
    raw[16] = 255
    r.write("v1_it", bytes(raw))
    r.check("v1: huge iteration count refused (10)", vt("v1open", r.p("v1_it"), pw, r.p("x")).returncode == 10)
    r.write("v1_cut", r.read("v1_pb")[:-5])
    r.check("v1: truncated file gives LENGTH (3)", vt("v1open", r.p("v1_cut"), pw, r.p("x")).returncode == 3)

    res = vt("v1import", r.p("v1_pb"), pw, r.p("v1store"), NOW)
    r.check("v1: import stats 2 added 1 replaced 0 skipped 1 blocked", res.returncode == 0 and res.stdout.decode().split() == ["2", "1", "0", "1"])
    if cbor2 is None:
        return
    recs = cbor2.loads(r.read("v1store"))

    def lid(o, u):
        return hashlib.sha256(b"vault v1 line" + o.encode() + u.encode()).digest()[:16]
    want = [login(lid("https://a.example", ""), NOW, NOW + 3, "https://a.example", ["https://a.example"], "alice", "newer", "", 0),
            login(lid("https://b.example", ""), NOW, NOW + 2, "https://b.example", ["https://b.example"], "bob", "p\tw\nd", "", 0)]
    r.check("v1: imported store has expected logins", cbor2.loads(r.read("v1store")) != [] and len(recs) == 2 and {x[13] for x in recs} == {"newer", "p\tw\nd"})

    fields = [("id1", "Carol", "https://f.example", "carol", "pw-one", "note", "1700000000"), ("id2", "", "https://g.example", "dave", "pw-two", "", "")]
    blob = len(fields).to_bytes(4, "big")
    for f in fields:
        for x in f:
            b = x.encode()
            blob += len(b).to_bytes(2, "big") + b
    r.write("v1_f", v1_seal(pw.encode(), blob, 1, 1000, 0, argon))
    res = vt("v1import", r.p("v1_f"), pw, r.p("v1fstore"), NOW)
    fr = cbor2.loads(r.read("v1fstore")) if res.returncode == 0 else []
    byuser = {x.get(12): x for x in fr}
    r.check("v1: field format import (title, note, seconds->ms, now default)",
            len(fr) == 2 and byuser["carol"][10] == "Carol" and byuser["carol"][14] == "note"
            and byuser["carol"][2] == 1700000000000 and byuser["dave"][2] == NOW)

    res = vt("v1migrate", r.p("v1_pb"), pw, r.p("v2m.vlt"), 64, 1, 1, NOW, 0, 0)
    r.check("v1: migrate rc", res.returncode == 0)
    return fr
