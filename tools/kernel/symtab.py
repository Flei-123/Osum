#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    python3 tools/kernel/symtab.py ABBILD.elf output.s
"""
import re
import struct
import subprocess
import sys

MAGIC = 0x314D59534F

HDR = 104
BLK = 16


def symbole(elf):
    aus = subprocess.run(["nm", "-n", elf], capture_output=True, text=True)
    if aus.returncode != 0:
        raise SystemExit("nm ist fehlgeschlagen: " + aus.stderr.strip())
    roh = []
    for line in aus.stdout.splitlines():
        parts = line.split()
        if len(parts) != 3:
            continue
        adr, art, name = parts
        if art not in ("T", "t"):
            continue
        roh.append((int(adr, 16), lesbar(name)))
    raus = []
    for adr, name in roh:
        if raus and raus[-1][0] == adr:
            if len(name) < len(raus[-1][1]):
                raus[-1] = (adr, name)
            continue
        raus.append((adr, name))
    return raus


def lesbar(name):
    if name.startswith("_F0.") or name.startswith("_F1."):
        name = name[4:]
    return name.replace("__", ".")


def lines(elf):
    aus = subprocess.run(["readelf", "--debug-dump=decodedline", elf],
                         capture_output=True, text=True)
    if aus.returncode != 0:
        return []
    roh = []
    for line in aus.stdout.splitlines():
        parts = line.split()
        if len(parts) < 3 or not parts[2].startswith("0x"):
            continue
        try:
            nr = int(parts[1])
            adr = int(parts[2], 16)
        except ValueError:
            continue
        roh.append((adr, parts[0], nr))
    roh.sort()
    raus = []
    for adr, file, nr in roh:
        if raus and raus[-1][0] == adr:
            raus[-1] = (adr, file, nr)
            continue
        if raus and raus[-1][1] == file and raus[-1][2] == nr:
            continue
        raus.append((adr, file, nr))
    return raus


def varint(v):
    out = bytearray()
    while True:
        b = v & 0x7F
        v >>= 7
        if v:
            out.append(b | 0x80)
        else:
            out.append(b)
            return bytes(out)


def pack_lines(ents):
    idx = bytearray()
    st = bytearray()
    pa = pp = 0
    for i, (a, pk) in enumerate(ents):
        if i % BLK == 0:
            idx += struct.pack("<II", a, len(st))
            st += varint(pk)
        else:
            d = pk - pp
            st += varint(a - pa)
            st += varint((d << 1) if d >= 0 else (((-d) << 1) - 1))
        pa, pp = a, pk
    return bytes(idx), bytes(st)


def unpack_line(idx, st, n, addr):
    nb = (n + BLK - 1) // BLK
    first = lambda k: struct.unpack_from("<I", idx, k * 8)[0]
    if addr < first(0):
        return 0
    lo, hi = 0, nb
    while lo + 1 < hi:
        mid = lo + (hi - lo) // 2
        if first(mid) <= addr:
            lo = mid
        else:
            hi = mid
    cnt = min(BLK, n - lo * BLK)
    p = struct.unpack_from("<I", idx, lo * 8 + 4)[0]

    def rd():
        nonlocal p
        v = sh = 0
        while True:
            b = st[p]
            p += 1
            v += (b & 0x7F) << sh
            sh += 7
            if b < 128:
                return v

    a = first(lo)
    pk = res = rd()
    for _ in range(1, cnt):
        na = a + rd()
        z = rd()
        npk = pk - ((z + 1) >> 1) if z & 1 else pk + (z >> 1)
        if na > addr:
            break
        a, pk, res = na, npk, npk
    return res


def blob(syms, lns):
    names = bytearray(b"\0")
    nvers = {}

    def leg_ab(s):
        b = s.encode("utf-8", "replace") + b"\0"
        if b in nvers:
            return nvers[b]
        p = len(names)
        names.extend(b)
        nvers[b] = p
        return p

    sym_adr = bytearray()
    sym_nam = bytearray()
    for adr, name in syms:
        sym_adr += struct.pack("<I", adr & 0xFFFFFFFF)
        sym_nam += struct.pack("<I", leg_ab(name))

    dateien = []
    dvers = {}
    zeil_roh = []
    for adr, file, nr in lns:
        if file not in dvers:
            dvers[file] = len(dateien)
            dateien.append(file)
        f = dvers[file]
        if nr > 0xFFFFF:
            nr = 0xFFFFF
        if f > 0xFFF:
            f = 0xFFF
        zeil_roh.append((adr & 0xFFFFFFFF, (f << 20) | nr))
    zeil, zstrom = pack_lines(zeil_roh)

    dnamen = bytearray(b"\0")
    dvers2 = {}

    def leg_file(s):
        b = s.encode("utf-8", "replace") + b"\0"
        if b in dvers2:
            return dvers2[b]
        p = len(dnamen)
        dnamen.extend(b)
        dvers2[b] = p
        return p

    dat_ver = bytearray()
    for d in dateien:
        dat_ver += struct.pack("<I", leg_file(d))

    o_sadr = HDR
    o_snam = o_sadr + len(sym_adr)
    o_str = o_snam + len(sym_nam)
    o_zeil = ausrichten(o_str + len(names))
    o_lstr = o_zeil + len(zeil)
    o_dver = ausrichten(o_lstr + len(zstrom))
    o_dstr = o_dver + len(dat_ver)

    lo = syms[0][0] if syms else 0
    hi = syms[-1][0] if syms else 0
    header = struct.pack("<13Q", MAGIC, len(syms), len(lns), o_sadr, o_snam,
                       o_str, o_zeil, o_dver, len(dateien), o_dstr, lo, hi, o_lstr)
    assert len(header) == HDR
    b = bytearray(header)
    b += sym_adr
    b += sym_nam
    b += names
    while len(b) < o_zeil:
        b.append(0)
    b += zeil
    b += zstrom
    while len(b) < o_dver:
        b.append(0)
    b += dat_ver
    b += dnamen
    return bytes(b)


def ausrichten(n):
    return (n + 7) & ~7


def write_s(path_2, data, syms, lns):
    with open(path_2, "w") as f:
        f.write("/* SPDX-License-Identifier: GPL-2.0-only */\n")
        f.write("/* ERZEUGT von tools/kernel/symtab.py -- NICHT VON HAND"
                " AENDERN.\n")
        f.write("   %d Symbole, %d Zeileneintraege, %d Oktette. */\n"
                % (len(syms), len(lns), len(data)))
        f.write("    .section .rodata\n")
        f.write("    .align 8\n")
        f.write("    .globl osym_tab\n")
        f.write("osym_tab:\n")
        for i in range(0, len(data), 32):
            chunk = data[i:i + 32]
            f.write("    .byte " + ",".join(str(x) for x in chunk) + "\n")


def main():
    if len(sys.argv) != 3:
        sys.stderr.write(__doc__)
        return 1
    elf, aus = sys.argv[1], sys.argv[2]
    syms = symbole(elf)
    if not syms:
        sys.stderr.write("symtab: nm hat kein einziges Textsymbol geliefert\n")
        return 1
    lns = lines(elf)
    data = blob(syms, lns)
    write_s(aus, data, syms, lns)
    sys.stderr.write("symtab: %d Symbole, %d Zeilen, %d Oktette\n"
                     % (len(syms), len(lns), len(data)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
