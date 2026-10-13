#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/fvcrypto/vectors.py -- drive the Firn FreeViewer crypto (fvt) and
compare every answer with an independent implementation.

  python3 vectors.py <fvt-binary> [rust-vectors.json]

References: RFC 7748 / RFC 5869-style HKDF / NIST GCM through the Python
`cryptography` package, hmac+hashlib for proofs and the code, the
phc-winner-argon2 CLI (`argon2`) for Argon2id with the argon2 crate 0.5
default parameters (m=19456 KiB, t=2, p=1, v=0x13, 32 octets).
The optional JSON is the Rust-generated contract file
(freeviewer/tests/orientos-vectors.json) and is compared when present.
"""
import hashlib
import hmac
import json
import os
import random
import subprocess
import sys

from cryptography.hazmat.primitives.asymmetric.x25519 import (
    X25519PrivateKey, X25519PublicKey)
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives import hashes

FVT = sys.argv[1]
RUST = sys.argv[2] if len(sys.argv) > 2 else ""
rnd = random.Random(0xF1EE7)
ok = bad = 0


def run(*a):
    r = subprocess.run([FVT, *a], capture_output=True, text=True, timeout=120)
    return r.stdout.strip().splitlines(), r.returncode


def one(*a):
    out, rc = run(*a)
    return out[0] if out else "", rc


def chk(name, got, want):
    global ok, bad
    if got == want:
        ok += 1
    else:
        bad += 1
        print("  FAIL  %s\n        got  %s\n        want %s" % (name, got[:140], want[:140]))


def h(b):
    return b.hex() if b else "-"


def x25519_ref(sk, pk):
    return X25519PrivateKey.from_private_bytes(sk).exchange(
        X25519PublicKey.from_public_bytes(pk))


def pub_ref(sk):
    from cryptography.hazmat.primitives import serialization as s
    return X25519PrivateKey.from_private_bytes(sk).public_key().public_bytes(
        s.Encoding.Raw, s.PublicFormat.Raw)


# ---------------------------------------------------------------- X25519
rfc = [
    ("a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4",
     "e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c",
     "c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552"),
    ("4b66e9d4d1b4673c5ad22691957d6af5c11b6421e0ea01d42ca4169e7918ba0d",
     "e5210f12786811d3f4b7959d0538ae2c31dbe7106fc03c3efc4cd549c715a493",
     "95cbde9476e8907d7aade45cb4b873f88b595a68799fa152e6f8f7647aac7957"),
]
for sk, pk, want in rfc:
    chk("x25519 RFC7748 5.2", one("x25519", sk, pk)[0], want)
alice = "77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a"
bob = "5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb"
chk("x25519 RFC7748 6.1 alice pub", one("pub", alice)[0],
    "8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a")
chk("x25519 RFC7748 6.1 bob pub", one("pub", bob)[0],
    "de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f")
chk("x25519 RFC7748 6.1 shared", one("x25519", alice, "de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f")[0],
    "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742")
# low order point (all zero u) must be refused
out, rc = run("x25519", alice, "00" * 32)
chk("x25519 zero point refused", str(rc), "1")

# ------------------------------------------------- session key + code
sessions = []
for i in range(40):
    a, b = rnd.randbytes(32), rnd.randbytes(32)
    salt = rnd.randbytes(16)
    shared = x25519_ref(a, pub_ref(b))
    key = HKDF(hashes.SHA256(), 32, salt, b"freeviewer-v1 session").derive(shared)
    chk("session key #%d" % i, one("session", a.hex(), pub_ref(b).hex(), salt.hex())[0], key.hex())
    # both sides derive the same key
    chk("session key sym #%d" % i, one("session", b.hex(), pub_ref(a).hex(), salt.hex())[0], key.hex())
    d = hashlib.sha256(b"freeviewer-v1 code" + key).digest()
    code = "%04d" % (int.from_bytes(d[:4], "big") % 10000)
    chk("session code #%d" % i, one("code", key.hex())[0], code)
    sessions.append((a, b, salt, key))

# ---------------------------------------------------------- auth proof
for i in range(30):
    pwk, c, hp, salt = (rnd.randbytes(n) for n in (32, 32, 32, 16))
    want = hmac.new(pwk, b"fv-auth" + c + hp + salt, hashlib.sha256).hexdigest()
    chk("auth proof #%d" % i, one("proof", pwk.hex(), c.hex(), hp.hex(), salt.hex())[0], want)

# ------------------------------------------------------------ AES-GCM
# NIST SP 800-38D test cases 13..16 style (AES-256)
chk("gcm NIST tc13", one("gcm", "00" * 32, "00" * 12, "-", "-")[0], "530f8afbc74536b9a963b4f1c4cb738b")
chk("gcm NIST tc14", one("gcm", "00" * 32, "00" * 12, "-", "00" * 16)[0],
    "cea7403d4d606b6e074ec5d3baf39d18d0d1c8a799996bf0265b98b5d48ab919")
k15 = "feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308"
iv15 = "cafebabefacedbaddecaf888"
pt15 = ("d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72"
        "1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b391aafd255")
chk("gcm NIST tc15", one("gcm", k15, iv15, "-", pt15)[0],
    "522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa"
    "8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662898015ad"
    "b094dac5d93471bdec1a502270e3cc6c")
sizes = [0, 1, 2, 15, 16, 17, 31, 32, 33, 47, 48, 63, 64, 65, 127, 128, 255, 256, 1000, 1500,
         4096, 16384, 33333]
for n in sizes:
    key, iv, aad, pt = rnd.randbytes(32), rnd.randbytes(12), rnd.randbytes(rnd.choice([0, 1, 13, 16, 20, 64])), rnd.randbytes(n)
    want = AESGCM(key).encrypt(iv, pt, aad or None).hex()
    chk("gcm random len %d" % n, one("gcm", key.hex(), iv.hex(), h(aad), h(pt))[0], want)

# ----------------------------------------------- Cipher frame, both ways


def py_frame(key, dirbyte, ctr, pt):
    nonce = bytes([dirbyte, 0, 0, 0]) + ctr.to_bytes(8, "big")
    return bytes([0x10]) + nonce + AESGCM(key).encrypt(nonce, pt, None)


key = rnd.randbytes(32)
msgs = [rnd.randbytes(n) for n in (0, 1, 5, 16, 100, 1000, 20000)]
# viewer (host=0) seals: python must open with direction 2 and counters 1..n
frames, _ = run("seal", key.hex(), "0", *[h(m) for m in msgs])
for i, (fr, m) in enumerate(zip(frames, msgs)):
    raw = bytes.fromhex(fr)
    want_nonce = bytes([2, 0, 0, 0]) + (i + 1).to_bytes(8, "big")
    chk("viewer seal frame#%d tag+nonce" % i, raw[:13].hex(), (bytes([0x10]) + want_nonce).hex())
    chk("viewer seal frame#%d decrypts" % i, AESGCM(key).decrypt(raw[1:13], raw[13:], None).hex(), m.hex())
# host seals: Firn "host=1" frames use dir byte 1
frames, _ = run("seal", key.hex(), "1", h(msgs[2]))
chk("host seal dir byte", frames[0][2:4], "01")
# python host frames -> Firn viewer opens
hostf = [py_frame(key, 1, i + 1, m) for i, m in enumerate(msgs)]
res, _ = run("open", key.hex(), "0", *[f.hex() for f in hostf])
chk("viewer opens host frames", res, ["ok:" + m.hex() for m in msgs])
# replay + reorder + dir + tamper (one process = one state)
f1, f2, f3, f4 = (py_frame(key, 1, c, b"m%d" % c) for c in (1, 2, 3, 4))
bit = bytearray(f4)
bit[20] ^= 1
trunc = f4[:20]
wrongdir = py_frame(key, 2, 9, b"x")
res, _ = run("open", key.hex(), "0", f2.hex(), f1.hex(), f2.hex(), f3.hex(), bit.hex(),
             trunc.hex(), wrongdir.hex(), f4.hex(), f4.hex())
chk("replay/reorder/tamper", res,
    ["ok:" + b"m2".hex(), "fail", "fail", "ok:" + b"m3".hex(), "fail", "fail", "fail",
     "ok:" + b"m4".hex(), "fail"])
bad_tag = bytes([0x11]) + f1[1:]
res, _ = run("open", key.hex(), "0", bad_tag.hex())
chk("wrong tag byte", res, ["fail"])
# counter 0 must be rejected (starts at 1)
res, _ = run("open", key.hex(), "0", py_frame(key, 1, 0, b"z").hex())
chk("counter 0 rejected", res, ["fail"])
# a wrong key never opens
res, _ = run("open", rnd.randbytes(32).hex(), "0", f1.hex())
chk("wrong key", res, ["fail"])

# -------------------------------------------------- Argon2id (default)
ARGON = "argon2"


def argon_ref(pw, salt):
    r = subprocess.run([ARGON, salt, "-id", "-t", "2", "-k", "19456", "-p", "1", "-l", "32", "-r"],
                       input=pw, capture_output=True, timeout=60)
    return r.stdout.decode().strip()


cases = [(b"password", b"somesaltsomesalt"), (b"hunter2", b"0123456789abcdef"),
         (b"Passw0rd!\xc3\xa4\xc3\xb6\xc3\xbc", b"fv-salt-ABCDEF12"), (b"x", b"~~~~~~~~~~~~~~~~"),
         (b"a" * 100, b"Z9y8X7w6V5u4T3s2"), (b"12345678", b"abcdefghijklmnop")]
for pw, salt in cases:
    ref = argon_ref(pw, salt)
    chk("argon2id default %r" % pw[:12], one("pwkey", h(pw), salt.hex())[0], ref)

# ---------------------------------------------------- Rust contract file
if RUST and os.path.exists(RUST):
    print("  rust vectors: %s present, comparing" % RUST)
    try:
        import rustcmp  # optional adapter next to this file
        ok_r, bad_r = rustcmp.compare(RUST, one, run, chk)
    except ImportError:
        print("  (no tools/fvcrypto/rustcmp.py adapter; Rust file not compared)")

print("fvcrypto vectors: %d ok, %d FAIL" % (ok, bad))
sys.exit(1 if bad else 0)
