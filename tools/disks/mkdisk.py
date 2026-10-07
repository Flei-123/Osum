#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/disks/mkdisk.py <outdir> -- disk images for the partition table reader (lib/disks/table.fi).

Writes, sparse, into <outdir>:
  gpt.img      16 MiB, protective MBR + GPT (primary and backup, right CRCs): EFI 1 MiB at 2048, OFS 8 MiB, "data" basic 4 MiB
  mbr.img      16 MiB, MBR with FAT32 (type 0x0C) at 2048 for 4 MiB and Linux (0x83) for 8 MiB after it
  badcrc.img   gpt.img with ONE byte of the entry array flipped (must read as no table)
  badhdr.img   gpt.img with one byte of the header flipped
  empty.img    16 MiB of zeros (no table)
  expect-*.txt the listing `unit` must print for each
"""
import os
import struct
import sys
import zlib

SECT = 512
TOTAL = 16 * 1024 * 1024 // SECT


def guid(bs):
    return bytes(bs)


BASIC = guid([0xA2, 0xA0, 0xD0, 0xEB, 0xE5, 0xB9, 0x33, 0x44, 0x87, 0xC0, 0x68, 0xB6, 0xB7, 0x26, 0x99, 0xC7])
ESP = guid([0x28, 0x73, 0x2A, 0xC1, 0x1F, 0xF8, 0xD2, 0x11, 0xBA, 0x4B, 0x00, 0xA0, 0xC9, 0x3E, 0xC9, 0x3B])
OFS = guid([0x4D, 0x55, 0x53, 0x4F, 0x46, 0x4F, 0x01, 0x53, 0x8E, 0x75, 0x6D, 0x6F, 0x72, 0x69, 0x4F, 0x53])
DISK = guid(range(1, 17))


def entry(tg, first, last, name):
    e = bytearray(128)
    e[0:16] = tg
    e[16:32] = guid([0x10 + len(name)] * 16)
    struct.pack_into("<QQQ", e, 32, first, last, 0)
    e[56:56 + 2 * len(name)] = name.encode("utf-16-le")
    return bytes(e)


def header(my, alt, first, last, ent_lba, ent_crc):
    h = bytearray(92)
    h[0:8] = b"EFI PART"
    struct.pack_into("<IIII", h, 8, 0x00010000, 92, 0, 0)
    struct.pack_into("<QQQQ", h, 24, my, alt, first, last)
    h[56:72] = DISK
    struct.pack_into("<QIII", h, 72, ent_lba, 128, 128, ent_crc)
    crc = zlib.crc32(bytes(h)) & 0xFFFFFFFF
    struct.pack_into("<I", h, 16, crc)
    return bytes(h)


def gpt():
    img = bytearray(TOTAL * SECT)
    # protective MBR
    img[446 + 4] = 0xEE
    struct.pack_into("<II", img, 446 + 8, 1, TOTAL - 1)
    img[510] = 0x55
    img[511] = 0xAA
    parts = [(ESP, 2048, 2048 + 2048 - 1, "EFI"), (OFS, 4096, 4096 + 16384 - 1, "OrientOS"),
             (BASIC, 4096 + 16384, 4096 + 16384 + 8192 - 1, "data")]
    arr = bytearray(128 * 128)
    for i, (tg, a, b, n) in enumerate(parts):
        arr[i * 128:(i + 1) * 128] = entry(tg, a, b, n)
    acrc = zlib.crc32(bytes(arr)) & 0xFFFFFFFF
    first, last = 34, TOTAL - 34
    img[SECT:SECT + 92] = header(1, TOTAL - 1, first, last, 2, acrc)
    img[2 * SECT:2 * SECT + len(arr)] = arr
    # backup: entries before the last sector, header in the last sector
    bent = TOTAL - 33
    img[bent * SECT:bent * SECT + len(arr)] = arr
    img[(TOTAL - 1) * SECT:(TOTAL - 1) * SECT + 92] = header(TOTAL - 1, 1, first, last, bent, acrc)
    return img, parts


def mbr():
    img = bytearray(TOTAL * SECT)
    def ent(i, typ, start, n):
        o = 446 + 16 * i
        img[o + 4] = typ
        struct.pack_into("<II", img, o + 8, start, n)
    ent(0, 0x0C, 2048, 8192)
    ent(1, 0x83, 2048 + 8192, 16384)
    img[510] = 0x55
    img[511] = 0xAA
    return img


KIND = {id(ESP): "efi", id(OFS): "ofs", id(BASIC): "basic"}


def write(d, name, data):
    with open(os.path.join(d, name), "wb") as f:
        f.write(data)


def main(d):
    os.makedirs(d, exist_ok=True)
    g, parts = gpt()
    write(d, "gpt.img", g)
    write(d, "mbr.img", mbr())
    b = bytearray(g)
    b[2 * SECT + 5] ^= 0x01
    write(d, "badcrc.img", b)
    h = bytearray(g)
    h[SECT + 40] ^= 0x01
    write(d, "badhdr.img", h)
    write(d, "empty.img", bytes(TOTAL * SECT))
    lines = ["scheme gpt count 3 total %d first 34 last %d flags 7" % (TOTAL, TOTAL - 34)]
    for i, (tg, a, bb, n) in enumerate(parts):
        lines.append("part %d start %d sectors %d kind %s name %s" % (i + 1, a, bb - a + 1, KIND[id(tg)], n))
    write(d, "expect-gpt.txt", ("\n".join(lines) + "\n").encode())
    write(d, "expect-mbr.txt", ("scheme mbr count 2 total %d first 0 last 0 flags 0\n"
                                "part 1 start 2048 sectors 8192 kind fat32 name \n"
                                "part 2 start 10240 sectors 16384 kind linux name \n" % TOTAL).encode())
    for n in ("badcrc", "badhdr", "empty"):
        write(d, "expect-%s.txt" % n, ("scheme none count 0 total %d first 0 last 0 flags 0\n" % TOTAL).encode())


if __name__ == "__main__":
    main(sys.argv[1])
