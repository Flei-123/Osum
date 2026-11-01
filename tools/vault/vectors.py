# SPDX-License-Identifier: GPL-2.0-only
import hashlib
import hmac as pyhmac
import sys

from cryptography.hazmat.primitives.ciphers import Cipher, algorithms


def chacha(key: bytes, nonce12: bytes, counter: int, data: bytes) -> bytes:
    full = counter.to_bytes(4, "little") + nonce12
    c = Cipher(algorithms.ChaCha20(key, full), mode=None)
    return c.encryptor().update(data)


RFC_2_3_2 = bytes.fromhex(
    "10f1e7e4d13b5915500fdd1fa32071c4"
    "c7d1f4c733c0680417a9e0dcc1d0d4e0"
    "b0b0b3b5c8f0e6e6d0a9b6a8d5b1f6d3"
)

def rfc_2_4_2_plain() -> bytes:
    return (b"Ladies and Gentlemen of the class of '99: If I could offer you "
            b"only one tip for the future, sunscreen would be it.")



ITERS = 2048

def fill(n: int, seed: int) -> bytes:
    s = seed
    out = bytearray()
    for _ in range(n):
        s = (s * 1103515245 + 12345) & 0xFFFFFFFF
        out.append((s >> 16) & 255)
    return bytes(out)


def H(key: bytes, msg: bytes) -> bytes:
    return pyhmac.new(key, msg, hashlib.sha256).digest()


def keyset(password: bytes, salt: bytes):
    mk = hashlib.pbkdf2_hmac("sha256", password, salt, ITERS, 32)
    return {
        "conv": H(mk, b"osum backup v1 convergence"),
        "enc": H(mk, b"osum backup v1 blockkey"),
        "mac": H(mk, b"osum backup v1 blockmac"),
        "chk": H(mk, b"osum backup v1 check"),
    }


def block_name(ks, plain: bytes) -> bytes:
    return H(ks["conv"], plain)


def seal(ks, plain: bytes):
    name = block_name(ks, plain)
    k = H(ks["enc"], name)
    ct = chacha(k, b"\0" * 12, 0, plain)
    tag = H(ks["mac"], name + ct)[:16]
    return name, ct, tag


def main() -> int:
    key = bytes(range(32))
    salt = bytes(range(16))

    n1 = bytes([0, 0, 0, 9, 0, 0, 0, 0x4A, 0, 0, 0, 0])
    cc1 = chacha(key, n1, 1, b"\0" * 64)
    print("cc1: " + cc1.hex())

    n2 = bytes([0, 0, 0, 0, 0, 0, 0, 0x4A, 0, 0, 0, 0])
    cc2 = chacha(key, n2, 1, rfc_2_4_2_plain())
    print("cc2: " + cc2.hex())

    p3 = fill(4096, 12345)
    cc3 = hashlib.sha256(chacha(key, n2, 0, p3)).hexdigest()
    print("cc3: " + cc3)

    print("hm1: " + H(key, p3).hex())

    print("pb1: " + hashlib.pbkdf2_hmac(
        "sha256", b"correct horse", salt, ITERS, 32).hex())

    ks = keyset(b"correct horse", salt)
    plain = fill(4096, 777)
    name, ct, tag = seal(ks, plain)
    print("sl1name: " + name.hex())
    print("sl1ct: " + ct[:32].hex())
    print("sl1tag: " + tag.hex())

    ks2 = keyset(b"battery staple", salt)
    print("sl5name: " + block_name(ks2, plain).hex())

    print("rfc242: " + (
        "6e2e359a2568f98041ba0728dd0d6981"
        "e97e7aec1d4360c20a27afccfd9fae0b"
        "f91b65c5524733ab8f593dabcd62b357"
        "1639d624e65152ab8f530c359f0861d8"
        "07ca0dbf500d6a6156a38e088a22b65e"
        "52bc514d16ccf806818ce91ab7793736"
        "5af90bbf74a35be6b40b8eedf2785e42"
        "874d"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
