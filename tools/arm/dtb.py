#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/arm/dtb.py -- read the device tree QEMU writes for `-M virt`.

Every address in `kernel/arch/aarch64/virt.inc` came out of this, and not
out of a manual:

    qemu-system-aarch64 -machine virt,dumpdtb=/tmp/virt.dtb -cpu cortex-a53
    ./tools/arm/dtb.py /tmp/virt.dtb

The point is not that the numbers are hard to look up. The point is that a
number looked up somewhere else is a claim about the machine, and a number
read out of the machine is a measurement. When `-M virt` moves the GIC in
some future QEMU, `tools/arm/run.sh` compares this output with `virt.inc`
and the disagreement is a failed test rather than a mystery.

It is a flat DTB reader, about a hundred lines, no library. `dtc` is not
installed on the measuring machine and adding a package for four numbers
would be the wrong trade.
"""
import struct
import sys

FDT_BEGIN_NODE = 1
FDT_END_NODE = 2
FDT_PROP = 3
FDT_NOP = 4
FDT_END = 9


def parse(path):
    d = open(path, "rb").read()
    (magic, _total, off_struct, off_str, _off_rsv, _ver,
     _lastcomp, _boot, size_str, size_struct) = struct.unpack(">10I", d[:40])
    if magic != 0xD00DFEED:
        raise SystemExit("%s: not a flat device tree" % path)
    st = d[off_struct:off_struct + size_struct]
    strs = d[off_str:off_str + size_str]

    def name_at(o):
        return strs[o:strs.index(b"\0", o)].decode()

    out = []
    i = 0
    path_parts = []
    while i < len(st):
        (tok,) = struct.unpack(">I", st[i:i + 4])
        i += 4
        if tok == FDT_BEGIN_NODE:
            e = st.index(b"\0", i)
            path_parts.append(st[i:e].decode())
            i = (e + 4) & ~3
        elif tok == FDT_END_NODE:
            path_parts.pop()
        elif tok == FDT_PROP:
            ln, no = struct.unpack(">II", st[i:i + 8])
            i += 8
            val = st[i:i + ln]
            i = (i + ln + 3) & ~3
            out.append(("/".join(path_parts), name_at(no), val))
        elif tok == FDT_NOP:
            pass
        elif tok == FDT_END:
            break
        else:
            raise SystemExit("unknown token %d at %d" % (tok, i))
    return out


def words(v):
    return struct.unpack(">%dI" % (len(v) // 4), v) if len(v) % 4 == 0 else ()


def reg64(v):
    """`reg` with #address-cells = #size-cells = 2: pairs of 64-bit values."""
    w = words(v)
    return [(w[i] << 32 | w[i + 1], w[i + 2] << 32 | w[i + 3])
            for i in range(0, len(w) - 3, 4)]


def main():
    if len(sys.argv) < 2:
        raise SystemExit("usage: dtb.py <file.dtb> [--facts]")
    props = parse(sys.argv[1])
    facts = "--facts" in sys.argv

    by_node = {}
    for node, name, val in props:
        by_node.setdefault(node, {})[name] = val

    def first(pred):
        for node, p in by_node.items():
            if pred(node, p):
                return node, p
        return None, None

    def compat(p):
        return p.get("compatible", b"").decode("utf-8", "replace").replace("\0", " ").strip()

    result = {}

    node, p = first(lambda n, p: "arm,pl011" in compat(p))
    if p:
        result["UART0"] = reg64(p["reg"])[0][0]
        w = words(p.get("interrupts", b""))
        if len(w) >= 3:
            result["UART_INTID"] = w[1] + (32 if w[0] == 0 else 16)

    node, p = first(lambda n, p: "gic" in compat(p) and "interrupt-controller" in p)
    if p:
        r = reg64(p["reg"])
        result["GICD"] = r[0][0]
        result["GICC"] = r[1][0]

    node, p = first(lambda n, p: n.startswith("/memory"))
    if p:
        r = reg64(p["reg"])[0]
        result["RAM_BASE"], result["RAM_SIZE"] = r

    slots = sorted(n for n in by_node if "virtio_mmio" in n)
    if slots:
        base = reg64(by_node[slots[0]]["reg"])[0][0]
        second = reg64(by_node[slots[1]]["reg"])[0][0] if len(slots) > 1 else base
        result["VIRTIO_MMIO"] = base
        result["VIRTIO_STRIDE"] = second - base
        result["VIRTIO_SLOTS"] = len(slots)
        w = words(by_node[slots[0]]["interrupts"])
        result["VIRTIO_INTID0"] = w[1] + (32 if w[0] == 0 else 16)

    node, p = first(lambda n, p: n == "/timer")
    if p:
        w = words(p["interrupts"])
        # four triples: secure phys, non-secure phys, virtual, hypervisor
        if len(w) >= 12:
            result["TIMER_INTID"] = w[7] + 16       # the virtual timer, a PPI

    if facts:
        for k in ("RAM_BASE", "RAM_SIZE", "UART0", "UART_INTID", "GICD", "GICC",
                  "TIMER_INTID", "VIRTIO_MMIO", "VIRTIO_STRIDE", "VIRTIO_SLOTS",
                  "VIRTIO_INTID0"):
            if k in result:
                print("%s 0x%x %d" % (k, result[k], result[k]))
        return

    for k, v in result.items():
        print("%-14s 0x%08x  (%d)" % (k, v, v))


if __name__ == "__main__":
    main()
