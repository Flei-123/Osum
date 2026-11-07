#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    python3 tools/hid/descs.py firn   > kernel/drv/hid/hidtest.fi
    python3 tools/hid/descs.py header              # Erwartung, row per device
    python3 tools/hid/descs.py felder            # Erwartung, row per field
    python3 tools/hid/descs.py error_count            (the broken ones, with number)
"""
import sys

KBD_BOOT = bytes([
    0x05, 0x01,
    0x09, 0x06,
    0xA1, 0x01,
    0x05, 0x07,
    0x19, 0xE0,
    0x29, 0xE7,
    0x15, 0x00,
    0x25, 0x01,
    0x75, 0x01,
    0x95, 0x08,
    0x81, 0x02,
    0x95, 0x01,
    0x75, 0x08,
    0x81, 0x01,
    0x95, 0x05,
    0x75, 0x01,
    0x05, 0x08,
    0x19, 0x01,
    0x29, 0x05,
    0x91, 0x02,
    0x95, 0x01,
    0x75, 0x03,
    0x91, 0x01,
    0x95, 0x06,
    0x75, 0x08,
    0x15, 0x00,
    0x25, 0x65,
    0x05, 0x07,
    0x19, 0x00,
    0x29, 0x65,
    0x81, 0x00,
    0xC0,
])

MOUSE_BOOT = bytes([
    0x05, 0x01,
    0x09, 0x02,
    0xA1, 0x01,
    0x09, 0x01,
    0xA1, 0x00,
    0x05, 0x09,
    0x19, 0x01,
    0x29, 0x03,
    0x15, 0x00,
    0x25, 0x01,
    0x95, 0x03,
    0x75, 0x01,
    0x81, 0x02,
    0x95, 0x01,
    0x75, 0x05,
    0x81, 0x01,
    0x05, 0x01,
    0x09, 0x30,
    0x09, 0x31,
    0x15, 0x81,
    0x25, 0x7F,
    0x75, 0x08,
    0x95, 0x02,
    0x81, 0x06,
    0xC0,
    0xC0,
])

MOUSE_WHEEL = bytes([
    0x05, 0x01,
    0x09, 0x02,
    0xA1, 0x01,
    0x85, 0x01,
    0x09, 0x01,
    0xA1, 0x00,
    0x05, 0x09,
    0x19, 0x01,
    0x29, 0x05,
    0x15, 0x00,
    0x25, 0x01,
    0x95, 0x05,
    0x75, 0x01,
    0x81, 0x02,
    0x95, 0x01,
    0x75, 0x03,
    0x81, 0x01,
    0x05, 0x01,
    0x09, 0x30,
    0x09, 0x31,
    0x16, 0x01, 0x80,
    0x26, 0xFF, 0x7F,
    0x75, 0x10,
    0x95, 0x02,
    0x81, 0x06,
    0x09, 0x38,
    0x15, 0x81,
    0x25, 0x7F,
    0x75, 0x08,
    0x95, 0x01,
    0x81, 0x06,
    0xC0,
    0xC0,
])


def _finger():
    return [
        0x05, 0x0D,
        0x09, 0x22,
        0xA1, 0x02,
        0x15, 0x00,
        0x25, 0x01,
        0x09, 0x47,
        0x09, 0x42,
        0x95, 0x02,
        0x75, 0x01,
        0x81, 0x02,
        0x95, 0x01,
        0x75, 0x02,
        0x81, 0x03,
        0x95, 0x01,
        0x75, 0x04,
        0x25, 0x05,
        0x09, 0x51,
        0x81, 0x02,
        0x05, 0x01,
        0x15, 0x00,
        0x26, 0x20, 0x0E,
        0x75, 0x10,
        0x55, 0x0E,
        0x65, 0x11,
        0x09, 0x30,
        0x35, 0x00,
        0x46, 0x60, 0x02,
        0x95, 0x01,
        0x81, 0x02,
        0x46, 0x8E, 0x01,
        0x26, 0x88, 0x08,
        0x09, 0x31,
        0x81, 0x02,
        0x05, 0x0D,
        0xC0,
    ]


PTP = bytes(
    [
        0x05, 0x0D,
        0x09, 0x05,
        0xA1, 0x01,
        0x85, 0x01,
    ]
    + _finger() * 5
    + [
        0x05, 0x0D,
        0x09, 0x54,
        0x95, 0x01,
        0x75, 0x07,
        0x15, 0x00,
        0x25, 0x05,
        0x81, 0x02,
        0x05, 0x09,
        0x09, 0x01,
        0x25, 0x01,
        0x75, 0x01,
        0x95, 0x01,
        0x81, 0x02,
        0x05, 0x0D,
        0x09, 0x56,
        0x55, 0x00,
        0x66, 0x01, 0x10,
        0x47, 0xFF, 0xFF, 0x00, 0x00,
        0x27, 0xFF, 0xFF, 0x00, 0x00,
        0x75, 0x10,
        0x95, 0x01,
        0x81, 0x02,
        0x09, 0x55,
        0x25, 0x05,
        0x75, 0x08,
        0xB1, 0x02,
        0xC0,
    ]
)

CONSUMER = bytes([
    0x05, 0x0C,
    0x09, 0x01,
    0xA1, 0x01,
    0x85, 0x03,
    0x15, 0x00,
    0x26, 0xFF, 0x03,
    0x19, 0x00,
    0x2A, 0xFF, 0x03,
    0x75, 0x10,
    0x95, 0x02,
    0x81, 0x00,
    0xC0,
])

KBD_NKRO = bytes([
    0x05, 0x01,
    0x09, 0x06,
    0xA1, 0x01,
    0x85, 0x02,
    0x05, 0x07,
    0x19, 0xE0,
    0x29, 0xE7,
    0x15, 0x00,
    0x25, 0x01,
    0x75, 0x01,
    0x95, 0x08,
    0x81, 0x02,
    0x19, 0x00,
    0x29, 0x77,
    0x95, 0x78,
    0x81, 0x02,
    0xC0,
])

GUT = [
    ("kbdboot", KBD_BOOT),
    ("mouse", MOUSE_BOOT),
    ("wheel", MOUSE_WHEEL),
    ("ptp", PTP),
    ("consumer", CONSUMER),
    ("nkro", KBD_NKRO),
]


E_OK, E_TRUNC, E_NEST, E_FIELDS, E_RIDS = 0, 1, 2, 3, 4
E_PUSH, E_SIZE, E_USAGE, E_LONG, E_EMPTY, E_BIG = 5, 6, 7, 8, 9, 10

BROKEN = [
    ("abgeschn", KBD_BOOT[:41], E_TRUNC),
    ("kopfleer", KBD_BOOT[:62] + bytes([0x26]), E_TRUNC),
    ("offen", KBD_BOOT[:-1], E_NEST),
    ("endeohne", bytes([0xC0]), E_NEST),
    ("zutief", bytes([0x05, 0x01, 0x09, 0x06] + [0xA1, 0x01] * 9), E_NEST),
    ("popleer", bytes([0x05, 0x01, 0x09, 0x06, 0xA1, 0x01, 0xB4, 0xC0]),
     E_PUSH),
    ("gr255", bytes([0x05, 0x01, 0x09, 0x06, 0xA1, 0x01,
                     0x75, 0xFF, 0x95, 0x01, 0x81, 0x02, 0xC0]), E_SIZE),
    ("ridnull", bytes([0x05, 0x01, 0x09, 0x06, 0xA1, 0x01,
                       0x85, 0x00, 0xC0]), E_SIZE),
    ("zugross", bytes([0x05, 0x01, 0x09, 0x06, 0xA1, 0x01,
                       0x75, 0x08, 0x96, 0x00, 0x04,
                       0x81, 0x02, 0xC0]), E_BIG),
    ("langpost", bytes([0x05, 0x01, 0xFE, 0x02, 0x00, 0x00, 0x00, 0xC0]),
     E_LONG),
    ("leer", b"", E_EMPTY),
    ("vielfeld",
     bytes([0x05, 0x01, 0x09, 0x06, 0xA1, 0x01, 0x75, 0x01, 0x95, 0x01]
           + [0x09, 0x30, 0x81, 0x02] * 65 + [0xC0]), E_FIELDS),
    ("vielrid",
     bytes([0x05, 0x01, 0x09, 0x06, 0xA1, 0x01, 0x75, 0x08, 0x95, 0x01]
           + sum([[0x85, i + 1, 0x09, 0x30, 0x81, 0x02] for i in range(17)], [])
           + [0xC0]), E_RIDS),
    ("vielgeb",
     bytes([0x05, 0x01, 0x09, 0x06, 0xA1, 0x01] + [0x09, 0x30] * 33
           + [0x75, 0x01, 0x95, 0x01, 0x81, 0x02, 0xC0]), E_USAGE),
]





def bitset(buf, bit, value, n=1):
    for k in range(n):
        if (value >> k) & 1:
            buf[bit // 8 + (bit % 8 + k) // 8] |= 1 << ((bit % 8 + k) % 8)
    return buf


def nkro(mods, keys):
    b = bytearray(17)
    b[0] = 2
    for m in mods:
        bitset(b, 8 + (m - 0xE0), 1)
    for u in keys:
        bitset(b, 8 + 8 + u, 1)
    return bytes(b)


def bootkbd(mods, keys):
    b = bytearray(8)
    for m in mods:
        b[0] |= 1 << (m - 0xE0)
    for i, u in enumerate(keys[:6]):
        b[2 + i] = u
    return bytes(b)


def ptp(finger, button=0, elapsed=0):
    b = bytearray(29)
    b[0] = 1
    for k, f in enumerate(finger[:5]):
        cid, x, y = f[0], f[1], f[2]
        conf = f[3] if len(f) > 3 else 1
        o = 8 + k * 40
        bitset(b, o + 0, conf)
        bitset(b, o + 1, 1)
        bitset(b, o + 4, cid, 4)
        bitset(b, o + 8, x, 16)
        bitset(b, o + 24, y, 16)
    bitset(b, 8 + 200, len(finger[:5]), 7)
    bitset(b, 8 + 207, button, 1)
    bitset(b, 8 + 208, elapsed, 16)
    return bytes(b)


def bootmaus(knoepfe, dx, dy):
    return bytes([knoepfe & 7, dx & 0xFF, dy & 0xFF])


BERICHTE = [
    (5, nkro([], [4, 5, 6, 7, 8, 9, 10, 11]), "acht Tasten"),
    (5, nkro([0xE1], [4, 5, 6, 7, 8, 9, 10, 11, 12, 13]), "elf mit Umschalt"),
    (5, nkro([], []), "alles losgelassen"),
    (5, nkro([0xE3], []), "Super gedrueckt"),
    (5, nkro([0xE3], [4]), "Super+a"),
    (5, nkro([0xE3], []), "Super+a los"),
    (5, nkro([], []), "Super losgelassen"),
    (0, bootkbd([], [4]), "boot: a"),
    (0, bootkbd([0xE1], [4]), "boot: Umschalt+a"),
    (0, bootkbd([], []), "boot: los"),
    (0, bootkbd([], [1, 1, 1, 1, 1, 1]), "boot: Ueberlauf"),
    (0, bootkbd([], [0x1B, 0x1D, 0x1C]), "boot: Reihenfolge xzy"),
    (0, bootkbd([], []), "boot: Reihenfolge los"),
    (0, bootkbd([0xE1, 0xE0], [4]), "boot: Strg+Umschalt+a"),
    (0, bootkbd([], []), "boot: Strg+Umschalt los"),
    (1, bootmaus(1, 10, 250), "maus: links, +10, -6"),
    (1, bootmaus(0, 0, 0), "maus: losgelassen"),
    (3, ptp([(1, 1000, 800)]), "pad: aufsetzen"),
    (3, ptp([(1, 1300, 800)]), "pad: +300x -> +100px"),
    (3, ptp([(1, 1300, 950)]), "pad: +150y -> +75px"),
    (3, ptp([(1, 1300, 950)], button=1), "pad: klick"),
    (3, ptp([(1, 1300, 950)], button=0), "pad: klick los"),
    (3, ptp([(1, 1300, 950), (2, 1800, 950)]), "pad: zwei Finger"),
    (3, ptp([(1, 1300, 1070), (2, 1800, 1070)]), "pad: rollen"),
    (3, ptp([]), "pad: abheben"),
    (3, ptp([(1, 3400, 2000)]), "pad: ecke aufsetzen"),
    (3, ptp([(1, 3400, 2000)], button=1), "pad: ecke klick"),
    (3, ptp([(1, 3400, 2000)], button=0), "pad: ecke los"),
    (3, ptp([]), "pad: ecke abheben"),
    (3, ptp([(1, 1500, 1000)]), "gest: tap aufsetzen"),
    (3, ptp([(1, 1500, 1000)]), "gest: tap halten"),
    (3, ptp([]), "gest: tap ende"),
    (3, ptp([(1, 1500, 1000), (2, 2000, 1000)]), "gest: zwei tap aufsetzen"),
    (3, ptp([(1, 1500, 1000), (2, 2000, 1000)]), "gest: zwei tap halten"),
    (3, ptp([]), "gest: zwei tap ende"),
    (3, ptp([(1, 1000, 1000), (2, 1500, 1000), (3, 2000, 1000)]),
     "gest: drei tap aufsetzen"),
    (3, ptp([]), "gest: drei tap ende"),
    (3, ptp([(1, 3400, 500)]), "gest: rand aufsetzen"),
    (3, ptp([(1, 3400, 520)]), "gest: rand zittern"),
    (3, ptp([(1, 3400, 700)]), "gest: rand scharf"),
    (3, ptp([(1, 3400, 1000)]), "gest: rand rollen"),
    (3, ptp([]), "gest: rand ende"),
    (3, ptp([(1, 1000, 1000), (2, 1500, 1000)]), "gest: rollen aufsetzen"),
    (3, ptp([(1, 1000, 1200), (2, 1500, 1200)]), "gest: rollen entscheiden"),
    (3, ptp([(1, 1000, 1400), (2, 1500, 1400)]), "gest: rollen rollen"),
    (3, ptp([]), "gest: rollen ende"),
    (3, ptp([(1, 1000, 1000), (2, 1500, 1000)]), "gest: seit aufsetzen"),
    (3, ptp([(1, 1200, 1000), (2, 1700, 1000)]), "gest: seit entscheiden"),
    (3, ptp([(1, 1400, 1000), (2, 1900, 1000)]), "gest: seit rollen"),
    (3, ptp([]), "gest: seit ende"),
    (3, ptp([(1, 1000, 1000), (2, 1600, 1000)]), "gest: kneifen aufsetzen"),
    (3, ptp([(1, 900, 1000), (2, 1700, 1000)]), "gest: kneifen entscheiden"),
    (3, ptp([(1, 800, 1000), (2, 1800, 1000)]), "gest: kneifen weiter"),
    (3, ptp([]), "gest: kneifen ende"),
    (3, ptp([(1, 2400, 1000), (2, 2800, 1000), (3, 3200, 1000)]),
     "gest: wisch aufsetzen"),
    (3, ptp([(1, 1700, 1000), (2, 2100, 1000), (3, 2500, 1000)]),
     "gest: wisch links"),
    (3, ptp([]), "gest: wisch ende"),
    (3, ptp([(1, 1500, 1000, 0)]), "gest: handballen aufsetzen"),
    (3, ptp([(1, 1500, 1000, 0)]), "gest: handballen halten"),
    (3, ptp([]), "gest: handballen ende"),
    (3, ptp([(1, 1500, 1000, 0), (2, 2000, 1200)]), "gest: ballen+finger aufsetzen"),
    (3, ptp([(1, 1500, 1000, 0), (2, 2000, 1200)]), "gest: ballen+finger halten"),
    (3, ptp([]), "gest: ballen+finger ende"),
    (3, ptp([]), "gest: ende"),
    (3, ptp([(1, 1500, 1000)]), "mf: drag tap aufsetzen"),
    (3, ptp([(1, 1500, 1000)]), "mf: drag tap halten"),
    (3, ptp([]), "mf: drag tap ende"),
    (3, ptp([(1, 1500, 1000)]), "mf: drag aufsetzen"),
    (3, ptp([(1, 1800, 1000)]), "mf: drag ziehen"),
    (3, ptp([(1, 2100, 1000)]), "mf: drag weiter"),
    (3, ptp([]), "mf: drag ende"),
    (3, ptp([(1, 1000, 1000), (2, 1800, 1000)]), "mf: zu aufsetzen"),
    (3, ptp([(1, 1100, 1000), (2, 1700, 1000)]), "mf: zu entscheiden"),
    (3, ptp([(1, 1200, 1000), (2, 1600, 1000)]), "mf: zu weiter"),
    (3, ptp([]), "mf: zu ende"),
    (3, ptp([(1, 1500, 1000), (2, 1900, 1000), (3, 2300, 1000)]), "mf: rechts aufsetzen"),
    (3, ptp([(1, 2200, 1000), (2, 2600, 1000), (3, 3000, 1000)]), "mf: rechts wisch"),
    (3, ptp([]), "mf: rechts ende"),
    (3, ptp([(1, 1500, 1500), (2, 1900, 1500), (3, 2300, 1500)]), "mf: hoch aufsetzen"),
    (3, ptp([(1, 1500, 800), (2, 1900, 800), (3, 2300, 800)]), "mf: hoch wisch"),
    (3, ptp([]), "mf: hoch ende"),
    (3, ptp([(1, 1500, 800), (2, 1900, 800), (3, 2300, 800)]), "mf: runter aufsetzen"),
    (3, ptp([(1, 1500, 1500), (2, 1900, 1500), (3, 2300, 1500)]), "mf: runter wisch"),
    (3, ptp([]), "mf: runter ende"),
    (3, ptp([(1, 3400, 2000)]), "mf: ecke aufsetzen"),
    (3, ptp([(1, 3400, 2000)], button=1), "mf: ecke klick"),
    (3, ptp([(1, 3400, 2000)], button=0), "mf: ecke los"),
    (3, ptp([]), "mf: ecke ende"),
    (3, ptp([(1, 1500, 1000)]), "mf: mitte aufsetzen"),
    (3, ptp([(1, 1500, 1000)], button=1), "mf: mitte klick"),
    (3, ptp([(1, 1500, 1000)], button=0), "mf: mitte los"),
    (3, ptp([]), "mf: mitte ende"),
    (3, ptp([]), "mf: optionen aus"),
    (3, ptp([(1, 3400, 2000)]), "mf: aus ecke aufsetzen"),
    (3, ptp([(1, 3400, 2000)], button=1), "mf: aus ecke klick"),
    (3, ptp([(1, 3400, 2000)], button=0), "mf: aus ecke los"),
    (3, ptp([]), "mf: aus ecke ende"),
    (3, ptp([(1, 1000, 1000), (2, 1800, 1000)]), "mf: aus zu aufsetzen"),
    (3, ptp([(1, 1100, 1000), (2, 1700, 1000)]), "mf: aus zu entscheiden"),
    (3, ptp([(1, 1200, 1000), (2, 1600, 1000)]), "mf: aus zu weiter"),
    (3, ptp([]), "mf: aus zu ende"),
    (3, ptp([(1, 2400, 1000), (2, 2800, 1000), (3, 3200, 1000)]), "mf: aus wisch aufsetzen"),
    (3, ptp([(1, 1700, 1000), (2, 2100, 1000), (3, 2500, 1000)]), "mf: aus wisch links"),
    (3, ptp([]), "mf: aus wisch ende"),
    (3, ptp([]), "mf: ende"),
]






def i2c_res(adr, hz=400000, source=b"\\_SB.PCI0.I2C1\0"):
    header = bytes([0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01])
    tdl = (6).to_bytes(2, "little")
    rest = header + tdl + hz.to_bytes(4, "little") \
        + adr.to_bytes(2, "little") + source
    return bytes([0x8E]) + len(rest).to_bytes(2, "little") + rest


def acpi_table(adressen, sig=b"DSDT"):
    koerper = bytearray()
    koerper += bytes([0x5B, 0x82, 0x30, 0x44, 0x45, 0x56, 0x30])
    koerper += bytes([0x08, 0x5F, 0x48, 0x49, 0x44])
    koerper += (0x500CD041).to_bytes(4, "little")
    koerper += bytes([0x8E, 0x00, 0x00, 0xFF])
    koerper += i2c_res(adressen[0])
    koerper += bytes([0x11, 0x22, 0x33, 0x44, 0x8E, 0x02])
    koerper += i2c_res(adressen[1], source=b"\\_SB.PCI0.I2C0\0")
    koerper += i2c_res(adressen[0])
    header = bytearray(36)
    header[0:4] = sig
    header[4:8] = (36 + len(koerper)).to_bytes(4, "little")
    header[8] = 2
    header[10:16] = b"OSUMHD"
    t = bytes(header) + bytes(koerper)
    t = bytearray(t)
    t[9] = (-sum(t)) & 0xFF
    return bytes(t)


I2C_ADRESSEN = [0x2C, 0x15]
ACPI_BLOB = acpi_table(I2C_ADRESSEN)



FL_CONST, FL_VAR = 1, 2
KIND_IN, KIND_OUT, KIND_FEAT = 1, 2, 3
MAX_FIELDS, MAX_RIDS, MAX_USAGES, MAX_DEPTH, MAX_PUSH = 64, 16, 32, 8, 8
M64 = 0xFFFFFFFFFFFFFFFF


class Error(Exception):
    def __init__(self, code, pos):
        self.code = code
        self.pos = pos


def sx(v, n):
    if n == 0:
        return 0
    if v & (1 << (n * 8 - 1)):
        return (v - (1 << (n * 8))) & M64
    return v


def art_von(page, usage):
    if page == 0x01 and usage == 0x06:
        return 1
    if page == 0x01 and usage == 0x02:
        return 2
    if page == 0x0D and usage in (0x04, 0x05):
        return 4
    if page == 0x0C and usage == 0x01:
        return 8
    return 0


def ausgeben(rid, kd, flags, base, rsize, rcount, page, ul, umin, umax,
             bereich, lmin, lmax):
    if rcount == 0 or rsize == 0:
        return []

    def F(off, cnt, pg, u, um):
        return {"rid": rid, "kind": kd, "flags": flags, "bitoff": off,
                "bitsz": rsize, "count": cnt, "page": pg, "usage": u,
                "umax": um, "lmin": lmin, "lmax": lmax}

    if flags & FL_CONST:
        return [F(base, rcount, page, 0, 0)]
    if not (flags & FL_VAR):
        if not bereich and ul:
            return [F(base, rcount, page, ul[0] & 0xFFFF, ul[0] & 0xFFFF)]
        return [F(base, rcount, page, umin & 0xFFFF, umax & 0xFFFF)]
    if bereich:
        return [F(base, rcount, page, umin & 0xFFFF, umax & 0xFFFF)]
    if not ul:
        return [F(base, rcount, page, 0, 0)]
    out, i = [], 0
    while i < rcount:
        if i >= len(ul):
            last = ul[-1]
            out.append(F(base + i * rsize, rcount - i,
                         (last >> 16) & 0xFFFF, last & 0xFFFF, 0))
            return out
        j = i
        while j + 1 < rcount and j + 1 < len(ul) and ul[j + 1] == ul[j] + 1:
            j += 1
        cnt = j - i + 1
        u0 = ul[i]
        out.append(F(base + i * rsize, cnt, (u0 >> 16) & 0xFFFF,
                     u0 & 0xFFFF, (u0 + cnt - 1) & 0xFFFF))
        i = j + 1
    return out


def zerlege(d):
    header = {"ok": 0, "err": 0, "errat": 0, "felder": 0, "rids": 0, "hasid": 0,
            "top": 0, "art": 0, "bits": 0, "posten": 0, "tiefe": 0,
            "len": len(d), "ridtab": []}
    felder = []
    if len(d) == 0 or len(d) > 1024:
        header["err"] = E_EMPTY
        return header, felder

    gl = [0] * 10
    stack = []
    ul, umin, umax, bereich = [], 0, 0, False
    rids = []
    p, tiefe, maxd, n = 0, 0, 0, 0
    top, card = 0, 0

    def rid_slot(r):
        for i, e in enumerate(rids):
            if e[0] == r:
                return i
        if len(rids) >= MAX_RIDS:
            return MAX_RIDS
        rids.append([r, 0, 0, 0])
        return len(rids) - 1

    def raus():
        header["felder"] = len(felder)
        header["rids"] = len(rids)
        header["top"] = top
        header["bits"] = rids[0][1] if rids else 0
        header["ridtab"] = rids

    try:
        while p < len(d):
            start = p
            b0 = d[p]
            p += 1
            if b0 == 0xFE:
                raise Error(E_LONG, start)
            bsize = b0 & 3
            if bsize == 3:
                bsize = 4
            btype = (b0 >> 2) & 3
            btag = (b0 >> 4) & 0xF
            if p + bsize > len(d):
                raise Error(E_TRUNC, start)
            data = 0
            for k in range(bsize):
                data |= d[p + k] << (k * 8)
            p += bsize
            n += 1

            if btype == 1:
                if btag == 0:
                    gl[0] = data & 0xFFFF
                elif btag == 1:
                    gl[1] = sx(data, bsize)
                elif btag == 2:
                    gl[2] = sx(data, bsize) if (gl[1] >> 63) else data
                elif btag == 3:
                    gl[3] = sx(data, bsize)
                elif btag == 4:
                    gl[4] = sx(data, bsize)
                elif btag in (5, 6, 7):
                    gl[btag] = data
                elif btag == 8:
                    if data == 0 or data > 255:
                        raise Error(E_SIZE, start)
                    gl[8] = data
                    header["hasid"] = 1
                elif btag == 9:
                    gl[9] = data
                elif btag == 10:
                    if len(stack) >= MAX_PUSH:
                        raise Error(E_PUSH, start)
                    stack.append(list(gl))
                elif btag == 11:
                    if not stack:
                        raise Error(E_PUSH, start)
                    gl = stack.pop()

            elif btype == 2:
                if btag == 0:
                    if len(ul) >= MAX_USAGES:
                        raise Error(E_USAGE, start)
                    ul.append(data if bsize == 4
                              else (gl[0] << 16) | (data & 0xFFFF))
                elif btag == 1:
                    umin = (data if bsize == 4
                            else (gl[0] << 16) | (data & 0xFFFF))
                    bereich = True
                elif btag == 2:
                    umax = (data if bsize == 4
                            else (gl[0] << 16) | (data & 0xFFFF))
                    bereich = True

            elif btype == 0:
                if btag == 0xA:
                    tiefe += 1
                    if tiefe > MAX_DEPTH:
                        raise Error(E_NEST, start)
                    maxd = max(maxd, tiefe)
                    if tiefe == 1:
                        tu = ul[0] if ul else (umin if bereich else 0)
                        if top == 0:
                            top = tu
                        card |= art_von((tu >> 16) & 0xFFFF, tu & 0xFFFF)
                elif btag == 0xC:
                    if tiefe == 0:
                        raise Error(E_NEST, start)
                    tiefe -= 1
                elif btag in (0x8, 0x9, 0xB):
                    kd = {0x8: KIND_IN, 0x9: KIND_OUT, 0xB: KIND_FEAT}[btag]
                    rsize, rcount = gl[7], gl[9]
                    if rsize > 32:
                        raise Error(E_SIZE, start)
                    if rcount > 1024:
                        raise Error(E_SIZE, start)
                    if rsize * rcount > 4096:
                        raise Error(E_BIG, start)
                    slot = rid_slot(gl[8])
                    if slot >= MAX_RIDS:
                        raise Error(E_RIDS, start)
                    idx = kd
                    base = rids[slot][idx]
                    if base + rsize * rcount > 4096:
                        raise Error(E_BIG, start)
                    for e in ausgeben(gl[8], kd, data & 0xFFFF, base, rsize,
                                      rcount, gl[0], ul, umin, umax, bereich,
                                      gl[1], gl[2]):
                        if len(felder) >= MAX_FIELDS:
                            raise Error(E_FIELDS, start)
                        felder.append(e)
                    rids[slot][idx] = base + rsize * rcount
                ul, umin, umax, bereich = [], 0, 0, False
        if tiefe != 0:
            raise Error(E_NEST, len(d))
    except Error as f:
        header["err"] = f.code
        header["errat"] = f.pos
        raus()
        return header, felder

    header["ok"] = 1
    raus()
    header["art"] = card
    header["posten"] = n
    header["tiefe"] = maxd
    return header, felder



ALL = GUT + [(k[0], k[1]) for k in BROKEN]


def firn():
    z = []
    a = z.append
    a("// SPDX-License-Identifier: GPL-2.0-only")
    a("// kernel/drv/hid/hidtest.fi -- ERZEUGT VON tools/hid/descs.py, NICHT VON HAND.")
    a("//")
    a("// Sechs ECHTE Berichtsbeschreibungen und vierzehn kaputte, gepackt zu")
    a("// je acht Oktett in ein Wort. Firn kann in einer Zeichenkette keine")
    a("// Oktette ueber 0x7F ausdruecken (dort faengt UTF-8 an), also stehen")
    a("// sie als Zahlen. Woher jede stammt und wie sie aussieht, steht in")
    a("// tools/hid/descs.py -- hier stuende es nur doppelt und waere beim")
    a("// naechsten Mal ungleich.")
    a("//")
    a("// Das Ganze kostet %d Oktett Nutzdaten im Abbild und wird NUR im"
      % sum(len(d) for _, d in ALL))
    a("// Modus `hidrep` angesehen.")
    a("")
    a("profile kernel")
    a("")
    a("import lib.kstate")
    a("")
    a("export { count, len_of, name_of, load, GUTE,")
    a("    bcount, bdesc, blen, bload, alen, aload, gbase, obase }")
    a("")
    a("const N: u64 = %d" % len(ALL))
    a("// Die ersten GUTE Beschreibungen muessen durchgehen, die uebrigen")
    a("// muessen mit einer bestimmten Fehlernummer scheitern.")
    a("const GUTE: u64 = %d" % len(GUT))
    a("")
    a("fn count() -> u64 {")
    a("    return N")
    a("}")
    a("")
    a("fn len_of(i: u64) -> u64 {")
    a("    var t: [u64; %d] = [%s]"
      % (len(ALL), ", ".join(str(len(d)) for _, d in ALL)))
    a("    if i >= N {")
    a("        return 0")
    a("    }")
    a("    return t[i as usize]")
    a("}")
    a("")
    a("// Der Name, acht Zeichen in EINEM Wort -- so bleibt die Meldung")
    a("// lesbar, ohne dass eine Zeichenkettentabelle noetig waere.")
    a("fn name_of(i: u64) -> u64 {")
    names = ["0x%016X" % int.from_bytes((nm + "        ")[:8].encode("ascii"),
                                        "little") for nm, _ in ALL]
    a("    var t: [u64; %d] = [%s]" % (len(ALL), ", ".join(names)))
    a("    if i >= N {")
    a("        return 0")
    a("    }")
    a("    return t[i as usize]")
    a("}")
    a("")
    offs, cur = [], 0
    for _, d in ALL:
        offs.append(cur)
        cur += (len(d) + 7) // 8
    a("fn off_of(i: u64) -> u64 {")
    a("    var t: [u64; %d] = [%s]"
      % (len(ALL), ", ".join(str(o) for o in offs)))
    a("    if i >= N {")
    a("        return 0")
    a("    }")
    a("    return t[i as usize]")
    a("}")
    a("")
    a("// Beschreibung `i` nach `dst` legen. Rueckgabe: die Laenge.")
    a("fn load(i: u64, dst: u64) -> u64 {")
    a("    let n: u64 = len_of(i)")
    a("    var k: u64 = 0")
    a("    while k < n {")
    a("        kstate.set8(dst + k, oktett(i, k) as u8)")
    a("        k = k + 1")
    a("    }")
    a("    return n")
    a("}")
    a("")
    a("fn oktett(i: u64, k: u64) -> u64 {")
    a("    let w: u64 = word(off_of(i) + k / 8)")
    a("    return (w >> ((k % 8) * 8)) & 0xFF")
    a("}")
    a("")
    worte = []
    for _, d in ALL:
        pad = d + b"\0" * ((8 - len(d) % 8) % 8)
        for k in range(0, len(pad), 8):
            worte.append(int.from_bytes(pad[k:k + 8], "little"))
    a("const NW: u64 = %d" % len(worte))
    a("")
    a("fn word(i: u64) -> u64 {")
    a("    var t: [u64; %d] = [" % len(worte))
    for k in range(0, len(worte), 4):
        chunk = ", ".join("0x%016X" % w for w in worte[k:k + 4])
        a("        %s%s" % (chunk, "," if k + 4 < len(worte) else ""))
    a("    ]")
    a("    if i >= NW {")
    a("        return 0")
    a("    }")
    a("    return t[i as usize]")
    a("}")
    a("")
    a("// ------------------------------------------------------ DIE BERICHTE")
    a("//")
    a("// Zu den Beschreibungen gehoeren Berichte, sonst ist der Zerleger eine")
    a("// Uebung ohne Gegenstand. Jeder ist von Hand gebaut, mit der Bitlage")
    a("// aus der Beschreibung daneben; was dabei herauskommen MUSS, steht in")
    a("// tools/hid/descs.py und wird von tools/hid/run.sh nachgerechnet.")
    a("const NB: u64 = %d" % len(BERICHTE))
    a("")
    a("fn bcount() -> u64 {")
    a("    return NB")
    a("}")
    a("")
    a("// First report of the gesture section (L-002 r797). The replay plays")
    a("// them only with the kernel word `hidgest`: the pad path of the older")
    a("// reports must stay exactly as it was measured.")
    a("fn gbase() -> u64 {")
    a("    return %d" % nr_von("gest: tap aufsetzen"))
    a("}")
    a("")
    a("// W-TPSET4: the report where the replay switches corner / pinch / swipe3 off.")
    a("fn obase() -> u64 {")
    a("    return %d" % nr_von("mf: optionen aus"))
    a("}")
    a("")
    a("// Zu welcher Beschreibung dieser Bericht gehoert.")
    a("fn bdesc(i: u64) -> u64 {")
    a("    var t: [u64; %d] = [%s]"
      % (len(BERICHTE), ", ".join(str(d) for d, _, _ in BERICHTE)))
    a("    if i >= NB {")
    a("        return 0")
    a("    }")
    a("    return t[i as usize]")
    a("}")
    a("")
    a("fn blen(i: u64) -> u64 {")
    a("    var t: [u64; %d] = [%s]"
      % (len(BERICHTE), ", ".join(str(len(b)) for _, b, _ in BERICHTE)))
    a("    if i >= NB {")
    a("        return 0")
    a("    }")
    a("    return t[i as usize]")
    a("}")
    a("")
    boffs, cur = [], 0
    for _, b, _ in BERICHTE:
        boffs.append(cur)
        cur += (len(b) + 7) // 8
    a("fn boff_of(i: u64) -> u64 {")
    a("    var t: [u64; %d] = [%s]"
      % (len(BERICHTE), ", ".join(str(o) for o in boffs)))
    a("    if i >= NB {")
    a("        return 0")
    a("    }")
    a("    return t[i as usize]")
    a("}")
    a("")
    a("fn bload(i: u64, dst: u64) -> u64 {")
    a("    let n: u64 = blen(i)")
    a("    var k: u64 = 0")
    a("    while k < n {")
    a("        kstate.set8(dst + k, boktett(i, k) as u8)")
    a("        k = k + 1")
    a("    }")
    a("    return n")
    a("}")
    a("")
    a("fn boktett(i: u64, k: u64) -> u64 {")
    a("    let w: u64 = bword(boff_of(i) + k / 8)")
    a("    return (w >> ((k % 8) * 8)) & 0xFF")
    a("}")
    a("")
    bworte = []
    for _, b, _ in BERICHTE:
        pad = b + b"\0" * ((8 - len(b) % 8) % 8)
        for k in range(0, len(pad), 8):
            bworte.append(int.from_bytes(pad[k:k + 8], "little"))
    a("const NBW: u64 = %d" % len(bworte))
    a("")
    a("fn bword(i: u64) -> u64 {")
    a("    var t: [u64; %d] = [" % len(bworte))
    for k in range(0, len(bworte), 4):
        st = ", ".join("0x%016X" % w for w in bworte[k:k + 4])
        a("        %s%s" % (st, "," if k + 4 < len(bworte) else ""))
    a("    ]")
    a("    if i >= NBW {")
    a("        return 0")
    a("    }")
    a("    return t[i as usize]")
    a("}")
    a("")
    a("// ------------------------------------ EINE GEBAUTE ACPI-TABELLE")
    a("//")
    a("// Mit GENAU zwei I2C-Verbindungen (Adressen %s) und drei"
      % ", ".join("0x%02X" % x for x in I2C_ADRESSEN))
    a("// Koedern, die wie eine aussehen und keine sind. Der Ersatzweg in")
    a("// i2chid.fi muss genau die zwei finden -- die dritte Vorlage ist")
    a("// eine WIEDERHOLUNG der ersten und darf nicht doppelt zaehlen.")
    a("const AN: u64 = %d" % len(ACPI_BLOB))
    a("")
    a("fn alen() -> u64 {")
    a("    return AN")
    a("}")
    a("")
    a("fn aload(dst: u64) -> u64 {")
    a("    var k: u64 = 0")
    a("    while k < AN {")
    a("        kstate.set8(dst + k, aoktett(k) as u8)")
    a("        k = k + 1")
    a("    }")
    a("    return AN")
    a("}")
    a("")
    a("fn aoktett(k: u64) -> u64 {")
    a("    return (aword(k / 8) >> ((k % 8) * 8)) & 0xFF")
    a("}")
    a("")
    ablob = ACPI_BLOB + b"\0" * ((8 - len(ACPI_BLOB) % 8) % 8)
    aworte = [int.from_bytes(ablob[k:k + 8], "little")
              for k in range(0, len(ablob), 8)]
    a("const NAW: u64 = %d" % len(aworte))
    a("")
    a("fn aword(i: u64) -> u64 {")
    a("    var t: [u64; %d] = [" % len(aworte))
    for k in range(0, len(aworte), 4):
        st = ", ".join("0x%016X" % w for w in aworte[k:k + 4])
        a("        %s%s" % (st, "," if k + 4 < len(aworte) else ""))
    a("    ]")
    a("    if i >= NAW {")
    a("        return 0")
    a("    }")
    a("    return t[i as usize]")
    a("}")
    print("\n".join(z))


def header_lines():
    out = []
    for i, (nm, d) in enumerate(ALL):
        k, _ = zerlege(d)
        out.append("hidrep: dev=%d ok=%d err=%d errat=%d felder=%d rids=%d "
                   "hasid=%d top=0x%x art=%d bits=%d posten=%d tiefe=%d"
                   % (i, k["ok"], k["err"], k["errat"], k["felder"], k["rids"],
                      k["hasid"], k["top"], k["art"], k["bits"], k["posten"],
                      k["tiefe"]))
    return out


def field_lines():
    out = []
    for i, (nm, d) in enumerate(ALL):
        k, f = zerlege(d)
        if not k["ok"]:
            continue
        for j, e in enumerate(f):
            out.append("hidf: %d %d rid=%d art=%d mrk=0x%x bit=%d gr=%d anz=%d "
                       "page=0x%x geb=0x%x gmax=0x%x lmin=0x%x lmax=0x%x"
                       % (i, j, e["rid"], e["kind"], e["flags"], e["bitoff"],
                          e["bitsz"], e["count"], e["page"], e["usage"],
                          e["umax"], e["lmin"] & M64, e["lmax"] & M64))
    return out


def nr_von(brand):
    for i, (_, _, k) in enumerate(BERICHTE):
        if k == brand:
            return i
    raise SystemExit("kein Bericht mit der Bemerkung %r" % brand)


def main():
    was = sys.argv[1] if len(sys.argv) > 1 else "kopf"
    if was == "nr":
        print(nr_von(sys.argv[2]))
        return 0
    if was == "firn":
        firn()
    elif was == "kopf":
        print("\n".join(header_lines()))
    elif was == "felder":
        print("\n".join(field_lines()))
    elif was == "fehler":
        bad_2 = 0
        for nm, d, e in BROKEN:
            k, _ = zerlege(d)
            gut = (e == k["err"] and k["ok"] == 0)
            bad_2 += 0 if gut else 1
            print("%-10s erwartet=%2d bekommen=%2d %s"
                  % (nm, e, k["err"], "ok" if gut else "FALSCH"))
        return 1 if bad_2 else 0
    else:
        print(__doc__)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
