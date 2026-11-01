#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""Usage:
    smbios.py <speicherabzug.bin>            die Felder, als key=value
    smbios.py --koeder <speicherabzug.bin>   der Beleg for die Pruefsumme
"""
import struct
import sys


def einstiegspunkte(d):
    treffer = []
    for at in range(0, len(d) - 32, 16):
        if d[at:at + 5] == b"_SM3_":
            ln = d[at + 6]
            if ln and at + ln <= len(d) and sum(d[at:at + ln]) % 256 == 0:
                treffer.append(("_SM3_", at, ln))
        elif d[at:at + 4] == b"_SM_":
            ln = d[at + 5]
            if ln and at + ln <= len(d) and sum(d[at:at + ln]) % 256 == 0:
                treffer.append(("_SM_", at, ln))
    return treffer


def strukturen(tbl):
    p = 0
    while p + 4 <= len(tbl):
        t, l = tbl[p], tbl[p + 1]
        if l < 4:
            return
        body = tbl[p:p + l]
        q = p + l
        texte = []
        if q + 1 < len(tbl) and tbl[q] == 0 and tbl[q + 1] == 0:
            q += 2
        else:
            while q < len(tbl):
                e = tbl.find(b"\0", q)
                if e < 0:
                    q = len(tbl)
                    break
                texte.append(tbl[q:e].decode("latin1"))
                q = e + 1
                if q < len(tbl) and tbl[q] == 0:
                    q += 1
                    break
        yield t, body, texte
        if t == 127:
            return
        p = q


def koeder(d):
    at = d.find(b"_SM3_")
    if at < 0:
        print("koeder=0")
        return 0
    ln = d[at + 6] if at + 6 < len(d) else 0
    gut = bool(ln) and at + ln <= len(d) and sum(d[at:at + ln]) % 256 == 0
    print("koeder=1")
    print("koeder_adresse=0x%x" % at)
    print("koeder_ausgerichtet=%s" % ("ja" if at % 16 == 0 else "nein"))
    print("koeder_pruefsumme=%s" % ("stimmt" if gut else "falsch"))
    return 0


def main(argv):
    if len(argv) > 1 and argv[1] == "--koeder":
        return koeder(open(argv[2], "rb").read())
    if len(argv) < 2:
        print(__doc__)
        return 2
    d = open(argv[1], "rb").read()

    treffer = einstiegspunkte(d)
    if not treffer:
        print("kein gueltiger Einstiegspunkt")
        return 1
    treffer.sort(key=lambda x: 3 if x[0] == "_SM3_" else 2)
    art, at, _ = treffer[-1]

    if art == "_SM_":
        main_2, neben = d[at + 6], d[at + 7]
        tlen = struct.unpack_from("<H", d, at + 0x16)[0]
        tadr = struct.unpack_from("<I", d, at + 0x18)[0]
        kind = 2
    else:
        main_2, neben = d[at + 7], d[at + 8]
        tlen = struct.unpack_from("<I", d, at + 0x0C)[0]
        tadr = struct.unpack_from("<Q", d, at + 0x10)[0]
        kind = 3

    print("entry=0x%x" % at)
    print("kind=%d" % kind)
    print("version=%d" % (main_2 * 100 + neben))
    print("table=0x%x" % tadr)
    print("tlen=%d" % tlen)

    tbl = d[tadr:tadr + tlen]
    felder = {}
    n = 0
    for t, body, texte in strukturen(tbl):
        n += 1

        def s(i):
            return texte[i - 1] if 1 <= i <= len(texte) else ""

        if t == 1:
            felder["sys_man"] = s(body[4])
            felder["sys_prod"] = s(body[5])
            felder["sys_ver"] = s(body[6])
            felder["sys_ser"] = s(body[7])
            if len(body) >= 24:
                felder["uuid"] = body[8:24].hex()
        elif t == 2:
            felder["brd_man"] = s(body[4])
            felder["brd_prod"] = s(body[5])
            felder["brd_ser"] = s(body[7])
    print("count=%d" % n)
    for k in ("sys_man", "sys_prod", "sys_ver", "sys_ser",
              "brd_man", "brd_prod", "brd_ser"):
        v = felder.get(k, "")
        print("%s=%s" % (k, v if v else "(empty)"))
    print("uuid=%s" % felder.get("uuid", "00" * 16))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
