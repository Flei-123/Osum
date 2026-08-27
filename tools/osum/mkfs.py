#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
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
    mkfs.py build <image> <blocks> [--v1] [--inodes=<n>] [<spec> ...]

`<neu>@<vorhanden>` ist ein ZWEITER NAME fuer dieselbe Datei (Runde K15):
zwei Verzeichniseintraege mit derselben Inode-Nummer, ein Exemplar der
Oktette.

`<path>=` mit nichts dahinter legt eine LEERE Datei an -- ein Name, ein
Inode, kein Datenblock. Der Namensindex des zweiten K15-Nachtrags wird an
mehreren Tausend davon gemessen, und mehrere Tausend Dateien mit Inhalt
passten nicht auf ein Abbild von zwei Megaoktett.

`--inodes=<n>` setzt die GROESSE DER INODE-TABELLE. Sie stand seit Runde
62 als 128 in beiden Umsetzungen; sie steht aber auch im Superblock, und
seit dem zweiten K15-Nachtrag liest `kernel/fs.fi` sie von dort. Ohne die
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
    def __init__(self, blocks, version=OFS_V2, inodes=INODE_COUNT):
        self.inodes = inodes
        self.itab_blocks = (inodes + INODES_PER_BLOCK - 1) // INODES_PER_BLOCK
        self.data_start = INODE_START + self.itab_blocks
        if blocks < self.data_start + 8:
            raise SystemExit("mkfs: a disk of %d blocks is too small for %d "
                             "inodes (the table alone takes %d)"
                             % (blocks, inodes, self.itab_blocks))
        if blocks > BS * 8:
            raise SystemExit("mkfs: the bitmap is one block, so at most %d "
                             "blocks fit; %d asked" % (BS * 8, blocks))
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
        b = self.data_start
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
        if ino < 1 or ino > self.inodes:
            raise SystemExit("mkfs: inode %d is outside the table (%d)"
                             % (ino, self.inodes))
        return ((INODE_START + (ino - 1) // INODES_PER_BLOCK) * BS
                + ((ino - 1) % INODES_PER_BLOCK) * INODE_SIZE)

    def iget(self, ino, field):
        return self.g64(self.inode_at(ino) + field)

    def iset(self, ino, field, v):
        self.p64(self.inode_at(ino) + field, v)

    def inode_alloc(self, kind):
        # Der naechste freie und nicht immer wieder von vorn: bei 4000
        # Dateien waere das linear von eins ein quadratischer Bau, und der
        # dauert auf dem Wirt Minuten statt Sekunden.
        start = getattr(self, "_next_ino", 1)
        for ino in range(start, self.inodes + 1):
            if self.iget(ino, I_TYPE) == T_FREE:
                at = self.inode_at(ino)
                self.d[at:at + INODE_SIZE] = bytes(INODE_SIZE)
                self.iset(ino, I_TYPE, kind)
                self.iset(ino, I_NLINK, 1)
                if self.version >= OFS_V2:
                    self.iset(ino, I_MODE, 0o755)
                self._next_ino = ino + 1
                return ino
        raise SystemExit("mkfs: no inode left (%d in the table)" % self.inodes)

    def used_inodes(self):
        return sum(1 for i in range(1, self.inodes + 1)
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

    # EIN GEDAECHTNIS JE VERZEICHNIS, und es ist nicht Bequemlichkeit.
    # `dir_find` und die Suche nach einem freien Platz gingen beide von
    # vorn durch das Verzeichnis; bei 4000 Dateien in einem Ordner sind
    # das acht Millionen Eintragsleseoperationen, und der Bau des
    # Messabbilds dauerte damit 59 Sekunden. Der Kernel darf so
    # arbeiten -- er legt selten viertausend Dateien an --, ein Werkzeug
    # auf dem Wirt nicht.
    def _cache(self, dirino):
        c = getattr(self, "_dc", None)
        if c is None:
            c = self._dc = {}
        got = c.get(dirino)
        if got is None:
            namen = {}
            frei = None
            n = self.dir_entries(dirino)
            for i in range(n):
                ino, name = self.entry(dirino, i)
                if ino:
                    namen[name] = ino
                elif frei is None:
                    frei = i
            got = c[dirino] = [namen, n if frei is None else frei]
        return got

    def dir_find(self, dirino, name):
        return self._cache(dirino)[0].get(name, 0)

    def dir_add(self, dirino, name, ino):
        if len(name.encode()) > NAME_LEN - 1:
            raise SystemExit("mkfs: the name '%s' is too long" % name)
        c = self._cache(dirino)
        slot = c[1]
        c[0][name] = ino
        c[1] = slot + 1
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

    # RUNDE K15: EIN ZWEITER NAME FUER DIESELBE DATEI.
    #
    # Ein Verzeichniseintrag ist eine Inode-Nummer und ein Name (32
    # Oktette, `kernel/fs.fi`). Zwei Eintraege mit DERSELBEN Nummer sind
    # deshalb zwei Namen fuer eine Datei -- ein harter Verweis, wie ihn
    # jedes Unix hat, und er braucht in diesem Format keine einzige neue
    # Zeile. Die Verweiszahl im Inode gibt es auch schon (`I_NLINK`); sie
    # wird hier hochgezaehlt, damit sie die Wahrheit sagt.
    #
    # WARUM DAS UND NICHT ZWEIMAL DIESELBE DATEI: `/bin/explorer` ist
    # 205 KiB. Zweimal waeren 410 KiB auf einem Abbild von 2 MiB, und die
    # beiden koennten auseinanderlaufen. Der Testlaeufer misst genau das:
    # er baut dasselbe Abbild einmal mit Verweis und einmal mit Kopie und
    # vergleicht die freien Bloecke.
    #
    # WAS DIESER KERNEL DABEI NOCH NICHT KANN, und es gehoert gesagt:
    # `unlink` zaehlt die Verweiszahl nicht herunter, es gibt den Inode
    # frei. Wer einen der beiden Namen loescht, macht den anderen
    # unbrauchbar. Auf einem Abbild, das nur gelesen wird -- und `/bin`
    # wird nur gelesen --, faellt das nicht an; ein `rm /bin/files` waere
    # trotzdem falsch, und das steht in docs/ROUNDK15.md.
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

    # ------------------------------------------------------------- format
    def format(self):
        self.p64(SB["MAGIC"], MAGIC)
        self.p64(SB["BSIZE"], BS)
        self.p64(SB["BLOCKS"], self.blocks)
        self.p64(SB["INODES"], self.inodes)
        self.p64(SB["BITMAP"], BITMAP_BLOCK)
        self.p64(SB["ITABLE"], INODE_START)
        self.p64(SB["DATA"], self.data_start)
        self.p64(SB["ROOT"], 1)
        self.p64(SB["VERSION"], self.version)
        for b in range(self.data_start):
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


# Ein Abbild vom Wirt lesen -- und die Geometrie AUS DEM SUPERBLOCK
# nehmen, nicht aus den Konstanten. Genau das tut `fs.mount` seit dem
# zweiten K15-Nachtrag auch; eine der beiden Umsetzungen, die es nicht
# taete, waere der Fehler, gegen den es die zweite ueberhaupt gibt.
def load(path):
    raw = open(path, "rb").read()
    if len(raw) < BS:
        return None
    inodes = struct.unpack_from("<Q", raw, SB["INODES"])[0] or INODE_COUNT
    version = struct.unpack_from("<Q", raw, SB["VERSION"])[0] or OFS_V2
    fs = Fs(max(len(raw) // BS, INODE_START
                + (inodes + INODES_PER_BLOCK - 1) // INODES_PER_BLOCK + 8),
            version, inodes)
    fs.d[:len(raw)] = raw
    if fs.g64(SB["MAGIC"]) != MAGIC:
        return None
    fs.root = fs.g64(SB["ROOT"])
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
        print("blocks=%d free=%d inodes=%d/%d"
              % (fs.g64(SB["BLOCKS"]), fs.free_blocks(), fs.used_inodes(),
                 fs.inodes))
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
    if cmd != "build":
        print("mkfs: unknown command '%s'" % cmd)
        return 2

    image, blocks = argv[2], int(argv[3])
    inodes = INODE_COUNT
    rest = []
    for spec in argv[4:]:
        if spec == "--v1":
            continue
        if spec.startswith("--inodes="):
            inodes = int(spec.split("=", 1)[1])
            continue
        rest.append(spec)
    fs = Fs(blocks, OFS_V1 if "--v1" in argv[4:] else OFS_V2, inodes)
    fs.format()
    for spec in rest:
        # ZWEI BEDEUTUNGEN FUER EIN ZEICHEN, und sie sind zu
        # unterscheiden: K13 haengt `@rechte[:uid[:gid]]` an einen
        # Dateinamen, K15 schreibt `<neu>@<vorhanden>` fuer einen
        # ZWEITEN NAMEN derselben Datei. Was hinter dem `@` steht,
        # entscheidet -- ein Pfad hat einen Schraegstrich, eine Rechte-
        # angabe hat nur Ziffern und Doppelpunkte. Beide Formen aus den
        # Runden davor gelten Zeichen fuer Zeichen weiter.
        mode, uid, gid = None, 0, 0
        if "@" in spec:
            head, _, meta = spec.partition("@")
            if "/" in meta:
                # <neuer pfad>@<vorhandener pfad> -- ein zweiter NAME fuer
                # dieselbe Datei, kein zweites Exemplar.
                fs.link(head, meta)
                continue
            spec = head
            parts = meta.split(":")
            mode = int(parts[0], 8)
            if len(parts) > 1 and parts[1] != "":
                uid = int(parts[1])
            if len(parts) > 2 and parts[2] != "":
                gid = int(parts[2])
        if spec.endswith("/"):
            fs.mkdir(spec[:-1], 0o755 if mode is None else mode, uid, gid)
            continue
        path, sep, host = spec.partition("=")
        if not sep:
            raise SystemExit("mkfs: '%s' needs <path>=<hostfile>" % spec)
        if not host:
            fs.addfile(path, b"")  # eine leere Datei: ein Name, kein Block
            continue
        with open(host, "rb") as f:
            fs.addfile(path, f.read(),
                       0o755 if mode is None else mode, uid, gid)
    with open(image, "wb") as f:
        f.write(fs.d)
    print("mkfs: %s  blocks=%d free=%d inodes=%d/%d data=%d"
          % (image, blocks, fs.free_blocks(), fs.used_inodes(), fs.inodes,
             fs.data_start))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
