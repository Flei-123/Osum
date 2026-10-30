import hashlib
import struct
import sys


def geometry(f):
    f.seek(0)
    sb = f.read(512)
    inodes, itable = struct.unpack_from("<QQ", sb, 24)[0], struct.unpack_from("<Q", sb, 40)[0]
    isize = struct.unpack_from("<Q", sb, 80)[0] or 128
    return inodes, itable, isize


def garbage(n):
    out = b""
    seed = b"hp inode 151"
    while len(out) < n:
        seed = hashlib.sha256(seed).digest()
        out += seed
    return out[:n]


def main():
    path, size = sys.argv[1], int(sys.argv[2])
    with open(path, "r+b") as f:
        inodes, itable, isize = geometry(f)
        per = 512 // isize
        for ino in range(1, inodes + 1):
            off = itable * 512 + (ino - 1) * isize
            f.seek(off)
            raw = f.read(isize)
            if struct.unpack_from("<Q", raw, 0)[0] == 1 and struct.unpack_from("<Q", raw, 8)[0] == size:
                f.seek(off)
                f.write(garbage(isize))
                slot = ino - 1
                partner = (slot // per) * per + ((slot % per) + 1) % per + 1
                print("planted", ino, "partner", partner)
                return 0
    print("no inode with size", size)
    return 1


sys.exit(main())
