#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/fremdfs/ext4info.py -- EIN ext4-ABBILD MIT FREMDEN AUGEN LESEN.

Dieses Programm ist KEIN zweiter Treiber und soll keiner werden. Es
beantwortet genau die Fragen, die der Pruefstand ueber ein Abbild
stellen muss, BEVOR Osum es zu sehen bekommt:

    tiefe <abbild> <pfad>    Die Tiefe des Extent-Baums dieser Datei.
                             Ohne diese Zahl waere "der Treiber kann
                             Extent-Baeume" eine Hoffnung: bei Tiefe 0
                             stehen alle Extents im Inode und der Baum
                             wird nie betreten.
    sb <abbild>              Die Kennzahlen des Superblocks, eine je
                             Zeile -- Blockgroesse, Inodegroesse,
                             Merkmale, Zustand.
    htree <abbild> <pfad>    Ist dieses Verzeichnis htree-indiziert?

Warum nicht `debugfs`: `debugfs` kann das alles, aber es schreibt es
als Fliesstext fuer Menschen, und der Pruefstand muesste ihn zerlegen.
Diese vierzig Zeilen lesen dieselben Felder unmittelbar.
"""
import struct
import sys


class Ext4:
    def __init__(self, pfad):
        self.f = open(pfad, 'rb')
        self.f.seek(1024)
        sb = self.f.read(1024)
        if struct.unpack_from('<H', sb, 0x38)[0] != 0xEF53:
            raise SystemExit('ext4info: keine ext4-Magie')
        self.bs = 1024 << struct.unpack_from('<I', sb, 0x18)[0]
        self.inodes_pro_gruppe = struct.unpack_from('<I', sb, 0x28)[0]
        self.inode_groesse = struct.unpack_from('<H', sb, 0x58)[0]
        self.erster_block = struct.unpack_from('<I', sb, 0x14)[0]
        self.desc_groesse = struct.unpack_from('<H', sb, 0xFE)[0] or 32
        self.inkompat = struct.unpack_from('<I', sb, 0x60)[0]
        self.kompat = struct.unpack_from('<I', sb, 0x5C)[0]
        self.rokompat = struct.unpack_from('<I', sb, 0x64)[0]
        # s_state steht bei 0x3A; bei 0x38 steht die Magie.
        self.zustand = struct.unpack_from('<H', sb, 0x3A)[0]
        self.bloecke = struct.unpack_from('<I', sb, 0x4)[0]
        self.sb = sb

    def block(self, n):
        self.f.seek(n * self.bs)
        return self.f.read(self.bs)

    def inode(self, ino):
        gruppe = (ino - 1) // self.inodes_pro_gruppe
        idx = (ino - 1) % self.inodes_pro_gruppe
        gd_block = self.erster_block + 1
        off = gruppe * self.desc_groesse
        self.f.seek(gd_block * self.bs + off)
        gd = self.f.read(self.desc_groesse)
        tab = struct.unpack_from('<I', gd, 0x8)[0]
        if self.desc_groesse >= 64:
            tab |= struct.unpack_from('<I', gd, 0x28)[0] << 32
        self.f.seek(tab * self.bs + idx * self.inode_groesse)
        return self.f.read(self.inode_groesse)

    def extent_tiefe(self, ino):
        inode = self.inode(ino)
        flags = struct.unpack_from('<I', inode, 0x20)[0]
        if not (flags & 0x80000):
            return -1          # keine Extents, sondern indirekte Bloecke
        magie, _, _, tiefe, _ = struct.unpack_from('<HHHHI', inode, 0x28)
        if magie != 0xF30A:
            return -2
        return tiefe

    def extent_zahl(self, ino):
        """Wie viele BLATT-Extents hat die Datei insgesamt."""
        inode = self.inode(ino)
        return self._zaehlen(inode[0x28:0x28 + 60])

    def _zaehlen(self, knoten):
        magie, eintraege, _, tiefe, _ = struct.unpack_from('<HHHHI', knoten, 0)
        if magie != 0xF30A:
            return 0
        if tiefe == 0:
            return eintraege
        summe = 0
        for i in range(eintraege):
            e = 12 + i * 12
            lo = struct.unpack_from('<I', knoten, e + 4)[0]
            hi = struct.unpack_from('<H', knoten, e + 8)[0]
            summe += self._zaehlen(self.block(lo | (hi << 32)))
        return summe

    def suchen(self, pfad):
        """Inodenummer zu einem Pfad. Nur so viel Verzeichnislogik wie
        noetig -- lineare Eintraege reichen, htree-Verzeichnisse haben
        dieselben linearen Bloecke darunter."""
        ino = 2
        for teil in [t for t in pfad.split('/') if t]:
            ino = self._eintrag(ino, teil)
            if ino is None:
                return None
        return ino

    def _bloecke_von(self, ino):
        inode = self.inode(ino)
        flags = struct.unpack_from('<I', inode, 0x20)[0]
        if not (flags & 0x80000):
            return []
        return list(self._blatt(inode[0x28:0x28 + 60]))

    def _blatt(self, knoten):
        magie, eintraege, _, tiefe, _ = struct.unpack_from('<HHHHI', knoten, 0)
        if magie != 0xF30A:
            return
        for i in range(eintraege):
            e = 12 + i * 12
            if tiefe == 0:
                laenge = struct.unpack_from('<H', knoten, e + 4)[0]
                lo = struct.unpack_from('<I', knoten, e + 8)[0]
                hi = struct.unpack_from('<H', knoten, e + 6)[0]
                start = lo | (hi << 32)
                for k in range(laenge & 0x7FFF):
                    yield start + k
            else:
                lo = struct.unpack_from('<I', knoten, e + 4)[0]
                hi = struct.unpack_from('<H', knoten, e + 8)[0]
                yield from self._blatt(self.block(lo | (hi << 32)))

    def _eintrag(self, dir_ino, name):
        ziel = name.encode()
        for b in self._bloecke_von(dir_ino):
            daten = self.block(b)
            off = 0
            while off < len(daten) - 8:
                ino, rec, nlen, _ = struct.unpack_from('<IHBB', daten, off)
                if rec < 8:
                    break
                if ino and daten[off + 8:off + 8 + nlen] == ziel:
                    return ino
                off += rec
        return None

    def htree(self, dir_ino):
        inode = self.inode(dir_ino)
        flags = struct.unpack_from('<I', inode, 0x20)[0]
        return bool(flags & 0x1000)     # EXT4_INDEX_FL


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    was, abbild = sys.argv[1], sys.argv[2]
    fs = Ext4(abbild)
    if was == 'sb':
        print(f'blockgroesse {fs.bs}')
        print(f'inodegroesse {fs.inode_groesse}')
        print(f'bloecke {fs.bloecke}')
        print(f'inkompat 0x{fs.inkompat:x}')
        print(f'rokompat 0x{fs.rokompat:x}')
        print(f'zustand {fs.zustand}')
        print(f'64bit {1 if fs.inkompat & 0x80 else 0}')
        return
    pfad = sys.argv[3]
    ino = fs.suchen(pfad)
    if ino is None:
        raise SystemExit(f'ext4info: {pfad} nicht gefunden')
    if was == 'tiefe':
        print(fs.extent_tiefe(ino))
    elif was == 'extents':
        print(fs.extent_zahl(ino))
    elif was == 'htree':
        print(1 if fs.htree(ino) else 0)
    elif was == 'inode':
        print(ino)
    else:
        raise SystemExit(__doc__)


if __name__ == '__main__':
    main()
