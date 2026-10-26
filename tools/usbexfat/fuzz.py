#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import random
import shutil
import struct
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0] + "/../exfat")
import exfat

WILD32 = [0, 1, 2, 3, 0xFFFFFFF7, 0xFFFFFFF8, 0xFFFFFFFF, 0x7FFFFFFF, 0x80000000]
WILD8 = [0, 1, 0x7F, 0x80, 0xFE, 0xFF]


def put_byte(fs, off, value):
    fs.wr(off, bytes([value & 0xFF]))


def boot_mutation(fs, rnd):
    off = rnd.choice(list(range(64, 120)) + [510, 511, 3, 4])
    value = rnd.choice(WILD8 + [rnd.randrange(256)])
    put_byte(fs, off, value)
    return "boot[%d]=%d" % (off, value)


def dir_mutation(fs, rnd, first, nofat, size):
    chain = fs.dir_chain(first, nofat, size)
    if not chain:
        return "dir-empty"
    cluster = rnd.choice(chain)
    entry = rnd.randrange(min(fs.csize // 32, 8))
    field = rnd.choice([1, 2, 3, 4, 5, 8, 9, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 31])
    off = fs.clus_off(cluster) + entry * 32 + field
    value = rnd.choice(WILD8 + [rnd.randrange(256)])
    put_byte(fs, off, value)
    return "dir[c%d e%d f%d]=%d" % (cluster, entry, field, value)


def fat_mutation(fs, rnd):
    used = [c for c in range(2, min(fs.nclus + 2, 400)) if fs.bmp_get(c)]
    c = rnd.choice(used)
    value = rnd.choice(WILD32 + [c, rnd.choice(used)])
    fs.fat_set(c, value)
    return "fat[%d]=%#x" % (c, value)


def bitmap_mutation(fs, rnd):
    off = fs.clus_off(fs.bmp_first) + rnd.randrange(8)
    put_byte(fs, off, rnd.choice([0, 0xFF, rnd.randrange(256)]))
    return "bitmap[%d]" % (off - fs.clus_off(fs.bmp_first))


def root_entry_mutation(fs, rnd):
    entry = rnd.randrange(8)
    field = rnd.choice([0, 1, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29])
    off = fs.clus_off(fs.root) + entry * 32 + field
    value = rnd.choice(WILD8 + [rnd.randrange(256)])
    put_byte(fs, off, value)
    return "root[e%d f%d]=%d" % (entry, field, value)


def mutate(fs, rnd):
    sub = fs.lookup("/sub")
    many = fs.lookup("/many")
    kind = rnd.randrange(6)
    if kind == 0:
        return boot_mutation(fs, rnd)
    if kind == 1:
        return root_entry_mutation(fs, rnd)
    if kind == 2:
        d = sub or many
        return dir_mutation(fs, rnd, d["first"], d["nofat"], d["size"])
    if kind == 3:
        return fat_mutation(fs, rnd)
    if kind == 4:
        return bitmap_mutation(fs, rnd)
    d = many or sub
    return dir_mutation(fs, rnd, d["first"], d["nofat"], d["size"])


def main():
    src, prefix, count, seed = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
    for i in range(count):
        out = "%s-%02d.fs" % (prefix, i)
        shutil.copyfile(src, out)
        fs = exfat.ExFat(out, 0)
        rnd = random.Random(seed * 1000 + i)
        notes = []
        for _ in range(1 + i % 3):
            notes.append(mutate(fs, rnd))
        fs.close()
        print("%02d %s" % (i, " ".join(notes)))


if __name__ == "__main__":
    main()
