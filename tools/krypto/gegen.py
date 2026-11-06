#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    tools/krypto/gegen.py read <image> <passphrase>
    tools/krypto/gegen.py write <image> <passphrase> [t] [m] [p]
    tools/krypto/gegen.py tree <image> <passphrase>
    tools/krypto/gegen.py raw <image>
    tools/krypto/gegen.py vectors <oracle>
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
    from cryptography.hazmat.primitives.kdf import argon2 as argon2kdf
except ImportError:
    Cipher = None
    argon2kdf = None

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
    absent = []
    if argon2ll is None:
        absent.append("argon2-cffi")
    if Cipher is None or argon2kdf is None:
        absent.append("cryptography")
    return absent


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
        raise ValueError("missing OSUMCRYPT magic")
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
            "index": i,
            "used": struct.unpack_from("<I", s, S_USED)[0],
            "t": struct.unpack_from("<I", s, S_TCOST)[0],
            "m": struct.unpack_from("<I", s, S_MCOST)[0],
            "p": struct.unpack_from("<I", s, S_LANES)[0],
            "salt": s[S_SALT:S_SALT + SALT_LEN],
            "wrapped": s[S_WRAPPED:S_WRAPPED + KEY_LEN],
            "mac": s[S_MAC:S_MAC + 32],
        })
    return k


def unlock_slot(sl, pw):
    if not sl["used"]:
        return None
    wrap = kdf(pw, sl["salt"], sl["t"], sl["m"], sl["p"])
    mac = hmac.new(wrap[64:96], sl["wrapped"], hashlib.sha256).digest()
    if not hmac.compare_digest(mac, sl["mac"]):
        return None
    return xts(wrap[:64], b"\0" * 16, sl["wrapped"], True)


def master_key(hdr, pw):
    k = header_read(hdr)
    for sl in k["slots"]:
        mk = unlock_slot(sl, pw)
        if mk is not None:
            return k, mk, sl["index"]
    return k, None, -1



def cmd_read(path, pw):
    d = open(path, "rb").read()
    hdr = d[:HDR_SECTORS * SECTOR]
    k, mk, where = master_key(hdr, pw)
    print("header: magic=1 version=%d cipher=%d kdf=%d sector=%d"
          % (k["version"], k["cipher"], k["kdf"], k["secsize"]))
    print("header: sum=%d first=%d count=%d"
          % (1 if k["sum_ok"] else 0, k["first"], k["count"]))
    used = [s["index"] for s in k["slots"] if s["used"]]
    print("header: slots=%d used=%s" % (len(used), ",".join(
        str(i) for i in used) or "-"))
    if mk is None:
        print("unlocked: 0")
        return 1
    print("unlocked: 1 slot=%d" % where)
    print("key: halves_differ=%d"
          % (1 if mk[:32] != mk[32:] else 0))
    first = k["first"]
    sb = xts(mk, tweak_of(0), d[first * SECTOR:(first + 1) * SECTOR], True)
    print("fs: magic=%s" % sb[:8].hex())
    print("fs: text=%s" % sb[:8].decode("latin1"))
    return 0



def cmd_write(path, pw, t=1, m=64, p=1, blocks=8192):
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
    struct.pack_into("<Q", hdr, H_COUNT, blocks - HDR_SECTORS)
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
        f.truncate(blocks * SECTOR)
    print("wrote: %s blocks=%d t=%d m=%d p=%d" % (path, blocks, t, m, p))
    print("key: %s" % mk.hex())
    return 0



def cmd_raw(path):
    import collections
    import math
    import re
    d = open(path, "rb").read()
    data = d[HDR_SECTORS * SECTOR:]
    n = len(data) // SECTOR

    sig = {
        b"OSUM-OFS": "OFS superblock",
        b"SFO-MUSO": "OFS magic reversed",
        b"NTFS": "NTFS",
        b"\x53\xef": "ext2/3/4",
        b"FAT1": "FAT",
    }
    print("raw: sectors=%d" % n)
    for pat, name in sig.items():
        print("raw: sig %s = %d" % (name, data.count(pat)))

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
    print("raw: empty=%d written=%d" % (empty, len(ents)))
    if ents:
        print("raw: entropy_min=%.3f mean=%.3f below7=%d"
              % (min(ents), sum(ents) / len(ents),
                 sum(1 for e in ents if e < 7.0)))
    long_runs = [r for r in re.findall(rb"[ -~]{16,}", data)]
    print("raw: text_runs16=%d" % len(long_runs))
    return 0



def cmd_vectors(oracle):
    def query(lines):
        r = subprocess.run([oracle], input="\n".join(lines) + "\n",
                           capture_output=True, text=True, timeout=1800)
        return r.stdout.strip().split("\n")

    total_good = 0
    total_all = 0

    lines, want = [], []
    for mlen in (0, 1, 2, 63, 64, 65, 127, 128, 129, 200, 1000):
        msg = bytes((i * 7 + 3) & 255 for i in range(mlen))
        for ol in (1, 16, 32, 48, 64):
            lines.append("b2b %s %d" % (msg.hex() if msg else "-", ol))
            want.append(hashlib.blake2b(msg, digest_size=ol).hexdigest())
    for klen in (1, 16, 32, 64):
        for mlen in (0, 1, 64, 129):
            key = bytes((i * 11 + 5) & 255 for i in range(klen))
            msg = bytes((i * 3 + 1) & 255 for i in range(mlen))
            lines.append("b2bkey %s %s 64"
                      % (key.hex(), msg.hex() if msg else "-"))
            want.append(hashlib.blake2b(msg, key=key,
                                        digest_size=64).hexdigest())
    got = query(lines)
    good = sum(1 for a, b in zip(got, want) if a == b)
    print("blake2b %d/%d" % (good, len(want)))
    total_good += good
    total_all += len(want)

    lines, want = [], []
    cases = []
    for t in (1, 2, 3):
        for m in (8, 16, 32, 64, 128, 256):
            for p in (1, 2, 4):
                if m < 8 * p:
                    continue
                cases.append((b"password", b"somesaltsomesalt",
                               t, m, p, 32, "ID"))
    cases += [
        (b"", b"12345678", 1, 8, 1, 32, "ID"),
        (b"x" * 100, b"s" * 32, 2, 64, 2, 128, "ID"),
        (b"pw", b"saltsalt", 2, 32, 2, 32, "I"),
        (b"pw", b"saltsalt", 3, 64, 4, 32, "D"),
    ]
    names = {"ID": "argon2id", "I": "argon2i", "D": "argon2d"}
    for pw, salt, t, m, p, n, ty in cases:
        lines.append("%s %s %s %d %d %d %d"
                  % (names[ty], pw.hex() if pw else "-", salt.hex(),
                     t, m, p, n))
        want.append(argon2ll.hash_secret_raw(
            secret=pw, salt=salt, time_cost=t, memory_cost=m,
            parallelism=p, hash_len=n,
            type=getattr(argon2ll.Type, ty), version=19).hex())
    got = query(lines)
    good = sum(1 for a, b in zip(got, want) if a == b)
    print("argon2 %d/%d" % (good, len(want)))
    total_good += good
    total_all += len(want)

    lines, want = [], []
    kdf_class = {"ID": argon2kdf.Argon2id, "I": argon2kdf.Argon2i,
                 "D": argon2kdf.Argon2d}
    oracle_word = {"ID": "argon2xid", "I": "argon2xi", "D": "argon2xd"}
    keyed = [
        (b"\x01" * 32, b"\x02" * 16, b"\x03" * 8, b"\x04" * 12, 3, 32, 4, 32),
        (b"", b"saltsalt", b"k", b"", 1, 8, 1, 16),
        (b"pw", b"saltsalt", b"", b"ad", 2, 16, 2, 32),
        (b"pw" * 20, b"s" * 24, b"x" * 100, b"y" * 200, 2, 64, 4, 64),
        (b"a", b"saltsalt", b"secret", b"assoc", 3, 128, 8, 48),
    ]
    for ty in ("ID", "I", "D"):
        for pw, salt, sec, ad, t, m, p, n in keyed:
            lines.append("%s %s %s %s %s %d %d %d %d" % (
                oracle_word[ty], pw.hex() or "-", salt.hex(),
                sec.hex() or "-", ad.hex() or "-", t, m, p, n))
            want.append(kdf_class[ty](
                salt=salt, length=n, iterations=t, lanes=p, memory_cost=m,
                ad=ad or None, secret=sec or None).derive(pw).hex())
    got = query(lines)
    good = sum(1 for a, b in zip(got, want) if a == b)
    print("argon2keyed %d/%d" % (good, len(want)))
    total_good += good
    total_all += len(want)

    lines, want = [], []
    for n in (16, 32, 48, 512, 4096):
        for kn in range(3):
            key = bytes((i * 17 + kn * 5 + 1) & 255 for i in range(64))
            pt = bytes((i * 13 + 7 + kn) & 255 for i in range(n))
            tw = bytes((i * 5 + 2 + kn) & 255 for i in range(16))
            ct = xts(key, tw, pt, False)
            lines.append("xtsenc %s %s %s" % (key.hex(), tw.hex(), pt.hex()))
            want.append(ct.hex())
            lines.append("xtsdec %s %s %s" % (key.hex(), tw.hex(), ct.hex()))
            want.append(pt.hex())
    for lba in (0, 1, 2, 63, 1000, 123456):
        key = bytes((i * 3 + 9) & 255 for i in range(64))
        pt = bytes((i * 11 + lba) & 255 for i in range(512))
        ct = xts(key, tweak_of(lba), pt, False)
        lines.append("xtssec %s %d %s" % (key.hex(), lba, pt.hex()))
        want.append(ct.hex())
        lines.append("xtssecd %s %d %s" % (key.hex(), lba, ct.hex()))
        want.append(pt.hex())
    got = query(lines)
    good = sum(1 for a, b in zip(got, want) if a == b)
    print("xts %d/%d" % (good, len(want)))
    total_good += good
    total_all += len(want)

    invalid = [
        "xtsenc %s %s %s" % (("11" * 32 + "11" * 32), "00" * 16, "00" * 16),
        "xtsenc %s %s %s" % ("00" * 32 + "11" * 32, "00" * 16, "00" * 8),
        "xtsenc %s %s %s" % ("00" * 32, "00" * 16, "00" * 16),
        "argon2id 4142 4142 1 8 1 32",
        "argon2xid 4142 %s 41 - 1 8 1 32" % ("41" * 7),
        "argon2xid 4142 %s zz - 1 8 1 32" % ("41" * 8),
        "argon2id 4142 %s 1 8 4 32" % ("41" * 16),
        "nonsense 00",
    ]
    got = query(invalid)
    good = sum(1 for z in got if z.strip() == "FAIL")
    print("negative %d/%d" % (good, len(invalid)))
    total_good += good
    total_all += len(invalid)

    print("total %d/%d" % (total_good, total_all))
    return 0 if total_good == total_all else 1


PER_BLOCK = SECTOR // 8


def _ofs_reader(blk):
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
    k, mk, where = master_key(d[:HDR_SECTORS * SECTOR], pw)
    if mk is None:
        print("tree: unlocked=0")
        return 1
    first = k["first"]

    def blk(i):
        return xts(mk, tweak_of(i),
                   d[(first + i) * SECTOR:(first + i + 1) * SECTOR], True)

    root, file = _ofs_reader(blk)
    lengths = [100, 700, 5000, 40000]
    try:
        entries = sorted(root(), key=lambda x: x[1])
    except (ZeroDivisionError, struct.error, IndexError, ValueError):
        print("tree: unlocked=1 slot=%d unreadable=1" % where)
        return 1
    print("tree: unlocked=1 slot=%d files=%d" % (where, len(entries)))
    good = 0
    for n, nm in entries:
        if len(nm) != 2 or nm[0] != "k" or not nm[1].isdigit():
            continue
        i = int(nm[1])
        if i >= len(lengths):
            continue
        length = lengths[i]
        want = hashlib.sha256(
            bytes(((i * 37 + q * 7 + 3) & 255) for q in range(length))).hexdigest()
        got = hashlib.sha256(file(n)).hexdigest()
        if want == got:
            good += 1
        print("tree: sha %s = %s %s" % (nm, got, "OK" if want == got else
                                        "WRONG(want %s)" % want))
    print("tree: good=%d of=%d" % (good, len(lengths)))
    return 0 if good == len(lengths) else 1


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 2
    absent = missing()
    if absent:
        print("gegen.py: missing: %s" % ", ".join(absent))
        return 3
    b = sys.argv[1]
    if b == "read":
        return cmd_read(sys.argv[2], sys.argv[3].encode())
    if b == "write":
        a = sys.argv[4:]
        return cmd_write(sys.argv[2], sys.argv[3].encode(),
                           int(a[0]) if len(a) > 0 else 1,
                           int(a[1]) if len(a) > 1 else 64,
                           int(a[2]) if len(a) > 2 else 1,
                           int(a[3]) if len(a) > 3 else 8192)
    if b == "tree":
        return cmd_tree(sys.argv[2], sys.argv[3].encode())
    if b == "raw":
        return cmd_raw(sys.argv[2])
    if b == "vectors":
        return cmd_vectors(sys.argv[2])
    print("unknown: %s" % b)
    return 2


if __name__ == "__main__":
    sys.exit(main())
