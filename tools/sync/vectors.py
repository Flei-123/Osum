#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import binascii
import hashlib
import hmac as pyhmac
import os
import random
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ORACLE = os.path.join(ROOT, ".probe", "syncoracle")

try:
    from nacl.bindings import (
        crypto_aead_xchacha20poly1305_ietf_encrypt as xenc,
        crypto_aead_xchacha20poly1305_ietf_decrypt as xdec,
    )
    HAT_SODIUM = True
except Exception:
    HAT_SODIUM = False

fails = []
count = 0


def hx(b):
    return binascii.hexlify(b).decode() if b else "-"


def ask(lines):
    p = subprocess.run([ORACLE], input="\n".join(lines) + "\n",
                       capture_output=True, text=True)
    if p.returncode != 0:
        print("  the oracle died, code %d: %s"
              % (p.returncode, p.stderr[:400]))
        sys.exit(1)
    out = p.stdout.split("\n")
    while out and out[-1] == "":
        out.pop()
    if len(out) != len(lines):
        print("  the oracle answered %d times to %d questions"
              % (len(out), len(lines)))
        sys.exit(1)
    return out


def eq(name, ist, soll):
    global count
    count += 1
    if ist != soll:
        fails.append("%s: %s != %s" % (name, str(ist)[:80], str(soll)[:80]))



def t_pbkdf2():
    q, w = [], []
    for pw, salt, it, dk in [(b"password", b"NaCl", 1, 64),
                             (b"passwd", b"salt", 4096, 32),
                             (b"", b"", 1, 32)]:
        q.append("pbkdf2 %s %s %d %d" % (hx(pw), hx(salt), it, dk))
        w.append(hashlib.pbkdf2_hmac("sha256", pw, salt, it, dk).hex())
    for _ in range(6):
        pw = os.urandom(random.randint(0, 80))
        salt = os.urandom(random.randint(0, 200))
        it = random.randint(1, 40)
        dk = random.randint(1, 200)
        q.append("pbkdf2 %s %s %d %d" % (hx(pw), hx(salt), it, dk))
        w.append(hashlib.pbkdf2_hmac("sha256", pw, salt, it, dk).hex())
    for name, ist, soll in zip(range(len(q)), ask(q), w):
        eq("pbkdf2/%d" % name, ist, soll)
    print("  PBKDF2-HMAC-SHA256: %d Faelle gegen hashlib" % len(q))



SALSA_IN = ("7e879a214f3ec9867ca940e641718f26baee555b8c61c1b50df846116dcd3b1d"
            "ee24f319df9b3d8514121e4b5ac5aa3276021d2909c74829edebc68db8b8c25e")
SALSA_OUT = ("a41f859c6608cc993b81cacb020cef05044b2181a2fd337dfd7b1c6396682f29"
             "b4393168e3c9e6bcfe6bc5b7a06d96bae424cc102c91745c24ad673dc7618f81")


def t_salsa():
    eq("salsa20/8 RFC 7914 §8", ask(["salsa " + SALSA_IN])[0], SALSA_OUT)
    print("  Salsa20/8: the test vector from RFC 7914 section 8")



def t_scrypt(voll):
    faelle = [(b"", b"", 16, 1, 1, 64),
              (b"password", b"NaCl", 1024, 8, 16, 64),
              (b"pleaseletmein", b"SodiumChloride", 16384, 8, 1, 64)]
    if voll:
        faelle.append((b"x" * 5, os.urandom(16), 256, 8, 1, 32))
        faelle.append((os.urandom(9), os.urandom(16), 512, 4, 2, 40))
    q = ["scrypt %s %s %d %d %d %d" % (hx(p), hx(s), N, r, P, dk)
         for (p, s, N, r, P, dk) in faelle]
    got = ask(q)
    for (c, g) in zip(faelle, got):
        w = hashlib.scrypt(c[0], salt=c[1], n=c[2], r=c[3], p=c[4],
                           dklen=c[5], maxmem=1 << 26).hex()
        eq("scrypt N=%d r=%d p=%d" % (c[2], c[3], c[4]), g, w)
    print("  scrypt: %d cases, including THREE of the four from RFC 7914 §12 "
          "(der vierte braucht 1 GiB)" % len(faelle))



def hkdf_ext(salt, ikm):
    return pyhmac.new(salt, ikm, hashlib.sha256).digest()


def hkdf_exp(prk, info, ln):
    t, o, i = b"", b"", 1
    while len(o) < ln:
        t = pyhmac.new(prk, t + info + bytes([i]), hashlib.sha256).digest()
        o += t
        i += 1
    return o[:ln]


def t_hkdf():
    faelle = [
        (bytes.fromhex("0b" * 22), bytes.fromhex("000102030405060708090a0b0c"),
         bytes.fromhex("f0f1f2f3f4f5f6f7f8f9"), 42,
         "077709362c2e32df0ddc3f0dc47bba6390b6c73bb50f9c3122ec844ad7c2b3e5",
         "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf"
         "34007208d5b887185865"),
        (bytes(range(0x50)), bytes(range(0x60, 0xb0)),
         bytes(range(0xb0, 0x100)), 82,
         "06a6b88c5853361a06104c9ceb35b45cef760014904671014a193f40c15fc244",
         "b11e398dc80327a1c8e7f78c596a49344f012eda2d4efad8a050cc4c19afa97c"
         "59045a99cac7827271cb41c65e590e09da3275600c2f09b8367793a9aca3db71"
         "cc30c58179ec3e87c14c01d5c1f3434f1d87"),
        (bytes.fromhex("0b" * 22), b"", b"", 42,
         "19ef24a32c717b167f33a91d6f648bdf96596776afdb6377ac434c1c293ccb04",
         "8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d"
         "9d201395faa4b61a96c8"),
    ]
    q = []
    for (ikm, salt, info, ln, prk, okm) in faelle:
        q.append("hkdfext %s %s" % (hx(salt), hx(ikm)))
    got = ask(q)
    for (c, g) in zip(faelle, got):
        eq("hkdf extract", g, c[4])
    q = ["hkdfexp %s %s %d" % (c[4], hx(c[2]), c[3]) for c in faelle]
    got = ask(q)
    for (c, g) in zip(faelle, got):
        eq("hkdf expand", g, c[5])
    q, w = [], []
    for _ in range(5):
        prk = os.urandom(32)
        info = os.urandom(random.randint(0, 40))
        ln = random.randint(1, 300)
        q.append("hkdfexp %s %s %d" % (hx(prk), hx(info), ln))
        w.append(hkdf_exp(prk, info, ln).hex())
    for (g, s) in zip(ask(q), w):
        eq("hkdf expand (zufall)", g, s)
    print("  HKDF-SHA256: RFC 5869 A.1/A.2/A.3 und 5 Zufallsfaelle")



def t_chain():
    pw = b"eine passphrase mit umlauten aeoeue"
    salt = os.urandom(16)
    N, r = 256, 8
    bund = ask(["keys %s %s %d %d" % (hx(pw), hx(salt), N, r)])[0]
    mk = hashlib.scrypt(pw, salt=salt, n=N, r=r, p=1, dklen=32, maxmem=1 << 26)
    prk = hkdf_ext(salt, mk)
    eq("schluesselbund", bund,
           hkdf_exp(prk, b"osum sync v1 unterkette", 160).hex())
    KI = bytes.fromhex(bund[0:64])
    KN = bytes.fromhex(bund[64:128])
    blk = os.urandom(4096)
    n1 = ask(["name %s %s" % (hx(KN), hx(blk))])[0]
    eq("blockname ist HMAC(K_NAME, P)", n1,
           pyhmac.new(KN, blk, hashlib.sha256).hexdigest())
    n2 = ask(["naiv %s" % hx(blk)])[0]
    eq("der naive Name ist der blanke SHA-256", n2,
           hashlib.sha256(blk).hexdigest())
    eq("und die beiden sind NICHT dasselbe", n1 != n2, True)
    name = bytes.fromhex(n1)
    ct = ask(["seal %s %s %s" % (hx(KI), hx(name), hx(blk))])[0]
    if HAT_SODIUM:
        kb = pyhmac.new(KI, name, hashlib.sha256).digest()
        nc = pyhmac.new(KI, b"nonce" + name, hashlib.sha256).digest()[:24]
        eq("siegel gegen libsodium", ct, xenc(blk, name, nc, kb).hex())
    eq("siegel ist 16 Oktette laenger", len(ct) // 2, 4096 + 16)
    eq("und geht wieder auf",
           ask(["open %s %s %s" % (hx(KI), hx(name), ct)])[0], blk.hex())
    bad = bytearray(bytes.fromhex(ct))
    bad[100] ^= 1
    eq("ein gekipptes Bit wird abgelehnt",
           ask(["open %s %s %s" % (hx(KI), hx(name), bad.hex())])[0], "FAIL")
    eq("ein fremder Name wird abgelehnt",
           ask(["open %s %s %s" % (hx(KI), hx(os.urandom(32)), ct)])[0], "FAIL")
    ct2 = ask(["seal %s %s %s" % (hx(KI), hx(name), hx(blk))])[0]
    eq("derselbe Klartext gibt denselben Geheimtext", ct, ct2)
    print("  the chain: bundle, names, seal%s"
          % (" (gegen libsodium)" if HAT_SODIUM else " (OHNE libsodium!)"))



def t_code():
    for _ in range(20):
        k = os.urandom(32)
        code = bytes.fromhex(ask(["rcenc %s" % hx(k)])[0]).decode()
        eq("code ist 65 Zeichen", len(code), 65)
        eq("code in elf Gruppen", code.count("-"), 10)
        eq("code zurueck", ask(["rcdec %s" % hx(code.encode())])[0], k.hex())
        eq("klein geschrieben geht auch",
               ask(["rcdec %s" % hx(code.lower().encode())])[0], k.hex())
        i = random.choice([j for j in range(65) if code[j] != "-"])
        a = code[i]
        b = random.choice([c for c in "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
                           if c != a])
        broken = code[:i] + b + code[i + 1:]
        eq("ein Tippfehler faellt auf",
               ask(["rcdec %s" % hx(broken.encode())])[0], "FAIL")
    k = os.urandom(32)
    code = bytes.fromhex(ask(["rcenc %s" % hx(k)])[0]).decode()
    stellen = [j for j in range(65) if code[j] != "-"]
    eq("55 bedeutsame Stellen", len(stellen), 55)
    ask_2, erwartet = [], 0
    for i in stellen:
        for b in "0123456789ABCDEFGHJKMNPQRSTVWXYZ":
            if b == code[i]:
                continue
            ask_2.append("rcdec %s" % hx((code[:i] + b + code[i + 1:])
                                          .encode()))
            erwartet += 1
    durch = [z for z in ask(ask_2) if z != "FAIL"]
    eq("KEIN einziger Tippfehler kommt durch (%d geprueft)" % erwartet,
           len(durch), 0)
    print("  recovery code: 21 codes back and forth, "
          "20 zufaellige und %d erschoepfende Tippfehler erkannt" % erwartet)


def t_envelope():
    for _ in range(5):
        mk, ek, nn = os.urandom(32), os.urandom(32), os.urandom(24)
        h = ask(["hwrap %s %s %s" % (hx(ek), hx(nn), hx(mk))])[0]
        if HAT_SODIUM:
            eq("huelle gegen libsodium", h,
                   xenc(mk, b"osum sync v1 huelle", nn, ek).hex())
        eq("huelle ist 48 Oktette", len(h) // 2, 48)
        eq("huelle auf", ask(["hopen %s %s %s" % (hx(ek), hx(nn), h)])[0],
               mk.hex())
        eq("falscher Einpackschluessel -> nein",
               ask(["hopen %s %s %s" % (hx(os.urandom(32)), hx(nn), h)])[0],
               "FAIL")
    print("  the envelope: 5 rounds, each with its control run")


if __name__ == "__main__":
    random.seed(20260830)
    voll = "--kurz" not in sys.argv
    if not os.path.exists(ORACLE):
        print("  the oracle is missing: %s" % ORACLE)
        sys.exit(1)
    if not HAT_SODIUM:
        print("  NOTE: PyNaCl is missing -- the AEAD is NOT checked against "
              "libsodium gemessen")
    t_pbkdf2()
    t_salsa()
    t_scrypt(voll)
    t_hkdf()
    t_chain()
    t_code()
    t_envelope()
    if fails:
        print("  %d von %d Zusagen GEFALLEN:" % (len(fails), count))
        for f in fails[:12]:
            print("    " + f)
        sys.exit(1)
    print("%d Zusagen, 0 Fehler" % count)
