import os
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "osum"))
import mkfs

PTRS = [24 + 8 * i for i in range(8)] + [112, 120, 128, 160]
KINDS = (mkfs.T_FILE, mkfs.T_DIR, mkfs.T_LINK)


def wrace_pattern(n, kib):
    return bytes((((o * 131) + (n * 17) + ((o >> 12) * 7)) & 255) ^ 0x5A for o in range(kib * 1024))


def check_files(img, d, procs, kib):
    bad = 0
    for n in range(procs):
        p = subprocess.run([sys.executable, os.path.join(HERE, "..", "osum", "mkfs.py"), "cat", img,
                            "%s/f%d" % (d, n)], capture_output=True)
        if p.stdout != wrace_pattern(n, kib):
            bad += 1
            print("host: f%d differs (%d octets)" % (n, len(p.stdout)))
    return bad


def check_itable(img):
    fs = mkfs.load(img)
    if fs is None:
        print("host: superblock unreadable")
        return 1
    total = os.path.getsize(img) // mkfs.BS
    raw = open(img, "rb").read()
    count = struct.unpack_from("<Q", raw, mkfs.SB["INODES"])[0]
    nptr = len(PTRS) if fs.version >= mkfs.OFS_V3 else 10
    bad = 0
    for ino in range(1, count + 1):
        off = fs.inode_at(ino)
        if off + 256 > len(raw):
            break
        kind = struct.unpack_from("<Q", raw, off)[0]
        if kind == 0:
            continue
        if kind not in KINDS:
            bad += 1
            if bad <= 5:
                print("host: inode %d bad type %#x" % (ino, kind))
            continue
        for f in PTRS[:nptr]:
            v = struct.unpack_from("<Q", raw, off + f)[0]
            if v and (v < fs.data_start or v >= total):
                bad += 1
                if bad <= 5:
                    print("host: inode %d field %d points at %#x" % (ino, f, v))
                break
    return bad


def main():
    img, d, procs, kib = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
    fb = check_files(img, d, procs, kib)
    ib = check_itable(img)
    print("host: files_bad=%d inodes_bad=%d" % (fb, ib))
    sys.exit(1 if fb or ib else 0)


main()
