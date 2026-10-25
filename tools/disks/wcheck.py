#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import importlib.util
import os
import struct
import sys
import zlib

SECT = 512
OFS_T = bytes([0x4D, 0x55, 0x53, 0x4F, 0x46, 0x4F, 0x01, 0x53, 0x8E, 0x75, 0x6D, 0x6F, 0x72, 0x69, 0x4F, 0x53])
ESP_T = bytes([0x28, 0x73, 0x2A, 0xC1, 0x1F, 0xF8, 0xD2, 0x11, 0xBA, 0x4B, 0x00, 0xA0, 0xC9, 0x3E, 0xC9, 0x3B])
LINUX_T = bytes([0xAF, 0x3D, 0xC6, 0x0F, 0x83, 0x84, 0x72, 0x47, 0x8E, 0x79, 0x3D, 0x69, 0xD8, 0x47, 0x7D, 0xE4])
KIND = {OFS_T: "ofs", ESP_T: "efi", LINUX_T: "linux"}

results = []


def check(name, cond, detail=""):
    results.append((name, cond))
    print("  %-5s %s%s" % ("OK" if cond else "FAIL", name, ("  " + detail) if (detail and not cond) else ""))


def header_ok(h):
    size = struct.unpack_from("<I", h, 12)[0]
    raw = bytearray(h[:size])
    stored = struct.unpack_from("<I", raw, 16)[0]
    raw[16:20] = bytes(4)
    return h[:8] == b"EFI PART" and (zlib.crc32(bytes(raw)) & 0xFFFFFFFF) == stored


def parse(img):
    total = len(img) // SECT
    out = {"errors": []}
    mbr = img[:SECT]
    if mbr[510:512] != b"\x55\xaa" or mbr[446 + 4] != 0xEE:
        out["errors"].append("protective mbr")
    if struct.unpack_from("<II", mbr, 446 + 8) != (1, total - 1):
        out["errors"].append("protective mbr range")
    ph = img[SECT:2 * SECT]
    bh = img[(total - 1) * SECT:total * SECT]
    if not header_ok(ph):
        out["errors"].append("primary header crc")
    if not header_ok(bh):
        out["errors"].append("backup header crc")
    pe = struct.unpack_from("<Q", ph, 72)[0]
    be = struct.unpack_from("<Q", bh, 72)[0]
    n, sz, acrc = struct.unpack_from("<III", ph, 80)
    arr_p = img[pe * SECT:pe * SECT + n * sz]
    arr_b = img[be * SECT:be * SECT + n * sz]
    if (zlib.crc32(arr_p) & 0xFFFFFFFF) != acrc:
        out["errors"].append("primary array crc")
    if (zlib.crc32(arr_b) & 0xFFFFFFFF) != struct.unpack_from("<I", bh, 88)[0]:
        out["errors"].append("backup array crc")
    if arr_p != arr_b:
        out["errors"].append("copies differ")
    if struct.unpack_from("<QQ", ph, 24) != (1, total - 1) or struct.unpack_from("<QQ", bh, 24) != (total - 1, 1):
        out["errors"].append("header lba fields")
    if struct.unpack_from("<QQ", ph, 40) != (34, total - 34):
        out["errors"].append("usable range")
    parts = []
    guids = set()
    for i in range(n):
        e = arr_p[i * sz:(i + 1) * sz]
        if e[:16] == bytes(16):
            continue
        first, last = struct.unpack_from("<QQ", e, 32)
        name = e[56:128].decode("utf-16-le").split("\0")[0]
        parts.append((first, last - first + 1, KIND.get(bytes(e[:16]), "other"), name))
        guids.add(bytes(e[16:32]))
    out["parts"] = parts
    out["unique"] = len(guids) == len(parts)
    return out, arr_p


def only_table_sectors_changed(img):
    total = len(img) // SECT
    body = img[34 * SECT:(total - 33) * SECT]
    return not any(body)


def main(d):
    def load(n):
        with open(os.path.join(d, n), "rb") as f:
            return f.read()

    print("== wcheck: GPT written by lib/disks/gptw.fi, verified by an independent parser ==")
    s1 = load("s1.img")
    p, _ = parse(s1)
    check("init: both headers, both arrays, protective MBR valid", not p["errors"], str(p["errors"]))
    check("init: no partitions", p["parts"] == [])
    check("init: nothing outside the table sectors written", only_table_sectors_changed(s1))
    s2 = load("s2.img")
    p, _ = parse(s2)
    check("create: table valid after two creates", not p["errors"], str(p["errors"]))
    check("create: exactly the two requested partitions",
          p["parts"] == [(2048, 8192, "ofs", "data1"), (10240, 4096, "efi", "boot")], str(p["parts"]))
    check("create: unique partition GUIDs", p["unique"])
    check("create: nothing outside the table sectors written", only_table_sectors_changed(s2))
    s3 = load("s3.img")
    p, _ = parse(s3)
    check("delete: table valid", not p["errors"], str(p["errors"]))
    check("delete: partition 1 gone, partition 2 untouched", p["parts"] == [(10240, 4096, "efi", "boot")], str(p["parts"]))
    s4 = load("s4.img")
    p, _ = parse(s4)
    check("reuse: freed slot reused, table valid", not p["errors"] and (2048, 2048, "linux", "big") in p["parts"], str(p))
    check("delete+reuse: nothing outside the table sectors written", only_table_sectors_changed(s4))

    spec = importlib.util.spec_from_file_location("mkfs", os.path.join(os.path.dirname(__file__), "..", "osum", "mkfs.py"))
    mk = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mk)
    print("== wcheck: OFS written by lib/disks/ofsfmt.fi against tools/osum/mkfs.py (the second implementation) ==")
    for name, blocks, ver, inodes in (("fmt-v2-small.img", 8192, 2, 128), ("fmt-v3-small.img", 8192, 3, 128),
                                      ("fmt-v2-big.img", 20000, 2, 1250), ("fmt-v3-big.img", 40000, 3, 2500)):
        img = load(name)
        fs = mk.Fs(blocks, version=ver, inodes=inodes, zeit=1700000000)
        fs.format()
        n = (fs.data_start + 1) * SECT
        check("%s: first %d blocks equal mkfs.py" % (name, fs.data_start + 1), img[:n] == bytes(fs.d[:n]))
        check("%s: nothing written behind the root directory" % name, not any(img[n:]))
        check("%s: size %d blocks" % (name, blocks), len(img) == blocks * SECT)
    bad = [n for n, c in results if not c]
    print("WCHECK: %d passed, %d failed" % (len(results) - len(bad), len(bad)))
    sys.exit(1 if bad else 0)




def vm(path, expect_parts, fmt_blocks):
    spec = importlib.util.spec_from_file_location("mkfs", os.path.join(os.path.dirname(__file__), "..", "osum", "mkfs.py"))
    mk = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mk)
    with open(path, "rb") as f:
        img = f.read()
    p, _ = parse(img)
    check("vm: table on the disposable disk valid (both copies, CRCs)", not p["errors"], str(p["errors"]))
    check("vm: partitions %s" % expect_parts, p["parts"] == expect_parts, str(p["parts"]))
    if fmt_blocks:
        start = p["parts"][0][0]
        fs = mk.Fs(fmt_blocks, version=2, inodes=max(128, min(4096, fmt_blocks // 16)), zeit=1700000000)
        fs.format()
        n = (fs.data_start + 1) * SECT
        got = img[start * SECT:start * SECT + n]
        check("vm: formatted partition equals mkfs.py (%d blocks)" % (fs.data_start + 1), got == bytes(fs.d[:n]))
    bad = [n for n, c in results if not c]
    print("WCHECK: %d passed, %d failed" % (len(results) - len(bad), len(bad)))
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    if sys.argv[1] == "vm":
        vm(sys.argv[2], eval(sys.argv[3]), int(sys.argv[4]))
    else:
        main(sys.argv[1])
