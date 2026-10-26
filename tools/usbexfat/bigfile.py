#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import struct
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0] + "/../exfat")
import exfat

MARK_HEAD = b"HEAD-MARK-0123456"
MARK_AT4G = b"AT4GIB-MARK-89abc"
MARK_TAIL = b"TAIL-MARK-fedcba9"
FOUR_GIB = 1 << 32


def bitmap_set_run(fs, first, n):
    base = fs.clus_off(fs.bmp_first)
    lo = first - 2
    hi = lo + n
    byte = lo // 8
    while byte * 8 < hi:
        bits = 0
        for b in range(8):
            c = byte * 8 + b
            if lo <= c < hi:
                bits |= 1 << b
        fs.wr(base + byte, bytes([fs.rd(base + byte, 1)[0] | bits]))
        byte += 1


def sparse_file(fs, name, size, chain):
    n = (size + fs.csize - 1) // fs.csize
    first = fs.alloc_run_fast(n)
    bitmap_set_run(fs, first, n)
    if chain:
        fat = bytearray()
        for k in range(n):
            fat += struct.pack("<I", first + k + 1 if k + 1 < n else 0xFFFFFFFF)
        fs.wr(fs.fat_off * 512 + first * 4, bytes(fat))
    marks = [(0, MARK_HEAD), (FOUR_GIB + 4096, MARK_AT4G), (size - len(MARK_TAIL), MARK_TAIL)]
    for off, data in marks:
        c = off // fs.csize
        fs.wr(fs.clus_off(first + c) + off % fs.csize, data)
    fs.dir_append("/", fs.make_set(name, 0x20, first, not chain, size))
    return first


def alloc_run_fast(self, n):
    first = 2
    while True:
        ok = True
        for c in range(first, first + n, 4096):
            if self.bmp_get(c):
                ok = False
                first = c + 1
                break
        if ok and not self.bmp_get(first + n - 1):
            return first
        if ok:
            first += n
        if first + n > self.nclus + 2:
            raise RuntimeError("no space")


exfat.ExFat.alloc_run_fast = alloc_run_fast

if __name__ == "__main__":
    img = sys.argv[1]
    base = int(sys.argv[2])
    size = int(sys.argv[3])
    fs = exfat.ExFat(img, base)
    sparse_file(fs, "bigA.bin", size, False)
    sparse_file(fs, "bigB.bin", size, True)
    fs.close()
