#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
# tools/dual/tafelpruef.py -- DIE TAFEL MIT FREMDEN AUGEN LESEN.
#
#   python3 tools/dual/tafelpruef.py <platte.img> [--json]
#
# ==================================================================
# WOFUER
# ==================================================================
#
# `dualkern.fi` rechnet zwei CRC32 und schreibt sie in eine fremde
# Partitionstafel. Wer nur mit demselben Code nachliest, den er
# geschrieben hat, prueft, ob er sich selbst wiederfindet -- und nicht,
# ob das Ergebnis RICHTIG ist.
#
# Diese Datei ist die zweite Meinung. Sie liest die Tafel nach der
# Beschreibung (UEFI 2.10, Abschnitt 5.3) und rechnet beide Summen neu,
# ohne eine Zeile aus dem Kernel zu benutzen:
#
#   * die Signatur "EFI PART" in Sektor 1
#   * die CRC32 des Kopfes (mit dem eigenen Feld auf Null)
#   * die CRC32 der ganzen Eintragstafel
#   * DASSELBE noch einmal fuer die Sicherung am Plattenende
#   * und die Gegenprobe, dass beide Koepfe aufeinander zeigen
#
# `sgdisk` prueft das auch, sagt aber bei einem Fehler nur "invalid".
# Hier steht, WELCHE der vier Summen nicht stimmt -- und das ist der
# Unterschied zwischen "kaputt" und "reparierbar".
import sys
import zlib
import json

BS = 512


def le(b, off, n):
    return int.from_bytes(b[off:off + n], "little")


class Befund:
    def __init__(self):
        self.fehler = []
        self.parts = []
        self.kopf = {}

    def bad(self, s):
        self.fehler.append(s)


def kopf_lesen(f, lba, b: Befund, name):
    f.seek(lba * BS)
    h = f.read(BS)
    if len(h) < 92:
        b.bad(f"{name}: Sektor {lba} nicht lesbar")
        return None
    if h[0:8] != b"EFI PART":
        b.bad(f"{name}: keine Signatur 'EFI PART' in Sektor {lba}")
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
        b.bad(f"{name}: KOPF-CRC32 falsch -- steht {want:#010x}, gerechnet {got:#010x}")
    return {
        "lba": lba,
        "meine": le(h, 24, 8),
        "andere": le(h, 32, 8),
        "erste": le(h, 40, 8),
        "letzte": le(h, 48, 8),
        "tafel": le(h, 72, 8),
        "anzahl": le(h, 80, 4),
        "esize": le(h, 84, 4),
        "tcrc": le(h, 88, 4),
        "hsize": hsize,
        "crc_ok": got == want,
    }


def tafel_pruefen(f, k, b: Befund, name):
    gesamt = k["anzahl"] * k["esize"]
    f.seek(k["tafel"] * BS)
    roh = f.read(gesamt)
    if len(roh) < gesamt:
        b.bad(f"{name}: Eintragstafel unvollstaendig")
        return []
    got = zlib.crc32(roh) & 0xFFFFFFFF
    if got != k["tcrc"]:
        b.bad(f"{name}: TAFEL-CRC32 falsch -- steht {k['tcrc']:#010x}, gerechnet {got:#010x}")
    parts = []
    for i in range(k["anzahl"]):
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
    pfad = sys.argv[1]
    als_json = "--json" in sys.argv
    b = Befund()

    with open(pfad, "rb") as f:
        f.seek(0, 2)
        groesse = f.tell()
        sekt = groesse // BS

        # ---- der Schutz-MBR
        f.seek(0)
        mbr = f.read(BS)
        if mbr[510:512] != b"\x55\xaa":
            b.bad("Schutz-MBR: die Signatur 0x55AA fehlt")
        typen = [mbr[446 + i * 16 + 4] for i in range(4)]
        if 0xEE not in typen:
            b.bad("Schutz-MBR: kein Eintrag vom Typ 0xEE")

        # ---- beide Koepfe
        prim = kopf_lesen(f, 1, b, "primaer")
        sich = kopf_lesen(f, sekt - 1, b, "sicherung")

        parts = []
        if prim:
            parts = tafel_pruefen(f, prim, b, "primaer")
            b.kopf = prim
        if sich:
            tafel_pruefen(f, sich, b, "sicherung")

        # ---- zeigen sie aufeinander?
        if prim and sich:
            if prim["andere"] != sich["meine"]:
                b.bad("die Koepfe zeigen nicht aufeinander (primaer -> sicherung)")
            if sich["andere"] != prim["meine"]:
                b.bad("die Koepfe zeigen nicht aufeinander (sicherung -> primaer)")
            if prim["tcrc"] != sich["tcrc"]:
                b.bad("die beiden Koepfe nennen verschiedene Tafelsummen")

        # ---- ueberschneiden sich Partitionen?
        srt = sorted(parts, key=lambda p: p["start"])
        for i in range(1, len(srt)):
            if srt[i]["start"] <= srt[i - 1]["ende"]:
                b.bad(f"Partition {srt[i]['nr']} ueberschneidet {srt[i-1]['nr']}")

        b.parts = parts

    if als_json:
        print(json.dumps({
            "sektoren": sekt,
            "fehler": b.fehler,
            "partitionen": b.parts,
        }, indent=2))
    else:
        print(f"== {pfad}  ({sekt} Sektoren)")
        if b.kopf:
            k = b.kopf
            print(f"   benutzbar {k['erste']}..{k['letzte']}, Tafel bei {k['tafel']}, "
                  f"{k['anzahl']} Eintraege zu {k['esize']}")
        for p in b.parts:
            gr = (p["ende"] - p["start"] + 1) * BS // (1024 * 1024)
            print(f"   {p['nr']:>3}  {p['start']:>9}..{p['ende']:<9} {gr:>6} MiB  "
                  f"{p['typ']}  {p['name']}")
        if b.fehler:
            print("   FEHLER:")
            for e in b.fehler:
                print(f"     - {e}")
        else:
            print("   beide Koepfe und beide Tafelsummen sind in Ordnung")

    return 1 if b.fehler else 0


if __name__ == "__main__":
    sys.exit(main())
