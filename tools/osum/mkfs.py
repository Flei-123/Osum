#!/usr/bin/env python3
"""tools/osum/mkfs.py -- an OFS disk image, built on the HOST.

Round K1 needs programs that the kernel has never seen. They therefore
cannot be produced by the kernel, and this is the second implementation
of the on-disk format of `kernel/fs.fi` -- written from the
constants in that file and from nothing else.

That it IS a second implementation is the point. Two programs, in two
languages, on two sides of a disk, agreeing on where an inode lies and
how a directory entry is spelled: any disagreement shows up at once as a
file the kernel cannot find or a name it reads as rubbish. A single
implementation could be wrong in the same way twice and nobody would
know.

The format, from `kernel/fs.fi`:

    block 0        superblock: magic, block size, blocks, inodes,
                   bitmap block, inode table, first data block, root inode
    block 1        the block bitmap, bit b in octet b/8
    blocks 2..33   the inode table, 128 octets each, four per block
    block 34..     data
    an inode       type, size, nlink, eleven direct blocks, one indirect,
                   one double indirect (round K4)
    a dirent       32 octets: inode number, then 24 for the name

Usage:
    mkfs.py build <image> <blocks> [--v1] [<spec> ...]
    mkfs.py list  <image>
    mkfs.py cat   <image> <path>
    mkfs.py meta  <image> [<path>]

Ein <spec> ist eines von

    <pfad>/                        ein Verzeichnis
    <pfad>=<wirtsdatei>            eine Datei
    <pfad>=<wirtsdatei>@<rechte>[:<uid>[:<gid>]]
    <pfad>/@<rechte>[:<uid>[:<gid>]]

RUNDE K13 hat die letzten beiden Formen und `meta` dazugelegt. <rechte>
ist oktal wie ueberall (`755`, `4755`, `600`); ohne Angabe bekommt alles
0755 und gehoert root. `--v1` baut ein Abbild der ALTEN Fassung -- ohne
Rechte, mit elf direkten Blockzeigern. Das ist die Gegenprobe zur
Fassungsnummer im Superblock, und ohne sie waere "rueckwaertsvertraeglich"
eine Behauptung.

`cat` stand seit Runde K4 im Rumpf, aber nicht hier oben. Es schreibt die
Oktette einer Datei AUS DEM ABBILD auf die Standardausgabe -- und das ist
die einzige ehrliche Art, "das Programm hat die richtigen Oktette
gesichert" zu pruefen: nicht ein Mitschnitt ueber eine serielle Leitung,
sondern der Inhalt der Platte. Runde K11 misst den Editor damit.
"""

import struct
import sys

BS = 512
MAGIC = 0x4F53554D2D4F4653  # "OSUM-OFS"
INODE_SIZE = 128
INODES_PER_BLOCK = 4
INODE_COUNT = 128
BITMAP_BLOCK = 1
INODE_START = 2
INODE_BLOCKS = 32
DATA_START = 34
DIRENT = 32
NAME_LEN = 24
DIRECT = 8      # Fassung 2
DIRECT_V1 = 11  # Fassung 1, vor Runde K13

T_FREE, T_FILE, T_DIR = 0, 1, 2
I_TYPE, I_SIZE, I_NLINK, I_DIRECT, I_INDIRECT = 0, 8, 16, 24, 112
# RUNDE K13. Die drei Woerter, die aus den Blockzeigern 8, 9 und 10
# wurden (`kernel/fs.fi`, dieselben Offsets). In einem Abbild der Fassung
# 1 gibt es sie nicht.
I_MODE, I_UID, I_GID = 88, 96, 104
OFS_V1, OFS_V2 = 1, 2
# ROUND K4: the twelfth direct slot became the double indirect pointer --
# 11 + 64 + 64 * 64 blocks instead of 12 + 64. `kernel/fs.fi` has the
# same three constants and the same two levels; the two must agree octet
# for octet, and section 3 of tools/posix/run.sh checks that they do.
I_DINDIRECT = 120
SB = dict(MAGIC=0, BSIZE=8, BLOCKS=16, INODES=24, BITMAP=32, ITABLE=40,
          DATA=48, ROOT=56, VERSION=64)


class Fs:
    def __init__(self, blocks, version=OFS_V2):
        if blocks < DATA_START + 8:
            raise SystemExit("mkfs: a disk of %d blocks is too small" % blocks)
        self.blocks = blocks
        self.d = bytearray(blocks * BS)
        self.root = 1
        self.version = version

    # RUNDE K13: wie viele direkte Blockzeiger dieses Abbild hat. Die
    # ZWEITE Umsetzung derselben Regel, die in `kernel/fs.fi::directs`
    # steht -- und genau deshalb faellt es auf, wenn eine der beiden
    # sich irrt: der Kern faende dann die Bloecke nicht, die dieses
    # Programm geschrieben hat.
    @property
    def directs(self):
        return DIRECT if self.version >= OFS_V2 else DIRECT_V1

    # ------------------------------------------------------------ octets
    def g64(self, at):
        return struct.unpack_from("<Q", self.d, at)[0]

    def p64(self, at, v):
        struct.pack_into("<Q", self.d, at, v & 0xFFFFFFFFFFFFFFFF)

    # ------------------------------------------------------------ bitmap
    def bit_set(self, b):
        self.d[BITMAP_BLOCK * BS + b // 8] |= 1 << (b % 8)

    def bit_get(self, b):
        return (self.d[BITMAP_BLOCK * BS + b // 8] >> (b % 8)) & 1

    def block_alloc(self):
        b = DATA_START
        while b < self.blocks and b < BS * 8:
            if not self.bit_get(b):
                self.bit_set(b)
                return b
            b += 1
        raise SystemExit("mkfs: the disk is full")

    def free_blocks(self):
        return sum(1 for b in range(min(self.blocks, BS * 8))
                   if not self.bit_get(b))

    # ------------------------------------------------------------ inodes
    def inode_at(self, ino):
        return ((INODE_START + (ino - 1) // INODES_PER_BLOCK) * BS
                + ((ino - 1) % INODES_PER_BLOCK) * INODE_SIZE)

    def iget(self, ino, field):
        return self.g64(self.inode_at(ino) + field)

    def iset(self, ino, field, v):
        self.p64(self.inode_at(ino) + field, v)

    def inode_alloc(self, kind):
        for ino in range(1, INODE_COUNT + 1):
            if self.iget(ino, I_TYPE) == T_FREE:
                at = self.inode_at(ino)
                self.d[at:at + INODE_SIZE] = bytes(INODE_SIZE)
                self.iset(ino, I_TYPE, kind)
                self.iset(ino, I_NLINK, 1)
                if self.version >= OFS_V2:
                    self.iset(ino, I_MODE, 0o755)
                return ino
        raise SystemExit("mkfs: no inode left")

    def used_inodes(self):
        return sum(1 for i in range(1, INODE_COUNT + 1)
                   if self.iget(i, I_TYPE) != T_FREE)

    # ------------------------------------------------------------- files
    def file_block(self, ino, index, grow):
        if index < self.directs:
            b = self.iget(ino, I_DIRECT + index * 8)
            if b or not grow:
                return b
            b = self.block_alloc()
            self.iset(ino, I_DIRECT + index * 8, b)
            return b
        k = index - self.directs
        if k < BS // 8:
            return self.single_block(ino, k, grow)
        d = k - BS // 8
        if d >= (BS // 8) * (BS // 8):
            raise SystemExit(
                "mkfs: a file may hold %d octets in this format (%d direct "
                "blocks, %d through the indirect one and %d through the "
                "double indirect one, see fs.fi); this one is bigger"
                % ((self.directs + BS // 8 + (BS // 8) ** 2) * BS,
                   self.directs,
                   BS // 8, (BS // 8) ** 2))
        return self.double_block(ino, d, grow)

    def single_block(self, ino, k, grow):
        ib = self.iget(ino, I_INDIRECT)
        if not ib:
            if not grow:
                return 0
            ib = self.block_alloc()
            self.iset(ino, I_INDIRECT, ib)
        b = self.g64(ib * BS + k * 8)
        if b or not grow:
            return b
        b = self.block_alloc()
        self.p64(ib * BS + k * 8, b)
        return b

    def double_block(self, ino, d, grow):
        l1 = self.iget(ino, I_DINDIRECT)
        if not l1:
            if not grow:
                return 0
            l1 = self.block_alloc()
            self.iset(ino, I_DINDIRECT, l1)
        slot = d // (BS // 8)
        l2 = self.g64(l1 * BS + slot * 8)
        if not l2:
            if not grow:
                return 0
            l2 = self.block_alloc()
            self.p64(l1 * BS + slot * 8, l2)
        at = d % (BS // 8)
        b = self.g64(l2 * BS + at * 8)
        if b or not grow:
            return b
        b = self.block_alloc()
        self.p64(l2 * BS + at * 8, b)
        return b

    def write_at(self, ino, off, data):
        n = 0
        while n < len(data):
            pos = off + n
            inb = pos % BS
            chunk = min(BS - inb, len(data) - n)
            b = self.file_block(ino, pos // BS, True)
            self.d[b * BS + inb:b * BS + inb + chunk] = data[n:n + chunk]
            n += chunk
        if n and off + n > self.iget(ino, I_SIZE):
            self.iset(ino, I_SIZE, off + n)
        return n

    def read_at(self, ino, off, length):
        size = self.iget(ino, I_SIZE)
        want = 0 if off >= size else min(length, size - off)
        out = bytearray()
        n = 0
        while n < want:
            pos = off + n
            inb = pos % BS
            chunk = min(BS - inb, want - n)
            b = self.file_block(ino, pos // BS, False)
            if b:
                out += self.d[b * BS + inb:b * BS + inb + chunk]
            else:
                out += bytes(chunk)
            n += chunk
        return bytes(out)

    # -------------------------------------------------------- directories
    def dir_entries(self, ino):
        return self.iget(ino, I_SIZE) // DIRENT

    def entry(self, dirino, i):
        raw = self.read_at(dirino, i * DIRENT, DIRENT)
        if len(raw) < DIRENT:
            return 0, ""
        ino = struct.unpack_from("<Q", raw, 0)[0]
        name = raw[8:].split(b"\0")[0].decode("ascii", "replace")
        return ino, name

    def dir_find(self, dirino, name):
        for i in range(self.dir_entries(dirino)):
            ino, got = self.entry(dirino, i)
            if ino and got == name:
                return ino
        return 0

    def dir_add(self, dirino, name, ino):
        if len(name.encode()) > NAME_LEN - 1:
            raise SystemExit("mkfs: the name '%s' is too long" % name)
        slot = self.dir_entries(dirino)
        for i in range(slot):
            if self.entry(dirino, i)[0] == 0:
                slot = i
                break
        rec = bytearray(DIRENT)
        struct.pack_into("<Q", rec, 0, ino)
        rec[8:8 + len(name)] = name.encode()
        self.write_at(dirino, slot * DIRENT, bytes(rec))

    def dir_init(self, ino, parent):
        self.dir_add(ino, ".", ino)
        self.dir_add(ino, "..", parent)

    # -------------------------------------------------------------- paths
    def resolve(self, path):
        ino = self.root
        for part in [p for p in path.split("/") if p]:
            if self.iget(ino, I_TYPE) != T_DIR:
                return 0
            ino = self.dir_find(ino, part)
            if not ino:
                return 0
        return ino

    def parent_of(self, path):
        parts = [p for p in path.split("/") if p]
        if not parts:
            raise SystemExit("mkfs: '%s' names no file" % path)
        dirino = self.resolve("/".join(parts[:-1]))
        if not dirino:
            raise SystemExit("mkfs: '%s' has no directory" % path)
        return dirino, parts[-1]

    def set_meta(self, ino, mode, uid, gid):
        if self.version < OFS_V2:
            return
        self.iset(ino, I_MODE, mode & 0o7777)
        self.iset(ino, I_UID, uid)
        self.iset(ino, I_GID, gid)

    def get_meta(self, ino):
        if self.version < OFS_V2:
            # Dieselbe Antwort wie `kernel/fs.fi::inode_mode`: ein
            # Abbild der Fassung 1 traegt keine Rechte, und vor dieser
            # Runde war dort alles erlaubt.
            return 0o755, 0, 0
        return (self.iget(ino, I_MODE) & 0o7777, self.iget(ino, I_UID),
                self.iget(ino, I_GID))

    def mkdir(self, path, mode=0o755, uid=0, gid=0):
        dirino, name = self.parent_of(path)
        there = self.dir_find(dirino, name)
        if there:
            self.set_meta(there, mode, uid, gid)
            return there
        ino = self.inode_alloc(T_DIR)
        self.dir_init(ino, dirino)
        self.dir_add(dirino, name, ino)
        self.set_meta(ino, mode, uid, gid)
        return ino

    def addfile(self, path, data, mode=0o755, uid=0, gid=0):
        dirino, name = self.parent_of(path)
        if self.dir_find(dirino, name):
            raise SystemExit("mkfs: '%s' is already there" % path)
        ino = self.inode_alloc(T_FILE)
        if data:
            self.write_at(ino, 0, data)
        self.dir_add(dirino, name, ino)
        self.set_meta(ino, mode, uid, gid)
        return ino

    # ------------------------------------------------------------- format
    def format(self):
        self.p64(SB["MAGIC"], MAGIC)
        self.p64(SB["BSIZE"], BS)
        self.p64(SB["BLOCKS"], self.blocks)
        self.p64(SB["INODES"], INODE_COUNT)
        self.p64(SB["BITMAP"], BITMAP_BLOCK)
        self.p64(SB["ITABLE"], INODE_START)
        self.p64(SB["DATA"], DATA_START)
        self.p64(SB["ROOT"], 1)
        self.p64(SB["VERSION"], self.version)
        for b in range(DATA_START):
            self.bit_set(b)
        self.root = 1
        ino = self.inode_alloc(T_DIR)
        if ino != 1:
            raise SystemExit("mkfs: the root did not become inode 1")
        self.dir_init(1, 1)
        self.set_meta(1, 0o755, 0, 0)

    def tree(self, ino=None, prefix="/", out=None):
        if out is None:
            out = []
        if ino is None:
            ino = self.root
        for i in range(self.dir_entries(ino)):
            child, name = self.entry(ino, i)
            if not child or name in (".", ".."):
                continue
            if self.iget(child, I_TYPE) == T_DIR:
                out.append("%s%s/" % (prefix, name))
                self.tree(child, prefix + name + "/", out)
            else:
                out.append("%s%s %d" % (prefix, name,
                                        self.iget(child, I_SIZE)))
        return out


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    cmd = argv[1]
    if cmd in ("list", "meta"):
        raw = open(argv[2], "rb").read()
        fs = Fs(max(len(raw) // BS, DATA_START + 8))
        fs.d[:len(raw)] = raw
        if fs.g64(SB["MAGIC"]) != MAGIC:
            print("no OSUM-OFS magic")
            return 1
        fs.root = fs.g64(SB["ROOT"])
        fs.version = fs.g64(SB["VERSION"]) or OFS_V1
        if cmd == "meta":
            # RUNDE K13: Rechte und Eigentuemer AUS DEM ABBILD, auf dem
            # Wirt gelesen. Das ist die ehrliche Art zu pruefen, dass
            # `chmod` im Gastsystem etwas getan hat -- nicht ein
            # Mitschnitt einer seriellen Leitung, sondern der Inode.
            if len(argv) > 3:
                ino = fs.resolve(argv[3])
                if not ino:
                    print("mkfs: no such path '%s'" % argv[3])
                    return 1
                m, u, g = fs.get_meta(ino)
                print("%s %o %d %d" % (argv[3], m, u, g))
                return 0
            print("version=%d" % fs.version)
            for line in fs.tree():
                path = line.split(" ")[0].rstrip("/")
                ino = fs.resolve(path)
                if ino:
                    m, u, g = fs.get_meta(ino)
                    print("%s %o %d %d" % (path, m, u, g))
            return 0
        print("blocks=%d free=%d inodes=%d"
              % (fs.g64(SB["BLOCKS"]), fs.free_blocks(), fs.used_inodes()))
        for line in fs.tree():
            print(line)
        return 0
    if cmd == "cat":
        # ROUND K4: read a file back OFF an image, on the host. The
        # counter-check to the double indirect block lives on it
        # (tools/posix/run.sh, section 3): a file of 100000 octets is
        # written and has to come back octet for octet -- the old format
        # stopped at 38912, and a reader that still walked only one level
        # would give back the first 38912 and call it a file.
        raw = open(argv[2], "rb").read()
        fs = Fs(max(len(raw) // BS, DATA_START + 8))
        fs.d[:len(raw)] = raw
        if fs.g64(SB["MAGIC"]) != MAGIC:
            print("no OSUM-OFS magic")
            return 1
        fs.root = fs.g64(SB["ROOT"])
        fs.version = fs.g64(SB["VERSION"]) or OFS_V1
        ino = fs.resolve(argv[3])
        if not ino:
            print("mkfs: no such path '%s'" % argv[3])
            return 1
        size = fs.iget(ino, I_SIZE)
        sys.stdout.buffer.write(fs.read_at(ino, 0, size))
        return 0
    if cmd != "build":
        print("mkfs: unknown command '%s'" % cmd)
        return 2

    image, blocks = argv[2], int(argv[3])
    rest = [a for a in argv[4:] if a != "--v1"]
    fs = Fs(blocks, OFS_V1 if "--v1" in argv[4:] else OFS_V2)
    fs.format()
    for spec in rest:
        # RUNDE K13: das Anhaengsel `@rechte[:uid[:gid]]`. Es steht
        # HINTER dem Dateinamen und nicht davor, damit jeder Aufruf aus
        # den Runden K1 bis K12 Zeichen fuer Zeichen weiter gilt.
        mode, uid, gid = None, 0, 0
        if "@" in spec:
            spec, _, meta = spec.partition("@")
            parts = meta.split(":")
            mode = int(parts[0], 8)
            if len(parts) > 1 and parts[1] != "":
                uid = int(parts[1])
            if len(parts) > 2 and parts[2] != "":
                gid = int(parts[2])
        if spec.endswith("/"):
            fs.mkdir(spec[:-1], 0o755 if mode is None else mode, uid, gid)
            continue
        path, _, host = spec.partition("=")
        if not host:
            raise SystemExit("mkfs: '%s' needs <path>=<hostfile>" % spec)
        with open(host, "rb") as f:
            fs.addfile(path, f.read(),
                       0o755 if mode is None else mode, uid, gid)
    with open(image, "wb") as f:
        f.write(fs.d)
    print("mkfs: %s  blocks=%d free=%d inodes=%d"
          % (image, blocks, fs.free_blocks(), fs.used_inodes()))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
