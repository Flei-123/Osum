#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")

BUFFER = re.compile(
    r"state\s*\+\s*kstate\.("
    r"NAME_OFF|BLOCK_OFF|EARG_OFF|FS_OFF|OFS3_OFF|LOAD_OFF|CONSOLE_OFF"
    r")")

LOCK = re.compile(r"\benter\(state\)|\bfs\.enter\(|atomic\.lock_take\("
                    r"|serial\.zeile_an\("
                    r"|stage_on\(|stage_if_|table_on\(|stage_of\(")

BASISZUGRIFF = re.compile(
    r"fn (\w+)\(state: u64\) -> u64 \{\s*\n\s*return state \+ kstate\.(\w+_OFF)")
def buffer2(zugriff):
    return re.compile(r"\b%s\(state\)\s*\+\s*([A-Z][A-Z0-9_]*)" % zugriff)

RUHIG = {
    "kmain.fi": "laeuft vor smp.probe, also bevor es zweite Kerne gibt",
}

MITWISSEN = {
    ("kernel/ui/wig.fi", "stage_of"):
        "gibt die Buehne DIESES Kerns (kstate.WIGST_OFF + cpu.here * "
        "STAGE_MAX). Die GETEILTE Seite kommt darin nur unter "
        "`glyphblind`/`glyphsperre` vor -- das sind die zwei "
        "Gegenproben, und ohne sie misst der Nachweis nichts.",
}


def funktionen(path_2):
    roh = open(path_2, "rb").read().decode("utf-8", "surrogateescape")
    aus = {}
    name = None
    leib = []
    for z in roh.split("\n"):
        m = re.match(r"^fn (\w+)\(", z)
        if m:
            if name:
                aus[name] = leib
            name = m.group(1)
            leib = []
        elif name is not None:
            if z == "}":
                aus[name] = leib
                name = None
                leib = []
            else:
                leib.append(z)
    if name:
        aus[name] = leib
    return aus


def main(argv):
    liste = "--liste" in argv
    nur = None
    for i, a in enumerate(argv):
        if a == "--nur" and i + 1 < len(argv):
            nur = argv[i + 1]

    gesperrt = []
    open_ = []
    mitwissen = []
    for root, _, dateien in os.walk(os.path.join(ROOT, "kernel")):
        for d in sorted(dateien):
            if not d.endswith(".fi"):
                continue
            if nur and d != nur:
                continue
            path_2 = os.path.join(root, d)
            short = os.path.relpath(path_2, ROOT)
            roh = open(path_2, "rb").read().decode("utf-8", "surrogateescape")
            zweite = [(z, page, buffer2(z))
                      for z, page in BASISZUGRIFF.findall(roh)]
            for fn, leib in sorted(funktionen(path_2).items()):
                text = "\n".join(leib)
                treffer = BUFFER.findall(text)
                for zugriff, page, muster in zweite:
                    if fn == zugriff:
                        continue
                    treffer = treffer + ["%s+%s" % (page, k)
                                         for k in muster.findall(text)]
                if not treffer:
                    continue
                entry = (short, fn, sorted(set(treffer)))
                if (short, fn) in MITWISSEN:
                    mitwissen.append(entry)
                    continue
                if LOCK.search(text) or d in RUHIG:
                    gesperrt.append(entry)
                else:
                    open_.append(entry)

    if liste:
        print("== LOCKED: the buffer is used under a lock ==")
        for k, f, p in gesperrt:
            print("   %-24s %-22s %s" % (k, f, ",".join(p)))
        print()
        print("== OPEN: no lock word in the body ==")
        for k, f, p in open_:
            print("   %-24s %-22s %s" % (k, f, ",".join(p)))
        print()
    if liste and mitwissen:
        print("== KNOWN: deliberately on the shared buffer ==")
        for k, f, p in mitwissen:
            print("   %-24s %-22s %s" % (k, f, ",".join(p)))
            print("      %s" % MITWISSEN[(k, f)])
        print()
    dat_open = sorted(set(k for k, _, _ in open_))
    print("einkern gesperrt=%d offen=%d mitwissen=%d dateien=%s"
          % (len(gesperrt), len(open_), len(mitwissen),
             ",".join(dat_open) or "-"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
