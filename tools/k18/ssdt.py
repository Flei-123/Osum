#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import argparse
import sys



def pkglen(n_payload):
    for width in (1, 2, 3, 4):
        total = n_payload + width
        if width == 1:
            if total <= 0x3F:
                return bytes([total])
            continue
        if total < (1 << (4 + 8 * (width - 1))):
            out = [((width - 1) << 6) | (total & 0x0F)]
            v = total >> 4
            for _ in range(width - 1):
                out.append(v & 0xFF)
                v >>= 8
            return bytes(out)
    raise ValueError("Paket zu gross")


def aml_int(v):
    if v == 0:
        return b"\x00"
    if v == 1:
        return b"\x01"
    if v == 0xFFFFFFFF:
        return b"\xff"
    if v <= 0xFF:
        return b"\x0a" + bytes([v])
    if v <= 0xFFFF:
        return b"\x0b" + v.to_bytes(2, "little")
    if v <= 0xFFFFFFFF:
        return b"\x0c" + v.to_bytes(4, "little")
    return b"\x0e" + v.to_bytes(8, "little")


def aml_str(s):
    return b"\x0d" + s.encode("ascii") + b"\x00"


def nameseg(s):
    s = (s + "____")[:4].upper()
    return s.encode("ascii")


def name_op(seg, data):
    return b"\x08" + nameseg(seg) + data


def package(elems):
    body = bytes([len(elems)]) + b"".join(elems)
    return b"\x12" + pkglen(len(body)) + body


def device(seg, body):
    inner = nameseg(seg) + body
    return b"\x5b\x82" + pkglen(len(inner)) + inner


def thermal_zone(seg, body):
    inner = nameseg(seg) + body
    return b"\x5b\x85" + pkglen(len(inner)) + inner


def method_returning(seg, data):
    inner = nameseg(seg) + bytes([0]) + b"\xa4" + data
    return b"\x14" + pkglen(len(inner)) + inner


def eisa_id(s):
    letters, digits = s[:3], s[3:]
    v = 0
    for ch in letters:
        v = (v << 5) | (ord(ch) - ord("A") + 1)
    return (v >> 8 & 0xFF) | ((v & 0xFF) << 8) | (int(digits, 16) << 16)



def build(a):
    out = b""

    if not a.kein_akku:
        bif = package([
            aml_int(a.einheit),
            aml_int(a.design),
            aml_int(a.voll),
            aml_int(1),
            aml_int(a.dvolt),
            aml_int(a.warnung),
            aml_int(a.untergrenze),
            aml_int(1),
            aml_int(1),
            aml_str(a.modell),
            aml_str(a.seriennr),
            aml_str(a.art),
            aml_str(a.hersteller),
        ])
        bst = package([
            aml_int(a.zustand),
            aml_int(a.rate),
            aml_int(a.rest),
            aml_int(a.volt),
        ])
        body = name_op("_HID", aml_int(eisa_id("PNP0C0A")))
        body += name_op("_UID", aml_int(0))
        body += name_op("_STA", aml_int(a.sta))
        body += name_op("_BIF", bif)
        if a.methode:
            body += method_returning("_BST", bst)
        else:
            body += name_op("_BST", bst)
        out += device("BAT0", body)

    if not a.kein_netzteil:
        body = name_op("_HID", aml_str("ACPI0003"))
        body += name_op("_PSR", aml_int(a.netz))
        out += device("ADP0", body)

    if not a.no_zone:
        body = name_op("_TMP", aml_int(a.temp))
        body += name_op("_CRT", aml_int(3732))
        out += thermal_zone("TZ00", body)

    return out


def main():
    p = argparse.ArgumentParser(add_help=True)
    p.add_argument("out")
    p.add_argument("--rest", type=int, default=3300)
    p.add_argument("--voll", type=int, default=4400)
    p.add_argument("--design", type=int, default=4400)
    p.add_argument("--rate", type=int, default=500)
    p.add_argument("--volt", type=int, default=10800)
    p.add_argument("--dvolt", type=int, default=10800)
    p.add_argument("--zustand", type=int, default=1)
    p.add_argument("--warnung", type=int, default=440)
    p.add_argument("--untergrenze", type=int, default=220)
    p.add_argument("--einheit", type=int, default=0)
    p.add_argument("--sta", type=int, default=0x1F)
    p.add_argument("--netz", type=int, default=0)
    p.add_argument("--temp", type=int, default=3032)
    p.add_argument("--modell", default="OSUM-BAT")
    p.add_argument("--seriennr", default="0001")
    p.add_argument("--art", default="LION")
    p.add_argument("--hersteller", default="FLEITEC")
    p.add_argument("--kein-akku", action="store_true")
    p.add_argument("--kein-netzteil", action="store_true")
    p.add_argument("--keine-zone", action="store_true")
    p.add_argument("--methode", action="store_true")
    a = p.parse_args()

    data = build(a)
    with open(a.out, "wb") as f:
        f.write(data)

    if a.kein_akku:
        prozent = minuten = -1
    else:
        prozent = (a.rest * 100 + a.voll // 2) // a.voll if a.voll else 0
        prozent = min(prozent, 100)
        if a.rate:
            set_2 = a.voll - a.rest if (a.zustand & 2) else a.rest
            minuten = (set_2 * 60) // a.rate
        else:
            minuten = 0
    grad = (a.temp - 2732) // 10
    print("oktette=%d prozent=%d minuten=%d grad=%d netz=%d"
          % (len(data), prozent, minuten, grad, a.netz))
    return 0


if __name__ == "__main__":
    sys.exit(main())
