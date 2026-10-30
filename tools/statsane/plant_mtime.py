import struct
import sys

I_TYPE = 0
I_SIZE = 8
I_MTIME = 144


def main():
    path, size, value = sys.argv[1], int(sys.argv[2]), int(sys.argv[3], 0)
    with open(path, "r+b") as f:
        sb = f.read(512)
        inodes, itable = struct.unpack_from("<Q", sb, 24)[0], struct.unpack_from("<Q", sb, 40)[0]
        isize = struct.unpack_from("<Q", sb, 80)[0] or 128
        for ino in range(1, inodes + 1):
            off = itable * 512 + (ino - 1) * isize
            f.seek(off)
            raw = f.read(isize)
            if struct.unpack_from("<Q", raw, I_TYPE)[0] == 1 and struct.unpack_from("<Q", raw, I_SIZE)[0] == size:
                f.seek(off + I_MTIME)
                f.write(struct.pack("<Q", value))
                print("planted", ino)
                return 0
    print("no inode with size", size)
    return 1


sys.exit(main())
