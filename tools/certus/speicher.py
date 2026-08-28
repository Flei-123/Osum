#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
"""tools/certus/speicher.py -- WIEVIEL SPEICHER CERTUS WIRKLICH BRAUCHT.

Osum gibt einem Prozess heute zwei Bereiche (kernel/sys.fi, kernel/proc.fi):

    0x40080000 .. 0x400F0000   die alte Halde   458.752 Oktette
    0x40600000 .. 0x40C00000   die grosse Arena 6.291.456 Oktette
                               --------------------------------
                                                6.750.208 Oktette

Ob Certus da hineinpasst, ist keine Meinungsfrage. Dieses Skript liest
eine `strace -e trace=mmap,munmap`-Aufzeichnung und rechnet aus, wieviel
Speicher GLEICHZEITIG abgebildet war -- der Hoechststand ist die Zahl,
die entscheidet.

    python3 tools/certus/speicher.py <strace-datei>
"""
import json
import re
import sys

MMAP = re.compile(r"^mmap\(([^,]+), (\d+),.*?\)\s*=\s*(0x[0-9a-f]+|-?\d+)")
MUNMAP = re.compile(r"^munmap\((0x[0-9a-f]+), (\d+)\)")


def main():
    cur = 0
    peak = 0
    peak_at = 0
    total_mapped = 0
    n_map = n_unmap = 0
    biggest = 0
    live = {}
    verlauf = []
    for line in open(sys.argv[1], encoding="utf-8", errors="replace"):
        line = line.strip()
        m = MMAP.match(line)
        if m:
            ln = int(m.group(2))
            ret = m.group(3)
            if ret.startswith("0x"):
                live[ret] = ln
                cur += ln
                total_mapped += ln
                n_map += 1
                if ln > biggest:
                    biggest = ln
                if cur > peak:
                    peak = cur
                    peak_at = n_map
                verlauf.append(cur)
            continue
        m = MUNMAP.match(line)
        if m:
            a, ln = m.group(1), int(m.group(2))
            cur -= ln
            n_unmap += 1
            live.pop(a, None)
            verlauf.append(cur)
    osum = 458752 + 6291456
    out = {
        "mmap_aufrufe": n_map,
        "munmap_aufrufe": n_unmap,
        "insgesamt_abgebildet": total_mapped,
        "groesste_einzelabbildung": biggest,
        "hoechststand_gleichzeitig": peak,
        "hoechststand_bei_aufruf": peak_at,
        "am_ende_offen": cur,
        "osum_platz_heute": osum,
        "passt_in_osum": peak <= osum,
        "faktor_zu_osum": round(peak / float(osum), 2),
    }
    print(json.dumps(out, indent=2))


if __name__ == "__main__":
    main()
