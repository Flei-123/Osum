# SPDX-License-Identifier: GPL-2.0-only
from dataclasses import dataclass

import hiditems as hi

FLAGS_DATA = 0x02
FLAGS_PAD = 0x03
GEOMETRY = ("rid", "bits", "lmin", "lmax", "pmin", "pmax", "unitexp", "unit")
PHYSICAL_FIELDS = (("pmin", hi.PHYSICAL_MIN), ("pmax", hi.PHYSICAL_MAX),
                   ("unitexp", hi.UNIT_EXPONENT), ("unit", hi.UNIT))


@dataclass(frozen=True)
class Coll:
    kind: int
    page: int
    usage: int
    children: tuple


@dataclass(frozen=True)
class Group:
    caps: tuple


@dataclass(frozen=True)
class AlignByte:
    kind: str
    rid: int


@dataclass(frozen=True)
class PadTo:
    kind: str
    rid: int
    total_bytes: int


class Builder:
    def __init__(self):
        self.out = bytearray()
        self.state = {}
        self.bits = {}
        self.notes = []

    def set_global(self, tag, value):
        if self.state.get(tag) == value:
            return
        self.state[tag] = value
        self.out += hi.global_item(tag, value)

    def add_bits(self, kind, rid, amount):
        key = (kind, rid)
        self.bits[key] = self.bits.get(key, 0) + amount

    def emit(self, nodes):
        for node in nodes:
            getattr(self, "emit_" + type(node).__name__.lower())(node)

    def emit_coll(self, node):
        self.set_global(hi.USAGE_PAGE, node.page)
        self.out += hi.local_item(hi.USAGE, node.usage)
        self.out += hi.collection_item(node.kind)
        self.emit(node.children)
        self.out += hi.end_item()

    def emit_group(self, node):
        first = node.caps[0]
        if len(node.caps) > 1:
            for cap in node.caps:
                same = all(getattr(cap, name) == getattr(first, name) for name in GEOMETRY)
                if not (same and cap.page == first.page and cap.kind == first.kind and cap.count == 1):
                    raise ValueError("group members differ: %s" % cap.label())
        total = sum(cap.count for cap in node.caps)
        self.set_global(hi.USAGE_PAGE, first.page)
        self.set_global(hi.REPORT_ID, first.rid)
        self.set_global(hi.LOGICAL_MIN, first.lmin)
        self.set_global(hi.LOGICAL_MAX, first.lmax)
        for name, tag in PHYSICAL_FIELDS:
            if getattr(first, name) is not None:
                self.set_global(tag, getattr(first, name))
        self.set_global(hi.REPORT_SIZE, first.bits)
        self.set_global(hi.REPORT_COUNT, total)
        for cap in node.caps:
            self.out += hi.local_item(hi.USAGE, cap.usage)
        self.out += hi.main_item(hi.MAIN_TAG[first.kind], FLAGS_DATA)
        self.add_bits(first.kind, first.rid, first.bits * total)

    def emit_pad(self, kind, rid, bits):
        while bits > 0:
            chunk = min(bits, 8)
            self.set_global(hi.REPORT_ID, rid)
            self.set_global(hi.REPORT_SIZE, chunk)
            self.set_global(hi.REPORT_COUNT, 1)
            self.out += hi.main_item(hi.MAIN_TAG[kind], FLAGS_PAD)
            self.add_bits(kind, rid, chunk)
            bits -= chunk

    def emit_alignbyte(self, node):
        self.emit_pad(node.kind, node.rid, -self.bits.get((node.kind, node.rid), 0) % 8)

    def emit_padto(self, node):
        current = self.bits.get((node.kind, node.rid), 0)
        missing = (node.total_bytes - 1) * 8 - current
        if missing < 0:
            raise ValueError("report %s rid=%d already longer than %d bytes" % (node.kind, node.rid, node.total_bytes))
        if missing:
            self.notes.append("explicit %d-bit padding item appended at the end of %s report rid=%d "
                              "to reach the measured length of %d bytes; HidP caps do not describe it"
                              % (missing, node.kind, node.rid, node.total_bytes))
            self.emit_pad(node.kind, node.rid, missing)

    def lengths(self):
        out = {"IN": 0, "OUT": 0, "FEAT": 0}
        for (kind, _), bits in self.bits.items():
            out[kind] = max(out[kind], 1 + (bits + 7) // 8)
        return out


def build(nodes):
    builder = Builder()
    builder.emit(nodes)
    return builder
