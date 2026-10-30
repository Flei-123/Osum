#!/usr/bin/env python3
import hashlib
import hmac
import os
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "krypto"))
import gegen

SECTOR = 512
SB_BITMAP = 32
SB_BLOCKS = 16


def build(src, dst, passphrase, t, m, p):
    data = open(src, "rb").read()
    if len(data) % SECTOR:
        data += b"\0" * (SECTOR - len(data) % SECTOR)
    sectors = len(data) // SECTOR
    master = os.urandom(gegen.KEY_LEN)
    while master[:32] == master[32:]:
        master = os.urandom(gegen.KEY_LEN)
    salt = os.urandom(gegen.SALT_LEN)
    wrap = gegen.kdf(passphrase, salt, t, m, p)
    wrapped = gegen.xts(wrap[:64], b"\0" * 16, master, False)
    mac = hmac.new(wrap[64:96], wrapped, hashlib.sha256).digest()
    hdr = bytearray(gegen.HDR_SECTORS * SECTOR)
    hdr[:len(gegen.MAGIC)] = gegen.MAGIC
    struct.pack_into("<IIII", hdr, gegen.H_VERSION, 1, 1, 1, SECTOR)
    struct.pack_into("<QQ", hdr, gegen.H_FIRST, gegen.HDR_SECTORS, sectors)
    base = gegen.SLOT_BASE
    struct.pack_into("<IIII", hdr, base + gegen.S_USED, 1, t, m, p)
    hdr[base + gegen.S_SALT:base + gegen.S_SALT + gegen.SALT_LEN] = salt
    hdr[base + gegen.S_WRAPPED:base + gegen.S_WRAPPED + gegen.KEY_LEN] = wrapped
    hdr[base + gegen.S_MAC:base + gegen.S_MAC + 32] = mac
    hdr[gegen.H_SUM:gegen.H_SUM + 32] = gegen.kopf_sum(bytes(hdr))
    with open(dst, "wb") as f:
        f.write(bytes(hdr))
        for i in range(sectors):
            f.write(gegen.xts(master, gegen.tweak_of(i),
                              data[i * SECTOR:(i + 1) * SECTOR], False))
    print("cryptdisk: header_sectors=%d data_sectors=%d slot=0 t=%d m=%d p=%d"
          % (gegen.HDR_SECTORS, sectors, t, m, p))


def leak(src, dst):
    data = bytearray(open(src, "rb").read())
    bitmap = struct.unpack_from("<Q", data, SB_BITMAP)[0]
    blocks = struct.unpack_from("<Q", data, SB_BLOCKS)[0]
    victim = blocks - 10
    off = bitmap * SECTOR + (victim // 8)
    data[off] |= 1 << (victim % 8)
    open(dst, "wb").write(data)
    print("cryptdisk: leaked_block=%d" % victim)


def corrupt(src, dst, sector):
    data = bytearray(open(src, "rb").read())
    off = (gegen.HDR_SECTORS + sector) * SECTOR
    for i in range(off, off + 32):
        data[i] ^= 0xFF
    open(dst, "wb").write(data)


def main(argv):
    if len(argv) >= 5 and argv[1] == "build":
        t, m, p = (int(x) for x in argv[5:8]) if len(argv) >= 8 else (1, 64, 1)
        build(argv[2], argv[3], argv[4].encode(), t, m, p)
        return 0
    if len(argv) == 4 and argv[1] == "leak":
        leak(argv[2], argv[3])
        return 0
    if len(argv) == 5 and argv[1] == "corrupt":
        corrupt(argv[2], argv[3], int(argv[4]))
        return 0
    print("usage: cryptdisk.py build <in> <out> <pass> [t m p] | leak <in> <out> | corrupt <in> <out> <data-sector>")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
