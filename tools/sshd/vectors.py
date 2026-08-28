#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/sshd/vectors.py -- die Bausteine der Runde SSHD gegen etwas,
das nicht aus diesem Baum stammt.

Gemessen wird `.probe/sshoracle`, ein gehostetes Firn-Programm, das
GENAU DIE DATEIEN bindet, die auch `kernel/user/sshd.fi` bindet:
lib/crypto/sha256.fi, lib/crypto/chacha.fi, lib/ssh/wire.fi,
lib/ssh/pack.fi, lib/ssh/kex.fi.

Wogegen:

  * SHA-256      -- FIPS 180-4 und Pythons `hashlib`
  * HMAC-SHA-256 -- RFC 4231 und Pythons `hmac`
  * mpint        -- die Beispiele aus RFC 4251 Abschnitt 5, Zahl fuer Zahl
  * Base64       -- RFC 4648 und Pythons `base64`
  * Ableitung    -- RFC 4253 Abschnitt 7.2, hier nochmal in Python
  * das AEAD     -- OpenSSHs `PROTOCOL.chacha20poly1305`, hier nochmal in
                    Python mit `cryptography` (ChaCha20 mit djbs
                    16-Oktett-Nonce = Zaehler || IV, und Poly1305)

Die zweite Umsetzung ist der ganze Punkt. Ein einziger Code, der sich
selbst prueft, ist auf beiden Seiten gleich falsch.
"""
import base64
import binascii
import hashlib
import hmac as pyhmac
import os
import random
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__))))
ORACLE = os.path.join(ROOT, ".probe", "sshoracle")

fails = []
count = 0


def hx(b):
    return binascii.hexlify(b).decode() if b else "-"


def ask(lines):
    """Ein Schwung durch das Orakel: Befehlszeilen rein, Antworten raus."""
    p = subprocess.run([ORACLE], input="\n".join(lines) + "\n",
                       capture_output=True, text=True)
    if p.returncode != 0:
        print("  das Orakel ist gestorben, Code %d: %s"
              % (p.returncode, p.stderr[:400]))
        sys.exit(1)
    out = p.stdout.split("\n")
    while out and out[-1] == "":
        out.pop()
    if len(out) != len(lines):
        print("  das Orakel hat %d mal geantwortet auf %d Fragen"
              % (len(out), len(lines)))
        sys.exit(1)
    return out


def check(name, got, want):
    global count
    count += 1
    if got != want:
        fails.append("%s: %s != %s" % (name, got, want))


# ===================================================== 1. SHA-256
def t_sha256():
    msgs = [b"", b"abc",
            b"abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq",
            b"a" * 1000, bytes(range(256)) * 4]
    rng = random.Random(20260828)
    for n in list(range(0, 130)) + [255, 256, 257, 4096, 40000]:
        msgs.append(bytes(rng.getrandbits(8) for _ in range(n)))
    q = ["sha256 %s" % hx(m) for m in msgs]
    a = ask(q)
    for m, got in zip(msgs, a):
        check("sha256(%d)" % len(m), got, hashlib.sha256(m).hexdigest())
    # Die zwei Vektoren, die in FIPS 180-4 mit ihrem Ergebnis abgedruckt
    # sind -- damit auch dann etwas auffiele, wenn hashlib und dieser
    # Code auf dieselbe Weise falsch waeren.
    check("FIPS abc", a[1],
          "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    check("FIPS leer", a[0],
          "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    check("FIPS 448bit", a[2],
          "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
    print("  SHA-256: %d Faelle gegen hashlib und FIPS 180-4" % len(msgs))


# ===================================================== 2. HMAC-SHA-256
def t_hmac():
    # RFC 4231, die sieben Faelle
    cases = [
        (b"\x0b" * 20, b"Hi There"),
        (b"Jefe", b"what do ya want for nothing?"),
        (b"\xaa" * 20, b"\xdd" * 50),
        (bytes(range(1, 26)), b"\xcd" * 50),
        (b"\x0c" * 20, b"Test With Truncation"),
        (b"\xaa" * 131, b"Test Using Larger Than Block-Size Key - Hash Key First"),
        (b"\xaa" * 131, b"This is a test using a larger than block-size key and a "
                        b"larger than block-size data. The key needs to be hashed "
                        b"before being used by the HMAC algorithm."),
    ]
    rng = random.Random(7)
    for _ in range(40):
        kl = rng.randrange(0, 200)
        ml = rng.randrange(0, 500)
        cases.append((bytes(rng.getrandbits(8) for _ in range(kl)),
                      bytes(rng.getrandbits(8) for _ in range(ml))))
    q = ["hmac256 %s %s" % (hx(k), hx(m)) for k, m in cases]
    a = ask(q)
    for (k, m), got in zip(cases, a):
        check("hmac(%d,%d)" % (len(k), len(m)), got,
              pyhmac.new(k, m, hashlib.sha256).hexdigest())
    check("RFC4231 #1", a[0],
          "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7")
    check("RFC4231 #2", a[1],
          "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843")
    check("RFC4231 #6", a[5],
          "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54")
    print("  HMAC-SHA-256: %d Faelle gegen hmac und RFC 4231" % len(cases))


# ===================================================== 3. mpint
def mpint(raw):
    """RFC 4251 Abschnitt 5, in Python."""
    v = int.from_bytes(raw, "big")
    if v == 0:
        return b"\x00\x00\x00\x00"
    b = v.to_bytes((v.bit_length() + 8) // 8, "big")
    return len(b).to_bytes(4, "big") + b


def t_mpint():
    cases = [b"", b"\x00", b"\x00" * 32, b"\x01", b"\x80", b"\xff",
             b"\x00\x80", b"\x7f\xff", b"\x00\x00\x01\x00"]
    # Die Beispiele, die RFC 4251 Abschnitt 5 abdruckt
    cases.append(bytes.fromhex("09a378f9b2e332a7"))
    rng = random.Random(31337)
    for _ in range(300):
        n = rng.randrange(1, 40)
        cases.append(bytes(rng.getrandbits(8) for _ in range(n)))
    for _ in range(64):
        # genau die Faelle, auf die es ankommt: das oberste Bit gesetzt
        cases.append(bytes([rng.randrange(128, 256)])
                     + bytes(rng.getrandbits(8) for _ in range(31)))
    q = ["mpint %s" % hx(c) for c in cases]
    a = ask(q)
    for c, got in zip(cases, a):
        check("mpint(%s)" % hx(c)[:16], got, hx(mpint(c)))
    check("RFC4251 0", a[0], hx(b"\x00\x00\x00\x00"))
    check("RFC4251 0x09a3...", a[9],
          "0000000809a378f9b2e332a7")
    check("RFC4251 0x80 braucht das fuehrende Null-Oktett", a[4],
          "0000000200" + "80")
    print("  mpint: %d Faelle gegen RFC 4251 Abschnitt 5" % len(cases))


# ===================================================== 4. Base64
def t_b64():
    rng = random.Random(99)
    cases = [b"", b"f", b"fo", b"foo", b"foob", b"fooba", b"foobar"]
    for n in range(0, 100):
        cases.append(bytes(rng.getrandbits(8) for _ in range(n)))
    q = ["b64ep %s" % hx(c) for c in cases]
    a = ask(q)
    for c, got in zip(cases, a):
        check("b64e(%d)" % len(c), got, hx(base64.b64encode(c)))
    q = ["b64e %s" % hx(c) for c in cases]
    a = ask(q)
    for c, got in zip(cases, a):
        check("b64e-ohne(%d)" % len(c), got,
              hx(base64.b64encode(c).rstrip(b"=")))
    # und zurueck
    q = ["b64d %s" % hx(base64.b64encode(c)) for c in cases]
    a = ask(q)
    for c, got in zip(cases, a):
        check("b64d(%d)" % len(c), got, hx(c))
    # eine echte authorized_keys-Zeile
    key = os.urandom(32)
    blob = (b"\x00\x00\x00\x0bssh-ed25519" + b"\x00\x00\x00\x20" + key)
    a = ask(["b64d %s" % hx(base64.b64encode(blob))])
    check("b64d des Schluessel-Blobs", a[0], hx(blob))
    # ein Zeichen, das nicht hineingehoert, muss abgelehnt werden
    a = ask(["b64d %s" % hx(b"AAAA!AAA")])
    check("b64d lehnt ein fremdes Zeichen ab", a[0], "FAIL")
    print("  Base64: %d Faelle hin und zurueck gegen base64" % (3 * len(cases)))


# ===================================================== 5. Ableitung
def derive(secret, h, sid, letter, want):
    """RFC 4253 Abschnitt 7.2, in Python."""
    k = mpint(secret)
    out = hashlib.sha256(k + h + letter + sid).digest()
    while len(out) < want:
        out += hashlib.sha256(k + h + out).digest()
    return out[:want]


def t_derive():
    rng = random.Random(4711)
    q, want = [], []
    for _ in range(60):
        s = bytes(rng.getrandbits(8) for _ in range(32))
        h = bytes(rng.getrandbits(8) for _ in range(32))
        sid = bytes(rng.getrandbits(8) for _ in range(32))
        letter = bytes([rng.choice(b"ABCDEF")])
        n = rng.choice([16, 32, 33, 64, 65, 96, 100])
        q.append("derive %s %s %s %s %d" % (hx(s), hx(h), hx(sid),
                                            hx(letter), n))
        want.append(hx(derive(s, h, sid, letter, n)))
    a = ask(q)
    for i, got in enumerate(a):
        check("derive #%d" % i, got, want[i])
    print("  Ableitung RFC 4253 7.2: %d Faelle, davon %d mit Verlaengerung"
          % (len(q), sum(1 for x in q if int(x.split()[-1]) > 32)))


# ============================ 6. chacha20-poly1305@openssh.com
def chacha20(key, iv8, counter, data):
    """djbs Aufteilung: 16 Oktette Nonce = Zaehler (8, klein zuerst)
    gefolgt vom IV (8). Genau das nimmt `cryptography`."""
    from cryptography.hazmat.primitives.ciphers import Cipher, algorithms
    nonce = counter.to_bytes(8, "little") + iv8
    c = Cipher(algorithms.ChaCha20(key, nonce), mode=None).encryptor()
    return c.update(data)


def ossh_seal(key64, seq, payload, padding):
    from cryptography.hazmat.primitives import poly1305
    k2, k1 = key64[:32], key64[32:]
    pad = padding
    packlen = 1 + len(payload) + len(pad)
    body = bytes([len(pad)]) + payload + pad
    seqb = seq.to_bytes(8, "big")
    hdr = chacha20(k1, seqb, 0, packlen.to_bytes(4, "big"))
    ct = chacha20(k2, seqb, 1, body)
    polykey = chacha20(k2, seqb, 0, b"\x00" * 32)
    p = poly1305.Poly1305(polykey)
    p.update(hdr + ct)
    return hdr + ct + p.finalize()


def padc(on, plen):
    base = (1 + plen) if on else (4 + 1 + plen)
    pad = 8 - (base % 8)
    if pad < 4:
        pad += 8
    return pad


def t_aead():
    rng = random.Random(2026)
    q, want = [], []
    cases = []
    for i in range(80):
        key = bytes(rng.getrandbits(8) for _ in range(64))
        seq = rng.choice([0, 1, 2, 17, 255, 256, 65535, 1000000])
        plen = rng.choice(list(range(0, 40)) + [100, 1000, 4096, 20000])
        payload = bytes(rng.getrandbits(8) for _ in range(plen))
        pad = bytes(rng.getrandbits(8) for _ in range(padc(True, plen)))
        cases.append((key, seq, payload, pad))
        q.append("seal %s %d %s %s" % (hx(key), seq, hx(payload), hx(pad)))
        want.append(hx(ossh_seal(key, seq, payload, pad)))
    a = ask(q)
    for i, got in enumerate(a):
        check("seal #%d" % i, got, want[i])
    print("  chacha20-poly1305@openssh.com: %d Pakete Oktett fuer Oktett "
          "gegen cryptography" % len(q))

    # ...und wieder herein. Das Orakel entschluesselt, was Python gebaut hat.
    q = ["openp %s %d %s" % (hx(k), s, w)
         for (k, s, p, pd), w in zip(cases, want)]
    a = ask(q)
    for i, got in enumerate(a):
        check("open #%d" % i, got, hx(cases[i][2]))
    print("  ...und dieselben %d Pakete wieder aufgemacht" % len(q))

    # DIE GEGENPROBE: ein einziges gekipptes Bit muss abgelehnt werden --
    # an jeder Stelle des Pakets, auch im Laengenfeld und im Merkmal.
    q, spots = [], []
    for i, ((k, s, p, pd), w) in enumerate(zip(cases[:25], want[:25])):
        raw = bytearray(binascii.unhexlify(w))
        pos = rng.randrange(len(raw))
        raw[pos] ^= 1 << rng.randrange(8)
        q.append("openp %s %d %s" % (hx(k), s, hx(bytes(raw))))
        spots.append(pos)
    a = ask(q)
    bad = 0
    for i, got in enumerate(a):
        # Ein Kippen im LAENGENFELD ergibt eine andere Laenge; das Orakel
        # sagt dann ebenfalls FAIL (die Laenge passt nicht zum Puffer).
        if got != "FAIL":
            bad += 1
            fails.append("gekipptes Bit an %d wurde ANGENOMMEN" % spots[i])
    global count
    count += len(a)
    print("  Gegenprobe: %d Pakete mit EINEM gekippten Bit, %d angenommen "
          "(erwartet 0)" % (len(a), bad))

    # Die falsche Paketnummer ist derselbe Fehler und muss ebenso auffallen.
    q = ["openp %s %d %s" % (hx(k), s + 1, w)
         for (k, s, p, pd), w in zip(cases[:25], want[:25])]
    a = ask(q)
    bad = sum(1 for g in a if g != "FAIL")
    count += len(a)
    if bad:
        fails.append("%d Pakete mit falscher Paketnummer angenommen" % bad)
    print("  Gegenprobe: %d Pakete unter der falschen Paketnummer, %d "
          "angenommen (erwartet 0)" % (len(a), bad))


# ===================================================== 7. Auffuellung
def t_pad():
    q, want = [], []
    for on in (0, 1):
        for plen in range(0, 300):
            q.append("padc %d %d" % (on, plen))
            want.append("%02x" % padc(on == 1, plen))
    a = ask(q)
    for i, got in enumerate(a):
        check("padc #%d" % i, got, want[i])
    # Und die Regel, die dahintersteht, noch einmal ausdruecklich:
    for plen in range(0, 300):
        p = padc(True, plen)
        assert p >= 4 and (1 + plen + p) % 8 == 0
        p = padc(False, plen)
        assert p >= 4 and (4 + 1 + plen + p) % 8 == 0
    print("  Auffuellung: %d Faelle, beide Regeln (mit und ohne AEAD)"
          % len(q))


# ===================================================== 8. Klartextpakete
def t_plain():
    rng = random.Random(5)
    q, want = [], []
    for plen in list(range(0, 60)) + [500, 4000]:
        payload = bytes(rng.getrandbits(8) for _ in range(plen))
        pad = bytes(rng.getrandbits(8) for _ in range(padc(False, plen)))
        packlen = 1 + plen + len(pad)
        raw = (packlen.to_bytes(4, "big") + bytes([len(pad)]) + payload
               + pad)
        q.append("sealp %s %s" % (hx(payload), hx(pad)))
        want.append(hx(raw))
    a = ask(q)
    for i, got in enumerate(a):
        check("sealp #%d" % i, got, want[i])
    q = ["openpp %s" % w for w in want]
    a = ask(q)
    rng = random.Random(5)
    for plen in list(range(0, 60)) + [500, 4000]:
        payload = bytes(rng.getrandbits(8) for _ in range(plen))
        rng.getrandbits(8 * padc(False, plen))
    print("  Klartextpakete: %d gebaut und %d wieder gelesen" % (len(q), len(a)))
    rng = random.Random(5)
    for i in range(len(a)):
        plen = (list(range(0, 60)) + [500, 4000])[i]
        payload = bytes(rng.getrandbits(8) for _ in range(plen))
        bytes(rng.getrandbits(8) for _ in range(padc(False, plen)))
        check("openpp #%d" % i, a[i], hx(payload))


# ===================================================== 9. name-list
def t_list():
    lst = b"curve25519-sha256,curve25519-sha256@libssh.org,ext-info-c"
    q, want = [], []
    for name, yes in [(b"curve25519-sha256", True),
                      (b"curve25519-sha256@libssh.org", True),
                      (b"ext-info-c", True),
                      (b"curve25519", False),
                      (b"sha256", False),
                      (b"ext-info-c,", False),
                      (b"", False),
                      (b"curve25519-sha256@libssh.or", False)]:
        q.append("listhas %s %s" % (hx(lst), hx(name)))
        want.append("1" if yes else "0")
    a = ask(q)
    for i, got in enumerate(a):
        check("listhas #%d" % i, got, want[i])
    print("  name-list: %d Faelle, ein Teilname darf NICHT passen" % len(q))


def main():
    if not os.access(ORACLE, os.X_OK):
        print("erst .probe/sshoracle bauen (tools/sshd/run.sh tut es)")
        return 1
    t_sha256()
    t_hmac()
    t_mpint()
    t_b64()
    t_derive()
    t_aead()
    t_pad()
    t_plain()
    t_list()
    if fails:
        print("\n%d von %d Vergleichen FEHLGESCHLAGEN:" % (len(fails), count))
        for f in fails[:25]:
            print("   " + f)
        return 1
    print("\n%d Vergleiche, 0 Fehler" % count)
    return 0


if __name__ == "__main__":
    sys.exit(main())
