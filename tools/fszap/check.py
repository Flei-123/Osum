import struct
import sys

I_ATIME = 152


def load(path):
    with open(path, "rb") as f:
        img = f.read()
    sb = img[:512]
    inodes, itable = struct.unpack_from("<Q", sb, 24)[0], struct.unpack_from("<Q", sb, 40)[0]
    isize = struct.unpack_from("<Q", sb, 80)[0] or 128
    bm, bmb = struct.unpack_from("<Q", sb, 32)[0], struct.unpack_from("<Q", sb, 72)[0] or 1
    nodes = []
    for ino in range(1, inodes + 1):
        off = itable * 512 + (ino - 1) * isize
        raw = bytearray(img[off:off + isize])
        if isize >= I_ATIME + 8:
            raw[I_ATIME:I_ATIME + 8] = b"\0" * 8
        nodes.append(bytes(raw))
    return nodes, img[bm * 512:(bm + bmb) * 512], isize


def main():
    before, after, target = sys.argv[1], sys.argv[2], int(sys.argv[3])
    a, abm, isize = load(before)
    b, bbm, _ = load(after)
    changed = [i + 1 for i in range(len(a)) if a[i] != b[i]]
    print("changed", " ".join(str(c) for c in changed) or "none")
    print("bitmap", "same" if abm == bbm else "differs")
    t = b[target - 1]
    typ, size, nlink = struct.unpack_from("<QQQ", t, 0)
    ptrs = [struct.unpack_from("<Q", t, o)[0] for o in list(range(24, 88, 8)) + [112, 120, 128] + ([160] if isize > 168 else [])]
    print("target type", typ, "size", size, "nlink", nlink, "ptrs", "zero" if not any(ptrs) else "set")
    return 0


sys.exit(main())
