#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import struct
import sys


def scope(kind, enum_id, bus, dev, fn):
    return struct.pack("<BBHBBBB", kind, 8, 0, enum_id, bus, dev, fn)


def drhd(flags, seg, base, scopes):
    body = b"".join(scopes)
    return struct.pack("<HHBBHQ", 0, 16 + len(body), flags, 0, seg, base) + body


def rmrr(seg, base, limit, scopes):
    body = b"".join(scopes)
    return struct.pack("<HHHHQQ", 1, 24 + len(body), 0, seg, base, limit) + body


def atsr(flags, seg, scopes):
    body = b"".join(scopes)
    return struct.pack("<HHBBH", 2, 8 + len(body), flags, 0, seg) + body


def rhsa(base, dom):
    return struct.pack("<HHIQI", 3, 20, 0, base, dom)


def table(haw, flags, structs, fix=True, sig=b"DMAR"):
    body = b"".join(structs)
    n = 48 + len(body)
    hdr = bytearray(sig + struct.pack("<IBB6s8sI4sI", n, 1, 0, b"OEMID ", b"OEMTABLE", 1, b"INTL", 1))
    hdr += bytes([haw, flags]) + b"\0" * 10
    t = bytearray(hdr + body)
    if fix:
        t[9] = (-sum(t)) & 0xFF
    return bytes(t)


def arr(name, data):
    return "static mut %s: [u8; %d] = [%s]\n" % (name, len(data), ", ".join("%d as u8" % b for b in data))


tables = {
    "t_full": table(38, 0x05, [
        drhd(0, 0, 0xFED90000, [scope(1, 0, 0, 2, 0)]),
        drhd(1, 0, 0xFED91000, []),
        rmrr(0, 0x7A000000, 0x7A1FFFFF, [scope(1, 0, 0, 0x14, 0)]),
        atsr(1, 0, []),
        rhsa(0xFED90000, 3),
    ]),
    "t_empty": table(35, 0x00, []),
    "t_badsig": table(38, 0x01, [drhd(1, 0, 0xFED90000, [])], sig=b"DMAX"),
    "t_badsum": table(38, 0x03, [drhd(1, 0, 0xFED90000, [])], fix=False),
    "t_trunc": table(38, 0x01, [drhd(1, 0, 0xFED90000, []), struct.pack("<HHI", 1, 2, 0), drhd(0, 0, 0xFED92000, [])]),
    "t_ioapic": table(38, 0x01, [drhd(1, 0, 0xFED90000, [struct.pack("<BBHBBBB", 3, 8, 0, 2, 0, 0x1F, 7)])]),
}

head = open(sys.argv[1]).read()
src = head + "\n" + "".join(arr(k, v) for k, v in tables.items())
src += "\nstatic mut outb: [u8; 4096] = [0 as u8; 4096]\n"
src += "\nfn tp(name: u64) -> u64 {\n"
for i, k in enumerate(tables):
    src += "    if name == %d {\n        return (&%s[0 as usize]) as u64\n    }\n" % (i, k)
src += "    return 0\n}\n"
src += "\nfn main() -> i32 {\n    return run_all()\n}\n"
open(sys.argv[2], "w").write(src)
print(" ".join(tables))
