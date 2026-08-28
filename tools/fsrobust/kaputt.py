#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/fsrobust/kaputt.py -- Abbilder, die MIT ABSICHT kaputt sind.

Die Aufgabe dieser Runde verlangt von `/bin/fsck` zwei Dinge, und das
zweite ist das schwerere: es soll Schaeden finden UND es soll auch bei
einem mutwillig zerstoerten Datentraeger FERTIG WERDEN statt sich
aufzuhaengen. Das laesst sich nur messen, wenn es solche Datentraeger
gibt -- also baut dieses Programm sie.

Jeder Fall greift genau eine Annahme an, die ein Pruefprogramm
stillschweigend machen koennte:

  kennung      der Superblock traegt keine OSUM-OFS-Kennung mehr.
  inodes       er behauptet 2^40 Inodes -- mehr, als zwischen Tabelle
               und Daten Platz haben. Wer die Zahl glaubt, laeuft
               eine Billion Mal durch eine Tabelle, die es nicht gibt.
  bloecke      er behauptet 2^50 Bloecke, also weit mehr als das Geraet.
  bereiche     Datenbereich VOR der Inodetabelle -- die Reihenfolge, auf
               der jede Rechnung beruht, ist umgedreht.
  zeigerkreis  ein einfach indirekter Blockzeiger zeigt AUF SICH SELBST.
               Wer ihm folgt, ohne die Tiefe zu zaehlen, kehrt nie um.
  verzkreis    zwei Verzeichnisse enthalten einander. Ein Durchlauf ohne
               Marke laeuft im Kreis.
  selbstverz   ein Verzeichnis enthaelt SICH SELBST unter einem Namen.
  doppelt      zwei Inodes zeigen auf denselben Datenblock.
  wildzeiger   ein Blockzeiger zeigt hinter das Ende der Platte.
  totlink      ein Verzeichniseintrag zeigt auf eine freie Inode.
  leerkarte    die Blockkarte ist genullt: alles sieht frei aus, obwohl
               es benutzt wird.
  muell        die ersten 64 Bloecke sind Zufallsoktette.
  jmuell       der Bestaetigungsblock des Journals traegt die richtige
               Kennung und eine falsche Pruefsumme -- genau das, was
               ein halb geschriebener Sektor hinterlaesst.

    kaputt.py <grundabbild> <ausgabeverzeichnis> [<fall> ...]
"""

import os
import shutil
import struct
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "..", "osum"))
import mkfs  # noqa: E402

BS = mkfs.BS


class Roh:
    """Ein Abbild, roh, blockweise -- ohne es in den Speicher zu ziehen."""

    def __init__(self, pfad):
        self.f = open(pfad, "r+b")
        self.sb = self.blk(0)

    def blk(self, n):
        self.f.seek(n * BS)
        d = self.f.read(BS)
        return bytearray(d.ljust(BS, b"\0"))

    def put(self, n, d):
        self.f.seek(n * BS)
        self.f.write(bytes(d).ljust(BS, b"\0"))

    def g(self, at):
        return struct.unpack_from("<Q", self.sb, at)[0]

    def s(self, at, v):
        struct.pack_into("<Q", self.sb, at, v & 0xFFFFFFFFFFFFFFFF)
        self.put(0, self.sb)

    @property
    def isize(self):
        return self.g(mkfs.SB["ISIZE"]) or mkfs.INODE_SIZE

    @property
    def ipb(self):
        return BS // self.isize

    @property
    def itable(self):
        return self.g(mkfs.SB["ITABLE"])

    @property
    def dirent(self):
        return self.g(mkfs.SB["DIRENT"]) or mkfs.DIRENT

    def inode_get(self, ino, feld):
        b = self.blk(self.itable + (ino - 1) // self.ipb)
        o = ((ino - 1) % self.ipb) * self.isize
        return struct.unpack_from("<Q", b, o + feld)[0]

    def inode_set(self, ino, feld, v):
        nr = self.itable + (ino - 1) // self.ipb
        b = self.blk(nr)
        o = ((ino - 1) % self.ipb) * self.isize
        struct.pack_into("<Q", b, o + feld, v & 0xFFFFFFFFFFFFFFFF)
        self.put(nr, b)

    def zu(self):
        self.f.close()


FAELLE = ["kennung", "inodes", "bloecke", "bereiche", "zeigerkreis",
          "verzkreis", "selbstverz", "doppelt", "wildzeiger", "totlink",
          "leerkarte", "muell", "jmuell"]


def mach(fall, grund, ziel):
    shutil.copyfile(grund, ziel)
    r = Roh(ziel)
    if fall == "kennung":
        r.s(mkfs.SB["MAGIC"], 0xDEADBEEFDEADBEEF)
    elif fall == "inodes":
        r.s(mkfs.SB["INODES"], 1 << 40)
    elif fall == "bloecke":
        r.s(mkfs.SB["BLOCKS"], 1 << 50)
    elif fall == "bereiche":
        r.s(mkfs.SB["DATA"], 1)
    elif fall == "zeigerkreis":
        # Eine Datei bekommt einen einfach indirekten Zeiger, der auf
        # SICH SELBST zeigt: der Block ist voll mit seiner eigenen
        # Nummer.
        b = r.g(mkfs.SB["DATA"]) + 3
        d = bytearray(BS)
        for i in range(BS // 8):
            struct.pack_into("<Q", d, i * 8, b)
        r.put(b, d)
        r.inode_set(2, mkfs.I_INDIRECT, b)
        r.inode_set(2, mkfs.I_SIZE, 1 << 20)
    elif fall == "verzkreis":
        # /bin bekommt einen Eintrag auf die Wurzel, und die Wurzel
        # einen auf /bin -- den hat sie schon. Ein Durchlauf ohne Marke
        # laeuft damit zwischen beiden hin und her.
        bild = _bild(ziel)
        binino = bild.finde("/bin")
        bild.f.close()
        _dir_add(r, binino, "hoch", 1)
    elif fall == "selbstverz":
        bild = _bild(ziel)
        binino = bild.finde("/bin")
        bild.f.close()
        _dir_add(r, binino, "ich", binino)
    elif fall == "doppelt":
        b = r.inode_get(2, mkfs.I_DIRECT)
        r.inode_set(3, mkfs.I_DIRECT, b)
    elif fall == "wildzeiger":
        r.inode_set(2, mkfs.I_DIRECT, r.g(mkfs.SB["BLOCKS"]) + 1000)
    elif fall == "totlink":
        bild = _bild(ziel)
        binino = bild.finde("/bin")
        bild.f.close()
        _dir_add(r, binino, "nirgends", r.g(mkfs.SB["INODES"]) - 1)
    elif fall == "leerkarte":
        bmb = r.g(mkfs.SB["BMBLOCKS"]) or 1
        for k in range(bmb):
            r.put(r.g(mkfs.SB["BITMAP"]) + k, bytearray(BS))
    elif fall == "muell":
        zuf = os.urandom(64 * BS)
        for i in range(64):
            r.put(i, bytearray(zuf[i * BS:(i + 1) * BS]))
    elif fall == "jmuell":
        js = r.g(mkfs.SB["JSTART"])
        if js:
            d = bytearray(BS)
            struct.pack_into("<Q", d, 0, 0x4D4D4F434A53464F)  # OFSJCOMM
            struct.pack_into("<Q", d, 8, 99)                  # Folgenummer
            struct.pack_into("<Q", d, 16, 5)                  # Anzahl
            struct.pack_into("<Q", d, 24, 0x1234567812345678)  # falsche Summe
            r.put(js + 521, d)
    else:
        raise SystemExit("kaputt: unbekannter Fall %s" % fall)
    r.zu()
    return ziel


def _bild(pfad):
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import pruef
    return pruef.Bild(pfad)


def _frei(r):
    """Der erste freie Block laut Karte, gleich als belegt eingetragen."""
    bms = r.g(mkfs.SB["BITMAP"]) or 1
    bmb = r.g(mkfs.SB["BMBLOCKS"]) or 1
    ds = r.g(mkfs.SB["DATA"])
    total = r.g(mkfs.SB["BLOCKS"])
    for k in range(bmb):
        d = r.blk(bms + k)
        for b in range(k * 4096, min((k + 1) * 4096, total)):
            if b < ds:
                continue
            if not (d[(b % 4096) // 8] >> (b % 8)) & 1:
                d[(b % 4096) // 8] |= 1 << (b % 8)
                r.put(bms + k, d)
                return b
    raise SystemExit("kaputt: kein freier Block")


def _dir_add(r, dirino, name, ziel):
    """Einen Eintrag ans Ende eines Verzeichnisses haengen, roh.

    Ein Eintrag der Fassung 3 ist 264 Oktette lang und geht deshalb
    regelmaessig UEBER eine Blockgrenze. Wer das nicht behandelt, kann
    an ein Verzeichnis nur jeden zweiten Eintrag haengen -- der erste
    Entwurf dieses Werkzeugs ist genau daran gescheitert.
    """
    dirent = r.dirent
    sz = r.inode_get(dirino, mkfs.I_SIZE)
    roh = bytearray(dirent)
    struct.pack_into("<Q", roh, 0, ziel)
    nm = name.encode("latin-1")[:dirent - 9] + b"\0"
    roh[8:8 + len(nm)] = nm
    geschrieben = 0
    while geschrieben < dirent:
        pos = sz + geschrieben
        idx = pos // BS
        inb = pos % BS
        b = r.inode_get(dirino, mkfs.I_DIRECT + idx * 8)
        if b == 0:
            b = _frei(r)
            r.inode_set(dirino, mkfs.I_DIRECT + idx * 8, b)
            r.put(b, bytearray(BS))
        d = r.blk(b)
        n = min(BS - inb, dirent - geschrieben)
        d[inb:inb + n] = roh[geschrieben:geschrieben + n]
        r.put(b, d)
        geschrieben += n
    r.inode_set(dirino, mkfs.I_SIZE, sz + dirent)


def main(argv):
    if len(argv) < 3:
        print(__doc__)
        return 2
    grund, aus = argv[1], argv[2]
    faelle = argv[3:] or FAELLE
    os.makedirs(aus, exist_ok=True)
    for f in faelle:
        z = os.path.join(aus, "kaputt-%s.img" % f)
        mach(f, grund, z)
        print("kaputt: %s" % z)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
