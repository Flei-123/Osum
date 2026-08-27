#!/usr/bin/env python3
"""tools/tresor/kaputt.py -- flip ONE octet inside a file of an OFS image.

This is the counter-check of `backup verify`. A verifier that only ever sees
healthy stores proves nothing at all; so the HOST reaches into the disk
image, changes a single octet of the pack file, and the next run of
`backup verify` on that store has to notice -- and `backup restore` has to hand
back something that is no longer identical.

The damage is done from OUTSIDE the kernel on purpose. That is what real
damage looks like: a drive that flips a bit does not ask the file system
first.

    kaputt.py <image> <pfad> <versatz> [<xor>]

Prints the octet before and after, so the runner can show what it did.
"""
import sys
import os

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                "..", "osum"))
import mkfs  # noqa: E402


def main(argv):
    if len(argv) < 4:
        print(__doc__)
        return 2
    image, path, off = argv[1], argv[2], int(argv[3], 0)
    xor = int(argv[4], 0) if len(argv) > 4 else 0xFF

    original = os.path.getsize(image)
    fs = mkfs.load(image)
    if fs is None:
        print("kaputt: %s ist kein OFS-Abbild" % image)
        return 1
    ino = fs.resolve(path)
    if ino is None:
        print("kaputt: %s gibt es nicht" % path)
        return 1
    size = fs.iget(ino, mkfs.I_SIZE)
    old = fs.read_at(ino, off, 1)
    if len(old) != 1:
        print("kaputt: Versatz %d liegt nicht in %s (Groesse %d)"
              % (off, path, size))
        return 1
    new = bytes([old[0] ^ xor])
    fs.write_at(ino, off, new)
    # NUR die urspruengliche Laenge zurueckschreiben: `load` legt sich ein
    # groesseres Feld an, als die Datei lang ist, und ein Abbild, das beim
    # Anfassen waechst, waere ein zweiter Unterschied neben dem gewollten.
    with open(image, "r+b") as f:
        f.write(bytes(fs.d[:original]))
    print("kaputt: %s[%d] 0x%02x -> 0x%02x" % (path, off, old[0], new[0]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
