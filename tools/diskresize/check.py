#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import importlib.util
import os
import re
import struct
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("wcheck", os.path.join(HERE, "..", "disks", "wcheck.py"))
wcheck = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wcheck)

SECT = 512
OLD = [(40, 500, "ofs", "a"), (600, 800, "efi", "b")]
NEW = [(40, 300, "ofs", "a"), (600, 800, "efi", "b")]
EXPECT_STATE = {0: "old", 1: "old", 2: "new", 3: "new", 4: "new"}
results = []


def check(name, cond, detail=""):
    results.append(cond)
    print("  %-5s %s%s" % ("OK" if cond else "FAIL", name, ("  " + str(detail)) if (detail and not cond) else ""))


def load(d, n):
    with open(os.path.join(d, n + ".img"), "rb") as f:
        return f.read()


def kv(line):
    return dict(re.findall(r"(\w+)=(\S+)", line))


def sgdisk_clean(path):
    r = subprocess.run(["sgdisk", "-v", path], capture_output=True, text=True)
    return "No problems found" in r.stdout


def sgdisk_range(path, idx):
    r = subprocess.run(["sgdisk", "-i", str(idx), path], capture_output=True, text=True)
    m1 = re.search(r"First sector: (\d+)", r.stdout)
    m2 = re.search(r"Last sector: (\d+)", r.stdout)
    return (int(m1.group(1)), int(m2.group(1))) if m1 and m2 else None


def body(img):
    total = len(img) // SECT
    return img[34 * SECT:(total - 33) * SECT]


def gpt_section(d, rows):
    base = load(d, "base")
    p, _ = wcheck.parse(base)
    check("base: valid GPT with the two partitions, sgdisk -v clean", not p["errors"] and p["parts"] == OLD and sgdisk_clean(os.path.join(d, "base.img")), p)
    fz = [r for n, r in rows if n == "f"]
    check("fuzz: 60 repaired images (5 crash points x 3 tear modes x 4 repair interruptions)", len(fz) == 60, len(fz))
    bad = []
    for k in range(5):
        for t in range(3):
            for j in range(4):
                name = "f%d%d%d" % (k, t, j)
                img = load(d, name)
                p, _ = wcheck.parse(img)
                want = NEW if EXPECT_STATE[k] == "new" else OLD
                ok = not p["errors"] and p["parts"] == want and body(img) == body(base) and sgdisk_clean(os.path.join(d, name + ".img"))
                if not ok:
                    bad.append((name, p["errors"], p["parts"]))
    check("fuzz: every crash point, tear mode and interrupted repair ends consistent: both copies equal, sgdisk -v clean, body untouched", not bad, bad[:3])
    check("fuzz: the commit point is the backup header write (crash after 0-1 writes = old table, after 2-4 = new table)", all(
        r["state"] == EXPECT_STATE[int(r["k"])] for r in fz), [r for r in fz if r["state"] != EXPECT_STATE[int(r["k"])]][:2])
    check("fuzz: a second repair never writes (idempotent)", all(r["idem"] == "0" and r["repair2"] == "0" for r in fz))
    check("fuzz: an interrupted repair reports the I/O error, a finished one rc 0", all(r["repair1"] in ("0", "5") for r in fz))
    pre_none = [r for r in fz if r["pre"] == "none"]
    check("counter-proof: some crashes leave a table the reader rejects before repair (%d of 60)" % len(pre_none), len(pre_none) >= 6)
    nr = [r for n, r in rows if n == "n"]
    check("counter-proof: 15 images without repair", len(nr) == 15, len(nr))
    for k in range(5):
        for t in range(3):
            img = load(d, "n%d%d" % (k, t))
            p, _ = wcheck.parse(img)
            if 1 <= k <= 3:
                check("counter-proof: no repair, crash after %d writes (tear %d): the independent parser sees the damage" % (k, t), bool(p["errors"]))
            if k == 4 or (k == 0 and t == 0):
                check("no repair needed, crash after %d writes: image already consistent" % k, not p["errors"], p["errors"])
    p3, _ = wcheck.parse(load(d, "n30"))
    check("counter-proof: sgdisk -v also flags the crash-after-3 image", not sgdisk_clean(os.path.join(d, "n30.img")))


def heal_section(d, byname):
    base = load(d, "base")
    for n in ("h_phdr", "h_parr", "h_bhdr", "h_barr", "h_clean"):
        r = byname[n]
        check("%s: repair rc 0, image byte-identical to the original" % n, r["rc"] == "0" and load(d, n) == base, r)
    check("h_phdr/h_parr: the reader rejects the damaged primary before repair", byname["h_phdr"]["pre"] == "none" and byname["h_parr"]["pre"] == "none")
    check("h_phdr/h_parr/h_bhdr/h_barr: exactly two writes (array + header)", all(byname[n]["writes"] == "2" for n in ("h_phdr", "h_parr", "h_bhdr", "h_barr")))
    check("h_clean: a healthy disk gets zero writes", byname["h_clean"]["writes"] == "0")
    check("h_both: both headers damaged -> rc 1, zero writes", byname["h_both"]["rc"] == "1" and byname["h_both"]["writes"] == "0")


def resize_section(d, byname):
    base = load(d, "base")
    for n, want, rng in (("r_shrink", NEW, (40, 339)), ("r_grow", [(40, 560, "ofs", "a"), (600, 800, "efi", "b")], (40, 599)),
                         ("r_second", [(40, 500, "ofs", "a"), (600, 400, "efi", "b")], None), ("r_afterrepair", NEW, None)):
        img = load(d, n)
        p, _ = wcheck.parse(img)
        ok = byname[n]["rc"] == "0" and not p["errors"] and p["parts"] == want and body(img) == body(base) and sgdisk_clean(os.path.join(d, n + ".img"))
        check("%s: rc 0, both copies consistent, partitions %s, sgdisk -v clean, body untouched" % (n, [x[:2] for x in want]), ok, (byname[n], p))
        if rng:
            check("%s: sgdisk -i reports sectors %s" % (n, rng), sgdisk_range(os.path.join(d, n + ".img"), 1) == rng)
    check("r_shrink: exactly 4 writes (backup array, backup header, primary array, primary header)", byname["r_shrink"]["writes"] == "4")
    for n, rc in (("r_overlap", "3"), ("r_badstart", "8"), ("r_zero", "2"), ("r_range", "2"), ("r_same", "0")):
        check("%s: rc %s and the disk is byte-identical, zero writes" % (n, rc), byname[n]["rc"] == rc and byname[n]["writes"] == "0" and load(d, n) == base, byname[n])
    check("r_nobackup: damaged backup refuses with rc 7 before any write", byname["r_nobackup"]["rc"] == "7" and byname["r_nobackup"]["writes"] == "0")
    check("r_notable: an empty disk refuses with rc 1", byname["r_notable"]["rc"] == "1")


def mbr_parts(img):
    out = []
    for i in range(4):
        e = img[446 + 16 * i:446 + 16 * (i + 1)]
        out.append((e[4], struct.unpack_from("<I", e, 8)[0], struct.unpack_from("<I", e, 12)[0]))
    return out


def sfdisk_ok(path):
    r = subprocess.run(["sfdisk", "-V", path], capture_output=True, text=True)
    return r.returncode == 0 and "No errors detected" in r.stdout


def chs(lba):
    cyl = lba // (255 * 63)
    if cyl > 1023:
        return bytes([254, 255, 255])
    return bytes([(lba // 63) % 255, (lba % 63 + 1) | ((cyl >> 8) << 6), cyl & 255])


def mbr_section(d, byname):
    base = load(d, "mbase")
    bp = mbr_parts(base)
    check("mbase: sfdisk -V clean", sfdisk_ok(os.path.join(d, "mbase.img")))
    for n, size in (("m_shrink", 300), ("m_grow", 536), ("m_second", None)):
        img = load(d, n)
        p = mbr_parts(img)
        want = list(bp)
        if n == "m_second":
            want[1] = (11, 600, 100)
        else:
            want[0] = (131, 64, size)
        ok = byname[n]["rc"] == "0" and byname[n]["writes"] == "1" and p == want and img[512:] == base[512:] and img[446:446 + 4] == base[446:446 + 4] \
            and sfdisk_ok(os.path.join(d, n + ".img"))
        check("%s: rc 0, one write, only that entry's length (and end CHS) changed, rest of the disk untouched, sfdisk -V clean" % n, ok, (p, want))
    for n, slot, start, size in (("m_shrink", 0, 64, 300), ("m_grow", 0, 64, 536), ("m_second", 1, 600, 100)):
        e = load(d, n)[446 + 16 * slot:446 + 16 * (slot + 1)]
        check("%s: end CHS bytes follow the new last sector" % n, e[5:8] == chs(start + size - 1), e[5:8].hex())
    for n, rc in (("m_overlap", "3"), ("m_ext", "6"), ("m_badstart", "8"), ("m_range", "2"), ("m_zero", "2"), ("m_same", "0"), ("m_crash", "5")):
        check("%s: rc %s, disk byte-identical, zero writes" % (n, rc), byname[n]["rc"] == rc and byname[n].get("writes", "0") == "0" and load(d, n) == base, byname[n])
    check("m_gpt: a protective MBR is refused with rc 6", byname["m_gpt"]["rc"] == "6")
    check("m_nosig: a disk without 55AA is refused with rc 1", byname["m_nosig"]["rc"] == "1")


def parse_out(path):
    rows = []
    for line in open(path):
        if line.startswith("case "):
            rows.append((line.split()[1], kv(line)))
    return rows


def main(g, m):
    rows = parse_out(os.path.join(g, "out.txt"))
    byname = dict(rows)
    print("== diskresize: gptw.repair / gptw.resize against sgdisk and the independent GPT parser ==")
    gpt_section(g, rows)
    heal_section(g, byname)
    resize_section(g, byname)
    print("== diskresize: mbrw.resize against sfdisk ==")
    mbr_section(m, dict(parse_out(os.path.join(m, "out.txt"))))
    bad = results.count(False)
    print("DISKRESIZE: %d passed, %d failed" % (len(results) - bad, bad))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
