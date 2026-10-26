#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import re
import socket
import sys

PROMPT = b"(qemu) "
MAX_BUS = 16
FUNCTIONS = 8
DEVICES = 32
VENDOR_ABSENT = 0xFFFF
HEADER_MULTI = 0x80
STATUS_CAP_LIST = 0x10
CAP_PTR_OFFSET = 0x34
CAP_EXPRESS = 0x10
EXT_START = 0x100
EXT_MAX = 480
READ_RE = re.compile(r"^[0-9a-f]+: 0x([0-9a-f]+)", re.M)


class Monitor:
    def __init__(self, path: str, base: int):
        self.base = base
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.settimeout(30)
        self.sock.connect(path)
        self.expect_prompt()

    def expect_prompt(self) -> bytes:
        buf = b""
        while not buf.endswith(PROMPT):
            chunk = self.sock.recv(65536)
            if not chunk:
                raise RuntimeError("monitor closed")
            buf += chunk
        return buf

    def dword(self, bus: int, dev: int, fn: int, off: int) -> int:
        addr = self.base + (bus << 20) + (dev << 15) + (fn << 12) + (off & 0xFFC)
        self.sock.sendall(("xp /wx 0x%x\n" % addr).encode())
        text = self.expect_prompt().decode("latin-1")
        match = READ_RE.search(text)
        if match is None:
            raise RuntimeError("no value for %x: %r" % (addr, text))
        return int(match.group(1), 16)


def has_express(mon: Monitor, bus: int, dev: int, fn: int) -> bool:
    status = mon.dword(bus, dev, fn, 4) >> 16
    if not status & STATUS_CAP_LIST:
        return False
    ptr = mon.dword(bus, dev, fn, CAP_PTR_OFFSET) & 0xFC
    seen = 0
    while ptr >= 0x40 and seen < 48:
        word = mon.dword(bus, dev, fn, ptr)
        if word & 0xFF == CAP_EXPRESS:
            return True
        ptr = (word >> 8) & 0xFC
        seen += 1
    return False


def ext_caps(mon: Monitor, bus: int, dev: int, fn: int) -> list:
    caps = []
    off = EXT_START
    while off >= EXT_START and len(caps) < EXT_MAX:
        header = mon.dword(bus, dev, fn, off)
        if header in (0, 0xFFFFFFFF):
            break
        caps.append((header & 0xFFFF, off, (header >> 16) & 0xF))
        off = (header >> 20) & 0xFFC
    return caps


def main(argv: list) -> int:
    if len(argv) != 3:
        sys.stderr.write("usage: ecamref.py MONITOR_SOCKET ECAM_BASE\n")
        return 2
    mon = Monitor(argv[1], int(argv[2], 0))
    for bus in range(MAX_BUS):
        for dev in range(DEVICES):
            first = mon.dword(bus, dev, 0, 0) & 0xFFFF
            if first == VENDOR_ABSENT:
                continue
            multi = (mon.dword(bus, dev, 0, 0x0C) >> 16) & HEADER_MULTI
            for fn in range(FUNCTIONS if multi else 1):
                if mon.dword(bus, dev, fn, 0) & 0xFFFF == VENDOR_ABSENT:
                    continue
                print("dev=%02x:%02x.%x" % (bus, dev, fn))
                if has_express(mon, bus, dev, fn):
                    caps = ext_caps(mon, bus, dev, fn)
                    if caps:
                        print("hdr %02x:%02x.%x 0x%x" % (bus, dev, fn, mon.dword(bus, dev, fn, EXT_START)))
                        print("pcie %02x:%02x.%x ext=%s" % (bus, dev, fn, ",".join(
                            "%04x@%03xv%d" % c for c in caps)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
