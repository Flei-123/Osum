#!/usr/bin/env python3
import hashlib
import os
import subprocess
import sys
import tempfile

from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

try:
    from argon2.low_level import Type, hash_secret_raw
except ImportError:
    hash_secret_raw = None

M64 = (1 << 64) - 1
MAGIC = b"VAULT2\0\0"
SLOT_PW, SLOT_LOGIN, SLOT_RECOVERY = 1, 2, 4
ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"


class Det:
    def __init__(self, seed, ascii_only):
        self.x = seed or 88172645463325252
        self.ascii_only = ascii_only

    def byte(self):
        x = self.x
        x ^= (x << 13) & M64
        x ^= x >> 7
        x ^= (x << 17) & M64
        self.x = x
        b = (x >> 24) & 255
        return 97 + b % 26 if self.ascii_only else b

    def take(self, n):
        return bytes(self.byte() for _ in range(n))


def be(v, n):
    return v.to_bytes(n, "big")


def argon(pw, salt, passes, kib, lanes):
    if hash_secret_raw is not None:
        return hash_secret_raw(pw, salt, passes, kib, lanes, 32, Type.ID)
    out = subprocess.run(
        ["/usr/bin/argon2", salt.decode("ascii"), "-id", "-t", str(passes),
         "-k", str(kib), "-p", str(lanes), "-l", "32", "-r"],
        input=pw, capture_output=True, check=True).stdout.strip()
    return bytes.fromhex(out.decode())


def hkdf(salt, ikm, info):
    return HKDF(algorithm=hashes.SHA256(), length=32, salt=salt, info=info).derive(ikm)


def pw_slot(kind, vault_id, vk, pw, kib, passes, lanes, salt, nonce):
    head = bytes([kind, 0]) + be(88, 2) + bytes([2, passes, lanes, 0]) + be(kib, 4) + salt
    kek = argon(pw, salt, passes, kib, lanes)
    wrapped = ChaCha20Poly1305(kek).encrypt(nonce, vk, vault_id + head)
    return head + nonce + wrapped


def key_slot(kind, vault_id, vk, key, nonce):
    head = bytes([kind, 0]) + be(64, 2)
    label = b"vault2 recovery slot" if kind == SLOT_RECOVERY else b"vault2 device slot"
    kek = hkdf(vault_id, key, label)
    return head + nonce + ChaCha20Poly1305(kek).encrypt(nonce, vk, vault_id + head)


def build(vault_id, vk, slots, flags, revision, body, body_salt):
    head = (MAGIC + be(40 + sum(len(s) for s in slots), 2) + bytes([len(slots), flags])
            + be(len(body), 4) + vault_id + be(revision, 8) + b"".join(slots))
    aad = head + body_salt
    sub = hkdf(body_salt, vk, b"vault2 body")
    return aad + ChaCha20Poly1305(sub).encrypt(b"\0" * 12, body, aad)


def parse(img):
    assert img[:8] == MAGIC
    hl = int.from_bytes(img[8:10], "big")
    count = img[10]
    body_len = int.from_bytes(img[12:16], "big")
    assert hl + 16 + body_len + 16 == len(img)
    slots, off = [], 40
    for _ in range(count):
        ln = int.from_bytes(img[off + 2:off + 4], "big")
        slots.append(img[off:off + ln])
        off += ln
    assert off == hl
    return {"vault_id": img[16:32], "flags": img[11], "revision": int.from_bytes(img[32:40], "big"),
            "slots": slots, "head": img[:hl], "salt": img[hl:hl + 16], "hl": hl, "body_len": body_len}


def unwrap_pw(img, kind, pw):
    p = parse(img)
    for s in p["slots"]:
        if s[0] != kind:
            continue
        passes, lanes, kib = s[5], s[6], int.from_bytes(s[8:12], "big")
        kek = argon(pw, s[12:28], passes, kib, lanes)
        return ChaCha20Poly1305(kek).decrypt(s[28:40], s[40:88], p["vault_id"] + s[:28])
    raise KeyError("no slot")


def unwrap_key(img, kind, key):
    p = parse(img)
    for s in p["slots"]:
        if s[0] == kind:
            label = b"vault2 recovery slot" if kind == SLOT_RECOVERY else b"vault2 device slot"
            return ChaCha20Poly1305(hkdf(p["vault_id"], key, label)).decrypt(
                s[4:16], s[16:64], p["vault_id"] + s[:4])
    raise KeyError("no slot")


def open_body(img, vk):
    p = parse(img)
    sub = hkdf(p["salt"], vk, b"vault2 body")
    return ChaCha20Poly1305(sub).decrypt(b"\0" * 12, img[p["hl"] + 16:], img[:p["hl"] + 16])


def rec_encode(key):
    nib = hashlib.sha256(key).digest()[0] >> 4
    bits = "".join(f"{b:08b}" for b in key) + f"{nib:04b}"
    syms = [ALPHABET[int(bits[i:i + 5], 2)] for i in range(0, 260, 5)]
    return "-".join("".join(syms[i:i + 4]) for i in range(0, 52, 4))


def rec_decode(text):
    syms = [c for c in text.upper() if c not in "- "]
    assert len(syms) == 52 and all(c in ALPHABET for c in syms)
    bits = "".join(f"{ALPHABET.index(c):05b}" for c in syms)
    key = bytes(int(bits[i:i + 8], 2) for i in range(0, 256, 8))
    assert int(bits[256:], 2) == hashlib.sha256(key).digest()[0] >> 4
    return key


class Run:
    def __init__(self, tool, work):
        self.tool, self.work, self.ok, self.bad = tool, work, 0, 0

    def check(self, name, cond):
        if cond:
            self.ok += 1
        else:
            self.bad += 1
            print("  FAIL  against:", name)

    def p(self, name):
        return os.path.join(self.work, name)

    def vt(self, *args):
        return subprocess.run([self.tool] + [str(a) for a in args], capture_output=True)

    def write(self, name, data):
        with open(self.p(name), "wb") as f:
            f.write(data)

    def read(self, name):
        with open(self.p(name), "rb") as f:
            return f.read()


def det_case(r, ascii_only, seed, tag):
    body = b"vault body " + tag.encode() + bytes(range(40))
    pw = b"correct horse battery"
    kib, passes, lanes = 64, 2, 1
    r.write("body_" + tag, body)
    res = r.vt("create", r.p("c_" + tag), pw.decode(), r.p("body_" + tag), kib, passes, lanes, seed,
               1 if ascii_only else 0)
    r.check(tag + ": create rc", res.returncode == 0)
    d = Det(seed, ascii_only)
    vault_id, vk, salt, nonce, bsalt = d.take(16), d.take(32), d.take(16), d.take(12), d.take(16)
    slot = pw_slot(SLOT_PW, vault_id, vk, pw, kib, passes, lanes, salt, nonce)
    want = build(vault_id, vk, [slot], 0, 1, body, bsalt)
    got = r.read("c_" + tag)
    r.check(tag + ": create equals python build", got == want)

    d2 = Det(seed + 1, ascii_only)
    res = r.vt("addrec", r.p("c_" + tag), pw.decode(), seed + 1, 1 if ascii_only else 0)
    r.check(tag + ": addrec rc", res.returncode == 0)
    rkey, rnonce, bsalt2 = d2.take(32), d2.take(12), d2.take(16)
    r.check(tag + ": recovery text equals python", res.stdout.decode().strip() == rec_encode(rkey))
    rslot = key_slot(SLOT_RECOVERY, vault_id, vk, rkey, rnonce)
    want2 = build(vault_id, vk, [slot, rslot], 0, 2, body, bsalt2)
    r.check(tag + ": addrec equals python build", r.read("c_" + tag) == want2)
    r.check(tag + ": python opens via password", open_body(want2, unwrap_pw(want2, SLOT_PW, pw)) == body)
    r.check(tag + ": python opens via recovery", open_body(want2, unwrap_key(want2, SLOT_RECOVERY, rkey)) == body)

    nbody = b"second body " + tag.encode()
    r.write("nb_" + tag, nbody)
    d3 = Det(seed + 2, ascii_only)
    res = r.vt("update", r.p("c_" + tag), pw.decode(), r.p("nb_" + tag), seed + 2, 1 if ascii_only else 0)
    r.check(tag + ": update rc", res.returncode == 0)
    want3 = build(vault_id, vk, [slot, rslot], 0, 3, nbody, d3.take(16))
    r.check(tag + ": update equals python build", r.read("c_" + tag) == want3)

    res = r.vt("rmslot", r.p("c_" + tag), pw.decode(), SLOT_RECOVERY)
    r.check(tag + ": rmslot rc", res.returncode == 0)
    img = r.read("c_" + tag)
    p = parse(img)
    r.check(tag + ": rmslot leaves pw slot only", len(p["slots"]) == 1 and p["slots"][0][0] == SLOT_PW)
    r.check(tag + ": rmslot bumps revision", p["revision"] == 4)
    r.check(tag + ": body survives rmslot", open_body(img, unwrap_pw(img, SLOT_PW, pw)) == nbody)
    res = r.vt("openrec", r.p("c_" + tag), rec_encode(rkey), r.p("nope"))
    r.check(tag + ": removed recovery slot refused", res.returncode == 9)


def salt16():
    if hash_secret_raw is not None:
        return os.urandom(16)
    return bytes(97 + b % 26 for b in os.urandom(16))


def python_made(r):
    rnd = os.urandom
    vault_id, vk = rnd(16), rnd(32)
    pw = "pässword mit ünicode ✓".encode()
    rkey = rnd(32)
    kib, passes, lanes = 64, 1, 2
    slot = pw_slot(SLOT_PW, vault_id, vk, pw, kib, passes, lanes, salt16(), rnd(12))
    rslot = key_slot(SLOT_RECOVERY, vault_id, vk, rkey, rnd(12))
    lslot = pw_slot(SLOT_LOGIN, vault_id, vk, b"login-secret", kib, passes, lanes, salt16(), rnd(12))
    body = rnd(3000)
    img = build(vault_id, vk, [slot, lslot, rslot], 1, 7, body, rnd(16))
    r.write("py.vlt", img)
    out = r.p("py.out")
    res = r.vt("open", r.p("py.vlt"), pw.decode(), out)
    r.check("python-made opens in firn (pw, utf-8 password)", res.returncode == 0 and r.read("py.out") == body)
    res = r.vt("openlogin", r.p("py.vlt"), "login-secret", out)
    r.check("python-made opens in firn (login slot)", res.returncode == 0 and r.read("py.out") == body)
    res = r.vt("openrec", r.p("py.vlt"), rec_encode(rkey).lower().replace("-", " "), out)
    r.check("python-made opens in firn (recovery, lowercase, spaces)", res.returncode == 0 and r.read("py.out") == body)
    res = r.vt("open", r.p("py.vlt"), "wrong password", out)
    r.check("firn: wrong password gives CRED (6)", res.returncode == 6)

    fresh = r.vt("addlogin", r.p("py.vlt"), pw.decode(), "second-login", "0", "0")
    r.check("firn addlogin refuses second login slot (PARAM 11)", fresh.returncode == 11)
    res = r.vt("rmslot", r.p("py.vlt"), pw.decode(), SLOT_LOGIN)
    r.check("firn rmslot login rc", res.returncode == 0)
    res = r.vt("addlogin", r.p("py.vlt"), pw.decode(), "second-login", "77", "1")
    r.check("firn addlogin rc", res.returncode == 0)
    img = r.read("py.vlt")
    p = parse(img)
    r.check("slot order pw, recovery, login", [s[0] for s in p["slots"]] == [SLOT_PW, SLOT_RECOVERY, SLOT_LOGIN])
    r.check("flags + vault id kept", p["flags"] == 1 and p["vault_id"] == vault_id and p["revision"] == 9)
    r.check("python opens firn-edited via login",
            open_body(img, unwrap_pw(img, SLOT_LOGIN, b"second-login")) == body)
    r.check("old login password gone",
            _fails(lambda: unwrap_pw(img, SLOT_LOGIN, b"login-secret")))
    r.check("recovery still works after edits",
            open_body(img, unwrap_key(img, SLOT_RECOVERY, rkey)) == body)


def _fails(fn):
    try:
        fn()
    except Exception:
        return True
    return False


def recovery_vectors(r):
    key = bytes(range(32))
    text = rec_encode(key)
    r.check("recovery vector shape", len(text) == 64 and text.count("-") == 12)
    r.check("recovery decode roundtrip", rec_decode(text) == key)
    print("  vector 00..1f:", text)


def rotate_check(r):
    pw = b"rotate-me-pw"
    r.write("rb", b"body-bytes")
    r.vt("create", r.p("rot"), pw.decode(), r.p("rb"), 64, 1, 1, 5, 1)
    rec = r.vt("addrec", r.p("rot"), pw.decode(), 6, 1)
    rtext = rec.stdout.decode().strip()
    old = r.read("rot")
    old_vk = unwrap_pw(old, SLOT_PW, pw)
    res = r.vt("rotate", r.p("rot"), pw.decode(), 0, 7, 1, rtext)
    new = r.read("rot")
    p0, p1 = parse(old), parse(new)
    new_vk = unwrap_pw(new, SLOT_PW, pw)
    r.check("rotate: rc 0, new vk differs, same vault id", res.returncode == 0 and new_vk != old_vk and p0["vault_id"] == p1["vault_id"])
    r.check("rotate: body kept, revision up", open_body(new, new_vk) == b"body-bytes" and p1["revision"] > p0["revision"])
    r.check("rotate: recovery slot rewrapped", open_body(new, unwrap_key(new, SLOT_RECOVERY, rec_decode(rtext))) == b"body-bytes")
    r.check("rotate: old vk cannot open new body", _fails(lambda: open_body(new, old_vk)))
    res = r.vt("rotate", r.p("rot"), pw.decode(), SLOT_RECOVERY, 8, 1, "")
    after = parse(r.read("rot"))
    r.check("rotate: dropping recovery slot", res.returncode == 0 and [s[0] for s in after["slots"]] == [SLOT_PW])


def main():
    tool, work = sys.argv[1], sys.argv[2]
    r = Run(tool, work)
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import against_rec
    det_case(r, True, 11, "a")
    if hash_secret_raw is not None:
        det_case(r, False, 4242, "b")
    python_made(r)
    recovery_vectors(r)
    if against_rec.cbor2 is None:
        print("  SKIP  cbor2 missing: records, merge and v1 checks not run")
    else:
        against_rec.rec_checks(r)
        against_rec.v1_checks(r, argon)
        img = r.read("v2m.vlt")
        body = open_body(img, unwrap_pw(img, SLOT_PW, "hunter22 ünï".encode()))
        r.check("v1: migrated v2 container opens in python, store matches import", body == r.read("v1store"))
        rotate_check(r)
    print("against.py: argon2 via", "argon2-cffi" if hash_secret_raw else "/usr/bin/argon2")
    print(f"against: OK {r.ok} FAIL {r.bad}")
    return 1 if r.bad else 0


if __name__ == "__main__":
    sys.exit(main())
