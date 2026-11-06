#!/usr/bin/env python3
import sys
import zlib
import json

BS = 512


def le(b, off, n):
    return int.from_bytes(b[off:off + n], "little")


class Befund:
    def __init__(self):
        self.error = []
        self.parts = []
        self.header = {}

    def bad(self, s):
        self.error.append(s)


def header_read(f, lba, b: Befund, name):
    f.seek(lba * BS)
    h = f.read(BS)
    if len(h) < 92:
        b.bad(f"{name}: Sektor {lba} nicht lesbar")
        return None
    if h[0:8] != b"EFI PART":
        b.bad(f"{name}: no signature 'EFI PART' in Sektor {lba}")
        return None
    hsize = le(h, 12, 4)
    if hsize < 92 or hsize > BS:
        b.bad(f"{name}: unsinnige Kopfgroesse {hsize}")
        return None
    want = le(h, 16, 4)
    roh = bytearray(h[:hsize])
    roh[16:20] = b"\0\0\0\0"
    got = zlib.crc32(bytes(roh)) & 0xFFFFFFFF
    if got != want:
        b.bad(f"{name}: HEADER-CRC32 wrong -- stored {want:#010x}, computed {got:#010x}")
    return {
        "lba": lba,
        "meine": le(h, 24, 8),
        "andere": le(h, 32, 8),
        "first": le(h, 40, 8),
        "last": le(h, 48, 8),
        "board": le(h, 72, 8),
        "count": le(h, 80, 4),
        "esize": le(h, 84, 4),
        "tcrc": le(h, 88, 4),
        "hsize": hsize,
        "crc_ok": got == want,
    }


def board_check(f, k, b: Befund, name):
    gesamt = k["count"] * k["esize"]
    f.seek(k["board"] * BS)
    roh = f.read(gesamt)
    if len(roh) < gesamt:
        b.bad(f"{name}: Eintragstafel unvollstaendig")
        return []
    got = zlib.crc32(roh) & 0xFFFFFFFF
    if got != k["tcrc"]:
        b.bad(f"{name}: TABLE-CRC32 wrong -- stored {k['tcrc']:#010x}, gerechnet {got:#010x}")
    parts = []
    for i in range(k["count"]):
        e = roh[i * k["esize"]:(i + 1) * k["esize"]]
        if e[0:16] == b"\0" * 16:
            continue
        typ = e[0:16]
        guid = "-".join([
            f"{le(typ,0,4):08X}", f"{le(typ,4,2):04X}", f"{le(typ,6,2):04X}",
            typ[8:10].hex().upper(), typ[10:16].hex().upper(),
        ])
        nm = e[56:128].decode("utf-16-le", "replace").split("\0")[0]
        parts.append({
            "nr": i + 1,
            "start": le(e, 32, 8),
            "ende": le(e, 40, 8),
            "typ": guid,
            "name": nm,
        })
    return parts


def main():
    if len(sys.argv) < 2:
        print("usage: tafelpruef.py <platte.img> [--json]", file=sys.stderr)
        return 2
    path = sys.argv[1]
    als_json = "--json" in sys.argv
    b = Befund()

    with open(path, "rb") as f:
        f.seek(0, 2)
        size = f.tell()
        sekt = size // BS

        f.seek(0)
        mbr = f.read(BS)
        if mbr[510:512] != b"\x55\xaa":
            b.bad("protective MBR: the signature 0x55AA is missing")
        typen = [mbr[446 + i * 16 + 4] for i in range(4)]
        if 0xEE not in typen:
            b.bad("protective MBR: no entry of type 0xEE")

        prim = header_read(f, 1, b, "primaer")
        sich = header_read(f, sekt - 1, b, "sicherung")

        parts = []
        if prim:
            parts = board_check(f, prim, b, "primaer")
            b.header = prim
        if sich:
            board_check(f, sich, b, "sicherung")

        if prim and sich:
            if prim["andere"] != sich["meine"]:
                b.bad("the headers do not point at each other (primary -> backup)")
            if sich["andere"] != prim["meine"]:
                b.bad("the headers do not point at each other (backup -> primary)")
            if prim["tcrc"] != sich["tcrc"]:
                b.bad("die beiden Koepfe nennen verschiedene Tafelsummen")

        srt = sorted(parts, key=lambda p: p["start"])
        for i in range(1, len(srt)):
            if srt[i]["start"] <= srt[i - 1]["ende"]:
                b.bad(f"Partition {srt[i]['nr']} ueberschneidet {srt[i-1]['nr']}")

        b.parts = parts

    if als_json:
        print(json.dumps({
            "sektoren": sekt,
            "fehler": b.error,
            "partitionen": b.parts,
        }, indent=2))
    else:
        print(f"== {path}  ({sekt} Sektoren)")
        if b.header:
            k = b.header
            print(f"   benutzbar {k['first']}..{k['last']}, Tafel bei {k['board']}, "
                  f"{k['count']} Eintraege zu {k['esize']}")
        for p in b.parts:
            gr = (p["ende"] - p["start"] + 1) * BS // (1024 * 1024)
            print(f"   {p['nr']:>3}  {p['start']:>9}..{p['ende']:<9} {gr:>6} MiB  "
                  f"{p['typ']}  {p['name']}")
        if b.error:
            print("   FEHLER:")
            for e in b.error:
                print(f"     - {e}")
        else:
            print("   both headers and both table sums are fine")

    return 1 if b.error else 0


if __name__ == "__main__":
    sys.exit(main())
