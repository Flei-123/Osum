# SPDX-License-Identifier: GPL-2.0-only
from dataclasses import dataclass

import bitreader

PAGE_DESKTOP = 0x1
PAGE_DIGITIZER = 0xD
PAGE_BUTTON = 0x9
PAGE_VENDOR = 0xFF00
ID_BITS = 8
FINGER_BITS = 40
FINGER_COUNT = 5


@dataclass(frozen=True)
class Field:
    name: str
    offset: int
    width: int
    page: int
    usage: int
    occurrence: int


@dataclass(frozen=True)
class Report:
    kind: str
    nbytes: int
    fields: tuple

    def covered(self):
        bits = set()
        for f in self.fields:
            bits.update(range(f.offset, f.offset + f.width))
        return bits


def touchpad_input():
    fields = []
    for k in range(FINGER_COUNT):
        base = ID_BITS + FINGER_BITS * k
        fields += [
            Field("contact%d.conf" % k, base + 0, 1, PAGE_DIGITIZER, 0x47, k),
            Field("contact%d.tip" % k, base + 1, 1, PAGE_DIGITIZER, 0x42, k),
            Field("contact%d.id" % k, base + 2, 3, PAGE_DIGITIZER, 0x51, k),
            Field("contact%d.x" % k, base + 8, 16, PAGE_DESKTOP, 0x30, k),
            Field("contact%d.y" % k, base + 24, 16, PAGE_DESKTOP, 0x31, k),
        ]
    tail = ID_BITS + FINGER_BITS * FINGER_COUNT
    fields += [
        Field("scan", tail, 16, PAGE_DIGITIZER, 0x56, 0),
        Field("count", tail + 16, 8, PAGE_DIGITIZER, 0x54, 0),
        Field("btn", tail + 24, 1, PAGE_BUTTON, 0x01, 0),
    ]
    return Report("IN", 30, tuple(fields))


def flat(kind, nbytes, rows):
    return Report(kind, nbytes, tuple(Field(*row) for row in rows))


DEVICES = {
    "touchpad-045e-09af": {
        ("IN", 4): touchpad_input(),
        ("FEAT", 4): flat("FEAT", 2, [
            ("count_max", 8, 4, PAGE_DIGITIZER, 0x55, 0),
            ("pad_type", 12, 4, PAGE_DIGITIZER, 0x59, 0),
        ]),
        ("FEAT", 6): flat("FEAT", 2, [("latency", 8, 4, PAGE_DIGITIZER, 0x60, 0)]),
    },
    "touchscreen-045e-0c32": {
        ("IN", 64): flat("IN", 6, [
            ("tip", 8, 1, PAGE_DIGITIZER, 0x42, 0),
            ("x", 16, 16, PAGE_DESKTOP, 0x30, 0),
            ("y", 32, 16, PAGE_DESKTOP, 0x31, 0),
        ]),
    },
    "pen-045e-0c32": {
        ("IN", 1): flat("IN", 16, [
            ("barrel", 8, 1, PAGE_DIGITIZER, 0x44, 0),
            ("invert", 9, 1, PAGE_DIGITIZER, 0x3C, 0),
            ("eraser", 10, 1, PAGE_DIGITIZER, 0x45, 0),
            ("tip", 11, 1, PAGE_DIGITIZER, 0x42, 0),
            ("inrange", 12, 1, PAGE_DIGITIZER, 0x32, 0),
            ("x", 16, 16, PAGE_DESKTOP, 0x30, 0),
            ("y", 32, 16, PAGE_DESKTOP, 0x31, 0),
            ("pressure", 48, 16, PAGE_DIGITIZER, 0x30, 0),
            ("xtilt", 64, 16, PAGE_DIGITIZER, 0x3D, 0),
            ("ytilt", 80, 16, PAGE_DIGITIZER, 0x3E, 0),
            ("scan", 96, 16, PAGE_DIGITIZER, 0x56, 0),
            ("vendor", 112, 8, PAGE_VENDOR, 0x01, 0),
        ]),
    },
    "inputmode-045e-09af": {
        ("FEAT", 7): flat("FEAT", 2, [("mode", 8, 8, PAGE_DIGITIZER, 0x52, 0)]),
        ("FEAT", 8): flat("FEAT", 2, [
            ("surface", 8, 1, PAGE_DIGITIZER, 0x57, 0),
            ("button", 9, 1, PAGE_DIGITIZER, 0x58, 0),
        ]),
    },
}


def kind_for_name(name):
    return "FEAT" if name.startswith("feat-") else "IN"


def lookup(device, name, rid):
    return DEVICES[device][(kind_for_name(name), rid)]


def encode(report, rid, values):
    buffer = bytearray(report.nbytes)
    buffer[0] = rid
    known = {f.name: f for f in report.fields}
    for name, value in values.items():
        field = known[name]
        bitreader.write_bits(buffer, field.offset, field.width, value)
    return bytes(buffer)


def decode(report, data):
    return {f.name: bitreader.read_bits(data, f.offset, f.width) for f in report.fields}


def stray_bits(report, data):
    covered = report.covered()
    out = []
    for position in range(ID_BITS, len(data) * 8):
        if position not in covered and bitreader.get_bit(data, position):
            out.append(position)
    return out
