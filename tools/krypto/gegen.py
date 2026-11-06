#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    tools/krypto/gegen.py lies <abbild> <passphrase>
    tools/krypto/gegen.py schreib <abbild> <passphrase> [t] [m] [p]
    tools/krypto/gegen.py baum <abbild> <passphrase>
    tools/krypto/gegen.py roh <abbild>
    tools/krypto/gegen.py vektoren <orakel>
"""
import hashlib
import hmac
import os
import struct
import subprocess
import sys

try:
    import argon2.low_level as argon2ll
except ImportError:
    argon2ll = None
try:
    from cryptography.hazmat.primitives.ciphers import (
        Cipher, algorithms, modes)
except ImportError:
    Cipher = None

SECTOR = 512
HDR_SECTORS = 8
SLOT_BASE = 0x100
SLOT_SIZE = 256
SLOTS = 8
MAGIC = b"OSUMCRYPT"

H_VERSION, H_CIPHER, H_KDF, H_SECSIZE = 0x10, 0x14, 0x18, 0x1C
H_FIRST, H_COUNT, H_SUM = 0x20, 0x28, 0x30
S_USED, S_TCOST, S_MCOST, S_LANES = 0x00, 0x04, 0x08, 0x0C
S_SALT, S_WRAPPED, S_MAC = 0x10, 0x30, 0x70
SALT_LEN, KEY_LEN, WRAP_LEN = 32, 64, 96


def missing():
    was = []
    if argon2ll is None:
        was.append("argon2-cffi")
    if Cipher is None:
        was.append("cryptography")
    return was


def kdf(pw, salt, t, m, p, n=WRAP_LEN):
    return argon2ll.hash_secret_raw(
        secret=pw, salt=salt, time_cost=t, memory_cost=m,
        parallelism=p, hash_len=n, type=argon2ll.Type.ID, version=19)


def xts(key, tweak, data, ent):
    c = Cipher(algorithms.AES(key), modes.XTS(tweak))
    k = c.decryptor() if ent else c.encryptor()
    return k.update(data) + k.finalize()


def tweak_of(lba):
    return struct.pack("<Q", lba) + b"\0" * 8


def header_sum(hdr):
    b = bytearray(hdr[:HDR_SECTORS * SECTOR])
    b[H_SUM:H_SUM + 32] = b"\0" * 32
    return hashlib.sha256(bytes(b)).digest()


def header_read(hdr):
    if hdr[:len(MAGIC)] != MAGIC:
        raise ValueError("keine OSUMCRYPT-Kennung")
    k = {
        "version": struct.unpack_from("<I", hdr, H_VERSION)[0],
        "cipher": struct.unpack_from("<I", hdr, H_CIPHER)[0],
        "kdf": struct.unpack_from("<I", hdr, H_KDF)[0],
        "secsize": struct.unpack_from("<I", hdr, H_SECSIZE)[0],
        "first": struct.unpack_from("<Q", hdr, H_FIRST)[0],
        "count": struct.unpack_from("<Q", hdr, H_COUNT)[0],
    }
    k["sum_ok"] = header_sum(hdr) == hdr[H_SUM:H_SUM + 32]
    k["slots"] = []
    for i in range(SLOTS):
        s = hdr[SLOT_BASE + i * SLOT_SIZE:SLOT_BASE + (i + 1) * SLOT_SIZE]
        k["slots"].append({
            "i": i,
            "used": struct.unpack_from("<I", s, S_USED)[0],
            "t": struct.unpack_from("<I", s, S_TCOST)[0],
            "m": struct.unpack_from("<I", s, S_MCOST)[0],
            "p": struct.unpack_from("<I", s, S_LANES)[0],
            "salt": s[S_SALT:S_SALT + SALT_LEN],
            "wrapped": s[S_WRAPPED:S_WRAPPED + KEY_LEN],
            "mac": s[S_MAC:S_MAC + 32],
        })
    return k


def space_auf(sl, pw):
    if not sl["used"]:
        return None
    wrap = kdf(pw, sl["salt"], sl["t"], sl["m"], sl["p"])
    mac = hmac.new(wrap[64:96], sl["wrapped"], hashlib.sha256).digest()
    if not hmac.compare_digest(mac, sl["mac"]):
        return None
    return xts(wrap[:64], b"\0" * 16, sl["wrapped"], True)


def hauptschluessel(hdr, pw):
    k = header_read(hdr)
    for sl in k["slots"]:
        mk = space_auf(sl, pw)
        if mk is not None:
            return k, mk, sl["i"]
    return k, None, -1



def cmd_read(path, pw):
    d = open(path, "rb").read()
    hdr = d[:HDR_SECTORS * SECTOR]
    k, mk, wo = hauptschluessel(hdr, pw)
    print("kopf: kennung=1 fassung=%d chiffre=%d kdf=%d sektor=%d"
          % (k["version"], k["cipher"], k["kdf"], k["secsize"]))
    print("kopf: summe=%d erster=%d anzahl=%d"
          % (1 if k["sum_ok"] else 0, k["first"], k["count"]))
    belegt = [s["i"] for s in k["slots"] if s["used"]]
    print("kopf: plaetze=%d belegt=%s" % (len(belegt), ",".join(
        str(i) for i in belegt) or "-"))
    if mk is None:
        print("up: 0")
        return 1
    print("up: 1 slot=%d" % wo)
    print("schluessel: haelften_ungleich=%d"
          % (1 if mk[:32] != mk[32:] else 0))
    erst = k["first"]
    sb = xts(mk, tweak_of(0), d[erst * SECTOR:(erst + 1) * SECTOR], True)
    print("fs: magie=%s" % sb[:8].hex())
    print("fs: text=%s" % sb[:8].decode("latin1"))
    return 0



def cmd_write(path, pw, t=1, m=64, p=1, bloecke=8192):
    mk = os.urandom(KEY_LEN)
    while mk[:32] == mk[32:]:
        mk = os.urandom(KEY_LEN)
    salt = os.urandom(SALT_LEN)
    wrap = kdf(pw, salt, t, m, p)
    wrapped = xts(wrap[:64], b"\0" * 16, mk, False)
    mac = hmac.new(wrap[64:96], wrapped, hashlib.sha256).digest()

    hdr = bytearray(HDR_SECTORS * SECTOR)
    hdr[:len(MAGIC)] = MAGIC
    struct.pack_into("<I", hdr, H_VERSION, 1)
    struct.pack_into("<I", hdr, H_CIPHER, 1)
    struct.pack_into("<I", hdr, H_KDF, 1)
    struct.pack_into("<I", hdr, H_SECSIZE, SECTOR)
    struct.pack_into("<Q", hdr, H_FIRST, HDR_SECTORS)
    struct.pack_into("<Q", hdr, H_COUNT, bloecke - HDR_SECTORS)
    sl = SLOT_BASE
    struct.pack_into("<I", hdr, sl + S_USED, 1)
    struct.pack_into("<I", hdr, sl + S_TCOST, t)
    struct.pack_into("<I", hdr, sl + S_MCOST, m)
    struct.pack_into("<I", hdr, sl + S_LANES, p)
    hdr[sl + S_SALT:sl + S_SALT + SALT_LEN] = salt
    hdr[sl + S_WRAPPED:sl + S_WRAPPED + KEY_LEN] = wrapped
    hdr[sl + S_MAC:sl + S_MAC + 32] = mac
    hdr[H_SUM:H_SUM + 32] = header_sum(bytes(hdr))

    with open(path, "wb") as f:
        f.write(bytes(hdr))
        f.truncate(bloecke * SECTOR)
    print("schrieb: %s bloecke=%d t=%d m=%d p=%d" % (path, bloecke, t, m, p))
    print("schluessel: %s" % mk.hex())
    return 0



def cmd_roh(path):
    import collections
    import math
    import re
    d = open(path, "rb").read()
    data = d[HDR_SECTORS * SECTOR:]
    n = len(data) // SECTOR

    sig = {
        b"OSUM-OFS": "OFS-Superblock",
        b"SFO-MUSO": "OFS-Kennung gedreht",
        b"NTFS": "NTFS",
        b"\x53\xef": "ext2/3/4",
        b"FAT1": "FAT",
    }
    print("roh: sektoren=%d" % n)
    for pat, name in sig.items():
        print("roh: sig %s = %d" % (name, data.count(pat)))

    empty = 0
    ents = []
    for i in range(n):
        s = data[i * SECTOR:(i + 1) * SECTOR]
        if s == b"\0" * SECTOR:
            empty += 1
            continue
        c = collections.Counter(s)
        ln = len(s)
        ents.append(-sum(v / ln * math.log2(v / ln) for v in c.values()))
    print("roh: leer=%d beschrieben=%d" % (empty, len(ents)))
    if ents:
        print("raw: entropy_min=%.3f mean=%.3f below7=%d"
              % (min(ents), sum(ents) / len(ents),
                 sum(1 for e in ents if e < 7.0)))
    lang = [r for r in re.findall(rb"[ -~]{16,}", data)]
    print("roh: textfolgen16=%d" % len(lang))
    return 0



def cmd_vektoren(orakel):
    def frag(lines):
        r = subprocess.run([orakel], input="\n".join(lines) + "\n",
                           capture_output=True, text=True, timeout=1800)
        return r.stdout.strip().split("\n")

    gesamt_gut = 0
    gesamt_all = 0

    fr, soll = [], []
    for mlen in (0, 1, 2, 63, 64, 65, 127, 128, 129, 200, 1000):
        msg = bytes((i * 7 + 3) & 255 for i in range(mlen))
        for ol in (1, 16, 32, 48, 64):
            fr.append("b2b %s %d" % (msg.hex() if msg else "-", ol))
            soll.append(hashlib.blake2b(msg, digest_size=ol).hexdigest())
    for klen in (1, 16, 32, 64):
        for mlen in (0, 1, 64, 129):
            key = bytes((i * 11 + 5) & 255 for i in range(klen))
            msg = bytes((i * 3 + 1) & 255 for i in range(mlen))
            fr.append("b2bkey %s %s 64"
                      % (key.hex(), msg.hex() if msg else "-"))
            soll.append(hashlib.blake2b(msg, key=key,
                                        digest_size=64).hexdigest())
    ist = frag(fr)
    gut = sum(1 for a, b in zip(ist, soll) if a == b)
    print("blake2b %d/%d" % (gut, len(soll)))
    gesamt_gut += gut
    gesamt_all += len(soll)

    fr, soll = [], []
    faelle = []
    for t in (1, 2, 3):
        for m in (8, 16, 32, 64, 128, 256):
            for p in (1, 2, 4):
                if m < 8 * p:
                    continue
                faelle.append((b"password", b"somesaltsomesalt",
                               t, m, p, 32, "ID"))
    faelle += [
        (b"", b"12345678", 1, 8, 1, 32, "ID"),
        (b"x" * 100, b"s" * 32, 2, 64, 2, 128, "ID"),
        (b"pw", b"saltsalt", 2, 32, 2, 32, "I"),
        (b"pw", b"saltsalt", 3, 64, 4, 32, "D"),
    ]
    word = {"ID": "argon2id", "I": "argon2i", "D": "argon2d"}
    for pw, salt, t, m, p, n, ty in faelle:
        fr.append("%s %s %s %d %d %d %d"
                  % (word[ty], pw.hex() if pw else "-", salt.hex(),
                     t, m, p, n))
        soll.append(argon2ll.hash_secret_raw(
            secret=pw, salt=salt, time_cost=t, memory_cost=m,
            parallelism=p, hash_len=n,
            type=getattr(argon2ll.Type, ty), version=19).hex())
    ist = frag(fr)
    gut = sum(1 for a, b in zip(ist, soll) if a == b)
    print("argon2 %d/%d" % (gut, len(soll)))
    gesamt_gut += gut
    gesamt_all += len(soll)

    fr, soll = [], []
    for n in (16, 32, 48, 512, 4096):
        for kn in range(3):
            key = bytes((i * 17 + kn * 5 + 1) & 255 for i in range(64))
            pt = bytes((i * 13 + 7 + kn) & 255 for i in range(n))
            tw = bytes((i * 5 + 2 + kn) & 255 for i in range(16))
            ct = xts(key, tw, pt, False)
            fr.append("xtsenc %s %s %s" % (key.hex(), tw.hex(), pt.hex()))
            soll.append(ct.hex())
            fr.append("xtsdec %s %s %s" % (key.hex(), tw.hex(), ct.hex()))
            soll.append(pt.hex())
    for lba in (0, 1, 2, 63, 1000, 123456):
        key = bytes((i * 3 + 9) & 255 for i in range(64))
        pt = bytes((i * 11 + lba) & 255 for i in range(512))
        ct = xts(key, tweak_of(lba), pt, False)
        fr.append("xtssec %s %d %s" % (key.hex(), lba, pt.hex()))
        soll.append(ct.hex())
        fr.append("xtssecd %s %d %s" % (key.hex(), lba, ct.hex()))
        soll.append(pt.hex())
    ist = frag(fr)
    gut = sum(1 for a, b in zip(ist, soll) if a == b)
    print("xts %d/%d" % (gut, len(soll)))
    gesamt_gut += gut
    gesamt_all += len(soll)

    bad = [
        "xtsenc %s %s %s" % (("11" * 32 + "11" * 32), "00" * 16, "00" * 16),
        "xtsenc %s %s %s" % ("00" * 32 + "11" * 32, "00" * 16, "00" * 8),
        "xtsenc %s %s %s" % ("00" * 32, "00" * 16, "00" * 16),
        "argon2id 4142 4142 1 8 1 32",
        "argon2id 4142 %s 1 8 4 32" % ("41" * 16),
        "quatsch 00",
    ]
    ist = frag(bad)
    gut = sum(1 for z in ist if z.strip() == "FAIL")
    print("negativ %d/%d" % (gut, len(bad)))
    gesamt_gut += gut
    gesamt_all += len(bad)

    print("gesamt %d/%d" % (gesamt_gut, gesamt_all))
    return 0 if gesamt_gut == gesamt_all else 1


PER_BLOCK = SECTOR // 8


def _ofs_leser(blk):
    sb = blk(0)
    g = lambda o: struct.unpack_from("<Q", sb, o)[0]
    itable = g(40)
    isz = g(80) or 128
    dent = g(88) or 32
    nlen = g(96) or 24
    ipb = SECTOR // isz

    def inode(n):
        b = blk(itable + (n - 1) // ipb)
        off = ((n - 1) % ipb) * isz
        return b[off:off + isz]

    def ptrs(ino):
        sz = struct.unpack_from("<Q", ino, 8)[0]
        need = (sz + SECTOR - 1) // SECTOR
        out = []
        for i in range(8):
            if len(out) >= need:
                break
            p = struct.unpack_from("<Q", ino, 24 + 8 * i)[0]
            if p:
                out.append(p)
        ind = struct.unpack_from("<Q", ino, 112)[0]
        if len(out) < need and ind:
            ib = blk(ind)
            for j in range(PER_BLOCK):
                if len(out) >= need:
                    break
                p = struct.unpack_from("<Q", ib, j * 8)[0]
                if p:
                    out.append(p)
        dind = struct.unpack_from("<Q", ino, 120)[0]
        if len(out) < need and dind:
            db = blk(dind)
            for j in range(PER_BLOCK):
                if len(out) >= need:
                    break
                p1 = struct.unpack_from("<Q", db, j * 8)[0]
                if not p1:
                    break
                ib = blk(p1)
                for m in range(PER_BLOCK):
                    if len(out) >= need:
                        break
                    p = struct.unpack_from("<Q", ib, m * 8)[0]
                    if p:
                        out.append(p)
        return sz, out

    def file(n):
        sz, bl = ptrs(inode(n))
        return b"".join(blk(b) for b in bl)[:sz]

    def root():
        sz, bl = ptrs(inode(1))
        raw = b"".join(blk(b) for b in bl)[:sz]
        out = []
        for off in range(0, sz, dent):
            e = raw[off:off + dent]
            if len(e) < dent:
                break
            n = struct.unpack_from("<Q", e, 0)[0]
            nm = e[8:8 + nlen].split(b"\0")[0].decode("latin1")
            if n and nm not in (".", ".."):
                out.append((n, nm))
        return out

    return root, file


def cmd_tree(path, pw):
    d = open(path, "rb").read()
    k, mk, wo = hauptschluessel(d[:HDR_SECTORS * SECTOR], pw)
    if mk is None:
        print("tree: up=0")
        return 1
    erst = k["first"]

    def blk(i):
        return xts(mk, tweak_of(i),
                   d[(erst + i) * SECTOR:(erst + i + 1) * SECTOR], True)

    root, file = _ofs_leser(blk)
    laengen = [100, 700, 5000, 40000]
    eintraege = sorted(root(), key=lambda x: x[1])
    print("tree: up=1 slot=%d files=%d" % (wo, len(eintraege)))
    gut = 0
    for n, nm in eintraege:
        if len(nm) != 2 or nm[0] != "k" or not nm[1].isdigit():
            continue
        i = int(nm[1])
        if i >= len(laengen):
            continue
        ln = laengen[i]
        soll = hashlib.sha256(
            bytes(((i * 37 + q * 7 + 3) & 255) for q in range(ln))).hexdigest()
        ist = hashlib.sha256(file(n)).hexdigest()
        if soll == ist:
            gut += 1
        print("baum: sha %s = %s %s" % (nm, ist, "OK" if soll == ist else
                                        "FALSCH(soll %s)" % soll))
    print("tree: good=%d of=%d" % (gut, len(laengen)))
    return 0 if gut == len(laengen) else 1


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    was = missing()
    if was:
        print("gegen.py: missing: %s" % ", ".join(was))
        return 3
    b = sys.argv[1]
    if b == "lies":
        return cmd_read(sys.argv[2], sys.argv[3].encode())
    if b == "schreib":
        a = sys.argv[4:]
        return cmd_write(sys.argv[2], sys.argv[3].encode(),
                           int(a[0]) if len(a) > 0 else 1,
                           int(a[1]) if len(a) > 1 else 64,
                           int(a[2]) if len(a) > 2 else 1,
                           int(a[3]) if len(a) > 3 else 8192)
    if b == "baum":
        return cmd_tree(sys.argv[2], sys.argv[3].encode())
    if b == "roh":
        return cmd_roh(sys.argv[2])
    if b == "vektoren":
        return cmd_vektoren(sys.argv[2])
    print("unbekannt: %s" % b)
    return 2


if __name__ == "__main__":
    sys.exit(main())
