#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/tunnel/vectors.py -- the four primitives against their RFCs.

WHY THIS FILE IS THE FIRST THING ROUND TUNNEL BUILT. A VPN is a pile of
plumbing wrapped around four arithmetic functions. If any one of the four
is wrong, everything above it is worse than useless: it looks encrypted
and is not. So the primitives are measured before a single packet is
sent, and they are measured TWICE over:

  1. AGAINST THE LITERAL VECTORS PRINTED IN THE RFC. These are typed in
     from the document text. They are the authority; a cross-check against
     another implementation only proves that two implementations agree,
     which is exactly what happens when both are wrong in the same way.
  2. AGAINST A SECOND, INDEPENDENT IMPLEMENTATION over generated inputs:
     Python's `hashlib` (which is OpenSSL/libb2 underneath) for BLAKE2s,
     `cryptography` (OpenSSL) for ChaCha20-Poly1305, and `nacl`
     (libsodium) for X25519 and XChaCha20-Poly1305. This is what catches
     the length and boundary cases no RFC prints.

The thing under test is `.probe/oracle`, a hosted Firn program that links
THE SAME `lib/crypto/*.fi` files the kernel links. That they compile in
both the hosted and the kernel profile is checked by section 62 of
./test.sh; that they COMPUTE THE RIGHT THING is checked here.

    ./tools/tunnel/vectors.py            run everything
    ./tools/tunnel/vectors.py --slow     also the 1 000 000 round X25519
"""
import os
import subprocess
import sys
import hashlib
import random

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ORACLE = os.path.join(ROOT, ".probe", "oracle")

TOTAL = 0
BAD = []
GROUPS = {}


def h(s):
    """Hex text -> bytes, ignoring the whitespace RFCs print for readability."""
    return bytes.fromhex("".join(s.split()))


def x(b):
    return b.hex() if len(b) else "-"


class Oracle:
    """One process, many questions -- starting a process per vector would
    measure `fork` rather than the arithmetic."""

    def __init__(self):
        self.lines = []
        self.tags = []

    def ask(self, cmd, tag, want):
        self.lines.append(cmd)
        self.tags.append((tag, want, cmd))

    def run(self):
        global TOTAL
        inp = ("\n".join(self.lines) + "\n").encode()
        p = subprocess.run([ORACLE], input=inp, capture_output=True)
        got = p.stdout.decode().splitlines()
        if len(got) != len(self.tags):
            print("the oracle answered %d of %d lines" % (len(got), len(self.tags)))
            print(p.stderr.decode()[:2000])
            sys.exit(1)
        for (tag, want, cmd), g in zip(self.tags, got):
            TOTAL += 1
            GROUPS[tag] = GROUPS.get(tag, 0) + 1
            if g != want:
                BAD.append((tag, cmd, want, g))
        self.lines = []
        self.tags = []


o = Oracle()

# =====================================================================
# BLAKE2s -- RFC 7693
# =====================================================================

# RFC 7693 Appendix B, the one vector the document prints in full.
o.ask("blake2s 32 - 616263", "RFC 7693 App. B",
      "508c5e8c327c14e2e1a72ba34eeb452f37458b209ed63a294d999b4c86675982")

# RFC 7693 Appendix A prints BLAKE2b; the BLAKE2s KAT that ships with the
# reference implementation (blake2s-kat.txt) is the 256 keyed hashes of
# the inputs 00, 0001, 000102, ... under the key 000102..1f. It is
# reproduced here through hashlib, which is the same libb2/OpenSSL code
# the KAT file was generated from.
KEY = bytes(range(32))
for n in range(0, 256):
    data = bytes(range(n))
    o.ask("blake2s 32 %s %s" % (x(KEY), x(data)), "BLAKE2s KAT (keyed)",
          hashlib.blake2s(data, key=KEY, digest_size=32).hexdigest())

# Unkeyed, every length up to two blocks and a bit -- the boundary at 64
# and at 128 octets is where a wrong "compress as soon as the buffer is
# full" shows up, and nowhere else.
for n in list(range(0, 200)) + [255, 256, 257, 511, 512, 513, 1000]:
    data = bytes((i * 7 + 3) & 255 for i in range(n))
    o.ask("blake2s 32 - %s" % x(data), "BLAKE2s length sweep",
          hashlib.blake2s(data, digest_size=32).hexdigest())

# Every digest length BLAKE2s allows. This is the check that the digest
# length goes into the PARAMETER BLOCK and is not a truncation.
for dl in range(1, 33):
    o.ask("blake2s %d - 616364" % dl, "BLAKE2s digest lengths",
          hashlib.blake2s(b"acd", digest_size=dl).hexdigest())
    o.ask("blake2s %d %s 616364" % (dl, x(KEY[:16])), "BLAKE2s digest lengths",
          hashlib.blake2s(b"acd", key=KEY[:16], digest_size=dl).hexdigest())

# Every key length BLAKE2s allows.
for kl in range(0, 33):
    o.ask("blake2s 32 %s 6d657373616765" % x(KEY[:kl]), "BLAKE2s key lengths",
          hashlib.blake2s(b"message", key=KEY[:kl], digest_size=32).hexdigest())

# Refusals. BLAKE2s has no digest above 32 and no key above 32; a
# silently truncated answer would be worse than an error.
o.ask("blake2s 33 - 00", "BLAKE2s refusals", "FAIL")
o.ask("blake2s 64 - 00", "BLAKE2s refusals", "FAIL")
o.ask("blake2s 32 %s 00" % x(bytes(33)), "BLAKE2s refusals", "FAIL")
o.ask("blake2s 0 - 00", "BLAKE2s refusals", "FAIL")

o.run()

# HMAC-BLAKE2s (RFC 2104 over BLAKE2s) -- WireGuard's HKDF is built on it.
# hashlib.blake2s is the hash; hmac.new does the construction.
import hmac as _hmac
for kl in [0, 1, 16, 31, 32, 63, 64, 65, 100, 200]:
    for ml in [0, 1, 15, 16, 63, 64, 65, 127, 128, 300]:
        key = bytes((i * 11 + 5) & 255 for i in range(kl))
        msg = bytes((i * 13 + 7) & 255 for i in range(ml))
        want = _hmac.new(key, msg, hashlib.blake2s).hexdigest()
        o.ask("hmacb2s %s %s" % (x(key), x(msg)), "HMAC-BLAKE2s", want)
o.run()

# =====================================================================
# ChaCha20 -- RFC 8439
# =====================================================================

# RFC 8439 2.3.2, the block function test vector. The keystream block is
# obtained by encrypting 64 zero octets with that counter.
o.ask("chacha20 %s %s 1 %s" % (
    "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f",
    "000000090000004a00000000", "00" * 64), "RFC 8439 2.3.2 block",
    "10f1e7e4d13b5915500fdd1fa32071c4c7d1f4c733c068030422aa9ac3d46c4e"
    "d2826446079faa0914c2d705d98b02a2b5129cd1de164eb9cbd083e8a2503c4e")

# RFC 8439 2.4.2, the encryption test vector -- 114 octets of the
# "Ladies and Gentlemen of the class of '99" text.
PLAIN_2_4_2 = h(
    "4c616469657320616e642047656e746c656d656e206f662074686520636c6173"
    "73206f66202739393a204966204920636f756c64206f6666657220796f75206f"
    "6e6c79206f6e652074697020666f7220746865206675747572652c2073756e73"
    "637265656e20776f756c642062652069742e")
o.ask("chacha20 %s %s 1 %s" % (
    "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f",
    "000000000000004a00000000", x(PLAIN_2_4_2)), "RFC 8439 2.4.2",
    "6e2e359a2568f98041ba0728dd0d6981e97e7aec1d4360c20a27afccfd9fae0b"
    "f91b65c5524733ab8f593dabcd62b3571639d624e65152ab8f530c359f0861d8"
    "07ca0dbf500d6a6156a38e088a22b65e52bc514d16ccf806818ce91ab7793736"
    "5af90bbf74a35be6b40b8eedf2785e42874d")

# RFC 8439 Appendix A.1 -- four block function vectors that walk the key,
# the counter and the nonce through their edge values.
A1 = [
    ("00" * 32, "00" * 12, 0,
     "76b8e0ada0f13d90405d6ae55386bd28bdd219b8a08ded1aa836efcc8b770dc7"
     "da41597c5157488d7724e03fb8d84a376a43b8f41518a11cc387b669b2ee6586"),
    ("00" * 32, "00" * 12, 1,
     "9f07e7be5551387a98ba977c732d080dcb0f29a048e3656912c6533e32ee7aed"
     "29b721769ce64e43d57133b074d839d531ed1f28510afb45ace10a1f4b794d6f"),
    ("00" * 31 + "01", "00" * 12, 1,
     "3aeb5224ecf849929b9d828db1ced4dd832025e8018b8160b82284f3c949aa5a"
     "8eca00bbb4a73bdad192b5c42f73f2fd4e273644c8b36125a64addeb006c13a0"),
    ("00ff" + "00" * 30, "00" * 12, 2,
     "72d54dfbf12ec44b362692df94137f328fea8da73990265ec1bbbea1ae9af0ca"
     "13b25aa26cb4a648cb9b9d1be65b2c0924a66c54d545ec1b7374f4872e99f096"),
    ("00" * 32, "00" * 11 + "02", 0,
     "c2c64d378cd536374ae204b9ef933fcd1a8b2288b3dfa49672ab765b54ee27c7"
     "8a970e0e955c14f3a88e741b97c286f75f8fc299e8148362fa198a39531bed6d"),
]
for key, nonce, ctr, want in A1:
    o.ask("chacha20 %s %s %d %s" % (key, nonce, ctr, "00" * 64),
          "RFC 8439 A.1 blocks", want)

# RFC 8439 Appendix A.2 -- three encryption vectors.
A2_2_PLAIN = h(
    "416e79207375626d697373696f6e20746f20746865204945544620696e74656e"
    "6465642062792074686520436f6e7472696275746f7220666f72207075626c69"
    "636174696f6e20617320616c6c206f722070617274206f6620616e2049455446"
    "20496e7465726e65742d4472616674206f722052464320616e6420616e792073"
    "746174656d656e74206d6164652077697468696e2074686520636f6e74657874"
    "206f6620616e204945544620616374697669747920697320636f6e7369646572"
    "656420616e20224945544620436f6e747269627574696f6e222e205375636820"
    "73746174656d656e747320696e636c756465206f72616c2073746174656d656e"
    "747320696e20494554462073657373696f6e732c2061732077656c6c20617320"
    "7772697474656e20616e6420656c656374726f6e696320636f6d6d756e696361"
    "74696f6e73206d61646520617420616e792074696d65206f7220706c6163652c"
    "207768696368206172652061646472657373656420746f")
o.ask("chacha20 %s %s 0 %s" % (
    "00" * 32, "00" * 12, "00" * 64), "RFC 8439 A.2 encrypt",
    "76b8e0ada0f13d90405d6ae55386bd28bdd219b8a08ded1aa836efcc8b770dc7"
    "da41597c5157488d7724e03fb8d84a376a43b8f41518a11cc387b669b2ee6586")
o.ask("chacha20 %s %s 1 %s" % (
    "00" * 31 + "01", "00" * 11 + "02", x(A2_2_PLAIN)),
    "RFC 8439 A.2 encrypt",
    "a3fbf07df3fa2fde4f376ca23e82737041605d9f4f4f57bd8cff2c1d4b7955ec"
    "2a97948bd3722915c8f3d337f7d370050e9e96d647b7c39f56e031ca5eb6250d"
    "4042e02785ececfa4b4bb5e8ead0440e20b6e8db09d881a7c6132f420e527950"
    "42bdfa7773d8a9051447b3291ce1411c680465552aa6c405b7764d5e87bea85a"
    "d00f8449ed8f72d0d662ab052691ca66424bc86d2df80ea41f43abf937d3259d"
    "c4b2d0dfb48a6c9139ddd7f76966e928e635553ba76c5c879d7b35d49eb2e62b"
    "0871cdac638939e25e8a1e0ef9d5280fa8ca328b351c3c765989cbcf3daa8b6c"
    "cc3aaf9f3979c92b3720fc88dc95ed84a1be059c6499b9fda236e7e818b04b0b"
    "c39c1e876b193bfe5569753f88128cc08aaa9b63d1a16f80ef2554d7189c411f"
    "5869ca52c5b83fa36ff216b9c1d30062bebcfd2dc5bce0911934fda79a86f6e6"
    "98ced759c3ff9b6477338f3da4f9cd8514ea9982ccafb341b2384dd902f3d1ab"
    "7ac61dd29c6f21ba5b862f3730e37cfdc4fd806c22f221")

# And a cross-check against OpenSSL over generated inputs, because the RFC
# prints no vector whose length is not a multiple of 64 except one.
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
rnd = random.Random(20260827)
for n in list(range(0, 130)) + [255, 256, 257, 1023, 1024, 1025]:
    key = bytes(rnd.randrange(256) for _ in range(32))
    nonce = bytes(rnd.randrange(256) for _ in range(12))
    ctr = rnd.randrange(0, 1 << 20)
    data = bytes(rnd.randrange(256) for _ in range(n))
    # OpenSSL's ChaCha20 takes a 16 octet "nonce" that is counter||nonce
    full = ctr.to_bytes(4, "little") + nonce
    c = Cipher(algorithms.ChaCha20(key, full), mode=None).encryptor()
    want = c.update(data) + c.finalize()
    o.ask("chacha20 %s %s %d %s" % (x(key), x(nonce), ctr, x(data)),
          "ChaCha20 vs OpenSSL", x(want) if n else "-")
o.run()

# =====================================================================
# Poly1305 -- RFC 8439
# =====================================================================

# RFC 8439 2.5.2.
o.ask("poly1305 %s %s" % (
    "85d6be7857556d337f4452fe42d506a80103808afb0db2fd4abff6af4149f51b",
    x(b"Cryptographic Forum Research Group")), "RFC 8439 2.5.2",
    "a8061dc1305136c6c22b8baf0c0127a9")

# RFC 8439 Appendix A.3 -- eleven vectors, and they are chosen to hit
# exactly the places a limb based implementation goes wrong: r = 0, s
# alone, the wrap at 2^130-5, a carry that must NOT be dropped.
A3 = [
    ("00" * 32, "00" * 64, "00000000000000000000000000000000"),
    ("00" * 16 + "36e5f6b5c5e06070f0efca96227a863e",
     x(h("416e79207375626d697373696f6e20746f20746865204945544620696e74656e"
         "6465642062792074686520436f6e7472696275746f7220666f72207075626c69"
         "636174696f6e20617320616c6c206f722070617274206f6620616e2049455446"
         "20496e7465726e65742d4472616674206f722052464320616e6420616e792073"
         "746174656d656e74206d6164652077697468696e2074686520636f6e74657874"
         "206f6620616e204945544620616374697669747920697320636f6e7369646572"
         "656420616e20224945544620436f6e747269627574696f6e222e205375636820"
         "73746174656d656e747320696e636c756465206f72616c2073746174656d656e"
         "747320696e20494554462073657373696f6e732c2061732077656c6c20617320"
         "7772697474656e20616e6420656c656374726f6e696320636f6d6d756e696361"
         "74696f6e73206d61646520617420616e792074696d65206f7220706c6163652c"
         "207768696368206172652061646472657373656420746f")),
     "36e5f6b5c5e06070f0efca96227a863e"),
    ("36e5f6b5c5e06070f0efca96227a863e" + "00" * 16,
     x(h("416e79207375626d697373696f6e20746f20746865204945544620696e74656e"
         "6465642062792074686520436f6e7472696275746f7220666f72207075626c69"
         "636174696f6e20617320616c6c206f722070617274206f6620616e2049455446"
         "20496e7465726e65742d4472616674206f722052464320616e6420616e792073"
         "746174656d656e74206d6164652077697468696e2074686520636f6e74657874"
         "206f6620616e204945544620616374697669747920697320636f6e7369646572"
         "656420616e20224945544620436f6e747269627574696f6e222e205375636820"
         "73746174656d656e747320696e636c756465206f72616c2073746174656d656e"
         "747320696e20494554462073657373696f6e732c2061732077656c6c20617320"
         "7772697474656e20616e6420656c656374726f6e696320636f6d6d756e696361"
         "74696f6e73206d61646520617420616e792074696d65206f7220706c6163652c"
         "207768696368206172652061646472657373656420746f")),
     "f3477e7cd95417af89a6b8794c310cf0"),
    ("1c9240a5eb55d38af333888604f6b5f0473917c1402b80099dca5cbc207075c0"
     ,
     "2754776173206272696c6c69672c20616e642074686520736c6974687920746f"
     "7665730a446964206779726520616e642067696d626c6520696e207468652077"
     "6162653a0a416c6c206d696d737920776572652074686520626f726f676f7665"
     "732c0a416e6420746865206d6f6d65207261746873206f757467726162652e",
     "4541669a7eaaee61e708dc7cbcc5eb62"),
    # A.3 #5..#11: the carry and wrap cases.
    ("02" + "00" * 31, "ff" * 16, "03000000000000000000000000000000"),
    ("02" + "00" * 15 + "ff" * 16,
     "02000000000000000000000000000000", "03000000000000000000000000000000"),
    ("01" + "00" * 31,
     "fffffffffffffffffffffffffffffffff0ffffffffffffffffffffffffffffff"
     "11000000000000000000000000000000", "05000000000000000000000000000000"),
    ("01" + "00" * 31,
     "fffffffffffffffffffffffffffffffffbfefefefefefefefefefefefefefefe"
     "01010101010101010101010101010101", "00000000000000000000000000000000"),
    ("02" + "00" * 31,
     "fdffffffffffffffffffffffffffffff", "faffffffffffffffffffffffffffffff"),
    # A.3 #10 and #11 -- r = 01 00..00 04 00..00, s = 0. These two are the
    # reason a Poly1305 implementation gets written twice: they are the
    # cases where the final reduction must and must not subtract p.
    ("0100000000000000" + "0400000000000000" + "00" * 16,
     "e33594d7505e43b900000000000000003394d7505e4379cd0100000000000000"
     "00000000000000000000000000000000" + "01000000000000000000000000000000",
     "14000000000000005500000000000000"),
    ("0100000000000000" + "0400000000000000" + "00" * 16,
     "e33594d7505e43b900000000000000003394d7505e4379cd0100000000000000"
     "00000000000000000000000000000000",
     "13000000000000000000000000000000"),
]
for i, (key, msg, want) in enumerate(A3):
    key = "".join(key.split())
    msg = "".join(msg.split())
    if len(key) != 64 or len(msg) % 2:
        print("vectors.py: A.3 literal %d is malformed -- fix the file" % i)
        sys.exit(1)
    o.ask("poly1305 %s %s" % (key, msg if msg else "-"),
          "RFC 8439 A.3 Poly1305", want)
o.run()

# =====================================================================
# ChaCha20-Poly1305 AEAD -- RFC 8439
# =====================================================================

# RFC 8439 2.8.2.
AAD = "50515253c0c1c2c3c4c5c6c7"
KEY_282 = "808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f"
NONCE_282 = "070000004041424344454647"
o.ask("seal %s %s %s %s" % (KEY_282, NONCE_282, AAD, x(PLAIN_2_4_2)),
      "RFC 8439 2.8.2 seal",
      "d31a8d34648e60db7b86afbc53ef7ec2a4aded51296e08fea9e2b5a736ee62d6"
      "3dbea45e8ca9671282fafb69da92728b1a71de0a9e060b2905d6a5b67ecd3b36"
      "92ddbd7f2d778b8c9803aee328091b58fab324e4fad675945585808b4831d7bc"
      "3ff4def08e4b7a9de576d26586cec64b6116"
      "1ae10b594f09e26a7e902ecbd0600691")

# RFC 8439 Appendix A.5 -- the decryption direction, with a different
# key, a 12 octet AAD and a long body.
A5_CT = h(
    "64a0861575861af460f062c79be643bd5e805cfd345cf389f108670ac76c8cb2"
    "4c6cfc18755d43eea09ee94e382d26b0bdb7b73c321b0100d4f03b7f355894cf"
    "332f830e710b97ce98c8a84abd0b948114ad176e008d33bd60f982b1ff37c855"
    "9797a06ef4f0ef61c186324e2b3506383606907b6a7c02b0f9f6157b53c867e4"
    "b9166c767b804d46a59b5216cde7a4e99040c5a40433225ee282a1b0a06c523e"
    "af4534d7f83fa1155b0047718cbc546a0d072b04b3564eea1b422273f548271a"
    "0bb2316053fa76991955ebd63159434ecebb4e466dae5a1073a6727627097a10"
    "49e617d91d361094fa68f0ff77987130305beaba2eda04df997b714d6c6f2c29"
    "a6ad5cb4022b02709beead9d67890cbb22392336fea1851f38")
o.ask("open %s %s %s %s" % (
    "1c9240a5eb55d38af333888604f6b5f0473917c1402b80099dca5cbc207075c0",
    "000000000102030405060708",
    "f33388860000000000004e91",
    x(A5_CT)), "RFC 8439 A.5 open",
    x(h("496e7465726e65742d4472616674732061726520647261667420646f63756d65"
        "6e74732076616c696420666f722061206d6178696d756d206f6620736978206d"
        "6f6e74687320616e64206d617920626520757064617465642c207265706c6163"
        "65642c206f72206f62736f6c65746564206279206f7468657220646f63756d65"
        "6e747320617420616e792074696d652e20497420697320696e617070726f7072"
        "6961746520746f2075736520496e7465726e65742d4472616674732061732072"
        "65666572656e6365206d6174657269616c206f7220746f206369746520746865"
        "6d206f74686572207468616e206173202fe2809c776f726b20696e2070726f67"
        "726573732e2fe2809d")))

# The refusal that matters more than any success: one flipped bit in the
# ciphertext, one in the AAD, one in the tag -- each MUST be refused. An
# AEAD that returns plaintext for a broken tag is not an AEAD.
good = h("d31a8d34648e60db7b86afbc53ef7ec2a4aded51296e08fea9e2b5a736ee62d6"
         "3dbea45e8ca9671282fafb69da92728b1a71de0a9e060b2905d6a5b67ecd3b36"
         "92ddbd7f2d778b8c9803aee328091b58fab324e4fad675945585808b4831d7bc"
         "3ff4def08e4b7a9de576d26586cec64b61161ae10b594f09e26a7e902ecbd06"
         "00691")
o.ask("open %s %s %s %s" % (KEY_282, NONCE_282, AAD, x(good)),
      "AEAD refusals", x(PLAIN_2_4_2))
for pos in [0, 50, len(good) - 17, len(good) - 1]:
    bad = bytearray(good)
    bad[pos] ^= 0x01
    o.ask("open %s %s %s %s" % (KEY_282, NONCE_282, AAD, x(bytes(bad))),
          "AEAD refusals", "FAIL")
badaad = bytearray(h(AAD))
badaad[0] ^= 0x80
o.ask("open %s %s %s %s" % (KEY_282, NONCE_282, x(bytes(badaad)), x(good)),
      "AEAD refusals", "FAIL")
badkey = bytearray(h(KEY_282))
badkey[31] ^= 0x01
o.ask("open %s %s %s %s" % (x(bytes(badkey)), NONCE_282, AAD, x(good)),
      "AEAD refusals", "FAIL")
badnonce = bytearray(h(NONCE_282))
badnonce[11] ^= 0x01
o.ask("open %s %s %s %s" % (KEY_282, x(bytes(badnonce)), AAD, x(good)),
      "AEAD refusals", "FAIL")
o.ask("open %s %s %s 00" % (KEY_282, NONCE_282, AAD), "AEAD refusals", "FAIL")

# And the sweep against OpenSSL: every plaintext length across the block
# boundary, with and without associated data.
from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305
for n in list(range(0, 80)) + [127, 128, 129, 255, 256, 1000]:
    key = bytes(rnd.randrange(256) for _ in range(32))
    nonce = bytes(rnd.randrange(256) for _ in range(12))
    aad = bytes(rnd.randrange(256) for _ in range(rnd.randrange(0, 24)))
    pt = bytes(rnd.randrange(256) for _ in range(n))
    want = ChaCha20Poly1305(key).encrypt(nonce, pt, aad if aad else None)
    o.ask("seal %s %s %s %s" % (x(key), x(nonce), x(aad), x(pt)),
          "AEAD vs OpenSSL", x(want))
    o.ask("open %s %s %s %s" % (x(key), x(nonce), x(aad), x(want)),
          "AEAD vs OpenSSL", x(pt))
o.run()

# =====================================================================
# XChaCha20-Poly1305 -- draft-irtf-cfrg-xchacha, used by the cookie reply
# =====================================================================

# draft-irtf-cfrg-xchacha-03 section 2.2.1: the HChaCha20 vector. It is
# exercised through the AEAD, since the oracle exposes no bare HChaCha20:
# a wrong subkey cannot produce the right ciphertext.
# A.3.1 of the same draft, the AEAD vector.
o.ask("xseal %s %s %s %s" % (
    "808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f",
    "404142434445464748494a4b4c4d4e4f5051525354555657",
    "50515253c0c1c2c3c4c5c6c7",
    x(h("4c616469657320616e642047656e746c656d656e206f662074686520636c6173"
        "73206f66202739393a204966204920636f756c64206f6666657220796f75206f"
        "6e6c79206f6e652074697020666f7220746865206675747572652c2073756e73"
        "637265656e20776f756c642062652069742e"))),
    "draft-xchacha A.3.1",
    "bd6d179d3e83d43b9576579493c0e939572a1700252bfaccbed2902c21396cbb"
    "731c7f1b0b4aa6440bf3a82f4eda7e39ae64c6708c54c216cb96b72e1213b452"
    "2f8c9ba40db5d945b11b69b982c1bb9e3f3fac2bc369488f76b2383565d3fff9"
    "21f9664c97637da9768812f615c68b13b52e"
    "c0875924c1c7987947deafd8780acf49")

# Cross-check against libsodium over generated inputs.
try:
    from nacl.bindings import (
        crypto_aead_xchacha20poly1305_ietf_encrypt as xenc,
        crypto_aead_xchacha20poly1305_ietf_decrypt as xdec)
    for n in list(range(0, 40)) + [63, 64, 65, 200]:
        key = bytes(rnd.randrange(256) for _ in range(32))
        nonce = bytes(rnd.randrange(256) for _ in range(24))
        aad = bytes(rnd.randrange(256) for _ in range(rnd.randrange(0, 20)))
        pt = bytes(rnd.randrange(256) for _ in range(n))
        want = xenc(pt, aad, nonce, key)
        o.ask("xseal %s %s %s %s" % (x(key), x(nonce), x(aad), x(pt)),
              "XChaCha20 vs libsodium", x(want))
        o.ask("xopen %s %s %s %s" % (x(key), x(nonce), x(aad), x(want)),
              "XChaCha20 vs libsodium", x(pt))
except ImportError:
    print("note: PyNaCl missing, the libsodium cross-check was skipped")
o.run()

# =====================================================================
# X25519 -- RFC 7748
# =====================================================================

# RFC 7748 5.2, the two single vectors printed in the document.
o.ask("x25519 %s %s" % (
    "a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4",
    "e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c"),
    "RFC 7748 5.2",
    "c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552")
o.ask("x25519 %s %s" % (
    "4b66e9d4d1b4673c5ad22691957d6af5c11b6421e0ea01d42ca4169e7918ba0d",
    "e5210f12786811d3f4b7959d0538ae2c31dbe7106fc03c3efc4cd549c715a493"),
    "RFC 7748 5.2",
    "95cbde9476e8907d7aade45cb4b873f88b595a68799fa152e6f8f7647aac7957")

# RFC 7748 6.1, the Diffie-Hellman example: both sides must reach the
# same secret, and both public keys must be the ones printed.
A_PRIV = "77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a"
A_PUB = "8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a"
B_PRIV = "5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb"
B_PUB = "de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f"
SHARED = "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742"
o.ask("x25519base %s" % A_PRIV, "RFC 7748 6.1", A_PUB)
o.ask("x25519base %s" % B_PRIV, "RFC 7748 6.1", B_PUB)
o.ask("x25519 %s %s" % (A_PRIV, B_PUB), "RFC 7748 6.1", SHARED)
o.ask("x25519 %s %s" % (B_PRIV, A_PUB), "RFC 7748 6.1", SHARED)

# RFC 7748 5.2, the iterated test. After 1 round and after 1000 rounds
# the document prints the value. The million round checkpoint is behind
# --slow because it takes minutes.
BASE9 = "0900000000000000000000000000000000000000000000000000000000000000"
o.ask("x25519iter 1 %s" % BASE9, "RFC 7748 5.2 iterated",
      "422c8e7a6227d7bca1350b3e2bb7279f7897b87bb6854b783c60e80311ae3079")
o.ask("x25519iter 1000 %s" % BASE9, "RFC 7748 5.2 iterated",
      "684cf59ba83309552800ef566f2f4d3c1c3887c49360e3875f2eb94d99532c51")
if "--slow" in sys.argv:
    o.ask("x25519iter 1000000 %s" % BASE9, "RFC 7748 5.2 iterated",
          "7c3911e0ab2586fd864497297e575e6f3bc601c0883c30df5f4dd2d24f665424")

# Cross-check against libsodium over generated scalars and points, which
# is where the clamping and the masked top bit get exercised.
try:
    from nacl.bindings import crypto_scalarmult, crypto_scalarmult_base
    for _ in range(200):
        s = bytes(rnd.randrange(256) for _ in range(32))
        p = bytes(rnd.randrange(256) for _ in range(32))
        o.ask("x25519base %s" % x(s), "X25519 vs libsodium",
              x(crypto_scalarmult_base(s)))
        try:
            want = x(crypto_scalarmult(s, p))
        except Exception:
            continue  # libsodium refuses all-zero results; skip, not a pass
        o.ask("x25519 %s %s" % (x(s), x(p)), "X25519 vs libsodium", want)
    # The top bit of the u coordinate MUST be ignored (RFC 7748 5,
    # "decodeUCoordinate"): setting it must not change the answer.
    for _ in range(20):
        s = bytes(rnd.randrange(256) for _ in range(32))
        p = bytearray(rnd.randrange(256) for _ in range(32))
        p[31] &= 0x7F
        want = x(crypto_scalarmult(s, bytes(p)))
        p2 = bytearray(p)
        p2[31] |= 0x80
        o.ask("x25519 %s %s" % (x(s), x(bytes(p2))),
              "X25519 top bit ignored", want)
except ImportError:
    print("note: PyNaCl missing, the libsodium cross-check was skipped")
o.run()

# =====================================================================

print()
w = max(len(k) for k in GROUPS)
for k in sorted(GROUPS):
    n = GROUPS[k]
    bad = sum(1 for b in BAD if b[0] == k)
    print("  %-*s  %5d vectors  %s" % (
        w, k, n, "all passed" if bad == 0 else "%d FAILED" % bad))
print()
if BAD:
    print("%d of %d vectors FAILED" % (len(BAD), TOTAL))
    for tag, cmd, want, got in BAD[:12]:
        print("  [%s]" % tag)
        print("    asked: %s" % cmd[:150])
        print("    want : %s" % want[:150])
        print("    got  : %s" % got[:150])
    sys.exit(1)
print("%d vectors, all passed" % TOTAL)
