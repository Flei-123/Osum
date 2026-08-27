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
    mkfs.py build <image> <blocks> [--v1] [--v3] [--inodes=<n>]
                                   [--time=<t>] [--reserve=<n>] [<spec> ...]
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
OFS_V1, OFS_V2, OFS_V3 = 1, 2, 3
# RUNDE OFS3. Die zweite Umsetzung derselben Zahlen, die in
# `kernel/fs.fi` stehen -- und dass es zwei sind, ist der ganze Sinn
# dieser Datei: zwei Programme, zwei Sprachen, zwei Seiten der Platte.
INODE_SIZE_V3 = 256
IPB_V3 = 2
DIRENT_V3 = 264
NAME_V3 = 256
BITS_PER_BLOCK = BS * 8  # 4096
T_LINK = 3
I_TINDIRECT, I_CTIME, I_MTIME, I_ATIME = 128, 136, 144, 152
# ROUND K4: the twelfth direct slot became the double indirect pointer --
# 11 + 64 + 64 * 64 blocks instead of 12 + 64. `kernel/fs.fi` has the
# same three constants and the same two levels; the two must agree octet
# for octet, and section 3 of tools/posix/run.sh checks that they do.
I_DINDIRECT = 120
SB = dict(MAGIC=0, BSIZE=8, BLOCKS=16, INODES=24, BITMAP=32, ITABLE=40,
          DATA=48, ROOT=56, VERSION=64,
          # RUNDE OFS3: vier Felder, alle mit derselben Regel wie
          # VERSION -- eine Null heisst "wie vor dieser Runde".
          BMBLOCKS=72, ISIZE=80, DIRENT=88, NAMELEN=96)


class Fs:
    def __init__(self, blocks, version=OFS_V2, inodes=INODE_COUNT,
                 zeit=0):
        self.inodes = inodes
        self.version = version
        self.zeit = zeit
        # RUNDE OFS3: DIE GEOMETRIE HAENGT AN DER FASSUNG. Sie steht in
        # `kernel/fs.fi::format_as` noch einmal, Zeile fuer Zeile
        # dieselbe Rechnung -- und wenn eine der beiden sich irrt,
        # findet der Kernel die Bloecke nicht, die dieses Programm
        # geschrieben hat.
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
            self.bmblocks = 1
        self.bmstart = BITMAP_BLOCK
        self.itable = self.bmstart + self.bmblocks
        self.itab_blocks = (inodes + self.ipb - 1) // self.ipb
        self.data_start = self.itable + self.itab_blocks
        if blocks < self.data_start + 8:
            raise SystemExit("mkfs: a disk of %d blocks is too small for %d "
                             "inodes (the table alone takes %d)"
                             % (blocks, inodes, self.itab_blocks))
        if blocks > self.bmblocks * BITS_PER_BLOCK:
            raise SystemExit("mkfs: die Karte hat %d Bloecke, also passen "
                             "hoechstens %d Bloecke; %d verlangt"
                             % (self.bmblocks,
                                self.bmblocks * BITS_PER_BLOCK, blocks))
        self.blocks = blocks
        # RUNDE OFS3: NUR SO VIEL, WIE GEBRAUCHT WIRD. Am Anfang die
        # Verwaltung und ein paar Datenbloecke; `_deck` legt nach.
        self.d = bytearray(min(blocks, self.data_start + 64) * BS)
        self.root = 1
        self._hint = self.data_start

    # Dafuer sorgen, dass Block `b` im Puffer liegt.
    def _deck(self, b):
        noetig = (b + 1) * BS
        if len(self.d) < noetig:
            # In Schritten von mindestens 1 MiB, sonst kostet das
            # Nachlegen bei jeder Zuteilung eine Kopie des Ganzen.
            neu = max(noetig, len(self.d) * 2, len(self.d) + (1 << 20))
            neu = min(neu, self.blocks * BS)
            self.d.extend(bytes(neu - len(self.d)))

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
    # RUNDE OFS3: DIE KARTE IST MEHRBLOCKIG. Block `bmstart + k` traegt
    # die Bits der Bloecke k*4096 .. k*4096+4095. Das `% BITS_PER_BLOCK`
    # ist die ganze Aenderung -- und ohne es zeigte die Rechnung bei
    # Block 4096 in den naechsten Kartenblock hinein.
    def _bm_at(self, b):
        return ((self.bmstart + b // BITS_PER_BLOCK) * BS
                + (b % BITS_PER_BLOCK) // 8)

    def bit_set(self, b):
        self.d[self._bm_at(b)] |= 1 << (b % 8)

    def bit_get(self, b):
        return (self.d[self._bm_at(b)] >> (b % 8)) & 1

    def block_alloc(self):
        # Wie im Kernel: ab dem letzten Fund, nicht immer von vorn. Ein
        # Abbild von 100 MiB waere sonst auch auf dem Wirt quadratisch.
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

    # RUNDE OFS3: die ersten `n` Datenbloecke belegen, ohne sie zu
    # benutzen. Danach beginnt die naechste Zuteilung bei
    # `data_start + n`, und eine Datei landet dort, wo man sie haben
    # will: hinter der alten Zwei-Megaoktett-Grenze.
    def reserve(self, n):
        b = self.data_start
        ende = min(self.data_start + n, self.blocks)
        # OKTETTWEISE, sonst ist eine Reservierung von Millionen Bloecken
        # auf dem Wirt eine Sache von Minuten. Der Rand links und rechts
        # geht bitweise, alles dazwischen als ganzes Oktett.
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

    # OKTETTWEISE, nicht bitweise -- dieselbe Ueberlegung wie in
    # `fs.free_blocks`. Bei vier Millionen Bloecken ist der Unterschied
    # zwischen einer halben Sekunde und einer halben Minute.
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

    # ------------------------------------------------------------ inodes
    def inode_at(self, ino):
        if ino < 1 or ino > self.inodes:
            raise SystemExit("mkfs: inode %d is outside the table (%d)"
                             % (ino, self.inodes))
        return ((self.itable + (ino - 1) // self.ipb) * BS
                + ((ino - 1) % self.ipb) * self.isize)

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
                self.d[at:at + self.isize] = bytes(self.isize)
                self.iset(ino, I_TYPE, kind)
                self.iset(ino, I_NLINK, 1)
                if self.version >= OFS_V2:
                    self.iset(ino, I_MODE, 0o755)
                # RUNDE OFS3: die drei Zeiten entstehen mit der Datei --
                # dieselbe Regel wie in `fs.inode_init`.
                if self.version >= OFS_V3:
                    self.iset(ino, I_CTIME, self.zeit)
                    self.iset(ino, I_MTIME, self.zeit)
                    self.iset(ino, I_ATIME, self.zeit)
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
        if d < (BS // 8) ** 2:
            return self.double_block(ino, d, grow)
        # RUNDE OFS3: die dritte Stufe, 64 * 64 * 64 Bloecke.
        if self.version >= OFS_V3:
            t = d - (BS // 8) ** 2
            if t < (BS // 8) ** 3:
                return self.triple_block(ino, t, grow)
        raise SystemExit(
            "mkfs: a file may hold %d octets in this format (%d direct "
            "blocks, %d through the indirect one and %d through the "
            "double indirect one, see fs.fi); this one is bigger"
            % (self.max_file(), self.directs, BS // 8, (BS // 8) ** 2))

    def max_file(self):
        n = self.directs + BS // 8 + (BS // 8) ** 2
        if self.version >= OFS_V3:
            n += (BS // 8) ** 3
        return n * BS

    # Dieselbe Bewegung wie `fs.stufe` im Kernel: der k-te Zeiger AUS
    # einem Zeigerblock, angelegt wenn noetig.
    def stufe(self, block, k, grow):
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
        l2 = self.stufe(l1, t // (per * per), grow)
        if not l2:
            return 0
        l3 = self.stufe(l2, (t // per) % per, grow)
        if not l3:
            return 0
        return self.stufe(l3, t % per, grow)

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
        return self.iget(ino, I_SIZE) // self.dirent

    def entry(self, dirino, i):
        raw = self.read_at(dirino, i * self.dirent, self.dirent)
        if len(raw) < self.dirent:
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

    # RUNDE OFS3: die drei Zeiten, aus dem Abbild gelesen. Der WIRT
    # prueft damit, was der Kernel im Gastsystem geschrieben hat -- nicht
    # ein Mitschnitt einer seriellen Leitung, sondern der Inode.
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

    # EIN SYMBOLISCHER VERWEIS. Eine eigene Inode der Art T_LINK, deren
    # INHALT der Pfad ist -- kein Sonderfeld, keine zweite Tafel.
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
        self.p64(SB["BITMAP"], self.bmstart)
        self.p64(SB["ITABLE"], self.itable)
        self.p64(SB["DATA"], self.data_start)
        self.p64(SB["ROOT"], 1)
        self.p64(SB["VERSION"], self.version)
        # RUNDE OFS3: die vier neuen Felder NUR in Fassung 3. In der
        # Fassung 2 bleiben sie null, und eine Null heisst dort "wie
        # vorher" -- ein Abbild ohne `--v3` ist damit Oktett fuer Oktett
        # eines aus Runde K13.
        if self.version >= OFS_V3:
            self.p64(SB["BMBLOCKS"], self.bmblocks)
            self.p64(SB["ISIZE"], self.isize)
            self.p64(SB["DIRENT"], self.dirent)
            self.p64(SB["NAMELEN"], self.namelen)
        for b in range(self.data_start):
            self.bit_set(b)
        # WAS HINTER DER PLATTE LIEGT, GILT ALS BELEGT -- dieselbe Regel
        # wie in `fs.format_as`. Die Karte fasst ein Vielfaches von 4096
        # Bloecken; die Bits dahinter freizulassen hiesse, dem Zuteiler
        # Bloecke anzubieten, die es nicht gibt.
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
    # RUNDE OFS3: die Geometrie kommt aus dem SUPERBLOCK und nicht aus
    # der Fassungsnummer -- ein Abbild darf 256er Inodes und 32er
    # Eintraege haben, wenn es das von sich sagt. Genau das tut
    # `fs.mount` auch.
    ipb = INODES_PER_BLOCK
    if version >= OFS_V3:
        isz = struct.unpack_from("<Q", raw, SB["ISIZE"])[0] or INODE_SIZE
        ipb = BS // isz
    bmb = struct.unpack_from("<Q", raw, SB["BMBLOCKS"])[0] or 1
    noetig = (1 + bmb + (inodes + ipb - 1) // ipb + 8)
    fs = Fs(max(len(raw) // BS, noetig), version, inodes)
    fs.d[:len(raw)] = raw
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
                # DIESE ZEILE BLEIBT, WIE SIE IST. Runde OFS3 wollte hier
                # zuerst die drei Zeiten anhaengen -- und hat damit auf
                # einen Schlag zehn Zusagen aus `tools/k13/run.sh`
                # umgeworfen, die die Zeile Zeichen fuer Zeichen
                # vergleichen. Eine bestehende Ausgabe ist eine
                # Schnittstelle. Was neu ist, bekommt einen eigenen
                # Befehl: `mkfs.py times <abbild> <pfad>`.
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
        print("blocks=%d free=%d inodes=%d/%d version=%d maxfile=%d"
              % (fs.g64(SB["BLOCKS"]), fs.free_blocks(), fs.used_inodes(),
                 fs.inodes, fs.version, fs.max_file()))
        for line in fs.tree():
            print(line)
        return 0
    # RUNDE OFS3: DIE DREI ZEITEN UND DIE ART, vom WIRT aus dem Inode
    # gelesen. Die Gegenprobe zu allem, was der Kern im Gastsystem in
    # einen Inode schreibt -- kein Mitschnitt einer seriellen Leitung,
    # sondern die Oktette auf der Platte.
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
    # RUNDE OFS3: `where <abbild> <pfad>` sagt, AN WELCHEN BLOECKEN eine
    # Datei wirklich liegt. Ein Testlaeufer kann damit belegen, dass die
    # Datei, die der Kern gleich liest, an Block 8.000.000 steht -- eine
    # Nummer, fuer die es in Fassung 2 kein Bit gab.
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
        # RUNDE OFS3: `--reserve=<n>` MARKIERT DIE ERSTEN n DATENBLOECKE
        # ALS BELEGT, ohne sie irgendeiner Datei zu geben. Das ist die
        # einzige Art, eine Datei ABSICHTLICH weit hinten auf eine grosse
        # Platte zu legen, ohne die Platte vorher wirklich vollzuschreiben
        # -- und weit hinten ist genau die Stelle, an der die alte,
        # einblockige Karte nichts mehr verwalten konnte. Der Kern liest
        # die Datei danach an einer Blocknummer, die in Fassung 2 kein
        # Bit gehabt haette; DAS ist der Beweis, und nicht die Zahl im
        # Superblock.
        if spec.startswith("--reserve="):
            reserve = int(spec.split("=", 1)[1])
            continue
        rest.append(spec)
    # RUNDE OFS3: DIE VORGABE BLEIBT FASSUNG 2. Das ist keine
    # Zaghaftigkeit -- Abschnitt 15d von `tools/k15/run.sh` baut dasselbe
    # Abbild zweimal, vergleicht es mit `cmp` und prueft, dass der
    # Datenbereich weiter bei Block 34 liegt. Waere die Vorgabe die neue
    # Fassung, waeren 1486 bestehende Zusagen an einer anderen Platte
    # gemessen worden, und keine einzige davon haette es gesagt.
    v = OFS_V2
    if "--v1" in argv[4:]:
        v = OFS_V1
    if "--v3" in argv[4:]:
        v = OFS_V3
    fs = Fs(blocks, v, inodes, zeit)
    fs.format()
    if reserve:
        fs.reserve(reserve)
    if zeit:
        fs.set_times(1, zeit, zeit, zeit)
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
        # RUNDE OFS3: `<pfad>-><ziel>` ist ein SYMBOLISCHER Verweis. Das
        # Zeichen `>` kommt in keinem Pfad dieses Systems vor, und `->`
        # ist genau das, was `ls -l` fuer einen Verweis schreibt.
        if "->" in spec:
            pfad, _, ziel = spec.partition("->")
            fs.symlink(pfad, ziel)
            continue
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
        # RUNDE OFS3: der Rest der Platte ist ein LOCH. Er liest sich als
        # Nullen und belegt keinen Block auf dem Wirt.
        f.truncate(fs.blocks * BS)
    print("mkfs: %s  blocks=%d free=%d inodes=%d/%d data=%d version=%d "
          "bmblocks=%d isize=%d dirent=%d namelen=%d maxfile=%d"
          % (image, blocks, fs.free_blocks(), fs.used_inodes(), fs.inodes,
             fs.data_start, fs.version, fs.bmblocks, fs.isize, fs.dirent,
             fs.namelen, fs.max_file()))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
