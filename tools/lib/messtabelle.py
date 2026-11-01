#!/usr/bin/env python3

import re
import sys

TIME = re.compile(r'^\s*\[(\w*)\s+(\d+),(\d{3}) s\s+(\S+)\]\s*$')
HEADER = re.compile(r'^== (.+?) ==\s*$')
FAIL = re.compile(r'^\s*FEHLER\s+(\S+) ist fehlgeschlagen')
ZUS = re.compile(r'^\s*([A-Za-z][A-Za-z0-9]*): (\d+) (passed|proofs)')
BILANZ = re.compile(r'^(ALLE (\d+) ABSCHNITTE BESTANDEN, (\d+) Zusagen'
                    r'|(\d+) Abschnitte bestanden, (\d+) FEHLGESCHLAGEN \((\d+) Zusagen\))')


def lies(pfad):
    """-> {name: {ms, accel, titel, ok, zusagen}}, gesamt_s, bilanz"""
    ab = {}
    titel = None
    offen = {"titel": None, "fehler": False, "zusagen": None}
    gesamt = None
    bilanz = None
    for zeile in open(pfad, errors="replace"):
        z = zeile.rstrip("\n")
        m = HEADER.match(z)
        if m:
            offen = {"titel": m.group(1), "fehler": False, "zusagen": None}
            continue
        m = ZUS.match(z)
        if m:
            offen["zusagen"] = int(m.group(2))
            continue
        if FAIL.match(z):
            offen["fehler"] = True
            continue
        m = TIME.match(z)
        if m:
            accel, s, ms, name = m.group(1), int(m.group(2)), int(m.group(3)), m.group(4)
            ab[name] = {
                "ms": s * 1000 + ms,
                "accel": accel or "tcg-fest",
                "titel": offen["titel"] or name,
                "ok": not offen["fehler"],
                "zusagen": offen["zusagen"],
            }
            continue
        m = re.match(r'^SEKUNDEN=(\d+)$|^RC=(\d+) SEKUNDEN=(\d+)$', z)
        if m:
            gesamt = int(m.group(1) or m.group(3))
            continue
        if BILANZ.match(z):
            bilanz = z
    return ab, gesamt, bilanz


def short(titel, name):
    """Die Abschnittsnummer und ein paar Worte."""
    m = re.match(r'^(\d+)\.\s*(.{0,42})', titel)
    if not m:
        return name
    return f"{m.group(1):>2}. {m.group(2).strip()}"


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    a, a_s, a_b = lies(sys.argv[1])
    b, b_s, b_b = lies(sys.argv[2])

    names = list(a.keys()) + [n for n in b if n not in a]

    print("| Abschnitt | TCG | KVM | Faktor | TCG-Ergebnis | KVM-Ergebnis |")
    print("|---|---:|---:|---:|---|---|")
    sum_a = sum_b = 0
    rot = []
    for n in names:
        ea, eb = a.get(n), b.get(n)
        ta = f"{ea['ms']/1000:.1f} s" if ea else "--"
        tb = f"{eb['ms']/1000:.1f} s" if eb else "--"
        if ea:
            sum_a += ea["ms"]
        if eb:
            sum_b += eb["ms"]
        if ea and eb and eb["ms"] > 0:
            f = ea["ms"] / eb["ms"]
            fak = f"{f:.1f}x" if f >= 1.05 else ("=" if f > 0.95 else f"{f:.2f}x")
        else:
            fak = "--"

        def erg(e):
            if not e:
                return "--"
            z = f"{e['zusagen']} Zusagen" if e["zusagen"] is not None else "?"
            mark = "gruen" if e["ok"] else "**ROT**"
            acc = f" ({e['accel']})" if e["accel"] not in ("kvm", "tcg", "?") else ""
            return f"{mark}, {z}{acc}"

        titel = short((ea or eb)["titel"], n)
        print(f"| {titel} (`{n}`) | {ta} | {tb} | {fak} | {erg(ea)} | {erg(eb)} |")
        if ea and eb and ea["ok"] and not eb["ok"]:
            rot.append(n)

    print(f"| **Sum of the sections** | **{sum_a/1000:.0f} s** | **{sum_b/1000:.0f} s** "
          f"| **{sum_a/sum_b:.1f}x** | | |" if sum_b else "")
    if a_s and b_s:
        print(f"| **Wanduhr, ganze Abnahme** | **{a_s} s** | **{b_s} s** "
              f"| **{a_s/b_s:.1f}x** | | |")
    print()
    if a_b:
        print(f"TCG-Bilanz: {a_b}")
    if b_b:
        print(f"KVM-Bilanz: {b_b}")
    if rot:
        print(f"\nUNTER KVM ROT GEWORDEN ({len(rot)}): " + ", ".join(rot))
    else:
        print("\nNo section turned red under KVM.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
