#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/exfat/exfat.py -- independent exFAT reader/writer for the host gate.

The host is an LXC without loop mounts, so the gate cannot mount an exFAT
image. This module is the reference: it parses an image made by
mkfs.exfat, populates it (files, directories, fragmented and contiguous
files, directories bigger than one cluster) and reads everything back.

Scope: 512-byte sectors, one FAT, bitmap in the root directory, names are
printable ASCII for writing and UTF-16 for reading, NoFatChain and
FAT-chained files and directories.

CLI:
  exfat.py populate IMG BASE   build the known tree, print "sha size path"
  exfat.py dump IMG BASE       print "sha size path" for every entry
"""
import hashlib
import struct
import sys

BS = 512


class ExFat:
    def __init__(self, path, base=0):
        self.f = open(path, "r+b")
        self.base = base
        b = self.rd(0, 512)
        assert b[3:11] == b"EXFAT   ", "no exFAT signature"
        self.fat_off, self.fat_len, self.heap_off, self.nclus, self.root = \
            struct.unpack_from("<IIIII", b, 80)
        assert b[108] == 9, "only 512-byte sectors"
        self.spc = 1 << b[109]
        self.csize = self.spc * BS
        self.bmp_first = None
        self.bmp_len = 0
        for e in self.dir_entries(self.root, False, None):
            if e[0] == 0x81:
                self.bmp_first = struct.unpack_from("<I", e, 20)[0]
                self.bmp_len = struct.unpack_from("<Q", e, 24)[0]
        assert self.bmp_first, "no bitmap entry"

    # ---- raw access
    def rd(self, off, n):
        self.f.seek(self.base + off)
        return self.f.read(n)

    def wr(self, off, data):
        self.f.seek(self.base + off)
        self.f.write(data)

    def clus_off(self, c):
        return (self.heap_off + (c - 2) * self.spc) * BS

    def fat_get(self, c):
        return struct.unpack("<I", self.rd(self.fat_off * BS + c * 4, 4))[0]

    def fat_set(self, c, v):
        self.wr(self.fat_off * BS + c * 4, struct.pack("<I", v))

    # ---- bitmap
    def bmp_get(self, c):
        i = c - 2
        return (self.rd(self.clus_off(self.bmp_first) + i // 8, 1)[0] >> (i % 8)) & 1

    def bmp_set(self, c, v):
        i = c - 2
        o = self.clus_off(self.bmp_first) + i // 8
        x = self.rd(o, 1)[0]
        x = (x | (1 << (i % 8))) if v else (x & ~(1 << (i % 8)))
        self.wr(o, bytes([x & 0xFF]))

    def used_count(self):
        return sum(1 for c in range(2, self.nclus + 2) if self.bmp_get(c))

    # ---- chains
    def chain_of(self, first, nofat, size):
        """cluster list of a file/directory with a known size"""
        n = (size + self.csize - 1) // self.csize
        if first == 0 or n == 0:
            return []
        if nofat:
            return list(range(first, first + n))
        out = []
        c = first
        while 2 <= c < 0xFFFFFFF0 and len(out) < n + 1:
            out.append(c)
            c = self.fat_get(c)
        return out

    def dir_chain(self, first, nofat, size):
        """cluster list of a directory (size None = follow the FAT)"""
        if nofat:
            return self.chain_of(first, True, size)
        cl = []
        c = first
        while 2 <= c < 0xFFFFFFF0 and len(cl) < 100000:
            cl.append(c)
            c = self.fat_get(c)
        return cl

    def read_file(self, d):
        data = b""
        for c in self.chain_of(d["first"], d["nofat"], d["size"]):
            data += self.rd(self.clus_off(c), self.csize)
        data = data[:d["size"]]
        if d["vdl"] < d["size"]:
            data = data[:d["vdl"]] + b"\0" * (d["size"] - d["vdl"])
        return data

    # ---- directories
    def dir_entries(self, first, nofat, size):
        out = []
        for c in self.dir_chain(first, nofat, size):
            blk = self.rd(self.clus_off(c), self.csize)
            for i in range(0, self.csize, 32):
                e = blk[i:i + 32]
                if e[0] == 0:
                    return out
                out.append(e)
        return out

    def list_dir(self, first, nofat, size):
        ents = self.dir_entries(first, nofat, size)
        res = []
        i = 0
        while i < len(ents):
            e = ents[i]
            if e[0] == 0x85:
                sec = e[1]
                st = ents[i + 1]
                assert st[0] == 0xC0, "stream entry missing"
                nlen = st[3]
                name = b""
                for k in range(2, 2 + sec - 1):
                    name += ents[i + k][2:32]
                name = name[:nlen * 2].decode("utf-16-le")
                raw = b"".join(ents[i:i + 1 + sec])
                res.append(dict(
                    name=name, attr=struct.unpack_from("<H", e, 4)[0],
                    first=struct.unpack_from("<I", st, 20)[0],
                    nofat=bool(st[1] & 2),
                    size=struct.unpack_from("<Q", st, 24)[0],
                    vdl=struct.unpack_from("<Q", st, 8)[0], idx=i,
                    sum=struct.unpack_from("<H", e, 2)[0],
                    sum_ok=(struct.unpack_from("<H", e, 2)[0] == self.set_checksum(raw)),
                    hash=struct.unpack_from("<H", st, 4)[0],
                    hash_ok=(struct.unpack_from("<H", st, 4)[0] == self.name_hash(name)),
                    raw=raw))
                i += 1 + sec
            else:
                i += 1
        return res

    def walk(self, first=None, nofat=False, size=None, prefix=""):
        if first is None:
            first, nofat, size = self.root, False, None
        for d in self.list_dir(first, nofat, size):
            p = prefix + "/" + d["name"]
            yield p, d
            if d["attr"] & 0x10:
                yield from self.walk(d["first"], d["nofat"], d["size"], p)

    def lookup(self, path):
        for p, d in self.walk():
            if p == path:
                return d
        return None

    # ---- checksums
    @staticmethod
    def set_checksum(raw):
        cs = 0
        for i, b in enumerate(raw):
            if i in (2, 3):
                continue
            cs = (((cs << 15) | (cs >> 1)) + b) & 0xFFFF
        return cs

    @staticmethod
    def name_hash(name):
        h = 0
        for b in name.upper().encode("utf-16-le"):
            h = (((h << 15) | (h >> 1)) + b) & 0xFFFF
        return h

    # ---- allocation
    def alloc_run(self, n):
        run = 0
        for c in range(2, self.nclus + 2):
            if self.bmp_get(c):
                run = 0
            else:
                run += 1
                if run == n:
                    first = c - n + 1
                    for k in range(first, first + n):
                        self.bmp_set(k, 1)
                    return first
        raise RuntimeError("no space")

    def alloc_one(self, after=0):
        for c in range(max(2, after + 1), self.nclus + 2):
            if not self.bmp_get(c):
                self.bmp_set(c, 1)
                return c
        raise RuntimeError("no space")

    def zero_clus(self, c):
        self.wr(self.clus_off(c), b"\0" * self.csize)

    def store(self, data, contiguous=True, spread=0):
        """-> (first, nofat). spread>0 skips clusters between pieces."""
        if not data:
            return 0, False   # empty file: first=0, no NoFatChain flag
        n = (len(data) + self.csize - 1) // self.csize
        if contiguous:
            first = self.alloc_run(n)
            for k in range(n):
                self.wr(self.clus_off(first + k),
                        data[k * self.csize:(k + 1) * self.csize].ljust(self.csize, b"\0"))
            return first, True
        cl = []
        last = 0
        for k in range(n):
            c = self.alloc_one(last + spread if last else 0)
            cl.append(c)
            last = c
        for k, c in enumerate(cl):
            self.wr(self.clus_off(c),
                    data[k * self.csize:(k + 1) * self.csize].ljust(self.csize, b"\0"))
            self.fat_set(c, cl[k + 1] if k + 1 < n else 0xFFFFFFFF)
        return cl[0], False

    # ---- creating entries
    def make_set(self, name, attr, first, nofat, size):
        u = name.encode("utf-16-le")
        nn = (len(name) + 14) // 15
        sec = 1 + nn
        e = bytearray(32 * (1 + sec))
        e[0] = 0x85
        e[1] = sec
        struct.pack_into("<H", e, 4, attr)
        for o in (8, 12, 16):
            struct.pack_into("<I", e, o, 0x5A2F0000)
        s = 32
        e[s] = 0xC0
        e[s + 1] = 0x01 | (0x02 if nofat else 0)
        e[s + 3] = len(name)
        struct.pack_into("<H", e, s + 4, self.name_hash(name))
        struct.pack_into("<Q", e, s + 8, size)
        struct.pack_into("<I", e, s + 20, first)
        struct.pack_into("<Q", e, s + 24, size)
        for k in range(nn):
            o = 64 + 32 * k
            e[o] = 0xC1
            part = u[k * 30:(k + 1) * 30]
            e[o + 2:o + 2 + len(part)] = part
        struct.pack_into("<H", e, 2, self.set_checksum(bytes(e)))
        return bytes(e)

    def _put_entries(self, cl, slot, raw):
        per = self.csize // 32
        for k in range(len(raw) // 32):
            s = slot + k
            self.wr(self.clus_off(cl[s // per]) + (s % per) * 32, raw[k * 32:(k + 1) * 32])

    def _dir_of(self, path):
        if path in ("", "/"):
            return self.root, False, None, None
        d = self.lookup(path)
        assert d and d["attr"] & 0x10, "no such dir " + path
        return d["first"], d["nofat"], d["size"], d

    def dir_append(self, dpath, raw):
        df, dn, ds, de = self._dir_of(dpath)
        used = len(self.dir_entries(df, dn, ds))
        cl = self.dir_chain(df, dn, ds)
        per = self.csize // 32
        need = len(raw) // 32
        grew = False
        while used + need > len(cl) * per:
            assert not dn, "cannot grow a NoFatChain directory"
            c = self.alloc_one()
            self.zero_clus(c)
            self.fat_set(cl[-1], c)
            self.fat_set(c, 0xFFFFFFFF)
            cl.append(c)
            grew = True
        self._put_entries(cl, used, raw)
        if grew and de is not None:
            parent = dpath.rsplit("/", 1)[0]
            pf, pn, ps, _ = self._dir_of(parent)
            pcl = self.dir_chain(pf, pn, ps)
            r = bytearray(de["raw"])
            struct.pack_into("<Q", r, 32 + 8, len(cl) * self.csize)
            struct.pack_into("<Q", r, 32 + 24, len(cl) * self.csize)
            struct.pack_into("<H", r, 2, self.set_checksum(bytes(r)))
            self._put_entries(pcl, de["idx"], bytes(r))

    def add_file(self, dirpath, name, data, contiguous=True, spread=0):
        first, nofat = self.store(data, contiguous, spread)
        self.dir_append(dirpath, self.make_set(name, 0x20, first, nofat, len(data)))

    def add_dir(self, dirpath, name, nofat=False):
        c = self.alloc_one()
        self.zero_clus(c)
        if not nofat:
            self.fat_set(c, 0xFFFFFFFF)
        self.dir_append(dirpath, self.make_set(name, 0x10, c, nofat, self.csize))

    def close(self):
        self.f.flush()
        self.f.close()


def pattern(n, seed):
    out = bytearray()
    x = (seed * 2654435761) & 0x7FFFFFFF
    while len(out) < n:
        x = (x * 1103515245 + 12345) & 0x7FFFFFFF
        out += struct.pack("<I", x)
    return bytes(out[:n])


# The known tree: (dir, name, size, seed, contiguous, spread)
TREE_FILES = [
    ("/", "hello.txt", 12, 1, True, 0),
    ("/", "empty.bin", 0, 2, True, 0),
    ("/", "one.bin", 1, 3, True, 0),
    ("/", "exact512.bin", 512, 4, True, 0),
    ("/", "contig.bin", 100000, 5, True, 0),
    ("/", "frag.bin", 70000, 6, False, 2),
    ("/", "big.bin", 1000000, 7, True, 0),
    ("/sub", "inner.txt", 100, 8, True, 0),
    ("/sub", "Mixed Case Name.dat", 3000, 9, False, 1),
    ("/sub/deep", "deepfile.bin", 5000, 10, True, 0),
]
MANY = 40  # files in /many: more than one 512-byte directory cluster


def populate(img, base):
    fs = ExFat(img, base)
    fs.add_dir("/", "sub")
    fs.add_dir("/sub", "deep", nofat=True)
    fs.add_dir("/", "many")
    for d, n, sz, seed, contig, spread in TREE_FILES:
        fs.add_file(d, n, pattern(sz, seed), contig, spread)
    for i in range(MANY):
        fs.add_file("/many", "file%02d.txt" % i, pattern(40 + i, 100 + i))
    fs.close()


def dump(img, base):
    fs = ExFat(img, base)
    rows = []
    for p, d in fs.walk():
        if d["attr"] & 0x10:
            rows.append("%s %d %s/" % ("-" * 64, 0, p))
        else:
            data = fs.read_file(d)
            rows.append("%s %d %s" % (hashlib.sha256(data).hexdigest(), len(data), p))
    fs.close()
    return rows


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "populate":
        populate(sys.argv[2], int(sys.argv[3]))
    if cmd in ("populate", "dump"):
        for r in dump(sys.argv[2], int(sys.argv[3])):
            print(r)
    else:
        sys.exit("usage: exfat.py populate|dump IMG BASE")
