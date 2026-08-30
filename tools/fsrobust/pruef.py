#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/fsrobust/pruef.py -- dasselbe wie /bin/fsck, auf dem WIRT.

Es gibt in diesem Baum eine Regel, und sie ist der Grund fuer diese
Datei: JEDE Aussage ueber das Format auf der Platte hat zwei
Umsetzungen, eine im Kern und eine hier. `kernel/fs.fi` und
`tools/osum/mkfs.py` sind das eine Paar; `kernel/user/fsck.fi` und
dieses Programm sind das zweite. Eine einzelne Umsetzung kann zweimal
denselben Fehler machen und niemand merkt es.

Es prueft, was `fsck` prueft, und es prueft zusaetzlich, was ein
Programm in Ring 3 nicht kann: es zaehlt die Bloecke der EINZELNEN
Dateien nach und liest den Inhalt der Messdateien der Runde FSROBUST
(`/d/roll`, `/d/fN`, `/d/count`) direkt aus dem Abbild.

    pruef.py struktur <abbild>
    pruef.py inhalt   <abbild>
    pruef.py journal  <abbild>
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


class Bild:
    """Ein Abbild, blockweise, ohne es in den Speicher zu ziehen."""

    def __init__(self, pfad):
        self.f = open(pfad, "rb")
        self.laenge = os.path.getsize(pfad)
        self.geraet = self.laenge // BS
        sb = self.blk(0)
        self.magic = int.from_bytes(sb[0:8], "little") == mkfs.MAGIC

        def g(at):
            return int.from_bytes(sb[at:at + 8], "little")

        self.bsize = g(mkfs.SB["BSIZE"])
        self.blocks = g(mkfs.SB["BLOCKS"]) or self.geraet
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
        # ------------------------------------------------ DIE DECKELUNG
        #
        # Sie steht hier und nicht erst in der Pruefung, und sie ist der
        # Grund, warum dieses Programm auf einem mutwillig zerstoerten
        # Abbild FERTIG WIRD. Ein Superblock ist die Behauptung eines
        # fremden Programms; wer sie glaubt, laeuft bei "2^40 Inodes"
        # eine Billion Mal durch eine Tabelle, die es nicht gibt. Genau
        # das ist dem ersten Entwurf dieser Datei passiert, gemessen an
        # tools/fsrobust/kaputt.py, Fall `inodes`.
        if self.blocks > self.geraet:
            self.blocks = self.geraet
        if not (0 < self.itable < self.data <= self.blocks):
            self.data = min(max(self.itable + 1, 2), self.blocks)
        passt = max(1, (self.data - self.itable)) * self.ipb
        if self.inodes > passt:
            self.inodes = passt

    def blk(self, n):
        self.f.seek(n * BS)
        d = self.f.read(BS)
        if len(d) < BS:
            d = d + bytes(BS - len(d))
        return d

    # ---------------------------------------------------------- Inodes
    def iat(self, ino):
        # `ino - 1`: die Tabelle faengt bei Nummer EINS an, es gibt
        # keinen Platz null -- `kernel/fs.fi::inode_block_of` rechnet
        # genauso.
        b = self.blk(self.itable + (ino - 1) // self.ipb)
        o = ((ino - 1) % self.ipb) * self.isize
        return b[o:o + self.isize]

    def ig(self, ino, feld):
        d = self.iat(ino)
        return int.from_bytes(d[feld:feld + 8], "little")

    def bit(self, b):
        blk = self.blk(self.bmstart + b // mkfs.BITS_PER_BLOCK)
        return (blk[(b % mkfs.BITS_PER_BLOCK) // 8] >> (b % 8)) & 1

    # Alle Bloecke, auf die eine Inode zeigt -- Daten UND Zeigerbloecke.
    def bloecke(self, ino):
        d = self.iat(ino)
        aus = []

        def g(at):
            return int.from_bytes(d[at:at + 8], "little")

        for k in range(self.directs):
            p = g(mkfs.I_DIRECT + k * 8)
            if p:
                aus.append(p)

        def stufe(p, tiefe):
            if not p:
                return
            aus.append(p)
            if p < self.data or p >= self.blocks:
                return
            if aus.count(p) > 1:
                # SCHON EINMAL DA. Ein Zeigerblock, der auf sich selbst
                # zeigt, wird EINMAL gezaehlt und nicht betreten --
                # dieselbe Regel wie in `kernel/user/fsck.fi`, sonst
                # sagen die beiden Umsetzungen ueber dasselbe kaputte
                # Abbild verschiedene Zahlen.
                return
            b = self.blk(p)
            for i in range(PER_BLOCK):
                q = int.from_bytes(b[i * 8:i * 8 + 8], "little")
                if not q:
                    continue
                if tiefe == 1:
                    aus.append(q)
                else:
                    stufe(q, tiefe - 1)

        stufe(g(mkfs.I_INDIRECT), 1)
        stufe(g(mkfs.I_DINDIRECT), 2)
        if self.version >= 3:
            stufe(g(mkfs.I_TINDIRECT), 3)
        return aus

    def datenblock(self, ino, idx):
        d = self.iat(ino)

        def g(at):
            return int.from_bytes(d[at:at + 8], "little")

        def im(p):
            return p if self.data <= p < self.blocks else 0

        def zeig(b, k):
            if not b:
                return 0
            blk = self.blk(b)
            return im(int.from_bytes(blk[k * 8:k * 8 + 8], "little"))

        if idx < self.directs:
            return im(g(mkfs.I_DIRECT + idx * 8))
        k = idx - self.directs
        if k < PER_BLOCK:
            return zeig(im(g(mkfs.I_INDIRECT)), k)
        k -= PER_BLOCK
        if k < PER_BLOCK ** 2:
            return zeig(zeig(im(g(mkfs.I_DINDIRECT)), k // PER_BLOCK),
                        k % PER_BLOCK)
        if self.version < 3:
            return 0
        k -= PER_BLOCK ** 2
        if k >= PER_BLOCK ** 3:
            return 0
        a = zeig(im(g(mkfs.I_TINDIRECT)), k // (PER_BLOCK ** 2))
        b = zeig(a, (k // PER_BLOCK) % PER_BLOCK)
        return zeig(b, k % PER_BLOCK)

    def lies(self, ino, off, n):
        aus = bytearray()
        while len(aus) < n:
            pos = off + len(aus)
            b = self.datenblock(ino, pos // BS)
            inb = pos % BS
            stueck = min(BS - inb, n - len(aus))
            if b == 0:
                aus += bytes(stueck)
            else:
                aus += self.blk(b)[inb:inb + stueck]
        return bytes(aus)

    def eintraege(self, ino):
        n = self.ig(ino, mkfs.I_SIZE) // self.dirent
        aus = []
        for i in range(n):
            roh = self.lies(ino, i * self.dirent, self.dirent)
            kind = int.from_bytes(roh[0:8], "little")
            if not kind:
                continue
            name = roh[8:8 + self.namelen].split(b"\0")[0].decode(
                "latin-1")
            aus.append((kind, name))
        return aus

    def finde(self, pfad):
        ino = self.root
        for teil in pfad.strip("/").split("/"):
            if not teil:
                continue
            gefunden = 0
            for kind, name in self.eintraege(ino):
                if name == teil:
                    gefunden = kind
                    break
            if not gefunden:
                return 0
            ino = gefunden
        return ino


def struktur(bild):
    """Die Strukturpruefung. Rueckgabe: (befunde, zahlen)."""
    z = dict(dateien=0, dirs=0, bloecke=0, ausser=0, doppelt=0, badtype=0,
             verloren=0, fehlend=0, totlinks=0, kreise=0)
    befunde = []
    if not bild.magic:
        return ["keine OSUM-OFS-Kennung"], z
    if bild.bsize != BS:
        befunde.append("Blockgroesse %d" % bild.bsize)
    if not (bild.bmstart < bild.itable < bild.data < bild.blocks):
        befunde.append("Bereiche nicht in der Reihenfolge "
                       "Karte<Tabelle<Daten<Ende")
    gesehen = bytearray(bild.blocks)
    for b in range(min(bild.data, bild.blocks)):
        gesehen[b] = 1
    for ino in range(1, bild.inodes + 1):
        art = bild.ig(ino, mkfs.I_TYPE)
        if art == 0:
            continue
        if art not in (mkfs.T_FILE, mkfs.T_DIR, mkfs.T_LINK):
            z["badtype"] += 1
            continue
        z["dateien"] += 1
        if art == mkfs.T_DIR:
            z["dirs"] += 1
        for p in bild.bloecke(ino):
            if p < bild.data or p >= bild.blocks:
                z["ausser"] += 1
            elif gesehen[p]:
                z["doppelt"] += 1
            else:
                gesehen[p] = 1
                z["bloecke"] += 1
    for b in range(bild.data, bild.blocks):
        bit = bild.bit(b)
        if bit and not gesehen[b]:
            z["verloren"] += 1
        if not bit and gesehen[b]:
            z["fehlend"] += 1
    # Der Verzeichnisbaum, mit Marke gegen Kreise.
    besucht = set()
    stapel = [bild.root]
    besucht.add(bild.root)
    while stapel:
        d = stapel.pop()
        for kind, name in bild.eintraege(d):
            if kind > bild.inodes or bild.ig(kind, mkfs.I_TYPE) == 0:
                z["totlinks"] += 1
            elif bild.ig(kind, mkfs.I_TYPE) == mkfs.T_DIR:
                if kind not in besucht:
                    besucht.add(kind)
                    stapel.append(kind)
                elif name not in (".", ".."):
                    z["kreise"] += 1
    for k in ("ausser", "doppelt", "badtype", "verloren", "fehlend",
              "totlinks", "kreise"):
        if z[k]:
            befunde.append("%s=%d" % (k, z[k]))
    return befunde, z


def journal(bild):
    """Steht eine Bestaetigung offen, und stimmt sie?"""
    if not bild.jstart or bild.jblocks < J_BLOCKS:
        return dict(vorhanden=0)
    c = bild.blk(bild.jstart + 521)
    magic = int.from_bytes(c[0:8], "little")
    if magic != COMMIT_MAGIC:
        return dict(vorhanden=1, offen=0)
    seq = int.from_bytes(c[8:16], "little")
    n = int.from_bytes(c[16:24], "little")
    sm = int.from_bytes(c[24:32], "little")
    if n == 0 or n > 512:
        return dict(vorhanden=1, offen=1, gueltig=0, grund="Anzahl %d" % n)
    h = bild.blk(bild.jstart)
    if (int.from_bytes(h[0:8], "little") != HEAD_MAGIC
            or int.from_bytes(h[8:16], "little") != seq
            or int.from_bytes(h[16:24], "little") != n):
        return dict(vorhanden=1, offen=1, gueltig=0, grund="Kopf passt nicht")
    ziele = []
    for k in range((n + 63) // 64):
        t = bild.blk(bild.jstart + 1 + k)
        for j in range(64):
            if k * 64 + j < n:
                ziele.append(int.from_bytes(t[j * 8:j * 8 + 8], "little"))
    p = mix(mix(FNV_OFF, seq), n)
    for i in range(n):
        p = mix(p, ziele[i])
        p = mix(p, block_hash(bild.blk(bild.jstart + 9 + i)))
    return dict(vorhanden=1, offen=1, gueltig=1 if p == sm else 0,
                seq=seq, n=n)


def muster(g, k):
    return (((g * 2654435761) & M64) + ((k * 40503) & M64)) % 251


def inhalt(bild):
    """Die Messdateien der Runde: /d/count, /d/roll, /d/fN."""
    befunde = []
    d = bild.finde("/d")
    if not d:
        return ["/d fehlt"], dict(count=0, ganz=0)
    ci = bild.finde("/d/count")
    c = 0
    if ci:
        roh = bild.lies(ci, 0, bild.ig(ci, mkfs.I_SIZE))
        ziffern = b""
        for ch in roh:
            if 48 <= ch <= 57:
                ziffern += bytes([ch])
            else:
                break
        c = int(ziffern) if ziffern else 0
    for name in ("/d/roll", "/d/roll2"):
        ri = bild.finde(name)
        if ri:
            sz = bild.ig(ri, mkfs.I_SIZE)
            if sz not in (0, 4096):
                befunde.append("%s ist %d Oktette gross" % (name, sz))
            elif sz == 0 and c:
                befunde.append("%s ist leer, der Zaehler steht auf %d"
                               % (name, c))
            elif sz == 4096:
                r = bild.lies(ri, 0, 4096)
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
        ino = bild.finde("/d/%d" % k)
        if not ino:
            befunde.append("/d/%d fehlt" % k)
            continue
        soll = 512 + (k * 617) % 1536
        sz = bild.ig(ino, mkfs.I_SIZE)
        if sz != soll:
            befunde.append("/d/%d ist %d statt %d Oktette" % (k, sz, soll))
            continue
        roh = bild.lies(ino, 0, sz)
        schlecht = -1
        for i in range(sz):
            if roh[i] != muster(k + 1000000, i):
                schlecht = i
                break
        if schlecht >= 0:
            befunde.append("/d/%d: Oktett %d falsch" % (k, schlecht))
            continue
        # Die Rechte-Metadaten (Runde MULTIUSER): der Modus wurde nach
        # dem Schreiben gesetzt, der Zaehler kam danach.
        m = bild.ig(ino, mkfs.I_MODE) & 0o7777
        if m != 0o600 + (k % 8):
            befunde.append("/d/%d traegt Modus %o statt %o"
                           % (k, m, 0o600 + (k % 8)))
        else:
            ganz += 1
    # Die Datei DANACH darf es nicht halb geben.
    ino = bild.finde("/d/%d" % (c + 1))
    naechste = 0
    if ino:
        sz = bild.ig(ino, mkfs.I_SIZE)
        soll = 512 + ((c + 1) * 617) % 1536
        if sz == 0:
            naechste = 1
        elif sz == soll:
            roh = bild.lies(ino, 0, sz)
            ok = all(roh[i] == muster(c + 1 + 1000000, i) for i in range(sz))
            naechste = 2 if ok else 3
        else:
            naechste = 3
        if naechste == 3:
            befunde.append("/d/%d ist halb geschrieben (%d Oktette)"
                           % (c + 1, sz))
    if bild.finde("/d/%d" % (c + 2)):
        befunde.append("/d/%d gibt es, obwohl der Zaehler auf %d steht"
                       % (c + 2, c))
    return befunde, dict(count=c, ganz=ganz, naechste=naechste)


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    was, pfad = argv[1], argv[2]
    bild = Bild(pfad)
    if was == "struktur":
        befunde, z = struktur(bild)
        print("struktur: " + " ".join("%s=%d" % kv for kv in z.items()))
        for b in befunde:
            print("  BEFUND " + b)
        return 1 if befunde else 0
    if was == "journal":
        print("journal: " + " ".join("%s=%s" % kv
                                     for kv in journal(bild).items()))
        return 0
    if was == "inhalt":
        befunde, z = inhalt(bild)
        print("inhalt: " + " ".join("%s=%d" % kv for kv in z.items()))
        for b in befunde:
            print("  BEFUND " + b)
        return 1 if befunde else 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
