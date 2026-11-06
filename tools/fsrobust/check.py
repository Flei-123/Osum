#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    check.py struktur <abbild>
    check.py inhalt   <abbild>
    check.py journal  <abbild>
"""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "..", "osum"))
import mkfs  # noqa: E402

BS = mkfs.BS
PER_BLOCK = 64
J_BLOCKS = 522
HEAD_MAGIC = 0x444145484A53464F
COMMIT_MAGIC = 0x4D4D4F434A53464F
FNV_OFF = 0xCBF29CE484222325
FNV_PRIME = 0x100000001B3
M64 = 0xFFFFFFFFFFFFFFFF


def mix(h, v):
    return ((h ^ v) * FNV_PRIME) & M64


def block_hash(b):
    h = FNV_OFF
    for i in range(0, BS, 8):
        h = mix(h, int.from_bytes(b[i:i + 8], "little"))
    return h


class Image_2:

    def __init__(self, path_2):
        self.f = open(path_2, "rb")
        self.len_2 = os.path.getsize(path_2)
        self.device = self.len_2 // BS
        sb = self.blk(0)
        self.magic = int.from_bytes(sb[0:8], "little") == mkfs.MAGIC

        def g(at):
            return int.from_bytes(sb[at:at + 8], "little")

        self.bsize = g(mkfs.SB["BSIZE"])
        self.blocks = g(mkfs.SB["BLOCKS"]) or self.device
        self.inodes = g(mkfs.SB["INODES"]) or mkfs.INODE_COUNT
        self.bmstart = g(mkfs.SB["BITMAP"]) or 1
        self.itable = g(mkfs.SB["ITABLE"]) or 2
        self.data = g(mkfs.SB["DATA"]) or 34
        self.root = g(mkfs.SB["ROOT"]) or 1
        self.version = g(mkfs.SB["VERSION"]) or 1
        self.bmblocks = g(mkfs.SB["BMBLOCKS"]) or 1
        self.isize = g(mkfs.SB["ISIZE"]) or mkfs.INODE_SIZE
        self.dirent = g(mkfs.SB["DIRENT"]) or mkfs.DIRENT
        self.namelen = g(mkfs.SB["NAMELEN"]) or mkfs.NAME_LEN
        self.jstart = g(mkfs.SB["JSTART"])
        self.jblocks = g(mkfs.SB["JBLOCKS"])
        self.ipb = BS // self.isize
        self.directs = 11 if self.version < 2 else 8
        if self.blocks > self.device:
            self.blocks = self.device
        if not (0 < self.itable < self.data <= self.blocks):
            self.data = min(max(self.itable + 1, 2), self.blocks)
        fits = max(1, (self.data - self.itable)) * self.ipb
        if self.inodes > fits:
            self.inodes = fits
        self.xin = 0
        self.xit = 0
        self.xbm = 0
        self.cover = (g(mkfs.SB["BMBLOCKS"]) or 1) * mkfs.BITS_PER_BLOCK
        self.hole_lo = 0
        self.hole_hi = 0
        if g(mkfs.SB["XVER"]):
            self.xin = g(mkfs.SB["XINODES"])
            self.xit = g(mkfs.SB["XITSTART"])
            self.xbm = g(mkfs.SB["XBMSTART"])
            self.hole_lo = self.blocks
            self.hole_hi = self.xit + (self.xin + self.ipb - 1) // self.ipb
            self.blocks = min(g(mkfs.SB["XBLOCKS"]), self.device)

    def total_inodes(self):
        return self.inodes + self.xin

    def valid(self, p):
        if p < self.data or p >= self.blocks:
            return False
        return not (self.hole_lo <= p < self.hole_hi)

    def blk(self, n):
        self.f.seek(n * BS)
        d = self.f.read(BS)
        if len(d) < BS:
            d = d + bytes(BS - len(d))
        return d

    def iat(self, ino):
        if self.xin and ino > self.inodes:
            slot = ino - 1 - self.inodes
            b = self.blk(self.xit + slot // self.ipb)
            o = (slot % self.ipb) * self.isize
            return b[o:o + self.isize]
        b = self.blk(self.itable + (ino - 1) // self.ipb)
        o = ((ino - 1) % self.ipb) * self.isize
        return b[o:o + self.isize]

    def ig(self, ino, field):
        d = self.iat(ino)
        return int.from_bytes(d[field:field + 8], "little")

    def bit(self, b):
        if self.xin and b >= self.cover:
            x = b - self.cover
            blk = self.blk(self.xbm + x // mkfs.BITS_PER_BLOCK)
            return (blk[(x % mkfs.BITS_PER_BLOCK) // 8] >> (x % 8)) & 1
        blk = self.blk(self.bmstart + b // mkfs.BITS_PER_BLOCK)
        return (blk[(b % mkfs.BITS_PER_BLOCK) // 8] >> (b % 8)) & 1

    def bloecke(self, ino):
        d = self.iat(ino)
        aus = []

        def g(at):
            return int.from_bytes(d[at:at + 8], "little")

        for k in range(self.directs):
            p = g(mkfs.I_DIRECT + k * 8)
            if p:
                aus.append(p)

        def level(p, tiefe):
            if not p:
                return
            aus.append(p)
            if not self.valid(p):
                return
            if aus.count(p) > 1:
                return
            b = self.blk(p)
            for i in range(PER_BLOCK):
                q = int.from_bytes(b[i * 8:i * 8 + 8], "little")
                if not q:
                    continue
                if tiefe == 1:
                    aus.append(q)
                else:
                    level(q, tiefe - 1)

        level(g(mkfs.I_INDIRECT), 1)
        level(g(mkfs.I_DINDIRECT), 2)
        if self.version >= 3:
            level(g(mkfs.I_TINDIRECT), 3)
            level(g(mkfs.I_QINDIRECT), 4)
        return aus

    def datenblock(self, ino, idx):
        d = self.iat(ino)

        def g(at):
            return int.from_bytes(d[at:at + 8], "little")

        def im(p):
            return p if self.valid(p) else 0

        def show(b, k):
            if not b:
                return 0
            blk = self.blk(b)
            return im(int.from_bytes(blk[k * 8:k * 8 + 8], "little"))

        if idx < self.directs:
            return im(g(mkfs.I_DIRECT + idx * 8))
        k = idx - self.directs
        if k < PER_BLOCK:
            return show(im(g(mkfs.I_INDIRECT)), k)
        k -= PER_BLOCK
        if k < PER_BLOCK ** 2:
            return show(show(im(g(mkfs.I_DINDIRECT)), k // PER_BLOCK),
                        k % PER_BLOCK)
        if self.version < 3:
            return 0
        k -= PER_BLOCK ** 2
        if k < PER_BLOCK ** 3:
            a = show(im(g(mkfs.I_TINDIRECT)), k // (PER_BLOCK ** 2))
            b = show(a, (k // PER_BLOCK) % PER_BLOCK)
            return show(b, k % PER_BLOCK)
        k -= PER_BLOCK ** 3
        if k >= PER_BLOCK ** 4:
            return 0
        a = show(im(g(mkfs.I_QINDIRECT)), k // (PER_BLOCK ** 3))
        b = show(a, (k // (PER_BLOCK ** 2)) % PER_BLOCK)
        c = show(b, (k // PER_BLOCK) % PER_BLOCK)
        return show(c, k % PER_BLOCK)

    def read_2(self, ino, off, n):
        aus = bytearray()
        while len(aus) < n:
            pos = off + len(aus)
            b = self.datenblock(ino, pos // BS)
            inb = pos % BS
            chunk = min(BS - inb, n - len(aus))
            if b == 0:
                aus += bytes(chunk)
            else:
                aus += self.blk(b)[inb:inb + chunk]
        return bytes(aus)

    def eintraege(self, ino):
        n = self.ig(ino, mkfs.I_SIZE) // self.dirent
        aus = []
        for i in range(n):
            roh = self.read_2(ino, i * self.dirent, self.dirent)
            kind = int.from_bytes(roh[0:8], "little")
            if not kind:
                continue
            name = roh[8:8 + self.namelen].split(b"\0")[0].decode(
                "latin-1")
            aus.append((kind, name))
        return aus

    def finde(self, path_2):
        ino = self.root
        for part in path_2.strip("/").split("/"):
            if not part:
                continue
            gefunden = 0
            for kind, name in self.eintraege(ino):
                if name == part:
                    gefunden = kind
                    break
            if not gefunden:
                return 0
            ino = gefunden
        return ino


def struktur(image):
    z = dict(dateien=0, dirs=0, bloecke=0, ausser=0, doppelt=0, badtype=0,
             lost=0, fehlend=0, totlinks=0, kreise=0)
    befunde = []
    if not image.magic:
        return ["keine OSUM-OFS-Kennung"], z
    if image.bsize != BS:
        befunde.append("Blockgroesse %d" % image.bsize)
    if not (image.bmstart < image.itable < image.data < image.blocks):
        befunde.append("Bereiche nicht in der Reihenfolge "
                       "Karte<Tabelle<Daten<Ende")
    seen = bytearray(image.blocks)
    for b in range(min(image.data, image.blocks)):
        seen[b] = 1
    for b in range(image.hole_lo, min(image.hole_hi, image.blocks)):
        seen[b] = 1
    for ino in range(1, image.total_inodes() + 1):
        art = image.ig(ino, mkfs.I_TYPE)
        if art == 0:
            continue
        if art not in (mkfs.T_FILE, mkfs.T_DIR, mkfs.T_LINK):
            z["badtype"] += 1
            continue
        z["dateien"] += 1
        if art == mkfs.T_DIR:
            z["dirs"] += 1
        for p in image.bloecke(ino):
            if not image.valid(p):
                z["ausser"] += 1
            elif seen[p]:
                z["doppelt"] += 1
            else:
                seen[p] = 1
                z["bloecke"] += 1
    for b in range(image.data, image.blocks):
        if image.hole_lo <= b < image.hole_hi:
            continue
        bit = image.bit(b)
        if bit and not seen[b]:
            z["lost"] += 1
        if not bit and seen[b]:
            z["fehlend"] += 1
    besucht = set()
    stack = [image.root]
    besucht.add(image.root)
    while stack:
        d = stack.pop()
        for kind, name in image.eintraege(d):
            if kind > image.total_inodes() or image.ig(kind, mkfs.I_TYPE) == 0:
                z["totlinks"] += 1
            elif image.ig(kind, mkfs.I_TYPE) == mkfs.T_DIR:
                if kind not in besucht:
                    besucht.add(kind)
                    stack.append(kind)
                elif name not in (".", ".."):
                    z["kreise"] += 1
    for k in ("ausser", "doppelt", "badtype", "lost", "fehlend",
              "totlinks", "kreise"):
        if z[k]:
            befunde.append("%s=%d" % (k, z[k]))
    return befunde, z


def journal(image):
    if not image.jstart or image.jblocks < J_BLOCKS:
        return dict(vorhanden=0)
    c = image.blk(image.jstart + 521)
    magic = int.from_bytes(c[0:8], "little")
    if magic != COMMIT_MAGIC:
        return dict(vorhanden=1, open_2=0)
    seq = int.from_bytes(c[8:16], "little")
    n = int.from_bytes(c[16:24], "little")
    sm = int.from_bytes(c[24:32], "little")
    if n == 0 or n > 512:
        return dict(vorhanden=1, open_2=1, gueltig=0, reason="Anzahl %d" % n)
    h = image.blk(image.jstart)
    if (int.from_bytes(h[0:8], "little") != HEAD_MAGIC
            or int.from_bytes(h[8:16], "little") != seq
            or int.from_bytes(h[16:24], "little") != n):
        return dict(vorhanden=1, open_2=1, gueltig=0, reason="Kopf passt nicht")
    ziele = []
    for k in range((n + 63) // 64):
        t = image.blk(image.jstart + 1 + k)
        for j in range(64):
            if k * 64 + j < n:
                ziele.append(int.from_bytes(t[j * 8:j * 8 + 8], "little"))
    p = mix(mix(FNV_OFF, seq), n)
    for i in range(n):
        p = mix(p, ziele[i])
        p = mix(p, block_hash(image.blk(image.jstart + 9 + i)))
    return dict(vorhanden=1, open_2=1, gueltig=1 if p == sm else 0,
                seq=seq, n=n)


def muster(g, k):
    return (((g * 2654435761) & M64) + ((k * 40503) & M64)) % 251


def inhalt(image):
    befunde = []
    d = image.finde("/d")
    if not d:
        return ["/d fehlt"], dict(count=0, ganz=0)
    ci = image.finde("/d/count")
    c = 0
    if ci:
        roh = image.read_2(ci, 0, image.ig(ci, mkfs.I_SIZE))
        ziffern = b""
        for ch in roh:
            if 48 <= ch <= 57:
                ziffern += bytes([ch])
            else:
                break
        c = int(ziffern) if ziffern else 0
    for name in ("/d/roll", "/d/roll2"):
        ri = image.finde(name)
        if ri:
            sz = image.ig(ri, mkfs.I_SIZE)
            if sz not in (0, 4096):
                befunde.append("%s ist %d Oktette gross" % (name, sz))
            elif sz == 0 and c:
                befunde.append("%s ist leer, der Zaehler steht auf %d"
                               % (name, c))
            elif sz == 4096:
                r = image.read_2(ri, 0, 4096)
                g = int.from_bytes(r[0:8], "little")
                for i in range(8, 4096):
                    if r[i] != muster(g, i):
                        befunde.append("%s: Oktett %d gehoert nicht zu "
                                       "Generation %d" % (name, i, g))
                        break
                if g < c:
                    befunde.append("%s ist Generation %d, der Zaehler "
                                   "steht auf %d" % (name, g, c))
        elif c:
            befunde.append("%s fehlt, obwohl der Zaehler auf %d steht"
                           % (name, c))
    ganz = 0
    for k in range(1, c + 1):
        ino = image.finde("/d/%d" % k)
        if not ino:
            befunde.append("/d/%d fehlt" % k)
            continue
        soll = 512 + (k * 617) % 1536
        sz = image.ig(ino, mkfs.I_SIZE)
        if sz != soll:
            befunde.append("/d/%d ist %d statt %d Oktette" % (k, sz, soll))
            continue
        roh = image.read_2(ino, 0, sz)
        bad_2 = -1
        for i in range(sz):
            if roh[i] != muster(k + 1000000, i):
                bad_2 = i
                break
        if bad_2 >= 0:
            befunde.append("/d/%d: Oktett %d falsch" % (k, bad_2))
            continue
        m = image.ig(ino, mkfs.I_MODE) & 0o7777
        if m != 0o600 + (k % 8):
            befunde.append("/d/%d traegt Modus %o statt %o"
                           % (k, m, 0o600 + (k % 8)))
        else:
            ganz += 1
    ino = image.finde("/d/%d" % (c + 1))
    next_2 = 0
    if ino:
        sz = image.ig(ino, mkfs.I_SIZE)
        soll = 512 + ((c + 1) * 617) % 1536
        if sz == 0:
            next_2 = 1
        elif sz == soll:
            roh = image.read_2(ino, 0, sz)
            ok = all(roh[i] == muster(c + 1 + 1000000, i) for i in range(sz))
            next_2 = 2 if ok else 3
        else:
            next_2 = 3
        if next_2 == 3:
            befunde.append("/d/%d ist halb geschrieben (%d Oktette)"
                           % (c + 1, sz))
    if image.finde("/d/%d" % (c + 2)):
        befunde.append("/d/%d gibt es, obwohl der Zaehler auf %d steht"
                       % (c + 2, c))
    return befunde, dict(count=c, ganz=ganz, next_2=next_2)


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    was, path_2 = argv[1], argv[2]
    image = Image_2(path_2)
    if was == "struktur":
        befunde, z = struktur(image)
        print("struktur: " + " ".join("%s=%d" % kv for kv in z.items()))
        for b in befunde:
            print("  BEFUND " + b)
        return 1 if befunde else 0
    if was == "journal":
        print("journal: " + " ".join("%s=%s" % kv
                                     for kv in journal(image).items()))
        return 0
    if was == "inhalt":
        befunde, z = inhalt(image)
        print("inhalt: " + " ".join("%s=%d" % kv for kv in z.items()))
        for b in befunde:
            print("  BEFUND " + b)
        return 1 if befunde else 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
