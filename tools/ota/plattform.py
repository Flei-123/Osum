#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import struct

ELF_MASCHINE = {62: "x86_64", 183: "aarch64"}
WOERTER = ("osum-x86_64", "osum-aarch64", "osum-any")


def parts_2(roh):
    if len(roh) < 64 or roh[0:8] != b"OPKG0001":
        raise ValueError("not an OPKG file (Kennung fehlt)")
    ml, dl = struct.unpack_from("<QQ", roh, 8)
    return roh[64:64 + ml], roh[64 + ml:64 + ml + dl]


def elf_maschine(oktette):
    if len(oktette) < 20 or oktette[0:4] != b"\x7fELF":
        return None
    (em,) = struct.unpack_from("<H", oktette, 18)
    return em


def maschinen_im_archive(data_2):
    aus = set()
    i = 0
    try:
        while i < len(data_2):
            typ = chr(data_2[i])
            i += 1
            _modus, nl = struct.unpack_from("<HH", data_2, i)
            i += 4 + nl
            (n,) = struct.unpack_from("<Q", data_2, i)
            i += 8
            if typ not in "fd" or n > len(data_2) - i:
                return set()
            if typ == "f":
                em = elf_maschine(data_2[i:i + 20])
                if em is not None:
                    aus.add(em)
            i += n
    except struct.error:
        return set()
    return aus


def aus_meta(meta):
    plattform = arch = None
    for z in meta.decode("utf-8", "replace").split("\n"):
        if z.startswith("plattform="):
            plattform = z[10:].strip()
        elif z.startswith("arch="):
            arch = z[5:].strip()
    if plattform:
        return plattform
    if arch and arch != "any":
        return "osum-" + arch
    return None


def plattform_von_roh(roh, name="?"):
    meta, data_2 = parts_2(roh)
    p = aus_meta(meta)
    if p is not None:
        if p not in WOERTER:
            raise SystemExit("plattform: %s nennt %r -- bekannt sind %s"
                             % (name, p, ", ".join(WOERTER)))
        return p
    ems = maschinen_im_archive(data_2)
    if not ems:
        return "osum-any"
    woerter = sorted(set(ELF_MASCHINE.get(e, "elf-%d" % e) for e in ems))
    foreign = [w for w in woerter if w.startswith("elf-")]
    if foreign:
        raise SystemExit("plattform: %s traegt ein ELF fuer eine Maschine, "
                         "die Osum nicht kennt (e_machine %s)"
                         % (name, ", ".join(w[4:] for w in foreign)))
    if len(woerter) > 1:
        raise SystemExit("plattform: %s traegt ELF-Dateien fuer MEHRERE "
                         "Maschinen (%s) -- ein Paket, eine Maschine"
                         % (name, ", ".join(woerter)))
    return "osum-" + woerter[0]


def plattform_von_opk(path_2):
    with open(path_2, "rb") as f:
        return plattform_von_roh(f.read(), path_2)


if __name__ == "__main__":
    import sys
    for p in sys.argv[1:]:
        print("%-40s %s" % (p, plattform_von_opk(p)))
