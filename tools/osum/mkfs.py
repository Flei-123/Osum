#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/osum/mkfs.py -- an OFS disk image, built on the HOST.

Round K1 needs programs that the kernel has never seen. They therefore
cannot be produced by the kernel, and this is the second implementation
of the on-disk format of `kernel/fs/fs.fi` -- written from the
constants in that file and from nothing else.

That it IS a second implementation is the point. Two programs, in two
languages, on two sides of a disk, agreeing on where an inode lies and
how a directory entry is spelled: any disagreement shows up at once as a
file the kernel cannot find or a name it reads as rubbish. A single
implementation could be wrong in the same way twice and nobody would
know.

The format, from `kernel/fs/fs.fi`:

    block 0        superblock: magic, block size, blocks, inodes,
                   bitmap block, inode table, first data block, root inode
    block 1        the block bitmap, bit b in octet b/8
    blocks 2..33   the inode table, 128 octets each, four per block
    block 34..     data
    an inode       type, size, nlink, eleven direct blocks, one indirect,
                   one double indirect (round K4)
    a dirent       32 octets: inode number, then 24 for the name

Usage:
    mkfs.py build <image> <blocks> [--v1] [--v3] [--inodes=<n>]
                                   [--time=<t>] [--reserve=<n>] [--journal]
                                   [<spec> ...]
    mkfs.py where <image> <path>
    mkfs.py times <image> <path>

`<neu>@<vorhanden>` ist ein ZWEITER NAME fuer dieselbe Datei (Runde K15):
zwei Verzeichniseintraege mit derselben Inode-Nummer, ein Exemplar der
Oktette.

`<path>=` mit nichts dahinter legt eine LEERE Datei an -- ein Name, ein
Inode, kein Datenblock. Der Namensindex des zweiten K15-Nachtrags wird an
mehreren Tausend davon gemessen, und mehrere Tausend Dateien mit Inhalt
passten nicht auf ein Abbild von zwei Megaoktett.

RUNDE OFS3: `--v3` baut ein Abbild der FASSUNG 3 -- mehrblockige
Blockkarte, 256er Inodes mit drei Zeitstempeln und einem dreifach
indirekten Zeiger, 264er Verzeichniseintraege mit 255 Zeichen Namen und
den symbolischen Verweis als eigene Inodeart. OHNE `--v3` bleibt alles
bei Fassung 2, und zwar OKTETT FUER OKTETT: `tools/k15/run.sh` baut
dasselbe Abbild zweimal und vergleicht es mit `cmp`, und Abschnitt 15d
prueft ausdruecklich, dass der Datenbereich weiter bei Block 34 anfaengt.
Eine neue Fassung, die die alte still veraendert, waere keine.

`--time=<sekunden>` setzt die drei Zeitstempel JEDER Datei in einem
Abbild der Fassung 3. Ohne die Angabe sind sie NULL -- nicht "jetzt".
Der Grund steht eine Zeile weiter oben: dasselbe Abbild muss zweimal
dieselben Oktette ergeben, und `time.time()` tut das nicht.

`<pfad>-><ziel>` legt einen SYMBOLISCHEN VERWEIS an (nur Fassung 3).
Der Unterschied zu `<neu>@<vorhanden>` ist der zwischen einem zweiten
Namen und einem Zeiger: der harte Verweis ist dieselbe Inode, der
symbolische ist eine eigene Inode, deren INHALT ein Pfad ist.

`--inodes=<n>` setzt die GROESSE DER INODE-TABELLE. Sie stand seit Runde
62 als 128 in beiden Umsetzungen; sie steht aber auch im Superblock, und
seit dem zweiten K15-Nachtrag liest `kernel/fs/fs.fi` sie von dort. Ohne die
Angabe bleiben es 128 -- Abbild fuer Abbild dieselben Oktette wie vorher.
Die Tabelle waechst um einen Block je vier Inodes, und der erste
Datenblock rueckt entsprechend nach hinten. Die Blockkarte bleibt EIN
Block, also hoechstens 4096 Bloecke je Abbild.
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

import mmap
import os
import struct
import sys

sys.path.append(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "marke"))
import brandrender as brand_render

BS = 512
MAGIC = 0x4F53554D2D4F4653
INODE_SIZE = 128
INODES_PER_BLOCK = 4
INODE_COUNT = 128
BITMAP_BLOCK = 1
INODE_START = 2
INODE_BLOCKS = 32
DATA_START = 34
DIRENT = 32
NAME_LEN = 24
DIRECT = 8
DIRECT_V1 = 11

T_FREE, T_FILE, T_DIR = 0, 1, 2
I_TYPE, I_SIZE, I_NLINK, I_DIRECT, I_INDIRECT = 0, 8, 16, 24, 112
I_MODE, I_UID, I_GID = 88, 96, 104
OFS_V1, OFS_V2, OFS_V3 = 1, 2, 3
INODE_SIZE_V3 = 256
IPB_V3 = 2
DIRENT_V3 = 264
NAME_V3 = 256
BITS_PER_BLOCK = BS * 8
T_LINK = 3
I_TINDIRECT, I_CTIME, I_MTIME, I_ATIME = 128, 136, 144, 152
I_QINDIRECT = 160
I_DINDIRECT = 120
SB = dict(MAGIC=0, BSIZE=8, BLOCKS=16, INODES=24, BITMAP=32, ITABLE=40,
          DATA=48, ROOT=56, VERSION=64,
          BMBLOCKS=72, ISIZE=80, DIRENT=88, NAMELEN=96,
          BITBLOCKS=72,
          JSTART=104, JBLOCKS=112,
          XVER=120, XBLOCKS=128, XBMSTART=136, XITSTART=144, XINODES=152,
          XPLAN=160, XCURSOR=168)
J_BLOCKS = 522


class Fs:
    def __init__(self, blocks, version=OFS_V2, inodes=INODE_COUNT,
                 zeit=0, karten=0, journal=0):
        self.inodes = inodes
        self.version = version
        self.zeit = zeit
        if version >= OFS_V3:
            self.isize = INODE_SIZE_V3
            self.ipb = IPB_V3
            self.dirent = DIRENT_V3
            self.namelen = NAME_V3
            self.bmblocks = max(1, (blocks + BITS_PER_BLOCK - 1)
                                // BITS_PER_BLOCK)
        else:
            self.isize = INODE_SIZE
            self.ipb = INODES_PER_BLOCK
            self.dirent = DIRENT
            self.namelen = NAME_LEN
            self.bmblocks = max(1, (blocks + BITS_PER_BLOCK - 1)
                                // BITS_PER_BLOCK)
        if karten > self.bmblocks:
            self.bmblocks = karten
        self.karten = self.bmblocks
        self.bmstart = BITMAP_BLOCK
        self.itable = self.bmstart + self.bmblocks
        self.itab_blocks = (inodes + self.ipb - 1) // self.ipb
        self.journal = J_BLOCKS if journal else 0
        self.jstart = self.itable + self.itab_blocks if self.journal else 0
        self.data_start = self.itable + self.itab_blocks + self.journal
        if blocks < self.data_start + 8:
            raise SystemExit("mkfs: a disk of %d blocks is too small for %d "
                             "inodes (the table alone takes %d)"
                             % (blocks, inodes, self.itab_blocks))
        self.blocks = blocks
        self.d = bytearray(min(blocks, self.data_start + 64) * BS)
        self.root = 1
        self._hint = self.data_start
        self.xblocks = 0
        self.xbm = 0
        self.xit = 0
        self.xin = 0

    def _deck(self, b):
        noetig = (b + 1) * BS
        if len(self.d) < noetig:
            new = max(noetig, len(self.d) * 2, len(self.d) + (1 << 20))
            new = min(new, self.blocks * BS)
            self.d.extend(bytes(new - len(self.d)))

    @property
    def directs(self):
        return DIRECT if self.version >= OFS_V2 else DIRECT_V1

    def g64(self, at):
        return struct.unpack_from("<Q", self.d, at)[0]

    def p64(self, at, v):
        struct.pack_into("<Q", self.d, at, v & 0xFFFFFFFFFFFFFFFF)

    def _bm_at(self, b):
        cover = self.bmblocks * BITS_PER_BLOCK
        if self.xblocks and b >= cover:
            x = b - cover
            return ((self.xbm + x // BITS_PER_BLOCK) * BS
                    + (x % BITS_PER_BLOCK) // 8)
        return ((self.bmstart + b // BITS_PER_BLOCK) * BS
                + (b % BITS_PER_BLOCK) // 8)

    def bit_set(self, b):
        self.d[self._bm_at(b)] |= 1 << (b % 8)

    def bit_clear(self, b):
        self.d[self._bm_at(b)] &= 0xFF ^ (1 << (b % 8))

    def bit_get(self, b):
        return (self.d[self._bm_at(b)] >> (b % 8)) & 1

    def block_alloc(self):
        b = max(self._hint, self.data_start)
        while b < self.blocks:
            if not self.bit_get(b):
                self.bit_set(b)
                self._hint = b
                self._deck(b)
                return b
            b += 1
        b = self.data_start
        while b < self._hint:
            if not self.bit_get(b):
                self.bit_set(b)
                self._hint = b
                self._deck(b)
                return b
            b += 1
        raise SystemExit("mkfs: the disk is full")

    def reserve(self, n):
        b = self.data_start
        ende = min(self.data_start + n, self.blocks)
        while b < ende and (b % 8) != 0:
            self.bit_set(b)
            b += 1
        while b + 8 <= ende:
            self.d[self._bm_at(b)] = 0xFF
            b += 8
        while b < ende:
            self.bit_set(b)
            b += 1
        self._hint = ende
        return ende - self.data_start

    def free_blocks(self):
        frei = 0
        b = 0
        while b < self.blocks:
            rest = self.blocks - b
            if (b % 8) == 0 and rest >= 8:
                o = self.d[self._bm_at(b)]
                if o == 0:
                    frei += 8
                elif o != 255:
                    frei += 8 - bin(o).count("1")
                b += 8
            else:
                if not self.bit_get(b):
                    frei += 1
                b += 1
        return frei

    def inode_at(self, ino):
        if ino < 1 or ino > self.inodes + self.xin:
            raise SystemExit("mkfs: inode %d is outside the table (%d)"
                             % (ino, self.inodes + self.xin))
        if ino > self.inodes:
            slot = ino - 1 - self.inodes
            return ((self.xit + slot // self.ipb) * BS
                    + (slot % self.ipb) * self.isize)
        return ((self.itable + (ino - 1) // self.ipb) * BS
                + ((ino - 1) % self.ipb) * self.isize)

    def iget(self, ino, field):
        return self.g64(self.inode_at(ino) + field)

    def iset(self, ino, field, v):
        self.p64(self.inode_at(ino) + field, v)

    def inode_alloc(self, kind):
        start = getattr(self, "_next_ino", 1)
        for ino in range(start, self.inodes + 1):
            if self.iget(ino, I_TYPE) == T_FREE:
                at = self.inode_at(ino)
                self.d[at:at + self.isize] = bytes(self.isize)
                self.iset(ino, I_TYPE, kind)
                self.iset(ino, I_NLINK, 1)
                if self.version >= OFS_V2:
                    self.iset(ino, I_MODE, 0o755)
                if self.version >= OFS_V3:
                    self.iset(ino, I_CTIME, self.zeit)
                    self.iset(ino, I_MTIME, self.zeit)
                    self.iset(ino, I_ATIME, self.zeit)
                self._next_ino = ino + 1
                return ino
        raise SystemExit("mkfs: no inode left (%d in the table)" % self.inodes)

    def used_inodes(self):
        return sum(1 for i in range(1, self.inodes + self.xin + 1)
                   if self.iget(i, I_TYPE) != T_FREE)

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
        if d < (BS // 8) ** 2:
            return self.double_block(ino, d, grow)
        if self.version >= OFS_V3:
            t = d - (BS // 8) ** 2
            if t < (BS // 8) ** 3:
                return self.triple_block(ino, t, grow)
            q = t - (BS // 8) ** 3
            if q < (BS // 8) ** 4:
                return self.quad_block(ino, q, grow)
        raise SystemExit(
            "mkfs: a file may hold %d octets in this format (%d direct "
            "blocks, %d through the indirect one and %d through the "
            "double indirect one, see fs.fi); this one is bigger"
            % (self.max_file(), self.directs, BS // 8, (BS // 8) ** 2))

    def max_file(self):
        n = self.directs + BS // 8 + (BS // 8) ** 2
        if self.version >= OFS_V3:
            n += (BS // 8) ** 3 + (BS // 8) ** 4
        return n * BS

    def level_2(self, block, k, grow):
        b = self.g64(block * BS + k * 8)
        if b or not grow:
            return b
        b = self.block_alloc()
        self.p64(block * BS + k * 8, b)
        return b

    def triple_block(self, ino, t, grow):
        l1 = self.iget(ino, I_TINDIRECT)
        if not l1:
            if not grow:
                return 0
            l1 = self.block_alloc()
            self.iset(ino, I_TINDIRECT, l1)
        per = BS // 8
        l2 = self.level_2(l1, t // (per * per), grow)
        if not l2:
            return 0
        l3 = self.level_2(l2, (t // per) % per, grow)
        if not l3:
            return 0
        return self.level_2(l3, t % per, grow)

    def quad_block(self, ino, q, grow):
        l1 = self.iget(ino, I_QINDIRECT)
        if not l1:
            if not grow:
                return 0
            l1 = self.block_alloc()
            self.iset(ino, I_QINDIRECT, l1)
        per = BS // 8
        l2 = self.level_2(l1, q // per ** 3, grow)
        if not l2:
            return 0
        l3 = self.level_2(l2, (q // per ** 2) % per, grow)
        if not l3:
            return 0
        l4 = self.level_2(l3, (q // per) % per, grow)
        if not l4:
            return 0
        return self.level_2(l4, q % per, grow)

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

    def dir_entries(self, ino):
        return self.iget(ino, I_SIZE) // self.dirent

    def entry(self, dirino, i):
        raw = self.read_at(dirino, i * self.dirent, self.dirent)
        if len(raw) < self.dirent:
            return 0, ""
        ino = struct.unpack_from("<Q", raw, 0)[0]
        name = raw[8:].split(b"\0")[0].decode("ascii", "replace")
        return ino, name

    def _cache(self, dirino):
        c = getattr(self, "_dc", None)
        if c is None:
            c = self._dc = {}
        got = c.get(dirino)
        if got is None:
            names = {}
            frei = None
            n = self.dir_entries(dirino)
            for i in range(n):
                ino, name = self.entry(dirino, i)
                if ino:
                    names[name] = ino
                elif frei is None:
                    frei = i
            got = c[dirino] = [names, n if frei is None else frei]
        return got

    def dir_find(self, dirino, name):
        return self._cache(dirino)[0].get(name, 0)

    def dir_add(self, dirino, name, ino):
        if len(name.encode()) > self.namelen - 1:
            raise SystemExit("mkfs: the name '%s' is too long (%d Zeichen, "
                             "hoechstens %d in Fassung %d)"
                             % (name, len(name.encode()), self.namelen - 1,
                                self.version))
        c = self._cache(dirino)
        slot = c[1]
        c[0][name] = ino
        c[1] = slot + 1
        rec = bytearray(self.dirent)
        struct.pack_into("<Q", rec, 0, ino)
        rec[8:8 + len(name)] = name.encode()
        self.write_at(dirino, slot * self.dirent, bytes(rec))

    def dir_init(self, ino, parent):
        self.dir_add(ino, ".", ino)
        self.dir_add(ino, "..", parent)

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

    def get_times(self, ino):
        if self.version < OFS_V3:
            return 0, 0, 0
        return (self.iget(ino, I_CTIME), self.iget(ino, I_MTIME),
                self.iget(ino, I_ATIME))

    def set_times(self, ino, c, m, a):
        if self.version < OFS_V3:
            return
        self.iset(ino, I_CTIME, c)
        self.iset(ino, I_MTIME, m)
        self.iset(ino, I_ATIME, a)

    def symlink(self, path, target):
        if self.version < OFS_V3:
            raise SystemExit("mkfs: symbolische Verweise gibt es erst in "
                             "Fassung 3 (--v3)")
        dirino, name = self.parent_of(path)
        if self.dir_find(dirino, name):
            raise SystemExit("mkfs: '%s' ist schon da" % path)
        ino = self.inode_alloc(T_LINK)
        self.write_at(ino, 0, target.encode())
        self.dir_add(dirino, name, ino)
        self.set_meta(ino, 0o777, 0, 0)
        return ino

    def get_meta(self, ino):
        if self.version < OFS_V2:
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

    def link(self, newpath, oldpath):
        ino = self.resolve(oldpath)
        if not ino:
            raise SystemExit("mkfs: '%s' gibt es nicht" % oldpath)
        dirino, name = self.parent_of(newpath)
        if self.dir_find(dirino, name):
            raise SystemExit("mkfs: '%s' ist schon da" % newpath)
        self.dir_add(dirino, name, ino)
        self.iset(ino, I_NLINK, self.iget(ino, I_NLINK) + 1)
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

    def format(self):
        self.p64(SB["MAGIC"], MAGIC)
        self.p64(SB["BSIZE"], BS)
        self.p64(SB["BLOCKS"], self.blocks)
        self.p64(SB["INODES"], self.inodes)
        self.p64(SB["BITMAP"], self.bmstart)
        self.p64(SB["ITABLE"], self.itable)
        self.p64(SB["DATA"], self.data_start)
        self.p64(SB["ROOT"], 1)
        self.p64(SB["VERSION"], self.version)
        if self.version >= OFS_V3:
            self.p64(SB["BMBLOCKS"], self.bmblocks)
            self.p64(SB["ISIZE"], self.isize)
            self.p64(SB["DIRENT"], self.dirent)
            self.p64(SB["NAMELEN"], self.namelen)
        if self.journal:
            self.p64(SB["JSTART"], self.jstart)
            self.p64(SB["JBLOCKS"], self.journal)
        if self.version >= OFS_V3:
            pass
        elif self.bmblocks > 1:
            self.p64(SB["BMBLOCKS"], self.bmblocks)
        for b in range(self.data_start):
            self.bit_set(b)
        for b in range(self.blocks, self.bmblocks * BITS_PER_BLOCK):
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


def load(path):
    with open(path, "rb") as fh:
        raw = fh.read(BS)
    if len(raw) < BS:
        return None
    size = os.path.getsize(path)
    xver = struct.unpack_from("<Q", raw, SB["XVER"])[0]
    if xver:
        return load_ext(path, size)
    raw = open(path, "rb").read()
    inodes = struct.unpack_from("<Q", raw, SB["INODES"])[0] or INODE_COUNT
    version = struct.unpack_from("<Q", raw, SB["VERSION"])[0] or OFS_V2
    ipb = INODES_PER_BLOCK
    if version >= OFS_V3:
        isz = struct.unpack_from("<Q", raw, SB["ISIZE"])[0] or INODE_SIZE
        ipb = BS // isz
    bmb = struct.unpack_from("<Q", raw, SB["BMBLOCKS"])[0] or 1
    noetig = (1 + bmb + (inodes + ipb - 1) // ipb + 8)
    fs = Fs(max(len(raw) // BS, noetig), version, inodes, 0, bmb)
    fs.d[:len(raw)] = raw
    if version < OFS_V3 and bmb > 1:
        fs.bmblocks = bmb
        fs.karten = bmb
        fs.itable = struct.unpack_from("<Q", raw, SB["ITABLE"])[0]
        fs.data_start = struct.unpack_from("<Q", raw, SB["DATA"])[0]
    if version >= OFS_V3:
        fs.bmstart = struct.unpack_from("<Q", raw, SB["BITMAP"])[0] or 1
        fs.bmblocks = bmb
        fs.itable = struct.unpack_from("<Q", raw, SB["ITABLE"])[0]
        fs.isize = struct.unpack_from("<Q", raw, SB["ISIZE"])[0]
        fs.ipb = BS // fs.isize
        fs.dirent = struct.unpack_from("<Q", raw, SB["DIRENT"])[0]
        fs.namelen = struct.unpack_from("<Q", raw, SB["NAMELEN"])[0]
        fs.data_start = struct.unpack_from("<Q", raw, SB["DATA"])[0]
    if fs.g64(SB["MAGIC"]) != MAGIC:
        return None
    fs.root = fs.g64(SB["ROOT"])
    fs.version = fs.g64(SB["VERSION"]) or OFS_V1
    return fs


def load_ext(path, size):
    fh = open(path, "rb")
    mm = mmap.mmap(fh.fileno(), 0, access=mmap.ACCESS_READ)
    g = lambda k: struct.unpack_from("<Q", mm, SB[k])[0]
    if g("MAGIC") != MAGIC:
        return None
    version = g("VERSION") or OFS_V2
    fs = Fs(max(g("BLOCKS"), g("DATA") + 8), version, g("INODES") or INODE_COUNT,
            0, g("BMBLOCKS") or 1)
    fs.d = mm
    fs.bmstart = g("BITMAP") or 1
    fs.bmblocks = g("BMBLOCKS") or 1
    fs.itable = g("ITABLE")
    if version >= OFS_V3:
        fs.isize = g("ISIZE")
        fs.ipb = BS // fs.isize
        fs.dirent = g("DIRENT")
        fs.namelen = g("NAMELEN")
    fs.data_start = g("DATA")
    fs.root = g("ROOT")
    fs.xblocks = g("XBLOCKS")
    fs.xbm = g("XBMSTART")
    fs.xit = g("XITSTART")
    fs.xin = g("XINODES")
    fs.blocks = fs.xblocks
    return fs


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    cmd = argv[1]
    if cmd in ("list", "meta"):
        fs = load(argv[2])
        if fs is None:
            print("no OSUM-OFS magic")
            return 1
        if cmd == "meta":
            if len(argv) > 3:
                ino = fs.resolve(argv[3])
                if not ino:
                    print("mkfs: no such path '%s'" % argv[3])
                    return 1
                m, u, g = fs.get_meta(ino)
                print("%s %o %d %d" % (argv[3], m, u, g))
                return 0
            print("version=%d bmblocks=%d isize=%d dirent=%d namelen=%d"
                  % (fs.version, fs.bmblocks, fs.isize, fs.dirent,
                     fs.namelen))
            for line in fs.tree():
                path = line.split(" ")[0].rstrip("/")
                ino = fs.resolve(path)
                if ino:
                    m, u, g = fs.get_meta(ino)
                    print("%s %o %d %d" % (path, m, u, g))
            return 0
        line = ("blocks=%d free=%d inodes=%d/%d version=%d maxfile=%d"
                % (fs.xblocks or fs.g64(SB["BLOCKS"]), fs.free_blocks(),
                   fs.used_inodes(), fs.inodes + fs.xin, fs.version,
                   fs.max_file()))
        if fs.xblocks:
            line += (" ext=1 baseblocks=%d xinodes=%d xbm=%d xit=%d"
                     % (fs.g64(SB["BLOCKS"]), fs.xin, fs.xbm, fs.xit))
        print(line)
        for line in fs.tree():
            print(line)
        return 0
    if cmd == "times":
        fs = load(argv[2])
        if fs is None:
            print("no OSUM-OFS magic")
            return 1
        ino = fs.resolve(argv[3])
        if not ino:
            print("mkfs: no such path '%s'" % argv[3])
            return 1
        c, mt, a = fs.get_times(ino)
        art = {0: "free", 1: "file", 2: "dir",
               T_LINK: "link"}.get(fs.iget(ino, I_TYPE), "?")
        print("%s %s ctime=%d mtime=%d atime=%d" % (argv[3], art, c, mt, a))
        return 0
    if cmd == "cat":
        fs = load(argv[2])
        if fs is None:
            print("no OSUM-OFS magic")
            return 1
        ino = fs.resolve(argv[3])
        if not ino:
            print("mkfs: no such path '%s'" % argv[3])
            return 1
        size = fs.iget(ino, I_SIZE)
        sys.stdout.buffer.write(fs.read_at(ino, 0, size))
        return 0
    if cmd == "where":
        fs = load(argv[2])
        ino = fs.resolve(argv[3])
        if not ino:
            print("mkfs: no such path: %s" % argv[3])
            return 1
        size = fs.iget(ino, I_SIZE)
        n = (size + BS - 1) // BS
        erst = fs.file_block(ino, 0, False)
        letzt = fs.file_block(ino, n - 1, False) if n else 0
        print("where %s ino=%d size=%d blocks=%d first=%d last=%d"
              % (argv[3], ino, size, n, erst, letzt))
        return 0
    if cmd != "build":
        print("mkfs: unknown command '%s'" % cmd)
        return 2

    image, blocks = argv[2], int(argv[3])
    inodes = INODE_COUNT
    zeit = 0
    reserve = 0
    karten = 0
    journal = 0
    rest = []
    for spec in argv[4:]:
        if spec in ("--v1", "--v3"):
            continue
        if spec.startswith("--inodes="):
            inodes = int(spec.split("=", 1)[1])
            continue
        if spec.startswith("--time="):
            zeit = int(spec.split("=", 1)[1])
            continue
        if spec.startswith("--reserve="):
            reserve = int(spec.split("=", 1)[1])
            continue
        if spec.startswith("--karten="):
            karten = int(spec.split("=", 1)[1])
            continue
        if spec == "--journal":
            journal = 1
            continue
        rest.append(spec)
    v = OFS_V2
    if "--v1" in argv[4:]:
        v = OFS_V1
    if "--v3" in argv[4:]:
        v = OFS_V3
    if v == OFS_V2:
        v2max = (DIRECT + BS // 8 + (BS // 8) ** 2) * BS
        for spec in rest:
            if "=" not in spec:
                continue
            src = spec.partition("=")[2].split("@")[0]
            if os.path.isfile(src) and os.path.getsize(src) > v2max:
                print("mkfs: %s is bigger than a format-2 file may be (%d octets): "
                      "building format 3" % (src, v2max), file=sys.stderr)
                v = OFS_V3
                break
    fs = Fs(blocks, v, inodes, zeit, karten, journal)
    fs.format()
    if reserve:
        fs.reserve(reserve)
    if zeit:
        fs.set_times(1, zeit, zeit, zeit)
    for spec in rest:
        mode, uid, gid = None, 0, 0
        head, _, meta = spec.rpartition("@")
        if "@" in spec and "->" not in spec and "=" not in meta:
            if "/" in meta:
                fs.link(head, meta)
                continue
            spec = head
            parts = meta.split(":")
            mode = int(parts[0], 8)
            if len(parts) > 1 and parts[1] != "":
                uid = int(parts[1])
            if len(parts) > 2 and parts[2] != "":
                gid = int(parts[2])
        if "->" in spec:
            path_2, _, target_2 = spec.partition("->")
            fs.symlink(path_2, target_2)
            continue
        if spec.endswith("/"):
            fs.mkdir(spec[:-1], 0o755 if mode is None else mode, uid, gid)
            continue
        path, sep, host = spec.partition("=")
        if not sep:
            raise SystemExit("mkfs: '%s' needs <path>=<hostfile>" % spec)
        if not host:
            fs.addfile(path, b"")
            continue
        with open(host, "rb") as f:
            payload = brand_render.render_for_image(f.read(), host)
        fs.addfile(path, payload, 0o755 if mode is None else mode, uid, gid)
    with open(image, "wb") as f:
        f.write(fs.d)
        f.truncate(fs.blocks * BS)
    print("mkfs: %s  blocks=%d free=%d inodes=%d/%d data=%d version=%d "
          "bmblocks=%d isize=%d dirent=%d namelen=%d maxfile=%d "
          "jstart=%d jblocks=%d"
          % (image, blocks, fs.free_blocks(), fs.used_inodes(), fs.inodes,
             fs.data_start, fs.version, fs.bmblocks, fs.isize, fs.dirent,
             fs.namelen, fs.max_file(), fs.jstart, fs.journal))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
