#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import subprocess
import sys

SEQ16 = bytes(range(16)).hex()
SEQ24 = bytes(range(24)).hex()
SEQ32 = bytes(range(32)).hex()
FIPS_PT = "00112233445566778899aabbccddeeff"

AES_VECTORS = [
    ("FIPS-197 B AES-128", "2b7e151628aed2a6abf7158809cf4f3c",
     "3243f6a8885a308d313198a2e0370734", "3925841d02dc09fbdc118597196a0b32"),
    ("FIPS-197 C.1 AES-128", SEQ16, FIPS_PT,
     "69c4e0d86a7b0430d8cdb78070b4c55a"),
    ("FIPS-197 C.2 AES-192", SEQ24, FIPS_PT,
     "dda97ca4864cdfe06eaf70a0ec0d7191"),
    ("FIPS-197 C.3 AES-256", SEQ32, FIPS_PT,
     "8ea2b7ca516745bfeafc49904b496089"),
    ("SP 800-38A F.1.1 AES-128", "2b7e151628aed2a6abf7158809cf4f3c",
     "6bc1bee22e409f96e93d7e117393172a", "3ad77bb40d7a3660a89ecaf32466ef97"),
    ("SP 800-38A F.1.3 AES-192",
     "8e73b0f7da0e6452c810f32b809079e562f8ead2522c6b7b",
     "6bc1bee22e409f96e93d7e117393172a", "bd334f1d6e45f25ff712a214571fa5cc"),
]

ARGON_VECTORS = [
    ("argon2i ref t=2 m=65536 p=1", "argon2i",
     "c1628832147d9720c5bd1cfd61367078729f6dfb6f8fea9ff98158e0d7816ed0"),
    ("argon2id ref t=2 m=65536 p=1", "argon2id",
     "09316115d5cf24ed5a15a31a3ba326e5cf32edc24702987c02b6566f61913cf7"),
    ("argon2d ref t=2 m=65536 p=1", "argon2d",
     "955e5d5b163a1b60bba35fc36d0496474fba4f6b59ad53628666f07fb2f93eaf"),
]

XTS_KEY = ("2718281828459045235360287471352662497757247093699959574966967627"
           "3141592653589793238462643383279502884197169399375105820974944592")
XTS_TWEAK = "ff" + "00" * 15
XTS_PLAIN = bytes(range(256)).hex() * 2
XTS_CIPHER_PREFIX = ("1c3b3a102f770386e4836c99e370cf9b"
                     "ea00803f5e482357a4ae12d414a3e63b")


def oracle(binary, lines):
    run = subprocess.run([binary], input="\n".join(lines) + "\n",
                         capture_output=True, text=True, timeout=600)
    return run.stdout.strip().split("\n")


class Tally:
    def __init__(self):
        self.good = 0
        self.total = 0

    def check(self, name, want, got):
        self.total += 1
        if want == got:
            self.good += 1
            print("kat: ok   %s" % name)
        else:
            print("kat: FAIL %s want=%s got=%s" % (name, want, got))


def run_aes(binary, tally):
    for name, key, plain, cipher in AES_VECTORS:
        for via, label in ((0, "table"), (1, "aesni")):
            got = oracle(binary, [
                "aesblk 0 %d %s %s" % (via, key, plain),
                "aesblk 1 %d %s %s" % (via, key, cipher)])
            tally.check("%s %s encrypt" % (name, label), cipher, got[0])
            tally.check("%s %s decrypt" % (name, label), plain, got[1])


def run_argon(binary, tally):
    for name, word, want in ARGON_VECTORS:
        got = oracle(binary, [
            "%s %s %s 2 65536 1 32" % (word, b"password".hex(),
                                       b"somesalt".hex())])
        tally.check(name, want, got[0])


def run_xts(binary, tally):
    for mode, label in (("noaesni", "table"), ("aesni", "aesni")):
        got = oracle(binary, [
            mode,
            "xtsenc %s %s %s" % (XTS_KEY, XTS_TWEAK, XTS_PLAIN)])
        cipher = got[1]
        tally.check("IEEE 1619 vector 10 %s prefix" % label,
                    XTS_CIPHER_PREFIX, cipher[:len(XTS_CIPHER_PREFIX)])
        back = oracle(binary, [
            mode,
            "xtsdec %s %s %s" % (XTS_KEY, XTS_TWEAK, cipher)])
        tally.check("IEEE 1619 vector 10 %s round trip" % label,
                    XTS_PLAIN, back[1])


def main():
    if len(sys.argv) != 2:
        print("usage: kat.py <oracle>")
        return 2
    tally = Tally()
    run_aes(sys.argv[1], tally)
    run_argon(sys.argv[1], tally)
    run_xts(sys.argv[1], tally)
    print("kat total %d/%d" % (tally.good, tally.total))
    return 0 if tally.good == tally.total and tally.total > 0 else 1


if __name__ == "__main__":
    sys.exit(main())
